package com.zentrip.api;

import java.time.Duration;
import java.time.Instant;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

@Service
public class GeoapifyAttractionService {
    private static final Logger LOG = LoggerFactory.getLogger(GeoapifyAttractionService.class);
    private static final Duration CACHE_TTL = Duration.ofMinutes(30);
    private static final Pattern WIKIDATA_QID = Pattern.compile("\\bQ[1-9][0-9]*\\b");
    private static final Pattern WIKIDATA_POINT = Pattern.compile(
            "Point\\s*\\(\\s*([-+]?[0-9]+(?:\\.[0-9]+)?)\\s+"
                    + "([-+]?[0-9]+(?:\\.[0-9]+)?)\\s*\\)");
    private static final String DEFAULT_CITY = "Tripoli";
    private static final String DEFAULT_COUNTRY = "Libya";
    private static final Set<String> VERIFIED_LANDMARK_TYPES = Set.of(
            "Q4989906", // monument
            "Q839954",  // archaeological site
            "Q33506",   // museum
            "Q207694",  // art museum
            "Q22698",   // park
            "Q46169",   // national park
            "Q9259",    // UNESCO World Heritage Site
            "Q41176",   // building
            "Q11303",   // skyscraper
            "Q174782"); // square
    private static final Map<String, List<String>> COUNTRY_SEARCH_CITIES = Map.of(
            "libya", List.of("Tripoli", "Misrata", "Benghazi", "Sebha"),
            "egypt", List.of("Cairo"),
            "tunisia", List.of("Tunis"),
            "turkiye", List.of("Istanbul"),
            "saudi arabia", List.of("Jeddah"),
            "united arab emirates", List.of("Dubai"),
            "indonesia", List.of("Denpasar", "Jakarta"));
    private static final Map<String, String> COUNTRY_CODES = Map.ofEntries(
            Map.entry("libya", "ly"),
            Map.entry("egypt", "eg"),
            Map.entry("tunisia", "tn"),
            Map.entry("turkiye", "tr"),
            Map.entry("turkey", "tr"),
            Map.entry("saudi arabia", "sa"),
            Map.entry("united arab emirates", "ae"),
            Map.entry("uae", "ae"),
            Map.entry("indonesia", "id"));

    private final String apiKey;
    private final RestClient geoapify;
    private final RestClient wikidata;
    private final Map<String, CacheEntry> cache = new ConcurrentHashMap<>();

    public GeoapifyAttractionService(@Value("${geoapify.api-key:}") String apiKey) {
        this(apiKey, geoapifyBuilder(), wikidataBuilder());
    }

    GeoapifyAttractionService(
            String apiKey,
            RestClient.Builder geoapifyBuilder,
            RestClient.Builder wikidataBuilder) {
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.geoapify = geoapifyBuilder.build();
        this.wikidata = wikidataBuilder
                .defaultHeader("User-Agent", "ZentripPOI/1.0 (https://zentrip.ly)")
                .defaultHeader("Accept", "application/sparql-results+json")
                .build();
    }

    private static RestClient.Builder geoapifyBuilder() {
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(3));
        requestFactory.setReadTimeout(Duration.ofSeconds(5));
        return RestClient.builder()
                .baseUrl("https://api.geoapify.com")
                .requestFactory(requestFactory);
    }

    private static RestClient.Builder wikidataBuilder() {
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(3));
        requestFactory.setReadTimeout(Duration.ofSeconds(5));
        return RestClient.builder()
                .baseUrl("https://query.wikidata.org")
                .requestFactory(requestFactory);
    }

    public List<Map<String, Object>> searchAttractions(
            String requestedCity, String requestedCountry, String requestedLanguage) {
        return searchAttractionsWithStatus(
                requestedCity, requestedCountry, requestedLanguage).places();
    }

    public SearchOutcome searchAttractionsWithStatus(
            String requestedCity, String requestedCountry, String requestedLanguage) {
        if (apiKey.isBlank()) return new SearchOutcome(List.of(), null);
        String city = nonBlank(requestedCity, DEFAULT_CITY).trim();
        String country = nonBlank(requestedCountry, DEFAULT_COUNTRY).trim();
        String language = "ar".equalsIgnoreCase(requestedLanguage) ? "ar" : "en";
        boolean countrySearch = requestedCity == null || requestedCity.isBlank();
        String cacheCity = countrySearch ? "country" : city;
        String cacheKey = (cacheCity + "|" + country + "|" + language)
                .toLowerCase(Locale.ROOT);

        CacheEntry previous = cache.get(cacheKey);
        Instant now = Instant.now();
        if (previous != null && now.isBefore(previous.expiresAt())) {
            return new SearchOutcome(previous.places(), previous.cityFound());
        }

        try {
            List<String> searchCities = countrySearch
                    ? COUNTRY_SEARCH_CITIES.get(country.toLowerCase(Locale.ROOT))
                    : List.of(city);
            if (searchCities == null || searchCities.isEmpty()) {
                cache.put(cacheKey, new CacheEntry(
                        List.of(), null, now.plus(CACHE_TTL)));
                return new SearchOutcome(List.of(), null);
            }

            List<PlaceBatch> batches = new ArrayList<>();
            List<Map<?, ?>> allFeatures = new ArrayList<>();
            boolean cityGeocoded = false;
            boolean providerFailed = false;
            for (String searchCity : searchCities) {
                try {
                    GeoPoint center = geocode(searchCity, country, language);
                    if (center == null) continue;
                    cityGeocoded = true;
                    List<Map<?, ?>> features = fetchPlaces(center, language);
                    batches.add(new PlaceBatch(searchCity, country, center, features));
                    allFeatures.addAll(features);
                } catch (RestClientException exception) {
                    providerFailed = true;
                    String reason = classifyProviderFailure(exception);
                    LOG.warn("Geoapify places unavailable for a destination city ({})", reason);
                }
            }

            Map<String, PlaceEnrichment> enrichments =
                    fetchWikidataEnrichment(allFeatures);
            Map<String, Map<String, Object>> uniquePlaces = new LinkedHashMap<>();
            for (PlaceBatch batch : batches) {
                for (Map<String, Object> place : normalize(
                        batch.features(), enrichments, batch.city(), batch.country(),
                        language, batch.location())) {
                    uniquePlaces.putIfAbsent(deduplicationKey(place), place);
                }
            }
            List<Map<String, Object>> places = uniquePlaces.values().stream()
                    .limit(countrySearch ? 50 : 20)
                    .toList();
            List<Map<String, Object>> immutablePlaces = List.copyOf(places);
            Boolean cityFound = countrySearch ? null
                    : cityGeocoded ? true : providerFailed ? null : false;
            cache.put(cacheKey,
                    new CacheEntry(immutablePlaces, cityFound, now.plus(CACHE_TTL)));
            return new SearchOutcome(immutablePlaces, cityFound);
        } catch (RestClientException exception) {
            String reason = exception instanceof RestClientResponseException response
                    ? "HTTP " + response.getStatusCode().value()
                    : "network or timeout error";
            LOG.warn("Geoapify attraction search failed ({})", reason);
            return previous == null
                    ? new SearchOutcome(List.of(), null)
                    : new SearchOutcome(previous.places(), previous.cityFound());
        }
    }

    public List<Map<String, Object>> searchAtCoordinates(
            double latitude, double longitude, String city, String country, String language) {
        if (apiKey.isBlank() || !Double.isFinite(latitude) || !Double.isFinite(longitude)
                || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return List.of();
        String cacheKey = "coordinates|" + latitude + "|" + longitude + "|" + language;
        Instant now = Instant.now();
        CacheEntry previous = cache.get(cacheKey);
        if (previous != null && now.isBefore(previous.expiresAt())) return previous.places();
        try {
            GeoPoint center = new GeoPoint(
                    latitude, longitude, null, city, country, null);
            List<Map<?, ?>> features = fetchPlaces(center, language);
            List<Map<String, Object>> places = List.copyOf(normalize(features,
                    fetchWikidataEnrichment(features), city, country, language, center));
            cache.put(cacheKey, new CacheEntry(places, null, now.plus(CACHE_TTL)));
            return places;
        } catch (RestClientException exception) {
            LOG.warn("Geoapify coordinate landmark lookup unavailable.");
            return previous == null ? List.of() : previous.places();
        }
    }

    @SuppressWarnings("unchecked")
    private GeoPoint geocode(String city, String country, String language) {
        String countryCode = COUNTRY_CODES.get(normalizeCountry(country));
        Map<?, ?> response = geoapify.get()
                .uri(uri -> uri.path("/v1/geocode/search")
                        .queryParam("text", countryCode == null ? city + ", " + country : city)
                        .queryParamIfPresent(
                                "filter",
                                countryCode == null
                                        ? java.util.Optional.empty()
                                        : java.util.Optional.of("countrycode:" + countryCode))
                        .queryParam("format", "json")
                        .queryParam("limit", 1)
                        .queryParam("lang", language)
                        .queryParam("apiKey", apiKey)
                        .build())
                .retrieve()
                .body(Map.class);
        List<?> results = list(map(response).get("results"));
        if (results.isEmpty()) return null;

        Map<?, ?> result = map(results.getFirst());
        String geocodedCountry = text(result.get("country"));
        if (geocodedCountry != null && !sameCountry(geocodedCountry, country)) {
            return null;
        }
        String resultCountryCode = text(result.get("country_code"));
        if (countryCode != null && resultCountryCode != null
                && !countryCode.equalsIgnoreCase(resultCountryCode)) {
            return null;
        }
        Double latitude = number(result.get("lat"));
        Double longitude = number(result.get("lon"));
        if (latitude == null || longitude == null
                || latitude < -90 || latitude > 90
                || longitude < -180 || longitude > 180) {
            return null;
        }
        String cityLabel = firstNonBlank(
                text(result.get("city")),
                text(result.get("town")),
                text(result.get("village")),
                city);
        return new GeoPoint(
                latitude,
                longitude,
                bounds(map(result.get("bbox"))),
                cityLabel,
                firstNonBlank(geocodedCountry, country),
                firstNonBlank(resultCountryCode, countryCode));
    }

    @SuppressWarnings("unchecked")
    private List<Map<?, ?>> fetchPlaces(GeoPoint center, String language) {
        Map<?, ?> response = geoapify.get()
                .uri(uri -> uri.path("/v2/places")
                        .queryParam("categories",
                                "tourism.sights,tourism.attraction,entertainment.museum,"
                                        + "leisure.park,heritage,building.historic")
                        .queryParam("filter", placeFilter(center))
                        .queryParam("bias", "proximity:" + center.longitude()
                                + "," + center.latitude())
                        .queryParam("limit", 20)
                        .queryParam("lang", language)
                        .queryParam("apiKey", apiKey)
                        .build())
                .retrieve()
                .body(Map.class);

        List<Map<?, ?>> features = new ArrayList<>();
        for (Object feature : list(map(response).get("features"))) {
            Map<?, ?> value = map(feature);
            if (!value.isEmpty()) features.add(value);
        }
        return features;
    }

    private Map<String, PlaceEnrichment> fetchWikidataEnrichment(List<Map<?, ?>> features) {
        Set<String> qids = new LinkedHashSet<>();
        for (Map<?, ?> feature : features) {
            String qid = wikidataQid(properties(feature));
            if (qid != null) qids.add(qid);
        }
        if (qids.isEmpty()) return Map.of();

        String values = qids.stream().map(qid -> "wd:" + qid)
                .reduce((left, right) -> left + " " + right).orElse("");
        String query = """
                PREFIX wd: <http://www.wikidata.org/entity/>
                PREFIX wdt: <http://www.wikidata.org/prop/direct/>
                PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
                PREFIX schema: <http://schema.org/>
                SELECT ?item ?landmarkType ?coordinates
                       ?labelEn ?labelAr ?descriptionEn ?descriptionAr
                       ?enwiki ?arwiki ?image ?enWikiImage ?arWikiImage
                WHERE {
                  VALUES ?item { %s }
                  VALUES ?landmarkType {
                    wd:Q4989906 wd:Q839954 wd:Q33506 wd:Q207694
                    wd:Q22698 wd:Q46169 wd:Q9259 wd:Q41176
                    wd:Q11303 wd:Q174782
                  }
                  ?item wdt:P31/wdt:P279* ?landmarkType .
                  ?item wdt:P625 ?coordinates .
                  OPTIONAL { ?item rdfs:label ?labelEn . FILTER(LANG(?labelEn) = "en") }
                  OPTIONAL { ?item rdfs:label ?labelAr . FILTER(LANG(?labelAr) = "ar") }
                  OPTIONAL { ?item schema:description ?descriptionEn .
                             FILTER(LANG(?descriptionEn) = "en") }
                  OPTIONAL { ?item schema:description ?descriptionAr .
                             FILTER(LANG(?descriptionAr) = "ar") }
                  OPTIONAL { ?enwiki schema:about ?item ;
                             schema:isPartOf <https://en.wikipedia.org/> . }
                  OPTIONAL { ?arwiki schema:about ?item ;
                             schema:isPartOf <https://ar.wikipedia.org/> . }
                  OPTIONAL { ?item wdt:P18 ?image . }
                  OPTIONAL { ?enwiki schema:image ?enWikiImage . }
                  OPTIONAL { ?arwiki schema:image ?arWikiImage . }
                }
                """.formatted(values);

        try {
            URI requestUri = URI.create("https://query.wikidata.org/sparql?query="
                    + URLEncoder.encode(query, StandardCharsets.UTF_8)
                    + "&format=json");
            Map<?, ?> response = wikidata.get()
                    .uri(requestUri)
                    .retrieve()
                    .body(Map.class);
            Map<?, ?> results = map(map(response).get("results"));
            Map<String, PlaceEnrichment> enrichments = new LinkedHashMap<>();
            for (Object row : list(results.get("bindings"))) {
                Map<?, ?> binding = map(row);
                String qid = extractQid(value(binding, "item"));
                String landmarkType = extractQid(value(binding, "landmarkType"));
                GeoPoint coordinates = wikidataPoint(value(binding, "coordinates"));
                if (qid == null
                        || !VERIFIED_LANDMARK_TYPES.contains(landmarkType)
                        || coordinates == null) {
                    continue;
                }
                PlaceEnrichment candidate = new PlaceEnrichment(
                        landmarkType,
                        coordinates.latitude(),
                        coordinates.longitude(),
                        value(binding, "labelEn"),
                        value(binding, "labelAr"),
                        value(binding, "descriptionEn"),
                        value(binding, "descriptionAr"),
                        value(binding, "enwiki"),
                        value(binding, "arwiki"),
                        value(binding, "image"),
                        value(binding, "enWikiImage"),
                        value(binding, "arWikiImage"));
                enrichments.merge(qid, candidate, GeoapifyAttractionService::mergeEnrichment);
            }
            return enrichments;
        } catch (RestClientException exception) {
            String reason = exception instanceof RestClientResponseException response
                    ? "HTTP " + response.getStatusCode().value()
                    : "network or timeout error";
            LOG.warn("Wikidata place enrichment unavailable ({})", reason);
            return Map.of();
        }
    }

    private List<Map<String, Object>> normalize(
            List<Map<?, ?>> features,
            Map<String, PlaceEnrichment> enrichments,
            String requestedCity,
            String requestedCountry,
            String language,
            GeoPoint center) {
        List<Map<String, Object>> places = new ArrayList<>();
        for (Map<?, ?> feature : features) {
            Map<?, ?> properties = properties(feature);
            String qid = wikidataQid(properties);
            PlaceEnrichment enrichment = qid == null ? null : enrichments.get(qid);

            String nameEn = firstNonBlank(
                    enrichment == null ? null : enrichment.labelEn(),
                    text(properties.get("name")),
                    text(map(map(properties.get("datasource")).get("raw")).get("name")));
            String nameAr = firstNonBlank(
                    enrichment == null ? null : enrichment.labelAr(),
                    text(map(map(properties.get("datasource")).get("raw")).get("name:ar")));
            String name = "ar".equals(language)
                    ? firstNonBlank(nameAr, nameEn)
                    : firstNonBlank(nameEn, nameAr);
            if (name == null) name = text(properties.get("address_line1"));
            if (name == null) continue;

            List<String> categories = strings(properties.get("categories"));
            if (!isAllowedLandmarkCategory(categories)) continue;
            String category = normalizeCategory(categories);
            Map<?, ?> raw = map(map(properties.get("datasource")).get("raw"));
            String city = firstNonBlank(
                    text(properties.get("city")),
                    text(properties.get("town")),
                    text(properties.get("village")),
                    text(properties.get("municipality")),
                    requestedCity);
            String country = firstNonBlank(text(properties.get("country")), requestedCountry);
            Double latitude = number(properties.get("lat"));
            Double longitude = number(properties.get("lon"));
            if (latitude == null || longitude == null) {
                List<?> coordinates = list(map(feature.get("geometry")).get("coordinates"));
                if (coordinates.size() >= 2) {
                    longitude = number(coordinates.get(0));
                    latitude = number(coordinates.get(1));
                }
            }
            if (latitude == null || longitude == null) continue;

            String placeId = firstNonBlank(
                    text(properties.get("place_id")),
                    text(raw.get("osm_id")),
                    text(raw.get("id")),
                    latitude + "," + longitude);
            Map<String, Object> place = new LinkedHashMap<>();
            place.put("id", "geoapify:" + placeId);
            place.put("name", name);
            place.put("name_en", nameEn);
            place.put("name_ar", nameAr);
            place.put("city", city);
            place.put("country", country);
            place.put("location", city + ", " + country);
            place.put("category", category);
            place.put("highlight_category", highlightCategory(categories));
            place.put("category_tag", categories.isEmpty()
                    ? category : String.join(", ", categories));
            place.put("source_attribution",
                    "Geoapify · © OpenStreetMap contributors");
            place.put("description", enrichment == null ? "" :
                    firstNonBlank(
                            "ar".equals(language) ? enrichment.descriptionAr()
                                    : enrichment.descriptionEn(),
                            enrichment.descriptionEn(),
                            enrichment.descriptionAr(),
                            ""));
            place.put("rating", 0);
            place.put("review_count", 0);
            place.put("visit_count", 0);
            place.put("country_visit_count", 0);
            place.put("entry_fee", null);
            String imageUrl = enrichment == null ? null : commonsImageUrl(firstNonBlank(
                    enrichment.imageUrl(), enrichment.wikiImage()));
            place.put("image_url", imageUrl);
            place.put("image_source", imageUrl == null ? null : "Wikimedia Commons");
            place.put("opening_hours", firstNonBlank(
                    text(properties.get("opening_hours")),
                    text(raw.get("opening_hours"))));
            place.put("best_time_to_visit", null);
            place.put("latitude", latitude);
            place.put("longitude", longitude);
            place.put("distance_km", distanceKm(properties, center));
            place.put("tags", categories);
            place.put("source_provider", "geoapify");
            place.put("source_attribution", "Geoapify · © OpenStreetMap contributors");
            place.put("wikidata_id", qid);
            place.put("wikipedia_url", enrichment == null ? null :
                    firstNonBlank(
                            "ar".equals(language) ? enrichment.arwiki() : enrichment.enwiki(),
                            enrichment.enwiki(),
                            enrichment.arwiki()));
            places.add(place);
        }

        places.sort((left, right) -> Double.compare(
                distanceValue(left.get("distance_km")),
                distanceValue(right.get("distance_km"))));
        return places;
    }

    private static Double distanceKm(Map<?, ?> properties, GeoPoint center) {
        Double distance = number(properties.get("distance"));
        if (distance != null && distance >= 0) return distance / 1000.0;

        Double latitude = number(properties.get("lat"));
        Double longitude = number(properties.get("lon"));
        if (latitude == null || longitude == null) return null;
        double lat1 = Math.toRadians(center.latitude());
        double lat2 = Math.toRadians(latitude);
        double deltaLat = lat2 - lat1;
        double deltaLon = Math.toRadians(longitude - center.longitude());
        double a = Math.sin(deltaLat / 2) * Math.sin(deltaLat / 2)
                + Math.cos(lat1) * Math.cos(lat2)
                * Math.sin(deltaLon / 2) * Math.sin(deltaLon / 2);
        return 6371.0 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    private static String normalizeCategory(List<String> categories) {
        String joined = String.join(" ", categories).toLowerCase(Locale.ROOT);
        if (joined.contains("museum")) return "museum";
        if (joined.contains("park")) return "park";
        if (joined.contains("historic") || joined.contains("heritage")
                || joined.contains("monument") || joined.contains("archaeological")) {
            return "historical";
        }
        if (joined.contains("tourism.sights.building")) return "architecture";
        return "landmark";
    }

    static boolean isAllowedLandmarkCategory(List<String> categories) {
        String joined = String.join(" ", categories).toLowerCase(Locale.ROOT);
        return joined.contains("tourism.sights")
                || joined.contains("tourism.attraction")
                || joined.contains("entertainment.museum")
                || joined.contains("leisure.park")
                || joined.contains("heritage")
                || joined.contains("historic")
                || joined.contains("monument")
                || joined.contains("archaeological");
    }

    static String classifyProviderFailure(RestClientException exception) {
        if (exception instanceof RestClientResponseException response) {
            return classifyProviderFailure(
                    response.getStatusCode().value(), response.getResponseBodyAsString());
        }
        return "network or timeout error";
    }

    static String classifyProviderFailure(int status, String responseBody) {
        if (status != 400) return "HTTP " + status;
        String safeBody = responseBody == null
                ? ""
                : responseBody.toLowerCase(Locale.ROOT);
        if (safeBody.contains("category")) return "HTTP 400 (category filter rejected)";
        if (safeBody.contains("filter")) return "HTTP 400 (place filter rejected)";
        return "HTTP 400 (provider rejected request)";
    }

    private static String highlightCategory(List<String> categories) {
        String joined = String.join(" ", categories).toLowerCase(Locale.ROOT);
        if (joined.contains("park")) {
            return "Nature";
        }
        if (joined.contains("architecture") || joined.contains("building")
                || joined.contains("church") || joined.contains("cathedral")) {
            return "Architecture";
        }
        if (joined.contains("historic") || joined.contains("historical")
                || joined.contains("ruin") || joined.contains("memorial")
                || joined.contains("monument") || joined.contains("archaeological")
                || joined.contains("heritage")) {
            return "Historical";
        }
        return "Family & Culture";
    }

    private static String commonsImageUrl(String imageUrl) {
        if (imageUrl == null) return null;
        String normalized = imageUrl.trim();
        if (!normalized.startsWith("http://commons.wikimedia.org/wiki/Special:FilePath/")
                && !normalized.startsWith(
                        "https://commons.wikimedia.org/wiki/Special:FilePath/")
                && !normalized.startsWith("https://upload.wikimedia.org/")) {
            return null;
        }
        normalized = normalized.replaceFirst("^http://", "https://");
        if (normalized.contains("Special:FilePath/")) {
            normalized += normalized.contains("?") ? "&width=1200" : "?width=1200";
        }
        return normalized;
    }

    private static boolean sameCountry(String first, String second) {
        return normalizeCountry(first).equals(normalizeCountry(second));
    }

    private static String normalizeCountry(String country) {
        String normalized = country.trim().toLowerCase(Locale.ROOT)
                .replace('ü', 'u')
                .replaceAll("[^a-z0-9]+", " ")
                .trim();
        return switch (normalized) {
            case "turkey", "turkiye" -> "turkiye";
            case "uae", "united arab emirates" -> "uae";
            default -> normalized;
        };
    }

    private static String wikidataQid(Map<?, ?> properties) {
        Map<?, ?> raw = map(map(properties.get("datasource")).get("raw"));
        String candidate = firstNonBlank(
                text(properties.get("wikidata")),
                text(raw.get("wikidata")));
        return extractQid(candidate);
    }

    private static String extractQid(String candidate) {
        if (candidate == null) return null;
        Matcher matcher = WIKIDATA_QID.matcher(candidate.toUpperCase(Locale.ROOT));
        return matcher.find() ? matcher.group() : null;
    }

    private static String value(Map<?, ?> bindings, String key) {
        return text(map(bindings.get(key)).get("value"));
    }

    private static Map<?, ?> properties(Map<?, ?> feature) {
        return map(feature.get("properties"));
    }

    private static Map<?, ?> map(Object value) {
        return value instanceof Map<?, ?> result ? result : Map.of();
    }

    private static List<?> list(Object value) {
        return value instanceof List<?> result ? result : List.of();
    }

    private static List<String> strings(Object value) {
        return list(value).stream().map(GeoapifyAttractionService::text)
                .filter(item -> item != null && !item.isBlank())
                .distinct().toList();
    }

    private static Double number(Object value) {
        if (value instanceof Number number) return number.doubleValue();
        if (value instanceof String string) {
            try {
                return Double.parseDouble(string);
            } catch (NumberFormatException ignored) {
                return null;
            }
        }
        return null;
    }

    private static double distanceValue(Object value) {
        Double number = number(value);
        return number == null ? Double.MAX_VALUE : number;
    }

    private static String text(Object value) {
        if (value == null) return null;
        String result = value.toString().trim();
        return result.isEmpty() ? null : result;
    }

    private static String nonBlank(String value, String fallback) {
        String text = text(value);
        return text == null ? fallback : text;
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            String text = text(value);
            if (text != null) return text;
        }
        return null;
    }

    private record GeoPoint(double latitude, double longitude) {}

    private record PlaceBatch(
            String city, GeoPoint center, List<Map<?, ?>> features) {}

    private record PlaceEnrichment(
            String labelEn,
            String labelAr,
            String descriptionEn,
            String descriptionAr,
            String enwiki,
            String arwiki,
            String imageUrl,
            String wikiImage) {}

    private record CacheEntry(List<Map<String, Object>> places, Instant expiresAt) {}
}

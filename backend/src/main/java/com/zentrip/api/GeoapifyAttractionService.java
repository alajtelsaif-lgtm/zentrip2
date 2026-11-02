package com.zentrip.api;

import java.time.Duration;
import java.time.Instant;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.text.Normalizer;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executor;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
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
    private static final Duration CACHE_TTL = Duration.ofHours(24);
    private static final int PROVIDER_PAGE_SIZE = 250;
    private static final int MAX_PROVIDER_PAGES = 4;
    private static final int MAX_CACHED_RESULTS = 1000;
    private static final Executor PROVIDER_EXECUTOR =
            task -> Thread.ofVirtual().start(task);
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
            "Q35112127", // historic building
            "Q23413",   // castle
            "Q1785071", // fort
            "Q570116",  // tourist attraction
            "Q40080",   // beach
            "Q167346",  // botanical garden
            "Q8502",    // mountain
            "Q46831",   // mountain range
            "Q23397",   // lake
            "Q34038",   // waterfall
            "Q35509",   // cave
            "Q179049"); // nature reserve
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
    private final Map<String, SuggestionCacheEntry> suggestionCache = new ConcurrentHashMap<>();

    @Autowired
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
        return searchAttractionsWithStatus(
                requestedCity, requestedCountry, requestedLanguage, "",
                null, null, null, null, null, null, null);
    }

    public SearchOutcome searchAttractionsWithStatus(
            String requestedCity,
            String requestedCountry,
            String requestedLanguage,
            String requestedCategory,
            Double requestedLatitude,
            Double requestedLongitude,
            Double south,
            Double west,
            Double north,
            Double east,
            String requestedPlaceId) {
        boolean countrySearch = requestedCity == null || requestedCity.isBlank();
        String city = nonBlank(requestedCity, DEFAULT_CITY).trim();
        String country = countrySearch
                ? nonBlank(requestedCountry, DEFAULT_COUNTRY).trim()
                : nonBlank(requestedCountry, "").trim();
        String language = "ar".equalsIgnoreCase(requestedLanguage) ? "ar" : "en";
        String category = nonBlank(requestedCategory, "").trim().toLowerCase(Locale.ROOT);
        if (!apiKey.isBlank() && !hasValidCoordinates(requestedLatitude, requestedLongitude)) {
            // City-only lookups require Geoapify to resolve a provider-backed boundary.
        } else if (apiKey.isBlank() && !hasValidCoordinates(
                requestedLatitude, requestedLongitude)) {
            return new SearchOutcome(
                    List.of(), null, Map.of(), 0,
                    List.of("Geoapify geocoding is unavailable because its key is not configured."),
                    List.of());
        }
        String cacheCity = countrySearch ? "country" : city;
        String cacheKey = (cacheCity + "|" + country + "|" + language + "|" + category
                + "|" + requestedPlaceId + "|" + requestedLatitude + "|" + requestedLongitude
                + "|" + south + "|" + west + "|" + north + "|" + east)
                .toLowerCase(Locale.ROOT);

        CacheEntry previous = cache.get(cacheKey);
        Instant now = Instant.now();
        if (previous != null && now.isBefore(previous.expiresAt())) {
            return new SearchOutcome(
                    previous.places(), previous.cityFound(), previous.droppedByReason(),
                    previous.candidateCount(), previous.warnings(), previous.droppedItems());
        }

        try {
            if (!hasValidCoordinates(requestedLatitude, requestedLongitude)
                    && apiKey.isBlank()) {
                return new SearchOutcome(List.of(), null, Map.of(), 0,
                        List.of("Geoapify geocoding is unavailable because its key is not configured."),
                        List.of());
            }
            List<String> searchCities = countrySearch
                    ? COUNTRY_SEARCH_CITIES.get(country.toLowerCase(Locale.ROOT))
                    : List.of(city);
            if (searchCities == null || searchCities.isEmpty()) {
                cache.put(cacheKey, new CacheEntry(
                        List.of(), null, Map.of(), 0, List.of(), List.of(),
                        now.plus(CACHE_TTL)));
                return new SearchOutcome(List.of(), null, Map.of(), 0, List.of(), List.of());
            }

            List<PlaceBatch> batches = new ArrayList<>();
            List<Map<?, ?>> allFeatures = new ArrayList<>();
            boolean cityGeocoded = false;
            List<String> warnings = new ArrayList<>();
            for (String searchCity : searchCities) {
                try {
                    GeoPoint center = hasValidCoordinates(requestedLatitude, requestedLongitude)
                            ? explicitGeoPoint(
                                    requestedLatitude, requestedLongitude, south, west, north, east,
                                    searchCity, country)
                            : geocode(searchCity, country, language);
                    if (center == null) continue;
                    cityGeocoded = true;
                    CompletableFuture<ProviderResult<List<Map<?, ?>>>> placesFuture =
                            CompletableFuture.supplyAsync(
                                    () -> fetchPlaces(center, language), PROVIDER_EXECUTOR);
                    CompletableFuture<ProviderResult<Map<String, PlaceEnrichment>>> wikidataFuture =
                            CompletableFuture.supplyAsync(
                                    () -> fetchWikidataPlaces(center, language),
                                    PROVIDER_EXECUTOR);
                    ProviderResult<List<Map<?, ?>>> placesResult =
                            providerResult(placesFuture, List.of());
                    ProviderResult<Map<String, PlaceEnrichment>> wikidataResult =
                            providerResult(wikidataFuture, Map.of());
                    allFeatures.addAll(placesResult.value());
                    warnings.addAll(placesResult.warnings());
                    warnings.addAll(wikidataResult.warnings());

                    NormalizationResult geoNormalized = normalize(
                            placesResult.value(), wikidataResult.value(), searchCity,
                            center.countryLabel(), language, center, "geoapify");
                    NormalizationResult wikidataNormalized = normalizeWikidata(
                            wikidataResult.value(), searchCity, center.countryLabel(),
                            language, center);
                    List<RejectedItem> rejected = new ArrayList<>();
                    rejected.addAll(geoNormalized.droppedItems());
                    rejected.addAll(wikidataNormalized.droppedItems());
                    Map<String, Integer> dropped = new LinkedHashMap<>();
                    mergeDropCounts(dropped, geoNormalized.droppedByReason());
                    mergeDropCounts(dropped, wikidataNormalized.droppedByReason());
                    List<Map<String, Object>> merged = mergeProviders(
                            geoNormalized.places(), wikidataNormalized.places(), dropped, rejected);
                    batches.add(new PlaceBatch(
                            searchCity, country, center, merged, dropped, rejected));
                } catch (RestClientException exception) {
                    String reason = classifyProviderFailure(exception);
                    warnings.add("Geoapify destination lookup unavailable.");
                    LOG.warn("Geoapify destination lookup unavailable ({})", reason);
                }
            }

            Map<String, Map<String, Object>> uniquePlaces = new LinkedHashMap<>();
            Map<String, Integer> droppedByReason = new LinkedHashMap<>();
            List<RejectedItem> droppedItems = new ArrayList<>();
            int candidateCount = 0;
            for (PlaceBatch batch : batches) {
                candidateCount += batch.features().size() + batch.droppedItems().size()
                        + batch.droppedByReason().values().stream()
                                .mapToInt(Integer::intValue).sum();
                mergeDropCounts(droppedByReason, batch.droppedByReason());
                droppedItems.addAll(batch.droppedItems());
                for (Map<String, Object> place : batch.features()) {
                    String duplicateKey = deduplicationKey(place);
                    if (findDuplicate(uniquePlaces.values(), place) != null) {
                        addCount(droppedByReason, "duplicate", 1);
                        droppedItems.add(rejected(place, "duplicate", "merged source or duplicate"));
                    } else {
                        uniquePlaces.putIfAbsent(duplicateKey, place);
                    }
                }
            }
            List<Map<String, Object>> places = uniquePlaces.values().stream()
                    .sorted(notabilityComparator())
                    .limit(MAX_CACHED_RESULTS)
                    .toList();
            if (!category.isBlank()) {
                places = places.stream()
                        .filter(place -> category.equals(
                                String.valueOf(place.get("category")).toLowerCase(Locale.ROOT))
                                || category.equals(
                                        String.valueOf(place.get("highlight_category"))
                                                .toLowerCase(Locale.ROOT)))
                        .toList();
            }
            droppedItems.forEach(item -> LOG.debug(
                    "Landmark candidate dropped reason={} source={} name={} id={}",
                    item.reason(), item.source(), item.name(), item.id()));
            List<Map<String, Object>> immutablePlaces = List.copyOf(places);
            Boolean cityFound = countrySearch ? null
                    : cityGeocoded ? true : warnings.isEmpty() ? false : null;
            Map<String, Integer> immutableDroppedByReason = Map.copyOf(droppedByReason);
            cache.put(cacheKey, new CacheEntry(
                    immutablePlaces, cityFound, immutableDroppedByReason,
                    candidateCount, List.copyOf(warnings), List.copyOf(droppedItems),
                    now.plus(CACHE_TTL)));
            return new SearchOutcome(
                    immutablePlaces, cityFound, immutableDroppedByReason, candidateCount,
                    warnings.stream().distinct().toList(), List.copyOf(droppedItems));
        } catch (RestClientException exception) {
            String reason = exception instanceof RestClientResponseException response
                    ? "HTTP " + response.getStatusCode().value()
                    : "network or timeout error";
            LOG.warn("Attraction destination lookup failed ({})", reason);
            return previous == null
                    ? new SearchOutcome(List.of(), null, Map.of(), 0,
                            List.of("Destination lookup is temporarily unavailable."), List.of())
                    : new SearchOutcome(
                            previous.places(), previous.cityFound(), previous.droppedByReason(),
                            previous.candidateCount(), previous.warnings(),
                            previous.droppedItems());
        }
    }

    public List<Map<String, Object>> suggestPlaces(
            String requestedQuery, String requestedLanguage) {
        String query = text(requestedQuery);
        if (apiKey.isBlank() || query == null || query.length() < 2) return List.of();
        String language = "ar".equalsIgnoreCase(requestedLanguage) ? "ar" : "en";
        String cacheKey = query.toLowerCase(Locale.ROOT) + "|" + language;
        Instant now = Instant.now();
        SuggestionCacheEntry cached = suggestionCache.get(cacheKey);
        if (cached != null && now.isBefore(cached.expiresAt())) return cached.suggestions();
        try {
            Map<?, ?> response = geoapify.get()
                    .uri(uri -> uri.path("/v1/geocode/autocomplete")
                            .queryParam("text", query)
                            .queryParam("format", "json")
                            .queryParam("limit", 6)
                            .queryParam("lang", language)
                            .queryParam("apiKey", apiKey)
                            .build())
                    .retrieve()
                    .body(Map.class);
            List<Map<String, Object>> suggestions = new ArrayList<>();
            Set<String> unique = new LinkedHashSet<>();
            for (Object item : list(map(response).get("results"))) {
                Map<?, ?> result = map(item);
                Double latitude = number(result.get("lat"));
                Double longitude = number(result.get("lon"));
                if (latitude == null || longitude == null
                        || !validCoordinates(latitude, longitude)) continue;
                String type = text(result.get("result_type"));
                boolean administrative = Set.of(
                                "country", "state", "county", "city", "town",
                                "village", "municipality", "district", "suburb",
                                "locality")
                        .contains(type == null ? "" : type.toLowerCase(Locale.ROOT));
                List<String> categories = strings(result.get("categories"));
                boolean landmark = isAllowedLandmarkCategory(categories)
                        && wikidataQid(result) != null;
                if (!administrative && !landmark) continue;
                String localizedName = localizedText(result.get("name"), language);
                String city = nonBlank(firstNonBlank(
                        localizedText(result.get("city"), language),
                        localizedText(result.get("town"), language),
                        localizedText(result.get("village"), language),
                        localizedText(result.get("municipality"), language),
                        Set.of("city", "town", "village", "municipality")
                                .contains(type == null ? "" : type.toLowerCase(Locale.ROOT))
                                ? localizedName : null,
                        ""), "");
                String country = firstNonBlank(
                        localizedText(result.get("country"), language), "");
                String label;
                if ("country".equalsIgnoreCase(nonBlank(type, ""))) {
                    label = firstNonBlank(country, localizedName);
                } else if (administrative && !city.isEmpty()) {
                    label = country.isEmpty()
                            ? city
                            : city + ("ar".equals(language) ? "، " : ", ") + country;
                } else {
                    label = firstNonBlank(
                            localizedName,
                            localizedText(result.get("address_line1"), language),
                            localizedText(result.get("formatted"), language));
                }
                if (label == null) continue;
                String key = normalizeName(label) + "|" + normalizeName(city)
                        + "|" + normalizeName(country);
                if (!unique.add(key)) continue;
                Map<String, Object> suggestion = new LinkedHashMap<>();
                suggestion.put("label", label);
                suggestion.put("city", city);
                suggestion.put("country", country);
                suggestion.put("country_code", text(result.get("country_code")));
                suggestion.put("latitude", latitude);
                suggestion.put("longitude", longitude);
                suggestion.put("result_type", type);
                String placeId = text(result.get("place_id"));
                if (placeId != null) suggestion.put("place_id", placeId);
                Bounds resultBounds = bounds(map(result.get("bbox")));
                if (resultBounds != null) {
                    suggestion.put("bbox_south", resultBounds.minLatitude());
                    suggestion.put("bbox_west", resultBounds.minLongitude());
                    suggestion.put("bbox_north", resultBounds.maxLatitude());
                    suggestion.put("bbox_east", resultBounds.maxLongitude());
                }
                suggestions.add(suggestion);
            }
            List<Map<String, Object>> immutableSuggestions = List.copyOf(suggestions);
            suggestionCache.put(
                    cacheKey, new SuggestionCacheEntry(
                            immutableSuggestions, now.plus(Duration.ofMinutes(15))));
            return immutableSuggestions;
        } catch (RestClientException exception) {
            String reason = exception instanceof RestClientResponseException response
                    ? "HTTP " + response.getStatusCode().value()
                    : "network or timeout error";
            LOG.warn("Geoapify attraction suggestions unavailable ({})", reason);
            return cached == null ? List.of() : cached.suggestions();
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
            ProviderResult<List<Map<?, ?>>> geo = fetchPlaces(center, language);
            ProviderResult<Map<String, PlaceEnrichment>> wikidataResult =
                    fetchWikidataPlaces(center, language);
            NormalizationResult geoNormalized = normalize(
                    geo.value(), wikidataResult.value(), city, country, language,
                    center, "geoapify");
            NormalizationResult wikidataNormalized = normalizeWikidata(
                    wikidataResult.value(), city, country, language, center);
            Map<String, Integer> dropped = new LinkedHashMap<>();
            mergeDropCounts(dropped, geoNormalized.droppedByReason());
            mergeDropCounts(dropped, wikidataNormalized.droppedByReason());
            List<RejectedItem> rejected = new ArrayList<>(geoNormalized.droppedItems());
            rejected.addAll(wikidataNormalized.droppedItems());
            List<Map<String, Object>> merged = mergeProviders(
                    geoNormalized.places(), wikidataNormalized.places(), dropped, rejected);
            List<Map<String, Object>> places = merged.stream()
                    .sorted(notabilityComparator()).limit(40).toList();
            cache.put(cacheKey, new CacheEntry(
                    places, null, dropped,
                    geo.value().size() + wikidataResult.value().size(),
                    mergeWarnings(geo.warnings(), wikidataResult.warnings()),
                    rejected,
                    now.plus(CACHE_TTL)));
            return places;
        } catch (RestClientException exception) {
            LOG.warn("Geoapify coordinate landmark lookup unavailable.");
            return previous == null ? List.of() : previous.places();
        }
    }

    @SuppressWarnings("unchecked")
    private GeoPoint geocode(String city, String country, String language) {
        String countryCode = country == null || country.isBlank()
                ? null
                : country.trim().matches("(?i)^[a-z]{2}$")
                        ? country.toLowerCase(Locale.ROOT)
                        : COUNTRY_CODES.get(normalizeCountry(country));
        Map<?, ?> response = geoapify.get()
                .uri(uri -> uri.path("/v1/geocode/search")
                        .queryParam("text", countryCode != null || country == null
                                || country.isBlank() ? city : city + ", " + country)
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
        String resultCountryCode = text(result.get("country_code"));
        if (countryCode != null && resultCountryCode != null) {
            if (!countryCode.equalsIgnoreCase(resultCountryCode)) return null;
        } else if (geocodedCountry != null && country != null && !country.isBlank()
                && !sameCountry(geocodedCountry, country)) {
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
                firstNonBlank(geocodedCountry, country, ""),
                firstNonBlank(resultCountryCode, countryCode));
    }

    @SuppressWarnings("unchecked")
    private List<Map<?, ?>> fetchPlaces(GeoPoint center, String language) {
        Map<?, ?> response = geoapify.get()
                .uri(uri -> uri.path("/v2/places")
                        .queryParam("categories",
                                "tourism.sights,tourism.attraction,entertainment.museum,"
                                        + "leisure.park,leisure.park.garden,beach,"
                                        + "heritage,building.historic")
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
                    wd:Q11303 wd:Q174782 wd:Q40080 wd:Q167346
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

    private NormalizationResult normalize(
            List<Map<?, ?>> features,
            Map<String, PlaceEnrichment> enrichments,
            String requestedCity,
            String requestedCountry,
            String language,
            GeoPoint center) {
        List<Map<String, Object>> places = new ArrayList<>();
        Map<String, Integer> droppedByReason = new LinkedHashMap<>();
        for (Map<?, ?> feature : features) {
            Map<?, ?> properties = properties(feature);
            String qid = wikidataQid(properties);
            PlaceEnrichment enrichment = qid == null ? null : enrichments.get(qid);
            List<String> categories = strings(properties.get("categories"));
            if (!isAllowedLandmarkCategory(categories)) {
                addCount(droppedByReason, categories.isEmpty()
                        ? "missing_or_unclassified_category"
                        : "category_not_in_landmark_allowlist", 1);
                continue;
            }
            Map<?, ?> raw = map(map(properties.get("datasource")).get("raw"));
            if (qid == null) {
                addCount(droppedByReason, "missing_wikidata_id", 1);
                continue;
            }
            if (enrichment == null) {
                addCount(droppedByReason, "wikidata_type_or_coordinates_unverified", 1);
                continue;
            }

            Double latitude = number(properties.get("lat"));
            Double longitude = number(properties.get("lon"));
            if (latitude == null || longitude == null) {
                List<?> coordinates = list(map(feature.get("geometry")).get("coordinates"));
                if (coordinates.size() >= 2) {
                    longitude = number(coordinates.get(0));
                    latitude = number(coordinates.get(1));
                }
            }
            if (latitude == null || longitude == null
                    || !validCoordinates(latitude, longitude)
                    || !withinSearchArea(latitude, longitude, center)
                    || !withinSearchArea(
                            enrichment.latitude(), enrichment.longitude(), center)) {
                addCount(droppedByReason, "invalid_or_out_of_city_coordinates", 1);
                continue;
            }

            String featureCountryCode = text(properties.get("country_code"));
            if (center.countryCode() != null && featureCountryCode != null
                    && !center.countryCode().equalsIgnoreCase(featureCountryCode)) {
                addCount(droppedByReason, "outside_selected_country", 1);
                continue;
            }
            String featureCountry = text(properties.get("country"));
            if (center.countryCode() == null && featureCountry != null
                    && requestedCountry != null
                    && !sameCountry(featureCountry, requestedCountry)) {
                addCount(droppedByReason, "outside_selected_country", 1);
                continue;
            }

            String nameEn = firstNonBlank(
                    enrichment.labelEn(),
                    englishText(properties.get("name")),
                    englishText(raw.get("name")));
            String nameAr = firstNonBlank(
                    arabicText(enrichment.labelAr()),
                    arabicText(raw.get("name:ar")),
                    arabicText(properties.get("name")));
            String name = "ar".equals(language) ? nameAr : nameEn;
            if (name == null) {
                addCount(droppedByReason, "missing_requested_language_label", 1);
                continue;
            }

            String city = firstNonBlank(
                    localizedText(properties.get("city"), language),
                    localizedText(properties.get("town"), language),
                    localizedText(properties.get("village"), language),
                    localizedText(properties.get("municipality"), language),
                    localizedText(center.cityLabel(), language),
                    localizedText(requestedCity, language),
                    "");
            String country = firstNonBlank(
                    localizedText(featureCountry, language),
                    localizedText(center.countryLabel(), language),
                    localizedText(requestedCountry, language),
                    "");
            String category = normalizeCategory(categories);
            String imageUrl = commonsImageUrl(firstNonBlank(
                    enrichment.imageUrl(),
                    "ar".equals(language)
                            ? enrichment.arWikiImage() : enrichment.enWikiImage(),
                    enrichment.enWikiImage(),
                    enrichment.arWikiImage()));
            String wikipediaUrl = "ar".equals(language)
                    ? enrichment.arwiki() : enrichment.enwiki();

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
            place.put("location", locationLabel(city, country));
            place.put("category", category);
            place.put("highlight_category", highlightCategory(categories));
            place.put("category_tag", category);
            place.put("source_attribution", "ar".equals(language)
                    ? "Geoapify · مساهمو OpenStreetMap"
                    : "Geoapify · © OpenStreetMap contributors");
            place.put("description", "ar".equals(language)
                    ? firstNonBlank(enrichment.descriptionAr(), "")
                    : firstNonBlank(enrichment.descriptionEn(), ""));
            place.put("rating", 0);
            place.put("review_count", 0);
            place.put("visit_count", 0);
            place.put("country_visit_count", 0);
            place.put("entry_fee", null);
            place.put("image_url", imageUrl);
            place.put("image_source", imageUrl == null ? null : "Wikimedia Commons");
            place.put("opening_hours", firstNonBlank(
                    text(properties.get("opening_hours")),
                    text(raw.get("opening_hours"))));
            place.put("best_time_to_visit", null);
            place.put("latitude", latitude);
            place.put("longitude", longitude);
            Double distanceMeters = number(properties.get("distance"));
            place.put("distance_km", distanceMeters != null && distanceMeters >= 0
                    ? distanceMeters / 1000.0
                    : distanceBetween(
                            latitude, longitude, center.latitude(), center.longitude()));
            place.put("tags", List.of(category));
            place.put("source_provider", "geoapify");
            place.put("wikidata_id", qid);
            place.put("wikipedia_url", wikipediaUrl);
            places.add(place);
        }

        places.sort((left, right) -> Double.compare(
                distanceValue(left.get("distance_km")),
                distanceValue(right.get("distance_km"))));
        return new NormalizationResult(List.copyOf(places), Map.copyOf(droppedByReason));
    }

    private static Bounds bounds(Map<?, ?> value) {
        Double lat1 = number(value.get("lat1"));
        Double lat2 = number(value.get("lat2"));
        Double lon1 = number(value.get("lon1"));
        Double lon2 = number(value.get("lon2"));
        if (lat1 == null || lat2 == null || lon1 == null || lon2 == null
                || !validCoordinates(lat1, lon1) || !validCoordinates(lat2, lon2)) {
            return null;
        }
        return new Bounds(
                Math.min(lat1, lat2), Math.max(lat1, lat2),
                Math.min(lon1, lon2), Math.max(lon1, lon2));
    }

    private static String placeFilter(GeoPoint center) {
        Bounds area = center.bounds();
        if (area == null) {
            return "circle:" + center.longitude() + "," + center.latitude() + ",25000";
        }
        return "rect:" + area.minLongitude() + "," + area.minLatitude()
                + "," + area.maxLongitude() + "," + area.maxLatitude();
    }

    private static boolean withinSearchArea(
            double latitude, double longitude, GeoPoint center) {
        if (!validCoordinates(latitude, longitude)) return false;
        Bounds area = center.bounds();
        return area == null
                ? distanceBetween(latitude, longitude, center.latitude(), center.longitude()) <= 25
                : area.contains(latitude, longitude);
    }

    private static boolean validCoordinates(double latitude, double longitude) {
        return Double.isFinite(latitude) && Double.isFinite(longitude)
                && latitude >= -90 && latitude <= 90
                && longitude >= -180 && longitude <= 180;
    }

    private static double distanceBetween(
            double firstLatitude, double firstLongitude,
            double secondLatitude, double secondLongitude) {
        double lat1 = Math.toRadians(firstLatitude);
        double lat2 = Math.toRadians(secondLatitude);
        double deltaLat = lat2 - lat1;
        double deltaLon = Math.toRadians(secondLongitude - firstLongitude);
        double a = Math.sin(deltaLat / 2) * Math.sin(deltaLat / 2)
                + Math.cos(lat1) * Math.cos(lat2)
                * Math.sin(deltaLon / 2) * Math.sin(deltaLon / 2);
        return 6371.0 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    private static String deduplicationKey(Map<String, Object> place) {
        String name = normalizeName(text(place.get("name")));
        double latitude = number(place.get("latitude")) == null
                ? 0 : number(place.get("latitude"));
        double longitude = number(place.get("longitude")) == null
                ? 0 : number(place.get("longitude"));
        return name + "|" + String.format(Locale.ROOT, "%.4f|%.4f", latitude, longitude);
    }

    private static String normalizeName(String value) {
        if (value == null) return "";
        return Normalizer.normalize(value, Normalizer.Form.NFD)
                .replaceAll("\\p{M}+", "")
                .toLowerCase(Locale.ROOT)
                .replaceAll("[^\\p{L}\\p{N}]+", " ")
                .trim()
                .replaceAll("\\s+", " ");
    }

    private static String locationLabel(String city, String country) {
        return Stream.of(city, country)
                .filter(value -> value != null && !value.isBlank())
                .reduce((left, right) -> left + ", " + right)
                .orElse("");
    }

    private static String normalizeCategory(List<String> categories) {
        String joined = String.join(" ", categories).toLowerCase(Locale.ROOT);
        if (joined.contains("beach")) return "beach";
        if (joined.contains("museum")) return "museum";
        if (joined.contains("park") || joined.contains("garden")) return "park";
        if (joined.contains("architecture")
                || joined.contains("tourism.sights.building")) return "architecture";
        if (joined.contains("historic") || joined.contains("heritage")
                || joined.contains("monument") || joined.contains("archaeological")) {
            return "historical";
        }
        return "landmark";
    }

    static boolean isAllowedLandmarkCategory(List<String> categories) {
        String joined = String.join(" ", categories).toLowerCase(Locale.ROOT);
        if (categories.stream().map(value -> value.toLowerCase(Locale.ROOT))
                .anyMatch(category -> category.startsWith("catering.")
                        || category.startsWith("commercial.")
                        || category.startsWith("catering")
                        || category.startsWith("commercial")
                        || category.startsWith("shop")
                        || category.startsWith("office")
                        || category.startsWith("accommodation.")
                        || category.contains("restaurant")
                        || category.contains("cafe")
                        || category.contains("market")
                        || category.contains("shopping"))) {
            return false;
        }
        return joined.contains("tourism.sights")
                || joined.contains("tourism.attraction")
                || joined.contains("entertainment.museum")
                || joined.contains("leisure.park")
                || joined.contains("leisure.park.garden")
                || joined.contains("tourism.sights.beach")
                || joined.contains("heritage")
                || joined.contains("historic")
                || joined.contains("monument")
                || joined.contains("archaeological")
                || joined.contains("beach");
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
        if (joined.contains("beach")) {
            return "Nature";
        }
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
            normalized = normalized.replaceAll("([?&])width=[^&]*", "$1")
                    .replaceAll("[?&]$", "");
            normalized += normalized.contains("?") ? "&width=1200" : "?width=1200";
        } else {
            try {
                URI imageUri = URI.create(normalized);
                String[] segments = imageUri.getRawPath().split("/");
                int thumb = -1;
                for (int index = 0; index < segments.length; index++) {
                    if ("thumb".equals(segments[index])) {
                        thumb = index;
                        break;
                    }
                }
                int fileIndex = thumb >= 0 ? thumb + 3 : segments.length - 1;
                if (fileIndex < 0 || fileIndex >= segments.length
                        || segments[fileIndex].isBlank()) return null;
                normalized = "https://commons.wikimedia.org/wiki/Special:FilePath/"
                        + segments[fileIndex] + "?width=1200";
            } catch (IllegalArgumentException ignored) {
                return null;
            }
        }
        return normalized;
    }

    private static String localizedText(Object value, String language) {
        String normalized = text(value);
        if (normalized == null) return null;
        return "ar".equals(language) ? arabicText(normalized) : englishText(normalized);
    }

    private static String arabicText(Object value) {
        String normalized = text(value);
        if (normalized == null) return null;
        return hasOnlyLettersInScript(normalized, Character.UnicodeScript.ARABIC)
                ? normalized : null;
    }

    private static String englishText(Object value) {
        String normalized = text(value);
        if (normalized == null) return null;
        return hasOnlyLettersInScript(normalized, Character.UnicodeScript.LATIN)
                ? normalized : null;
    }

    private static boolean hasOnlyLettersInScript(
            String value, Character.UnicodeScript expectedScript) {
        boolean hasLetter = false;
        for (int codePoint : value.codePoints().toArray()) {
            if (!Character.isLetter(codePoint)) continue;
            hasLetter = true;
            if (Character.UnicodeScript.of(codePoint) != expectedScript) return false;
        }
        return hasLetter;
    }

    private static GeoPoint wikidataPoint(String value) {
        if (value == null) return null;
        Matcher matcher = WIKIDATA_POINT.matcher(value);
        if (!matcher.find()) return null;
        try {
            double longitude = Double.parseDouble(matcher.group(1));
            double latitude = Double.parseDouble(matcher.group(2));
            return validCoordinates(latitude, longitude)
                    ? new GeoPoint(latitude, longitude, null, null, null, null)
                    : null;
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static PlaceEnrichment mergeEnrichment(
            PlaceEnrichment first, PlaceEnrichment next) {
        return new PlaceEnrichment(
                first.landmarkType(),
                first.latitude(),
                first.longitude(),
                firstNonBlank(first.labelEn(), next.labelEn()),
                firstNonBlank(first.labelAr(), next.labelAr()),
                firstNonBlank(first.descriptionEn(), next.descriptionEn()),
                firstNonBlank(first.descriptionAr(), next.descriptionAr()),
                firstNonBlank(first.enwiki(), next.enwiki()),
                firstNonBlank(first.arwiki(), next.arwiki()),
                firstNonBlank(first.imageUrl(), next.imageUrl()),
                firstNonBlank(first.enWikiImage(), next.enWikiImage()),
                firstNonBlank(first.arWikiImage(), next.arWikiImage()));
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

    private static void addCount(
            Map<String, Integer> counts, String reason, int count) {
        if (count > 0) counts.merge(reason, count, Integer::sum);
    }

    public record SearchOutcome(
            List<Map<String, Object>> places,
            Boolean cityFound,
            Map<String, Integer> droppedByReason,
            int candidateCount,
            List<String> warnings,
            List<RejectedItem> droppedItems) {
        public SearchOutcome(List<Map<String, Object>> places, Boolean cityFound) {
            this(places, cityFound, Map.of(), 0, List.of(), List.of());
        }

        public SearchOutcome(
                List<Map<String, Object>> places,
                Boolean cityFound,
                Map<String, Integer> droppedByReason) {
            this(places, cityFound, droppedByReason, 0, List.of(), List.of());
        }

        public SearchOutcome(
                List<Map<String, Object>> places,
                Boolean cityFound,
                Map<String, Integer> droppedByReason,
                int candidateCount) {
            this(places, cityFound, droppedByReason, candidateCount, List.of(), List.of());
        }

        public SearchOutcome {
            places = List.copyOf(places);
            droppedByReason = Map.copyOf(droppedByReason);
            warnings = List.copyOf(warnings);
            droppedItems = List.copyOf(droppedItems);
        }
    }

    public record RejectedItem(String name, String id, String category, String source, String reason) {}

    public record DestinationBounds(
            Double south, Double west, Double north, Double east) {}

    record LandmarkValidation(boolean accepted, String reason) {}

    private record GeoPoint(
            double latitude,
            double longitude,
            Bounds bounds,
            String cityLabel,
            String countryLabel,
            String countryCode) {}

    private record Bounds(
            double minLatitude,
            double maxLatitude,
            double minLongitude,
            double maxLongitude) {
        boolean contains(double latitude, double longitude) {
            return latitude >= minLatitude && latitude <= maxLatitude
                    && longitude >= minLongitude && longitude <= maxLongitude;
        }
    }

    private record PlaceBatch(
            String city,
            String country,
            GeoPoint location,
            List<Map<String, Object>> features,
            Map<String, Integer> droppedByReason,
            List<RejectedItem> droppedItems,
            int candidateCount) {}

    private record NormalizationResult(
            List<Map<String, Object>> places,
            Map<String, Integer> droppedByReason,
            List<RejectedItem> droppedItems) {}

    private record PlaceEnrichment(
            String landmarkType,
            double latitude,
            double longitude,
            String labelEn,
            String labelAr,
            String descriptionEn,
            String descriptionAr,
            String enwiki,
            String arwiki,
            String imageUrl,
            String enWikiImage,
            String arWikiImage,
            int sitelinks) {}

    private record CacheEntry(
            List<Map<String, Object>> places,
            Boolean cityFound,
            Map<String, Integer> droppedByReason,
            int candidateCount,
            List<String> warnings,
            List<RejectedItem> droppedItems,
            Instant expiresAt) {}

    private record SuggestionCacheEntry(
            List<Map<String, Object>> suggestions, Instant expiresAt) {}

    private record ProviderResult<T>(T value, List<String> warnings) {
        private ProviderResult {
            warnings = List.copyOf(warnings);
        }
    }
}

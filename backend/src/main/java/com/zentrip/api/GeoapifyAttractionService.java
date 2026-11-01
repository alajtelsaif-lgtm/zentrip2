package com.zentrip.api;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
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
    private static final String DEFAULT_CITY = "Tripoli";
    private static final String DEFAULT_COUNTRY = "Libya";

    private final String apiKey;
    private final RestClient geoapify;
    private final RestClient wikidata;
    private final Map<String, CacheEntry> cache = new ConcurrentHashMap<>();

    public GeoapifyAttractionService(@Value("${geoapify.api-key:}") String apiKey) {
        this.apiKey = apiKey == null ? "" : apiKey.trim();

        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(3));
        requestFactory.setReadTimeout(Duration.ofSeconds(5));

        this.geoapify = RestClient.builder()
                .baseUrl("https://api.geoapify.com")
                .requestFactory(requestFactory)
                .build();
        this.wikidata = RestClient.builder()
                .baseUrl("https://query.wikidata.org")
                .requestFactory(requestFactory)
                .defaultHeader("User-Agent", "ZentripPOI/1.0 (https://zentrip.ly)")
                .defaultHeader("Accept", "application/sparql-results+json")
                .build();
    }

    public List<Map<String, Object>> searchAttractions(
            String requestedCity, String requestedCountry, String requestedLanguage) {
        if (apiKey.isBlank()) return List.of();

        String city = nonBlank(requestedCity, DEFAULT_CITY).trim();
        String country = nonBlank(requestedCountry, DEFAULT_COUNTRY).trim();
        String language = "ar".equalsIgnoreCase(requestedLanguage) ? "ar" : "en";
        String cacheKey = (city + "|" + country + "|" + language).toLowerCase(Locale.ROOT);

        CacheEntry previous = cache.get(cacheKey);
        Instant now = Instant.now();
        if (previous != null && now.isBefore(previous.expiresAt())) {
            return previous.places();
        }

        try {
            GeoPoint center = geocode(city, country);
            if (center == null) {
                cache.put(cacheKey, new CacheEntry(List.of(), now.plus(CACHE_TTL)));
                return List.of();
            }

            List<Map<?, ?>> features = fetchPlaces(center, language);
            Map<String, PlaceEnrichment> enrichments = fetchWikidataEnrichment(features);
            List<Map<String, Object>> places = normalize(
                    features, enrichments, city, country, language, center);
            List<Map<String, Object>> immutablePlaces = List.copyOf(places);
            cache.put(cacheKey, new CacheEntry(immutablePlaces, now.plus(CACHE_TTL)));
            return immutablePlaces;
        } catch (RestClientException exception) {
            String reason = exception instanceof RestClientResponseException response
                    ? "HTTP " + response.getStatusCode().value()
                    : "network or timeout error";
            LOG.warn("Geoapify attraction search failed ({})", reason);
            return previous == null ? List.of() : previous.places();
        }
    }

    @SuppressWarnings("unchecked")
    private GeoPoint geocode(String city, String country) {
        Map<?, ?> response = geoapify.get()
                .uri(uri -> uri.path("/v1/geocode/search")
                        .queryParam("text", city + ", " + country)
                        .queryParam("format", "json")
                        .queryParam("limit", 1)
                        .queryParam("apiKey", apiKey)
                        .build())
                .retrieve()
                .body(Map.class);
        List<?> results = list(map(response).get("results"));
        if (results.isEmpty()) return null;

        Map<?, ?> result = map(results.getFirst());
        Double latitude = number(result.get("lat"));
        Double longitude = number(result.get("lon"));
        if (latitude == null || longitude == null
                || latitude < -90 || latitude > 90
                || longitude < -180 || longitude > 180) {
            return null;
        }
        return new GeoPoint(latitude, longitude);
    }

    @SuppressWarnings("unchecked")
    private List<Map<?, ?>> fetchPlaces(GeoPoint center, String language) {
        Map<?, ?> response = geoapify.get()
                .uri(uri -> uri.path("/v2/places")
                        .queryParam("categories", "tourism.sights,tourism.attraction")
                        .queryParam("filter", "circle:" + center.longitude()
                                + "," + center.latitude() + ",25000")
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
                SELECT ?item ?labelEn ?labelAr ?descriptionEn ?descriptionAr ?enwiki ?arwiki
                WHERE {
                  VALUES ?item { %s }
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
                }
                """.formatted(values);

        try {
            Map<?, ?> response = wikidata.get()
                    .uri(uri -> uri.path("/sparql")
                            .queryParam("query", query)
                            .queryParam("format", "json")
                            .build())
                    .retrieve()
                    .body(Map.class);
            Map<?, ?> results = map(map(response).get("results"));
            Map<String, PlaceEnrichment> enrichments = new LinkedHashMap<>();
            for (Object row : list(results.get("bindings"))) {
                Map<?, ?> binding = map(row);
                String qid = extractQid(value(binding, "item"));
                if (qid == null) continue;
                enrichments.put(qid, new PlaceEnrichment(
                        value(binding, "labelEn"),
                        value(binding, "labelAr"),
                        value(binding, "descriptionEn"),
                        value(binding, "descriptionAr"),
                        value(binding, "enwiki"),
                        value(binding, "arwiki")));
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
            place.put("category_tag", categories.isEmpty()
                    ? category : String.join(", ", categories));
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
            place.put("image_url", null);
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
        if (joined.contains("beach")) return "beach";
        if (joined.contains("historic")) return "historical";
        if (joined.contains("natural")) return "natural";
        if (joined.contains("architecture")) return "architecture";
        return "landmark";
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

    private record PlaceEnrichment(
            String labelEn,
            String labelAr,
            String descriptionEn,
            String descriptionAr,
            String enwiki,
            String arwiki) {}

    private record CacheEntry(List<Map<String, Object>> places, Instant expiresAt) {}
}

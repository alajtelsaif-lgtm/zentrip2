package com.zentrip.api;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

@Service
public class GeoapifyAirportService {
    private static final Logger LOG = LoggerFactory.getLogger(GeoapifyAirportService.class);
    private static final Duration CACHE_TTL = Duration.ofMinutes(30);
    private static final int SEARCH_RADIUS_METERS = 50_000;

    private final String apiKey;
    private final RestClient geoapify;
    private final Map<String, CacheEntry> cache = new ConcurrentHashMap<>();
    private final Map<String, LocationCacheEntry> locationCache = new ConcurrentHashMap<>();

    public GeoapifyAirportService(@Value("${geoapify.api-key:}") String apiKey) {
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(3));
        requestFactory.setReadTimeout(Duration.ofSeconds(5));
        this.geoapify = RestClient.builder()
                .baseUrl("https://api.geoapify.com")
                .requestFactory(requestFactory)
                .build();
    }

    public List<Map<String, Object>> search(String requestedQuery) {
        String query = requestedQuery == null ? "" : requestedQuery.trim();
        if (apiKey.isBlank() || query.length() < 2) return List.of();

        String cacheKey = query.toLowerCase(Locale.ROOT);
        CacheEntry previous = cache.get(cacheKey);
        Instant now = Instant.now();
        if (previous != null && now.isBefore(previous.expiresAt())) {
            return previous.airports();
        }

        try {
            GeocodedPlace geocoded = resolveLocation(query);
            if (geocoded == null) {
                cache.put(cacheKey, new CacheEntry(List.of(), now.plus(CACHE_TTL)));
                return List.of();
            }
            double latitude = geocoded.latitude();
            double longitude = geocoded.longitude();

            Map<?, ?> placesResponse = geoapify.get()
                    .uri(uri -> uri.path("/v2/places")
                            .queryParam("categories", "airport")
                            .queryParam("filter", "circle:" + longitude + ","
                                    + latitude + "," + SEARCH_RADIUS_METERS)
                            .queryParam("bias", "proximity:" + longitude + "," + latitude)
                            .queryParam("limit", 20)
                            .queryParam("lang", "en")
                            .queryParam("apiKey", apiKey)
                            .build())
                    .retrieve()
                    .body(Map.class);

            Map<String, Map<String, Object>> unique = new LinkedHashMap<>();
            for (Object feature : list(map(placesResponse).get("features"))) {
                Map<?, ?> properties = map(map(feature).get("properties"));
                Map<?, ?> raw = map(map(properties.get("datasource")).get("raw"));
                String categories = String.join(
                        " ", list(properties.get("categories"))
                                .stream().map(GeoapifyAirportService::text)
                                .filter(value -> value != null)
                                .toList())
                        .toLowerCase(Locale.ROOT);
                if (categories.contains("military")
                        || categories.contains("private")
                        || categories.contains("helipad")) {
                    continue;
                }
                String placeId = firstNonBlank(
                        text(properties.get("place_id")),
                        text(raw.get("osm_id")),
                        text(raw.get("id")));
                if (placeId == null) continue;

                String code = firstNonBlank(
                        text(raw.get("iata")),
                        text(properties.get("iata")));
                if (code == null || !code.matches("(?i)[A-Z]{3}")) continue;
                code = code.toUpperCase(Locale.ROOT);

                String airportName = firstNonBlank(
                        text(properties.get("name")),
                        text(properties.get("address_line1")),
                        text(raw.get("name")));
                if (airportName == null) continue;
                String normalizedName = airportName.toLowerCase(Locale.ROOT);
                if (normalizedName.contains("aerodrome")
                        || normalizedName.contains("airfield")
                        || normalizedName.contains("air park")
                        || normalizedName.contains("air base")
                        || normalizedName.startsWith("raf ")
                        || normalizedName.contains("helipad")
                        || normalizedName.contains("heliport")) {
                    continue;
                }
                String city = firstNonBlank(
                        geocoded.city(),
                        text(properties.get("city")),
                        text(properties.get("town")),
                        text(properties.get("village")),
                        text(properties.get("municipality")),
                        query);
                String country = firstNonBlank(
                        text(properties.get("country")),
                        geocoded.country(),
                        "");
                String region = firstNonBlank(
                        text(properties.get("state")),
                        text(properties.get("state_code")),
                        geocoded.region(),
                        "");

                Map<String, Object> airport = new LinkedHashMap<>();
                airport.put("code", code);
                airport.put("city", city);
                airport.put("airport_name", airportName);
                airport.put("country", country);
                airport.put("region", region);
                airport.put("latitude", number(properties.get("lat")));
                airport.put("longitude", number(properties.get("lon")));
                airport.put("icao_code", firstNonBlank(
                        text(raw.get("icao")),
                        text(raw.get("icao_code"))));
                airport.put("is_major", categories.contains("large_airport"));
                airport.put("airport_type", "provider");
                airport.put("scheduled_service", null);
                airport.put("source_provider", "geoapify");
                unique.putIfAbsent(code, airport);
            }

            List<Map<String, Object>> airports = List.copyOf(unique.values());
            cache.put(cacheKey, new CacheEntry(airports, now.plus(CACHE_TTL)));
            return airports;
        } catch (RestClientException exception) {
            String reason = exception instanceof RestClientResponseException response
                    ? "HTTP " + response.getStatusCode().value()
                    : "network or timeout error";
            LOG.warn("Geoapify airport search failed ({})", reason);
            return previous == null ? List.of() : previous.airports();
        }
    }

    public GeocodedPlace resolveLocation(String requestedQuery) {
        return resolveLocation(requestedQuery, "");
    }

    public GeocodedPlace resolveLocation(String requestedQuery, String countryCode) {
        return resolveLocation(requestedQuery, countryCode, null);
    }

    public GeocodedPlace resolveCity(String requestedQuery, String countryCode) {
        return resolveLocation(requestedQuery, countryCode, "city");
    }

    private GeocodedPlace resolveLocation(
            String requestedQuery, String countryCode, String resultType) {
        String query = requestedQuery == null ? "" : requestedQuery.trim();
        if (apiKey.isBlank() || query.length() < 2) return null;

        String filterCountry = countryCode == null ? ""
                : countryCode.trim().toLowerCase(Locale.ROOT);
        if (!filterCountry.isEmpty() && !filterCountry.matches("[a-z]{2}")) return null;
        String cacheKey = query.toLowerCase(Locale.ROOT) + "|" + filterCountry
                + "|" + (resultType == null ? "" : resultType);
        LocationCacheEntry previous = locationCache.get(cacheKey);
        Instant now = Instant.now();
        if (previous != null && now.isBefore(previous.expiresAt())) {
            return previous.place();
        }

        try {
            Map<?, ?> response = geoapify.get()
                    .uri(uri -> {
                        var builder = uri.path("/v1/geocode/search")
                            .queryParam("text", query)
                            .queryParam("format", "json")
                            .queryParam("limit", 1)
                            .queryParam("apiKey", apiKey);
                        if (resultType != null && !resultType.isBlank()) {
                            builder.queryParam("type", resultType);
                        }
                        if (!filterCountry.isBlank()) {
                            builder.queryParam("filter", "countrycode:" + filterCountry);
                        }
                        return builder.build();
                    })
                    .retrieve()
                    .body(Map.class);
            List<?> results = list(map(response).get("results"));
            if (results.isEmpty()) {
                locationCache.put(cacheKey, new LocationCacheEntry(null, now.plus(CACHE_TTL)));
                return null;
            }

            Map<?, ?> result = map(results.getFirst());
            Double latitude = number(result.get("lat"));
            Double longitude = number(result.get("lon"));
            if (latitude == null || longitude == null
                    || latitude < -90 || latitude > 90
                    || longitude < -180 || longitude > 180) {
                return null;
            }
            Map<?, ?> raw = map(map(result.get("datasource")).get("raw"));
            GeocodedPlace place = new GeocodedPlace(
                    firstNonBlank(text(result.get("name")),
                            text(result.get("address_line1")), query),
                    firstNonBlank(text(result.get("city")), text(result.get("town")),
                            text(result.get("village")), text(result.get("municipality"))),
                    text(result.get("country")),
                    firstNonBlank(text(result.get("country_code")),
                            text(result.get("country_code_iso3166_1"))),
                    firstNonBlank(text(result.get("state")),
                            text(result.get("state_code"))),
                    text(result.get("formatted")),
                    text(result.get("result_type")),
                    firstNonBlank(text(result.get("place_id")), text(raw.get("osm_id"))),
                    firstNonBlank(text(result.get("wikidata")), text(raw.get("wikidata"))),
                    latitude,
                    longitude);
            locationCache.put(cacheKey, new LocationCacheEntry(place, now.plus(CACHE_TTL)));
            return place;
        } catch (RestClientException exception) {
            String reason = exception instanceof RestClientResponseException response
                    ? "HTTP " + response.getStatusCode().value()
                    : "network or timeout error";
            LOG.warn("Geoapify location resolution failed ({})", reason);
            return previous == null ? null : previous.place();
        }
    }

    private static Map<?, ?> map(Object value) {
        return value instanceof Map<?, ?> result ? result : Map.of();
    }

    private static List<?> list(Object value) {
        return value instanceof List<?> result ? result : List.of();
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

    private static String text(Object value) {
        if (value == null) return null;
        String result = value.toString().trim();
        return result.isEmpty() ? null : result;
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            String text = text(value);
            if (text != null) return text;
        }
        return null;
    }

    private record CacheEntry(List<Map<String, Object>> airports, Instant expiresAt) {}

    private record LocationCacheEntry(GeocodedPlace place, Instant expiresAt) {}

    public record GeocodedPlace(
            String name,
            String city,
            String country,
            String countryCode,
            String region,
            String formattedAddress,
            String resultType,
            String placeId,
            String wikidataId,
            double latitude,
            double longitude) {}
}

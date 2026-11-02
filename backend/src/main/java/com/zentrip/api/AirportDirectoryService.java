package com.zentrip.api;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.BadSqlGrammarException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.sql.SQLException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;

@Service
public class AirportDirectoryService {
    private static final Logger LOG = LoggerFactory.getLogger(AirportDirectoryService.class);
    private static final int DEFAULT_LIMIT = 50;
    private static final int COUNTRY_LIMIT = 1_000;
    private static final int NEAREST_LIMIT = 5;
    private static final Pattern AIRPORT_CODE = Pattern.compile("(?i)^[a-z]{3,4}$");

    private static final String AIRPORT_COLUMNS = """
            TRIM(code) AS code, TRIM(icao_code) AS icao_code, city, airport_name,
            country, region, latitude, longitude, airport_type, is_major,
            scheduled_service, TRIM(iso_country) AS iso_country, keywords,
            wikipedia_link, source_provider
            """;
    private static final String AIRPORT_ORDER = """
            ORDER BY is_major DESC,
                     CASE airport_type
                       WHEN 'large_airport' THEN 0
                       WHEN 'medium_airport' THEN 1
                       WHEN 'small_airport' THEN 2
                       ELSE 3
                     END,
                     LOWER(city), LOWER(airport_name), code
            """;

    private final JdbcTemplate jdbc;
    private final GeoapifyAirportService geoapifyAirportService;
    private final LandmarkProvider openTripMapAttractionService;

    public AirportDirectoryService(
            JdbcTemplate jdbc,
            GeoapifyAirportService geoapifyAirportService,
            LandmarkProvider openTripMapAttractionService) {
        this.jdbc = jdbc;
        this.geoapifyAirportService = geoapifyAirportService;
        this.openTripMapAttractionService = openTripMapAttractionService;
    }

    public Map<String, Object> search(String requestedQuery) {
        String query = requestedQuery == null ? "" : requestedQuery.trim();
        ParsedCategory parsedCategory = parseCategory(query);
        if (parsedCategory.isCategoryOnly()) {
            return response(query, "category", List.of(), List.of(),
                    "Add a city or place, for example “Nature in Bali, Indonesia”.", 0);
        }

        String searchText = parsedCategory.locationQuery();
        try {
            return searchDirectory(query, searchText, parsedCategory.category());
        } catch (BadSqlGrammarException exception) {
            if (!isMissingDirectorySchema(exception)) throw exception;
            return legacyFallback(query);
        }
    }

    private Map<String, Object> searchDirectory(
            String originalQuery, String searchText, String requestedCategory) {
        List<Map<String, Object>> airports;
        String queryType;
        String city = "";
        String country = "";

        if (searchText.isBlank()) {
            airports = jdbc.queryForList("""
                    SELECT %s
                    FROM airports
                    WHERE scheduled_service = TRUE
                    %s
                    LIMIT ?
                    """.formatted(AIRPORT_COLUMNS, AIRPORT_ORDER), DEFAULT_LIMIT);
            queryType = "popular_airports";
        } else if (AIRPORT_CODE.matcher(searchText).matches()
                && !(airports = exactAirport(searchText)).isEmpty()) {
            airports = decorate(airports);
            queryType = "airport_code";
        } else {
            String[] cityAndCountry = splitCityCountry(searchText);
            city = cityAndCountry[0];
            country = cityAndCountry[1];
            if (isCountryQuery(searchText)) {
                airports = countryAirports(searchText, COUNTRY_LIMIT);
                queryType = "country";
            } else if (isCityQuery(city, country)) {
                airports = cityAirports(city, country, COUNTRY_LIMIT);
                queryType = requestedCategory == null ? "city" : "category";
            } else {
                airports = fuzzyAirports(searchText, DEFAULT_LIMIT);
                queryType = isAirportNameQuery(airports) ? "airport_name" : "search";
            }
        }

        if (requestedCategory != null) {
            return categorySearch(
                    originalQuery, searchText, requestedCategory, airports, queryType);
        }

        if (airports.isEmpty()) {
            return landmarkSearch(originalQuery, searchText);
        }

        List<Map<String, Object>> landmarks = List.of();
        String landmarkWarning = null;
        if ("city".equals(queryType)) {
            try {
                landmarks = cityLandmarks(city, country, airports, null);
            } catch (ResponseStatusException exception) {
                if (exception.getStatusCode().value() != 503) throw exception;
                LOG.warn("OpenTripMap landmarks unavailable in airport search (HTTP 503)");
                landmarkWarning = "Landmark results are temporarily unavailable.";
            }
        }
        int total = isCountryQuery(searchText)
                ? Math.max(airports.size(), countryCount(searchText))
                : airports.size();
        Map<String, Object> result =
                response(originalQuery, queryType, airports, landmarks, null, total);
        if (landmarkWarning != null) result.put("landmark_warning", landmarkWarning);
        return result;
    }

    private List<Map<String, Object>> exactAirport(String query) {
        return decorate(jdbc.queryForList("""
                SELECT %s
                FROM airports
                WHERE scheduled_service = TRUE
                  AND (UPPER(TRIM(code)) = UPPER(?) OR UPPER(TRIM(icao_code)) = UPPER(?))
                ORDER BY CASE WHEN UPPER(TRIM(code)) = UPPER(?) THEN 0 ELSE 1 END
                LIMIT 1
                """.formatted(AIRPORT_COLUMNS), query, query, query));
    }

    private List<Map<String, Object>> countryAirports(String query, int limit) {
        String countryCode = countryCodeAlias(query);
        return decorate(jdbc.queryForList("""
                SELECT %s
                FROM airports
                WHERE scheduled_service = TRUE
                  AND (LOWER(country) = LOWER(?) OR UPPER(TRIM(iso_country)) = UPPER(?))
                %s
                LIMIT ?
                """.formatted(AIRPORT_COLUMNS, AIRPORT_ORDER), query, countryCode, limit));
    }

    private List<Map<String, Object>> cityAirports(
            String city, String country, int limit) {
        String countryCode = countryCodeAlias(country);
        if (country.isBlank()) {
            return decorate(jdbc.queryForList("""
                    SELECT %s
                    FROM airports
                    WHERE scheduled_service = TRUE
                      AND (LOWER(city) = LOWER(?)
                           OR LOWER(airport_name) LIKE LOWER(?) || ' %%')
                    %s
                    LIMIT ?
                    """.formatted(AIRPORT_COLUMNS, AIRPORT_ORDER), city, city, limit));
        }
        return decorate(jdbc.queryForList("""
                SELECT %s
                FROM airports
                WHERE scheduled_service = TRUE
                  AND (LOWER(city) = LOWER(?)
                       OR LOWER(airport_name) LIKE LOWER(?) || ' %%')
                  AND (LOWER(country) = LOWER(?) OR UPPER(TRIM(iso_country)) = UPPER(?)
                       OR POSITION(LOWER(?) IN LOWER(country)) > 0)
                %s
                LIMIT ?
                """.formatted(AIRPORT_COLUMNS, AIRPORT_ORDER),
                city, city, country, countryCode, country, limit));
    }

    private List<Map<String, Object>> fuzzyAirports(String query, int limit) {
        String[] cityAndCountry = splitCityCountry(query);
        String search = cityAndCountry[0];
        String country = cityAndCountry[1];
        if (!country.isBlank()) {
            return cityAirports(search, country, limit);
        }
        return decorate(jdbc.queryForList("""
                SELECT %s
                FROM airports
                WHERE scheduled_service = TRUE
                  AND (
                    POSITION(LOWER(?) IN LOWER(TRIM(code))) > 0
                    OR POSITION(LOWER(?) IN LOWER(TRIM(icao_code))) > 0
                    OR POSITION(LOWER(?) IN LOWER(city)) > 0
                    OR POSITION(LOWER(?) IN LOWER(airport_name)) > 0
                    OR POSITION(LOWER(?) IN LOWER(country)) > 0
                    OR POSITION(LOWER(?) IN LOWER(COALESCE(keywords, ''))) > 0
                  )
                ORDER BY
                  CASE
                    WHEN LOWER(TRIM(code)) = LOWER(?) THEN 0
                    WHEN LOWER(TRIM(icao_code)) = LOWER(?) THEN 1
                    WHEN LOWER(city) = LOWER(?) THEN 2
                    WHEN LOWER(airport_name) = LOWER(?) THEN 3
                    WHEN LOWER(airport_name) LIKE LOWER(?) || '%%' THEN 4
                    WHEN LOWER(city) LIKE LOWER(?) || '%%' THEN 5
                    ELSE 6
                  END,
                  is_major DESC,
                  CASE airport_type
                    WHEN 'large_airport' THEN 0
                    WHEN 'medium_airport' THEN 1
                    WHEN 'small_airport' THEN 2
                    ELSE 3
                  END,
                  LOWER(city), LOWER(airport_name), code
                LIMIT ?
                """.formatted(AIRPORT_COLUMNS),
                query, query, query, query, query, query,
                query, query, query, query, query, query, limit));
    }

    private boolean isCountryQuery(String query) {
        String countryCode = countryCodeAlias(query);
        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*)
                FROM airports
                WHERE scheduled_service = TRUE
                  AND (LOWER(country) = LOWER(?) OR UPPER(TRIM(iso_country)) = UPPER(?))
                """, Integer.class, query, countryCode);
        return count != null && count > 0;
    }

    private int countryCount(String query) {
        String countryCode = countryCodeAlias(query);
        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*)
                FROM airports
                WHERE scheduled_service = TRUE
                  AND (LOWER(country) = LOWER(?) OR UPPER(TRIM(iso_country)) = UPPER(?))
                """, Integer.class, query, countryCode);
        return count == null ? 0 : count;
    }

    private boolean isCityQuery(String city, String country) {
        if (city.isBlank()) return false;
        String countryCode = countryCodeAlias(country);
        Integer count = country.isBlank()
                ? jdbc.queryForObject("""
                        SELECT COUNT(*) FROM airports
                        WHERE scheduled_service = TRUE AND LOWER(city) = LOWER(?)
                        """, Integer.class, city)
                : jdbc.queryForObject("""
                        SELECT COUNT(*) FROM airports
                        WHERE scheduled_service = TRUE
                          AND LOWER(city) = LOWER(?)
                          AND (LOWER(country) = LOWER(?)
                               OR UPPER(TRIM(iso_country)) = UPPER(?)
                               OR POSITION(LOWER(?) IN LOWER(country)) > 0)
                        """, Integer.class, city, country, countryCode, country);
        return count != null && count > 0;
    }

    private boolean isAirportNameQuery(List<Map<String, Object>> airports) {
        return !airports.isEmpty()
                && airports.stream().anyMatch(airport -> {
                    String type = String.valueOf(airport.getOrDefault("airport_type", ""));
                    return !type.isBlank();
                });
    }

    private Map<String, Object> landmarkSearch(String originalQuery, String searchText) {
        GeoapifyAirportService.GeocodedPlace location =
                resolvePlace(searchText);
        if (location == null) {
            return response(originalQuery, "no_match", List.of(), List.of(),
                    "No matching airport, city, country, or landmark was found.", 0);
        }

        List<Map<String, Object>> nearest =
                nearestAirports(location.latitude(), location.longitude(), NEAREST_LIMIT);
        List<Map<String, Object>> landmarks = new ArrayList<>();
        if (hasText(location.city()) && hasText(location.country())) {
            List<Map<String, Object>> places = openTripMapAttractionService.searchAtCoordinates(
                    location.latitude(), location.longitude(),
                    location.city(), location.country(), "en");
            String normalizedSearch = normalize(originalQuery);
            places.stream()
                    .filter(place -> normalize(String.valueOf(place.get("name")))
                            .contains(normalizedSearch)
                            || normalizedSearch.contains(
                                    normalize(String.valueOf(place.get("name")))))
                    .limit(1)
                    .map(place -> withNearestAirport(
                            place, nearestAirports(
                                    number(place.get("latitude")), number(place.get("longitude")), 1)))
                    .forEach(landmarks::add);
        }

        Map<String, Object> resolvedLocation = new LinkedHashMap<>();
        resolvedLocation.put("name", location.name());
        resolvedLocation.put("city", location.city());
        resolvedLocation.put("country", location.country());
        resolvedLocation.put("latitude", location.latitude());
        resolvedLocation.put("longitude", location.longitude());
        resolvedLocation.put("result_type", location.resultType());
        resolvedLocation.put("wikidata_id", location.wikidataId());
        return response(originalQuery, "landmark", nearest, landmarks, null,
                nearest.size(), resolvedLocation);
    }

    private Map<String, Object> categorySearch(
            String originalQuery,
            String searchText,
            String category,
            List<Map<String, Object>> cityAirports,
            String originalType) {
        GeoapifyAirportService.GeocodedPlace location =
                resolvePlace(searchText);
        if (location == null || !hasText(location.country())) {
            return response(originalQuery, "category", List.of(), List.of(),
                    "Add a city or place after the category.", 0);
        }

        List<Map<String, Object>> places = openTripMapAttractionService.searchAtCoordinates(
                location.latitude(), location.longitude(),
                hasText(location.city()) ? location.city()
                        : splitCityCountry(searchText)[0], location.country(), "en",
                openTripMapCategory(category));
        List<Map<String, Object>> landmarks = places.stream()
                .filter(place -> matchesHighlightCategory(place, category))
                .limit(12)
                .map(place -> withNearestAirport(
                        place, nearestAirports(
                                number(place.get("latitude")), number(place.get("longitude")), 1)))
                .toList();

        Map<String, Map<String, Object>> uniqueAirports = new LinkedHashMap<>();
        for (Map<String, Object> landmark : landmarks) {
            Object nearest = landmark.get("nearest_airport");
            if (nearest instanceof Map<?, ?> airport) {
                uniqueAirports.putIfAbsent(
                        String.valueOf(airport.get("code")),
                        new LinkedHashMap<>((Map<String, Object>) airport));
            }
        }
        if (uniqueAirports.isEmpty()) {
            List<Map<String, Object>> nearest =
                    nearestAirports(location.latitude(), location.longitude(), 1);
            nearest.forEach(airport -> uniqueAirports.putIfAbsent(
                    String.valueOf(airport.get("code")), airport));
        }
        if (uniqueAirports.isEmpty()) {
            cityAirports.stream().limit(NEAREST_LIMIT).forEach(airport ->
                    uniqueAirports.putIfAbsent(
                            String.valueOf(airport.get("code")), airport));
        }
        return response(originalQuery, "category",
                List.copyOf(uniqueAirports.values()), landmarks,
                landmarks.isEmpty()
                        ? "No photo-verified landmarks matched that category in this location."
                        : null,
                uniqueAirports.size());
    }

    private List<Map<String, Object>> cityLandmarks(
            String city,
            String country,
            List<Map<String, Object>> airports,
            String category) {
        Set<String> destinations = new LinkedHashSet<>();
        for (Map<String, Object> airport : airports) {
            destinations.add(String.valueOf(airport.get("city")) + "\u001f"
                    + String.valueOf(airport.get("country")));
        }

        List<Map<String, Object>> landmarks = new ArrayList<>();
        for (String destination : destinations.stream().limit(3).toList()) {
            String[] parts = destination.split("\u001f", 2);
            String resolvedCity = parts[0];
            String resolvedCountry = parts.length > 1 ? parts[1] : country;
            if (!country.isBlank() && !matchesCountry(resolvedCountry, country)) continue;
            List<Map<String, Object>> places =
                    openTripMapAttractionService.searchAttractions(
                            resolvedCity, resolvedCountry, "en");
            places.stream()
                    .filter(place -> category == null
                            || matchesHighlightCategory(place, category))
                    .limit(4)
                    .map(place -> withNearestAirport(
                            place, nearestAirports(
                                    number(place.get("latitude")), number(place.get("longitude")), 1)))
                    .forEach(landmarks::add);
        }
        return List.copyOf(landmarks);
    }

    private List<Map<String, Object>> nearestAirports(
            double latitude, double longitude, int limit) {
        if (!Double.isFinite(latitude) || !Double.isFinite(longitude)
                || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
            return List.of();
        }
        return decorate(jdbc.queryForList("""
                SELECT %s,
                    6371.0 * 2 * ASIN(SQRT(LEAST(1.0,
                        POWER(SIN(RADIANS(latitude - ?) / 2), 2)
                        + COS(RADIANS(?)) * COS(RADIANS(latitude))
                        * POWER(SIN(RADIANS(longitude - ?) / 2), 2)
                    ))) AS distance_km
                FROM airports
                WHERE scheduled_service = TRUE
                  AND latitude IS NOT NULL AND longitude IS NOT NULL
                ORDER BY distance_km ASC, is_major DESC, code ASC
                LIMIT ?
                """.formatted(AIRPORT_COLUMNS), latitude, latitude, longitude, limit));
    }

    private static Map<String, Object> withNearestAirport(
            Map<String, Object> place, List<Map<String, Object>> nearestAirports) {
        Map<String, Object> result = new LinkedHashMap<>(place);
        result.put("highlight_category",
                place.getOrDefault("highlight_category", "Family & Culture"));
        result.put("nearest_airport",
                nearestAirports.isEmpty() ? null : nearestAirports.getFirst());
        return result;
    }

    private static boolean matchesHighlightCategory(
            Map<String, Object> place, String category) {
        String requested = normalize(category).replace("&", "")
                .replace(" and ", " ").replaceAll("\\s+", " ");
        String actual = normalize(String.valueOf(place.get("category")))
                .replace("&", "").replace(" and ", " ").replaceAll("\\s+", " ");
        return switch (requested) {
            case "historical", "history" -> actual.equals("historical");
            case "nature", "natural" -> actual.equals("natural");
            case "shopping", "shops" -> false;
            case "architecture", "architectural" -> actual.equals("architecture");
            case "family culture", "culture", "family" ->
                    Set.of("historical", "museum", "architecture").contains(actual);
            default -> false;
        };
    }

    private static String openTripMapCategory(String category) {
        return switch (normalize(category)) {
            case "historical", "history" -> "historical";
            case "nature", "natural" -> "natural";
            case "architecture", "architectural" -> "architecture";
            case "family culture", "culture", "family" -> "cultural";
            case "shopping", "shops" -> "shopping";
            default -> null;
        };
    }

    private static boolean matchesCountry(String actual, String requested) {
        return normalize(actual).equals(normalize(requested))
                || countryCodeAlias(actual).equalsIgnoreCase(countryCodeAlias(requested));
    }

    private static String[] splitCityCountry(String query) {
        String[] parts = query.split(",", 2);
        return parts.length == 1
                ? new String[] {parts[0].trim(), ""}
                : new String[] {parts[0].trim(), parts[1].trim()};
    }

    private static String countryCodeAlias(String value) {
        return switch (value.trim().toUpperCase(Locale.ROOT)) {
            case "UK", "GREAT BRITAIN", "UNITED KINGDOM" -> "GB";
            case "USA", "UNITED STATES", "UNITED STATES OF AMERICA" -> "US";
            case "UAE" -> "AE";
            case "TURKEY", "TURKIYE", "TÜRKIYE" -> "TR";
            default -> value.trim().toUpperCase(Locale.ROOT);
        };
    }

    private static ParsedCategory parseCategory(String query) {
        String normalized = query.trim().toLowerCase(Locale.ROOT);
        Map<String, String> categories = Map.of(
                "historical", "Historical",
                "history", "Historical",
                "nature", "Nature",
                "natural", "Nature",
                "shopping", "Shopping",
                "architecture", "Architecture",
                "family & culture", "Family & Culture",
                "family and culture", "Family & Culture",
                "culture", "Family & Culture");
        for (Map.Entry<String, String> entry : categories.entrySet()) {
            if (normalized.equals(entry.getKey())) {
                return new ParsedCategory(entry.getValue(), "", true);
            }
            String prefix = entry.getKey() + " in ";
            if (normalized.startsWith(prefix)) {
                return new ParsedCategory(
                        entry.getValue(), query.substring(prefix.length()).trim(), false);
            }
        }
        return new ParsedCategory(null, query, false);
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().toLowerCase(Locale.ROOT)
                .replaceAll("\\s+", " ");
    }

    private static boolean hasText(String value) {
        return value != null && !value.isBlank();
    }

    private GeoapifyAirportService.GeocodedPlace resolvePlace(String requestedText) {
        String text = switch (normalize(requestedText)) {
            case "pyramids", "the pyramids", "pyramids of giza" ->
                    "Giza Pyramids, Egypt";
            default -> requestedText;
        };
        String[] parts = splitCityCountry(text);
        if (parts[1].isBlank()) return geoapifyAirportService.resolveLocation(text);
        List<Map<String, Object>> countries = jdbc.queryForList("""
                SELECT TRIM(iso_country) AS iso_country FROM airports
                WHERE LOWER(country) = LOWER(?) OR UPPER(iso_country) = ?
                LIMIT 1
                """, parts[1], countryCodeAlias(parts[1]));
        if (countries.isEmpty()) return null;
        String iso = String.valueOf(countries.getFirst().get("iso_country"));
        return geoapifyAirportService.resolveLocation(parts[0], iso);
    }

    private static Double number(Object value) {
        if (value instanceof Number number) return number.doubleValue();
        if (value instanceof String string) {
            try {
                return Double.parseDouble(string);
            } catch (NumberFormatException ignored) {
                return Double.NaN;
            }
        }
        return Double.NaN;
    }

    private static List<Map<String, Object>> decorate(
            List<Map<String, Object>> airports) {
        return airports.stream().map(airport -> {
            Map<String, Object> result = new LinkedHashMap<>(airport);
            boolean major = Boolean.TRUE.equals(result.get("is_major"));
            result.put("priority", major ? "major" : "minor");
            result.put("code", String.valueOf(result.getOrDefault("code", "")).trim());
            result.put("icao_code",
                    String.valueOf(result.getOrDefault("icao_code", "")).trim());
            return result;
        }).toList();
    }

    private Map<String, Object> legacyFallback(String query) {
        List<Map<String, Object>> airports;
        try {
            String pattern = "%" + query.toLowerCase(Locale.ROOT) + "%";
            airports = jdbc.queryForList("""
                    SELECT code, city, airport_name, country, region
                    FROM airports
                    WHERE ? = '' OR LOWER(code) LIKE ? OR LOWER(city) LIKE ?
                          OR LOWER(airport_name) LIKE ? OR LOWER(country) LIKE ?
                          OR LOWER(region) LIKE ?
                    ORDER BY city, code
                    LIMIT 50
                    """, query.toLowerCase(Locale.ROOT), pattern, pattern, pattern,
                    pattern, pattern);
        } catch (DataAccessException ignored) {
            airports = List.of();
        }
        if (airports.isEmpty() && query.length() >= 2) {
            airports = geoapifyAirportService.search(query);
        }
        return response(query, "search", airports, List.of(), null, airports.size());
    }

    private static boolean isMissingDirectorySchema(Throwable exception) {
        for (Throwable cause = exception; cause != null; cause = cause.getCause()) {
            if (cause instanceof SQLException sql
                    && ("42703".equals(sql.getSQLState())
                        || "42P01".equals(sql.getSQLState()))) {
                return true;
            }
        }
        return false;
    }

    private static Map<String, Object> response(
            String query,
            String queryType,
            List<Map<String, Object>> airports,
            List<Map<String, Object>> landmarks,
            String message,
            int total) {
        return response(query, queryType, airports, landmarks, message, total, null);
    }

    private static Map<String, Object> response(
            String query,
            String queryType,
            List<Map<String, Object>> airports,
            List<Map<String, Object>> landmarks,
            String message,
            int total,
            Map<String, Object> resolvedLocation) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("query", query);
        result.put("query_type", queryType);
        result.put("airports", airports);
        result.put("landmarks", landmarks);
        result.put("total", total);
        result.put("has_more", total > airports.size());
        result.put("source", "OurAirports");
        result.put("airport_attribution", "OurAirports public-domain airport data");
        result.put("landmark_attribution",
                "OpenTripMap · follow each place’s source and image attribution.");
        if (message != null) result.put("message", message);
        if (resolvedLocation != null) result.put("resolved_location", resolvedLocation);
        return result;
    }

    private record ParsedCategory(
            String category, String locationQuery, boolean isCategoryOnly) {}
}

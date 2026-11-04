package com.zentrip.api;

import java.text.Normalizer;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class HotelDestinationCatalogService {
    private static final Logger LOG =
            LoggerFactory.getLogger(HotelDestinationCatalogService.class);
    private static final long CATALOG_RECHECK_INTERVAL_MILLIS = 60_000L;
    private static final int SUGGESTION_LIMIT = 12;

    private final JdbcTemplate jdbc;
    private final GeoapifyAirportService geoapify;
    private final AtomicBoolean missingTableLogged = new AtomicBoolean();
    private volatile Boolean catalogAvailable;
    private volatile long catalogCheckedAtMillis;

    public HotelDestinationCatalogService(
            JdbcTemplate jdbc,
            GeoapifyAirportService geoapify) {
        this.jdbc = jdbc;
        this.geoapify = geoapify;
    }

    public List<Map<String, Object>> suggest(String query, String language) {
        String normalized = normalize(query);
        if (normalized.length() < 2) return List.of();
        String locale = "ar".equalsIgnoreCase(language) ? "ar" : "en";

        List<Map<String, Object>> local = searchCatalog(normalized, locale);
        if (!local.isEmpty()) return local;

        try {
            GeoapifyAirportService.GeocodedPlace place =
                    geoapify.resolveCity(query, "");
            Map<String, Object> suggestion = citySuggestion(place, query);
            if (suggestion != null) return List.of(suggestion);
        } catch (RuntimeException exception) {
            LOG.debug("Geoapify hotel destination lookup unavailable ({})",
                    exception.getClass().getSimpleName());
        }
        return List.of();
    }

    private List<Map<String, Object>> searchCatalog(String query, String language) {
        if (!isCatalogAvailable()) return List.of();
        String prefix = query + "%";
        String contains = "%" + query + "%";
        try {
            List<Map<String, Object>> rows = jdbc.queryForList("""
                    SELECT destination_type, destination_code, name_en, name_ar,
                           country_code,
                           country_name_en, country_name_ar, latitude, longitude
                    FROM public.hotel_destinations
                    WHERE search_text LIKE ?
                    ORDER BY CASE destination_type
                                 WHEN 'city' THEN 0
                                 WHEN 'zone' THEN 1
                                 ELSE 2
                             END,
                             CASE WHEN search_text LIKE ? THEN 0 ELSE 1 END,
                             LOWER(name_en)
                    LIMIT 12
                    """, contains, prefix);
            List<Map<String, Object>> suggestions = new ArrayList<>();
            for (Map<String, Object> row : rows) {
                Map<String, Object> suggestion = new LinkedHashMap<>();
                suggestion.put("name", text(row.get("name_en")).isBlank()
                        ? text(row.get("name_ar")) : text(row.get("name_en")));
                suggestion.put("localized_name", nullableText(row.get("name_ar")));
                suggestion.put("country_name", nullableText(row.get("country_name_en")));
                suggestion.put("country_name_localized",
                        nullableText(row.get("country_name_ar")));
                String countryCode = text(row.get("country_code")
                        ).toUpperCase(Locale.ROOT);
                if (countryCode.matches("[A-Z]{2}")) {
                    suggestion.put("country_code", countryCode);
                }
                String type = text(row.get("destination_type"));
                suggestion.put("type", type);
                if (!"country".equals(type)) {
                    suggestion.put("destination_code",
                            text(row.get("destination_code")));
                }
                addCoordinate(suggestion, "latitude", row.get("latitude"));
                addCoordinate(suggestion, "longitude", row.get("longitude"));
                suggestions.add(suggestion);
            }
            return List.copyOf(suggestions);
        } catch (DataAccessException exception) {
            catalogAvailable = false;
            catalogCheckedAtMillis = System.currentTimeMillis();
            if (missingTableLogged.compareAndSet(false, true)) {
                LOG.warn("Hotel destination catalog query unavailable; using "
                        + "Geoapify city geocoding ({})",
                        exception.getClass().getSimpleName());
            }
            return List.of();
        }
    }

    private boolean isCatalogAvailable() {
        Boolean available = catalogAvailable;
        long now = System.currentTimeMillis();
        if (Boolean.TRUE.equals(available)) return true;
        if (Boolean.FALSE.equals(available)
                && now - catalogCheckedAtMillis < CATALOG_RECHECK_INTERVAL_MILLIS) {
            return false;
        }
        synchronized (this) {
            now = System.currentTimeMillis();
            if (Boolean.TRUE.equals(catalogAvailable)) return true;
            if (Boolean.FALSE.equals(catalogAvailable)
                    && now - catalogCheckedAtMillis
                    < CATALOG_RECHECK_INTERVAL_MILLIS) {
                return false;
            }
            try {
                catalogAvailable = Boolean.TRUE.equals(jdbc.queryForObject(
                        "SELECT to_regclass('public.hotel_destinations') IS NOT NULL",
                        Boolean.class));
            } catch (DataAccessException exception) {
                catalogAvailable = false;
            }
            catalogCheckedAtMillis = now;
            if (!catalogAvailable && missingTableLogged.compareAndSet(false, true)) {
                LOG.warn("Hotel destination catalog table is not installed; using "
                        + "Geoapify city geocoding");
            }
            return catalogAvailable;
        }
    }

    private static Map<String, Object> citySuggestion(
            GeoapifyAirportService.GeocodedPlace place, String query) {
        if (place == null || place.latitude() < -90 || place.latitude() > 90
                || place.longitude() < -180 || place.longitude() > 180) {
            return null;
        }
        String name = firstNonBlank(place.city(), place.name(), query);
        String countryCode = text(place.countryCode()).toUpperCase(Locale.ROOT);
        if (name.isBlank() || !countryCode.matches("[A-Z]{2}")) return null;

        Map<String, Object> suggestion = new LinkedHashMap<>();
        suggestion.put("name", name);
        suggestion.put("country_name", nullableText(place.country()));
        suggestion.put("country_code", countryCode);
        suggestion.put("place_id", nullableText(place.placeId()));
        suggestion.put("type", "city");
        suggestion.put("latitude", place.latitude());
        suggestion.put("longitude", place.longitude());
        return suggestion;
    }

    private static String normalize(String value) {
        if (value == null) return "";
        String normalized = Normalizer.normalize(value, Normalizer.Form.NFD)
                .replaceAll("\\p{M}+", "")
                .replace('\u0640', ' ')
                .toLowerCase(Locale.ROOT);
        return normalized.replaceAll("\\s+", " ").trim();
    }

    private static String text(Object value) {
        return value == null ? "" : value.toString().trim();
    }

    private static String nullableText(Object value) {
        String text = text(value);
        return text.isBlank() ? null : text;
    }

    private static void addCoordinate(
            Map<String, Object> destination, String key, Object value) {
        if (value instanceof Number number
                && Double.isFinite(number.doubleValue())) {
            destination.put(key, number.doubleValue());
        }
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            String candidate = text(value);
            if (!candidate.isBlank()) return candidate;
        }
        return "";
    }
}

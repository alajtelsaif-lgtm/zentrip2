package com.zentrip.api;

import java.text.Normalizer;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.BatchPreparedStatementSetter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class HotelDestinationCatalogService {
    private static final Logger LOG =
            LoggerFactory.getLogger(HotelDestinationCatalogService.class);
    private static final Duration REFRESH_INTERVAL = Duration.ofDays(7);
    private static final long CATALOG_RECHECK_INTERVAL_MILLIS = 60_000L;
    private static final int SUGGESTION_LIMIT = 12;

    private final JdbcTemplate jdbc;
    private final HotelbedsHotelService hotelbeds;
    private final OpenTripMapAttractionService openTripMap;
    private final AtomicBoolean missingTableLogged = new AtomicBoolean();
    private volatile Boolean catalogAvailable;
    private volatile long catalogCheckedAtMillis;

    public HotelDestinationCatalogService(
            JdbcTemplate jdbc,
            HotelbedsHotelService hotelbeds,
            OpenTripMapAttractionService openTripMap) {
        this.jdbc = jdbc;
        this.hotelbeds = hotelbeds;
        this.openTripMap = openTripMap;
    }

    public List<Map<String, Object>> suggest(String query, String language) {
        String normalized = normalize(query);
        if (normalized.length() < 2) return List.of();
        String locale = "ar".equalsIgnoreCase(language) ? "ar" : "en";

        List<Map<String, Object>> local = searchCatalog(normalized, locale);
        if (!local.isEmpty()) return local;

        List<Map<String, Object>> popular = popularMatches(normalized);
        if (!popular.isEmpty()) return popular;

        try {
            OpenTripMapAttractionService.DestinationSuggestion place =
                    openTripMap.suggestDestination(query, locale);
            if (place != null) {
                Map<String, Object> suggestion = new LinkedHashMap<>();
                suggestion.put("name", place.name());
                suggestion.put("localized_name", locale.equals("ar")
                        ? place.name() : null);
                suggestion.put("country_name", place.country());
                suggestion.put("country_name_localized", null);
                suggestion.put("type", "city");
                suggestion.put("latitude", place.latitude());
                suggestion.put("longitude", place.longitude());
                return List.of(suggestion);
            }
        } catch (RuntimeException exception) {
            LOG.debug("OpenTripMap destination fallback unavailable ({})",
                    exception.getClass().getSimpleName());
        }
        return List.of();
    }

    @Scheduled(initialDelay = 60_000L, fixedDelay = 300_000L)
    @Transactional
    public void refreshIfStale() {
        try {
            jdbc.execute("SET LOCAL ROLE zentrip_api_runtime");
            if (!isCatalogAvailable()) return;
            Timestamp lastUpdated = jdbc.queryForObject(
                    "SELECT MAX(updated_at) FROM public.hotel_destinations",
                    Timestamp.class);
            if (lastUpdated != null
                    && Instant.now().isBefore(
                            lastUpdated.toInstant().plus(REFRESH_INTERVAL))) {
                return;
            }

            List<Map<String, Object>> destinations =
                    hotelbeds.fetchDestinationCatalog();
            if (destinations.isEmpty()) {
                LOG.warn("Hotelbeds destination catalog refresh returned no destinations; "
                        + "keeping the current local catalog");
                return;
            }
            jdbc.batchUpdate("""
                    INSERT INTO public.hotel_destinations (
                        destination_type, destination_code, parent_code,
                        name_en, name_ar, country_code, country_name_en,
                        country_name_ar, latitude, longitude, search_text, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
                    ON CONFLICT (destination_type, destination_code, parent_code)
                    DO UPDATE SET
                        name_en = COALESCE(
                            NULLIF(EXCLUDED.name_en, ''), hotel_destinations.name_en),
                        name_ar = COALESCE(
                            NULLIF(EXCLUDED.name_ar, ''), hotel_destinations.name_ar),
                        country_code = EXCLUDED.country_code,
                        country_name_en = COALESCE(
                            NULLIF(EXCLUDED.country_name_en, ''),
                            hotel_destinations.country_name_en),
                        country_name_ar = COALESCE(
                            NULLIF(EXCLUDED.country_name_ar, ''),
                            hotel_destinations.country_name_ar),
                        latitude = COALESCE(EXCLUDED.latitude, hotel_destinations.latitude),
                        longitude = COALESCE(EXCLUDED.longitude, hotel_destinations.longitude),
                        search_text = LOWER(CONCAT_WS(' ',
                            COALESCE(NULLIF(EXCLUDED.name_en, ''),
                                hotel_destinations.name_en),
                            COALESCE(NULLIF(EXCLUDED.name_ar, ''),
                                hotel_destinations.name_ar),
                            COALESCE(NULLIF(EXCLUDED.country_name_en, ''),
                                hotel_destinations.country_name_en),
                            COALESCE(NULLIF(EXCLUDED.country_name_ar, ''),
                                hotel_destinations.country_name_ar),
                            COALESCE(NULLIF(EXCLUDED.country_code, ''),
                                hotel_destinations.country_code))),
                        updated_at = NOW()
                    """, new BatchPreparedStatementSetter() {
                        @Override
                        public void setValues(
                                java.sql.PreparedStatement statement, int index)
                                throws java.sql.SQLException {
                            Map<String, Object> row = destinations.get(index);
                            String nameEn = text(row.get("name_en"));
                            String nameAr = text(row.get("name_ar"));
                            String countryEn = text(row.get("country_name_en"));
                            String countryAr = text(row.get("country_name_ar"));
                            String searchable = normalize(String.join(" ",
                                    nameEn, nameAr, countryEn, countryAr,
                                    text(row.get("country_code"))));
                            statement.setString(1, text(row.get("destination_type")));
                            statement.setString(2, text(row.get("destination_code")));
                            statement.setString(3, text(row.get("parent_code")));
                            statement.setString(4, nameEn);
                            statement.setString(5, nameAr);
                            statement.setString(6, text(row.get("country_code")));
                            statement.setString(7, countryEn);
                            statement.setString(8, countryAr);
                            setNullableDouble(statement, 9, row.get("latitude"));
                            setNullableDouble(statement, 10, row.get("longitude"));
                            statement.setString(11, searchable);
                        }

                        @Override
                        public int getBatchSize() {
                            return destinations.size();
                        }
                    });
            LOG.info("Hotelbeds destination catalog refreshed with {} records",
                    destinations.size());
        } catch (DataAccessException exception) {
            LOG.warn("Hotel destination catalog refresh skipped because the catalog "
                    + "schema is unavailable ({})", exception.getClass().getSimpleName());
            catalogAvailable = false;
        } catch (RuntimeException exception) {
            LOG.warn("Hotel destination catalog refresh failed ({})",
                    exception.getClass().getSimpleName());
        }
    }

    private List<Map<String, Object>> searchCatalog(String query, String language) {
        if (!isCatalogAvailable()) return List.of();
        String prefix = query + "%";
        String contains = "%" + query + "%";
        try {
            List<Map<String, Object>> rows = jdbc.queryForList("""
                    SELECT destination_type, destination_code, name_en, name_ar,
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
                LOG.warn("Hotel destination catalog query unavailable; using cached "
                        + "geocoding and popular cities ({})",
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
                        + "OpenTripMap and popular-city fallbacks");
            }
            return catalogAvailable;
        }
    }

    private static List<Map<String, Object>> popularMatches(String query) {
        List<PopularDestination> popular = List.of(
                new PopularDestination("London", "لندن", "United Kingdom",
                        "المملكة المتحدة", 51.5072, -0.1276),
                new PopularDestination("Paris", "باريس", "France", "فرنسا",
                        48.8566, 2.3522),
                new PopularDestination("Dubai", "دبي", "United Arab Emirates",
                        "الإمارات العربية المتحدة", 25.2048, 55.2708),
                new PopularDestination("Cairo", "القاهرة", "Egypt", "مصر",
                        30.0444, 31.2357),
                new PopularDestination("Tripoli", "طرابلس", "Libya", "ليبيا",
                        32.8872, 13.1913),
                new PopularDestination("Istanbul", "إسطنبول", "Türkiye", "تركيا",
                        41.0082, 28.9784),
                new PopularDestination("Tunis", "تونس", "Tunisia", "تونس",
                        36.8065, 10.1815));
        return popular.stream()
                .filter(place -> normalize(place.name()).contains(query)
                        || normalize(place.localizedName()).contains(query)
                        || normalize(place.country()).contains(query)
                        || normalize(place.localizedCountry()).contains(query))
                .limit(SUGGESTION_LIMIT)
                .map(place -> {
                    Map<String, Object> suggestion = new LinkedHashMap<>();
                    suggestion.put("name", place.name());
                    suggestion.put("localized_name", place.localizedName());
                    suggestion.put("country_name", place.country());
                    suggestion.put("country_name_localized",
                            place.localizedCountry());
                    suggestion.put("type", "city");
                    suggestion.put("latitude", place.latitude());
                    suggestion.put("longitude", place.longitude());
                    return suggestion;
                })
                .toList();
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

    private static void setNullableDouble(
            java.sql.PreparedStatement statement, int index, Object value)
            throws java.sql.SQLException {
        if (value instanceof Number number && Double.isFinite(number.doubleValue())) {
            statement.setDouble(index, number.doubleValue());
        } else {
            statement.setNull(index, java.sql.Types.DOUBLE);
        }
    }

    private static void addCoordinate(
            Map<String, Object> destination, String key, Object value) {
        if (value instanceof Number number
                && Double.isFinite(number.doubleValue())) {
            destination.put(key, number.doubleValue());
        }
    }

    private record PopularDestination(
            String name,
            String localizedName,
            String country,
            String localizedCountry,
            double latitude,
            double longitude) {}
}

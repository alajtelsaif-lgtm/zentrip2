package com.zentrip.api;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.sql.SQLException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.BadSqlGrammarException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Persistent cache and canonical identity layer for imported landmark data.
 *
 * <p>All values originate from the configured landmark provider. If the
 * additive catalog migration is not installed or the database is unavailable,
 * live OpenTripMap results remain usable and are not replaced with mock data.</p>
 */
@Service
public class LandmarkCatalogService {
    private static final Logger LOG =
            LoggerFactory.getLogger(LandmarkCatalogService.class);
    private static final Duration CACHE_TTL = Duration.ofDays(30);
    private static final int ALIAS_RESULT_LIMIT = 20;
    private static final double NEARBY_CANDIDATE_METERS = 300.0;
    private static final double AUTOMATIC_MERGE_METERS = 50.0;
    private static final Pattern PROVIDER_ID = Pattern.compile("^[A-Za-z0-9_-]{1,64}$");
    private static final TypeReference<LinkedHashMap<String, Object>> MAP_TYPE =
            new TypeReference<>() {};

    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;
    private final LandmarkDuplicateVerifier duplicateVerifier;
    private final AtomicBoolean missingSchemaLogged = new AtomicBoolean();
    private volatile Boolean schemaAvailable;

    public LandmarkCatalogService(
            JdbcTemplate jdbc,
            ObjectMapper mapper,
            LandmarkDuplicateVerifier duplicateVerifier) {
        this.jdbc = jdbc;
        this.mapper = mapper;
        this.duplicateVerifier = duplicateVerifier;
    }

    /**
     * Builds a stable, language- and viewport-specific key for the database cache.
     */
    public String cacheKey(Map<String, ?> request) {
        Map<String, Object> sorted = new java.util.TreeMap<>();
        request.forEach((key, value) -> {
            if (value == null) return;
            String text = String.valueOf(value).trim();
            if ("query".equals(key) || "city".equals(key) || "country".equals(key)) {
                text = normalize(text);
            }
            sorted.put(key, text);
        });
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(mapper.writeValueAsBytes(sorted));
            return HexFormat.of().formatHex(digest);
        } catch (Exception exception) {
            throw new IllegalStateException("Unable to create landmark cache key", exception);
        }
    }

    /**
     * Returns an unexpired response, or an expired response when it may be used
     * as a provider-outage fallback.
     */
    public Map<String, Object> cachedArea(String cacheKey, boolean allowExpired) {
        if (!catalogAvailable()) return null;
        try {
            List<Map<String, Object>> rows = jdbc.queryForList("""
                    SELECT response_payload::text AS response_payload,
                           expires_at > NOW() AS is_fresh
                    FROM landmark_search_areas
                    WHERE cache_key = ?
                    LIMIT 1
                    """, cacheKey);
            if (rows.isEmpty()) return null;
            Map<String, Object> row = rows.getFirst();
            if (!allowExpired && !Boolean.TRUE.equals(row.get("is_fresh"))) return null;
            Object raw = row.get("response_payload");
            if (raw == null) return null;
            return mapper.readValue(String.valueOf(raw), MAP_TYPE);
        } catch (DataAccessException exception) {
            logCatalogReadFailure(exception);
            return null;
        } catch (Exception exception) {
            LOG.warn("Cached landmark response could not be decoded");
            return null;
        }
    }

    /** Saves a normalized response for 30 days; this method never deletes records. */
    public void cacheArea(String cacheKey, Map<String, Object> request,
                          Map<String, Object> response) {
        if (!catalogAvailable()) return;
        try {
            jdbc.update("""
                    INSERT INTO landmark_search_areas (
                        cache_key, area_kind, query_text, language,
                        south, west, north, east, request_payload,
                        response_payload, fetched_at, expires_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?::jsonb, ?::jsonb,
                            NOW(), NOW() + INTERVAL '30 days')
                    ON CONFLICT (cache_key) DO UPDATE SET
                        area_kind = EXCLUDED.area_kind,
                        query_text = EXCLUDED.query_text,
                        language = EXCLUDED.language,
                        south = EXCLUDED.south,
                        west = EXCLUDED.west,
                        north = EXCLUDED.north,
                        east = EXCLUDED.east,
                        request_payload = EXCLUDED.request_payload,
                        response_payload = EXCLUDED.response_payload,
                        fetched_at = NOW(),
                        expires_at = NOW() + INTERVAL '30 days'
                    """,
                    cacheKey,
                    value(request, "area_kind", "search"),
                    value(request, "query", value(request, "city", "")),
                    value(request, "lang", "en"),
                    number(request.get("south")),
                    number(request.get("west")),
                    number(request.get("north")),
                    number(request.get("east")),
                    json(request),
                    json(response));
        } catch (DataAccessException exception) {
            logCatalogReadFailure(exception);
        }
    }

    /**
     * Persists provider records, applies exact identifier matches, and collapses
     * records closer than 50 m. Pairs between 50 m and 300 m remain distinct and
     * are added to the manual review queue because no verifier key is configured.
     */
    @Transactional
    public List<Map<String, Object>> persistAndCanonicalize(
            List<Map<String, Object>> incomingPlaces) {
        if (!catalogAvailable() || incomingPlaces == null || incomingPlaces.isEmpty()) {
            return incomingPlaces == null ? List.of() : incomingPlaces;
        }
        try {
            // Serialize the short identity-check/write section across server instances.
            jdbc.execute("SELECT pg_advisory_xact_lock(22814188)");
            List<Map<String, Object>> result = new ArrayList<>(incomingPlaces.size());
            for (Map<String, Object> incoming : incomingPlaces) {
                result.add(persistOne(incoming));
            }
            return List.copyOf(result);
        } catch (DataAccessException exception) {
            throw exception;
        }
    }

    /**
     * Searches aliases collected from provider responses, prioritizing exact,
     * then prefix matches and popularity. The query works across stored languages.
     */
    public List<Map<String, Object>> searchAliases(String query, String language, int limit) {
        String normalized = normalize(query);
        if (normalized.length() < 2 || !catalogAvailable()) return List.of();
        String like = escapeLike(normalized);
        int safeLimit = Math.max(1, Math.min(ALIAS_RESULT_LIMIT, limit));
        try {
            List<Map<String, Object>> rows = jdbc.queryForList("""
                    SELECT DISTINCT ON (COALESCE(root.id, place.id))
                           COALESCE(root.payload, place.payload)::text AS payload,
                           alias.alias_name,
                           COALESCE(root.provider_place_id, place.provider_place_id) AS xid,
                           COALESCE(root.id, place.id)::text AS canonical_place_id,
                           COALESCE(root.rate, place.rate, 0) AS rate
                    FROM landmark_place_aliases alias
                    JOIN landmark_places place ON place.id = alias.canonical_place_id
                    LEFT JOIN landmark_places root
                        ON root.id = place.canonical_place_id
                    WHERE alias.normalized_name LIKE '%' || ? || '%' ESCAPE '\\'
                    ORDER BY COALESCE(root.id, place.id),
                             CASE
                               WHEN alias.normalized_name = ? THEN 0
                               WHEN alias.normalized_name LIKE ? || '%' ESCAPE '\\' THEN 1
                               ELSE 2
                             END,
                             COALESCE(root.rate, place.rate, 0) DESC,
                             alias.alias_name
                    LIMIT ?
                    """, like, normalized, like, safeLimit);
            List<Map<String, Object>> suggestions = new ArrayList<>();
            for (Map<String, Object> row : rows) {
                Map<String, Object> place = readMap(row.get("payload"));
                if (place.isEmpty()) continue;
                Map<String, Object> suggestion = new LinkedHashMap<>();
                String matchedName = value(row, "alias_name", value(place, "name", ""));
                suggestion.put("label", matchedName);
                suggestion.put("city", value(place, "city", ""));
                suggestion.put("country", value(place, "country", ""));
                suggestion.put("country_code", value(place, "country_code", ""));
                suggestion.put("result_type", "landmark");
                suggestion.put("place_id", value(row, "xid", value(place, "xid", "")));
                suggestion.put("canonical_place_id", row.get("canonical_place_id"));
                suggestion.put("latitude", place.get("latitude"));
                suggestion.put("longitude", place.get("longitude"));
                suggestion.put("source_provider", value(place, "source_provider", "opentripmap"));
                suggestion.put("wikidata_id", place.get("wikidata_id"));
                suggestions.add(suggestion);
            }
            return List.copyOf(suggestions);
        } catch (DataAccessException exception) {
            logCatalogReadFailure(exception);
            return List.of();
        }
    }

    /** Returns full canonical attraction payloads for global alias searches. */
    public List<Map<String, Object>> searchCachedPlaces(
            String query, String language, int limit) {
        String normalized = normalize(query);
        if (normalized.length() < 2 || !catalogAvailable()) return List.of();
        String like = escapeLike(normalized);
        int safeLimit = Math.max(1, Math.min(100, limit));
        try {
            List<Map<String, Object>> rows = jdbc.queryForList("""
                    SELECT DISTINCT ON (COALESCE(root.id, place.id))
                           COALESCE(root.payload, place.payload)::text AS payload,
                           alias.alias_name,
                           COALESCE(root.provider_place_id, place.provider_place_id) AS xid,
                           COALESCE(root.id, place.id)::text AS canonical_place_id
                    FROM landmark_place_aliases alias
                    JOIN landmark_places place ON place.id = alias.canonical_place_id
                    LEFT JOIN landmark_places root
                        ON root.id = place.canonical_place_id
                    WHERE alias.normalized_name LIKE '%' || ? || '%' ESCAPE '\\'
                    ORDER BY COALESCE(root.id, place.id),
                             CASE
                               WHEN alias.normalized_name = ? THEN 0
                               WHEN alias.normalized_name LIKE ? || '%' ESCAPE '\\' THEN 1
                               ELSE 2
                             END,
                             CASE WHEN alias.language = ? THEN 0 ELSE 1 END,
                             COALESCE(root.rate, place.rate, 0) DESC,
                             alias.alias_name
                    LIMIT ?
                    """, like, normalized, like, language == null ? "en" : language, safeLimit);
            List<Map<String, Object>> places = new ArrayList<>();
            for (Map<String, Object> row : rows) {
                Map<String, Object> place = readMap(row.get("payload"));
                if (place.isEmpty()) continue;
                place.put("canonical_place_id", row.get("canonical_place_id"));
                place.put("id", row.get("xid"));
                place.putIfAbsent("xid", row.get("xid"));
                place.put("matched_alias", row.get("alias_name"));
                places.add(place);
            }
            return List.copyOf(places);
        } catch (DataAccessException exception) {
            logCatalogReadFailure(exception);
            return List.of();
        }
    }

    private Map<String, Object> persistOne(Map<String, Object> input) {
        Map<String, Object> incoming = new LinkedHashMap<>(input);
        String xid = value(incoming, "xid", value(incoming, "id", ""));
        String provider = value(incoming, "source_provider", "opentripmap");
        Double latitude = number(incoming.get("latitude"));
        Double longitude = number(incoming.get("longitude"));
        if (!"opentripmap".equals(provider) || !PROVIDER_ID.matcher(xid).matches()
                || latitude == null || longitude == null
                || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
            return incoming;
        }

        String wikidataId = value(incoming, "wikidata_id", "");
        CatalogPlace canonical = wikidataId.isBlank() ? null : byWikidata(wikidataId);
        if (canonical == null) canonical = byProviderId(provider, xid);
        if (canonical != null) {
            Map<String, Object> merged = fillMissing(canonical.payload(), incoming);
            updateRoot(canonical.id(), merged, incoming);
            saveAlias(canonical.id(), incoming, "opentripmap");
            insertSourceIdentity(provider, xid, canonical, incoming);
            return withCanonicalIdentity(merged, canonical.id(), canonical.providerPlaceId());
        }

        NearbyPlace nearest = nearestRoot(latitude, longitude, xid);
        if (nearest != null && nearest.distanceMeters() < AUTOMATIC_MERGE_METERS) {
            Map<String, Object> merged = fillMissing(nearest.place().payload(), incoming);
            updateRoot(nearest.place().id(), merged, incoming);
            saveAlias(nearest.place().id(), incoming, "opentripmap");
            insertSourceIdentity(provider, xid, nearest.place(), incoming);
            return withCanonicalIdentity(
                    merged, nearest.place().id(), nearest.place().providerPlaceId());
        }

        LandmarkDuplicateVerifier.Verification verification = null;
        if (nearest != null && duplicateVerifier.isAvailable()) {
            try {
                verification = duplicateVerifier.verify(
                        nearest.place().payload(), incoming, nearest.distanceMeters());
            } catch (RuntimeException exception) {
                LOG.warn("Landmark duplicate verification failed; candidate will be queued");
            }
        }
        if (nearest != null && verification != null
                && verification.samePlace() && verification.confidence() >= 0.85) {
            Map<String, Object> merged = fillMissing(nearest.place().payload(), incoming);
            updateRoot(nearest.place().id(), merged, incoming);
            UUID sourceId = insertSourceIdentity(provider, xid, nearest.place(), incoming);
            saveAlias(nearest.place().id(), incoming, "opentripmap");
            recordCandidate(nearest.place().id(), sourceId, nearest.distanceMeters(),
                    verification.confidence(), "merged", incoming);
            return withCanonicalIdentity(
                    merged, nearest.place().id(), nearest.place().providerPlaceId());
        }

        UUID id = UUID.randomUUID();
        Map<String, Object> rootPayload = withCanonicalIdentity(incoming, id, xid);
        insertRoot(id, provider, xid, wikidataId, latitude, longitude, incoming, rootPayload);
        saveAlias(id, incoming, "opentripmap");
        if (nearest != null) {
            boolean needsReview = verification == null
                    || verification.confidence() >= 0.5
                            && verification.confidence() < 0.85;
            String status = needsReview ? "pending" : "separate";
            queueReview(nearest.place(), id, incoming, nearest.distanceMeters(),
                    verification == null ? null : verification.confidence(), status);
        }
        return rootPayload;
    }

    private CatalogPlace byWikidata(String wikidataId) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id::text AS id, provider_place_id, payload::text AS payload
                FROM landmark_places
                WHERE wikidata_id = ? AND canonical_place_id IS NULL
                ORDER BY fetched_at DESC
                LIMIT 1
                FOR UPDATE
                """, wikidataId);
        return rows.isEmpty() ? null : catalogPlace(rows.getFirst());
    }

    private CatalogPlace byProviderId(String provider, String xid) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT COALESCE(root.id, place.id)::text AS id,
                       COALESCE(root.provider_place_id, place.provider_place_id) AS provider_place_id,
                       COALESCE(root.payload, place.payload)::text AS payload
                FROM landmark_places place
                LEFT JOIN landmark_places root ON root.id = place.canonical_place_id
                WHERE place.provider = ? AND place.provider_place_id = ?
                LIMIT 1
                FOR UPDATE OF place
                """, provider, xid);
        return rows.isEmpty() ? null : catalogPlace(rows.getFirst());
    }

    private NearbyPlace nearestRoot(double latitude, double longitude, String xid) {
        double latitudeDelta = NEARBY_CANDIDATE_METERS / 110_000.0;
        double longitudeDelta = Math.min(180.0, latitudeDelta
                / Math.max(0.05, Math.cos(Math.toRadians(latitude))));
        double minLongitude = longitude - longitudeDelta;
        double maxLongitude = longitude + longitudeDelta;
        boolean crossesDateline = minLongitude < -180 || maxLongitude > 180;
        minLongitude = Math.max(-180, minLongitude);
        maxLongitude = Math.min(180, maxLongitude);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id::text AS id, provider_place_id, payload::text AS payload,
                       latitude, longitude
                FROM landmark_places
                WHERE canonical_place_id IS NULL
                  AND provider_place_id <> ?
                  AND latitude BETWEEN ? AND ?
                  AND (? = TRUE OR longitude BETWEEN ? AND ?)
                FOR UPDATE
                """,
                xid,
                Math.max(-90, latitude - latitudeDelta),
                Math.min(90, latitude + latitudeDelta),
                crossesDateline, minLongitude, maxLongitude);
        return rows.stream()
                .map(row -> {
                    CatalogPlace place = catalogPlace(row);
                    double distance = distanceMeters(
                            latitude, longitude,
                            number(row.get("latitude")), number(row.get("longitude")));
                    return new NearbyPlace(place, distance);
                })
                .filter(place -> place.distanceMeters() <= NEARBY_CANDIDATE_METERS)
                .min(Comparator.comparingDouble(NearbyPlace::distanceMeters))
                .orElse(null);
    }

    private void insertRoot(UUID id, String provider, String xid, String wikidataId,
                            double latitude, double longitude, Map<String, Object> source,
                            Map<String, Object> payload) {
        jdbc.update("""
                INSERT INTO landmark_places (
                    id, canonical_place_id, provider, provider_place_id, wikidata_id,
                    latitude, longitude, category, rate, city, country, image_url,
                    names, descriptions, payload, fetched_at, updated_at
                )
                VALUES (?::uuid, NULL, ?, ?, NULLIF(?, ''), ?, ?, ?, ?, ?, ?, ?,
                        ?::jsonb, ?::jsonb, ?::jsonb, NOW(), NOW())
                ON CONFLICT (provider, provider_place_id) DO NOTHING
                """,
                id.toString(), provider, xid, wikidataId, latitude, longitude,
                value(source, "category", "landmark"),
                intValue(source.get("rating")),
                value(source, "city", ""), value(source, "country", ""),
                value(source, "image_url", ""),
                json(names(source)), json(descriptions(source)), json(payload));
    }

    private UUID insertSourceIdentity(String provider, String xid,
                                      CatalogPlace canonical, Map<String, Object> source) {
        if (provider.equals(canonical.provider()) && xid.equals(canonical.providerPlaceId())) {
            return canonical.id();
        }
        UUID sourceId = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO landmark_places (
                    id, canonical_place_id, provider, provider_place_id, wikidata_id,
                    latitude, longitude, category, rate, city, country, image_url,
                    names, descriptions, payload, fetched_at, updated_at
                )
                VALUES (?::uuid, ?::uuid, ?, ?, NULLIF(?, ''), ?, ?, ?, ?, ?, ?, ?,
                        ?::jsonb, ?::jsonb, ?::jsonb, NOW(), NOW())
                ON CONFLICT (provider, provider_place_id) DO NOTHING
                """,
                sourceId.toString(), canonical.id().toString(), provider, xid,
                value(source, "wikidata_id", ""),
                number(source.get("latitude")), number(source.get("longitude")),
                value(source, "category", "landmark"), intValue(source.get("rating")),
                value(source, "city", ""), value(source, "country", ""),
                value(source, "image_url", ""), json(names(source)),
                json(descriptions(source)), json(source));
        return sourceId;
    }

    private void updateRoot(UUID id, Map<String, Object> payload, Map<String, Object> source) {
        jdbc.update("""
                UPDATE landmark_places
                SET payload = ?::jsonb,
                    wikidata_id = COALESCE(NULLIF(wikidata_id, ''), NULLIF(?, '')),
                    image_url = COALESCE(NULLIF(image_url, ''), NULLIF(?, ''), ''),
                    city = COALESCE(NULLIF(city, ''), NULLIF(?, '')),
                    country = COALESCE(NULLIF(country, ''), NULLIF(?, '')),
                    names = ?::jsonb || names,
                    descriptions = ?::jsonb || descriptions,
                    fetched_at = NOW(),
                    updated_at = NOW()
                WHERE id = ?::uuid
                """,
                json(payload), value(source, "wikidata_id", ""),
                value(source, "image_url", ""), value(source, "city", ""),
                value(source, "country", ""), json(names(source)),
                json(descriptions(source)), id.toString());
    }

    private void queueReview(CatalogPlace candidate, UUID newPlaceId,
                             Map<String, Object> incoming, double distanceMeters,
                             Double confidence, String status) {
        recordCandidate(candidate.id(), newPlaceId, distanceMeters,
                confidence, status, incoming);
    }

    private void recordCandidate(UUID firstId, UUID secondId, double distanceMeters,
                                 Double confidence, String status,
                                 Map<String, Object> incoming) {
        boolean firstComesFirst =
                firstId.toString().compareTo(secondId.toString()) < 0;
        UUID left = firstComesFirst ? firstId : secondId;
        UUID right = firstComesFirst ? secondId : firstId;
        jdbc.update("""
                INSERT INTO landmark_merge_candidates (
                    id, left_place_id, right_place_id, distance_meters, confidence,
                    evidence, status, created_at, updated_at
                )
                VALUES (?::uuid, ?::uuid, ?::uuid, ?, ?, ?::jsonb, ?, NOW(), NOW())
                ON CONFLICT (left_place_id, right_place_id) DO NOTHING
                """,
                UUID.randomUUID().toString(), left.toString(), right.toString(),
                distanceMeters, confidence, json(Map.of(
                        "candidate_name", value(incoming, "name", ""),
                        "candidate_city", value(incoming, "city", ""),
                        "candidate_country", value(incoming, "country", ""),
                        "candidate_category", value(incoming, "category", ""),
                        "candidate_latitude", number(incoming.get("latitude")),
                        "candidate_longitude", number(incoming.get("longitude")),
                        "reason", confidence == null
                                ? "verifier_unavailable_or_failed" : "verifier_decision")),
                status);
    }

    private void saveAlias(UUID canonicalId, Map<String, Object> place, String source) {
        String responseLanguage = value(place, "response_language", "en");
        saveAlias(canonicalId, value(place, "name", ""), responseLanguage, source);
        saveAlias(canonicalId, value(place, "name_en", ""), "en", source);
        saveAlias(canonicalId, value(place, "name_ar", ""), "ar", source);
    }

    private void saveAlias(UUID canonicalId, String alias, String language, String source) {
        String normalized = normalize(alias);
        if (normalized.isBlank()) return;
        jdbc.update("""
                INSERT INTO landmark_place_aliases (
                    canonical_place_id, alias_name, normalized_name,
                    language, source, created_at
                )
                VALUES (?::uuid, ?, ?, ?, ?, NOW())
                ON CONFLICT (canonical_place_id, normalized_name, language, source)
                DO NOTHING
                """, canonicalId.toString(), alias.trim(), normalized, language, source);
    }

    private boolean catalogAvailable() {
        Boolean available = schemaAvailable;
        if (available != null) return available;
        synchronized (this) {
            if (schemaAvailable != null) return schemaAvailable;
            try {
                schemaAvailable = Boolean.TRUE.equals(jdbc.queryForObject("""
                        SELECT to_regclass('public.landmark_places') IS NOT NULL
                           AND to_regclass('public.landmark_place_aliases') IS NOT NULL
                           AND to_regclass('public.landmark_search_areas') IS NOT NULL
                           AND to_regclass('public.landmark_merge_candidates') IS NOT NULL
                        """, Boolean.class));
            } catch (DataAccessException exception) {
                schemaAvailable = false;
                LOG.warn("Landmark database cache unavailable; live provider search remains enabled");
            }
            if (!schemaAvailable && missingSchemaLogged.compareAndSet(false, true)) {
                LOG.warn("Landmark catalog migration is not installed; using live OpenTripMap results");
            }
            return schemaAvailable;
        }
    }

    private void logCatalogReadFailure(DataAccessException exception) {
        if (isMissingRelation(exception)) {
            schemaAvailable = false;
            if (missingSchemaLogged.compareAndSet(false, true)) {
                LOG.warn("Landmark catalog migration is not installed; using live OpenTripMap results");
            }
            return;
        }
        LOG.warn("Landmark database cache operation failed; using live provider data");
    }

    private static boolean isMissingRelation(Throwable error) {
        for (Throwable cause = error; cause != null; cause = cause.getCause()) {
            if (cause instanceof SQLException sqlException
                    && "42P01".equals(sqlException.getSQLState())) return true;
        }
        return error instanceof BadSqlGrammarException;
    }

    private CatalogPlace byCanonical(UUID id) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id::text AS id, provider, provider_place_id, payload::text AS payload
                FROM landmark_places WHERE id = ?::uuid
                """, id.toString());
        return rows.isEmpty() ? null : catalogPlace(rows.getFirst());
    }

    private CatalogPlace catalogPlace(Map<String, Object> row) {
        return new CatalogPlace(
                UUID.fromString(String.valueOf(row.get("id"))),
                value(row, "provider", "opentripmap"),
                value(row, "provider_place_id", ""),
                readMap(row.get("payload")));
    }

    private Map<String, Object> readMap(Object value) {
        if (value == null) return new LinkedHashMap<>();
        try {
            return mapper.readValue(String.valueOf(value), MAP_TYPE);
        } catch (Exception exception) {
            return new LinkedHashMap<>();
        }
    }

    private String json(Object value) {
        try {
            return mapper.writeValueAsString(value);
        } catch (Exception exception) {
            throw new IllegalStateException("Could not encode landmark cache record", exception);
        }
    }

    private static Map<String, Object> names(Map<String, Object> place) {
        Map<String, Object> result = new LinkedHashMap<>();
        copyIfPresent(place, result, "name", value(place, "response_language", "en"));
        copyIfPresent(place, result, "name_en", "en");
        copyIfPresent(place, result, "name_ar", "ar");
        return result;
    }

    private static Map<String, Object> descriptions(Map<String, Object> place) {
        Map<String, Object> result = new LinkedHashMap<>();
        String description = value(place, "description", "");
        if (!description.isBlank()) {
            result.put(value(place, "response_language", "en"), description);
        }
        return result;
    }

    private static void copyIfPresent(Map<String, Object> source,
                                      Map<String, Object> target,
                                      String field, String language) {
        String value = value(source, field, "");
        if (!value.isBlank()) target.put(language, value);
    }

    private static Map<String, Object> fillMissing(
            Map<String, Object> existing, Map<String, Object> incoming) {
        Map<String, Object> merged = new LinkedHashMap<>(existing);
        incoming.forEach((key, value) -> {
            Object previous = merged.get(key);
            if (previous == null || previous instanceof String text && text.isBlank()) {
                if (value != null && (!(value instanceof String text) || !text.isBlank())) {
                    merged.put(key, value);
                }
            }
        });
        return merged;
    }

    private static Map<String, Object> withCanonicalIdentity(
            Map<String, Object> place, UUID canonicalId, String providerXid) {
        Map<String, Object> result = new LinkedHashMap<>(place);
        result.put("canonical_place_id", canonicalId.toString());
        result.put("id", providerXid);
        result.putIfAbsent("xid", providerXid);
        return result;
    }

    private static String normalize(String value) {
        if (value == null) return "";
        return value.trim().toLowerCase(Locale.ROOT)
                .replaceAll("[\\u064B-\\u065F\\u0670\\u0640]", "")
                .replace('أ', 'ا').replace('إ', 'ا').replace('آ', 'ا')
                .replace('ة', 'ه').replace('ى', 'ي')
                .replaceAll("\\s+", " ");
    }

    private static String escapeLike(String value) {
        return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
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

    private static int intValue(Object value) {
        Double parsed = number(value);
        return parsed == null ? 0 : Math.max(0, Math.min(3, parsed.intValue()));
    }

    private static double distanceMeters(
            double latitude1, double longitude1,
            Double latitude2Value, Double longitude2Value) {
        if (latitude2Value == null || longitude2Value == null) return Double.MAX_VALUE;
        double latitude2 = latitude2Value;
        double longitude2 = longitude2Value;
        double lat1 = Math.toRadians(latitude1);
        double lat2 = Math.toRadians(latitude2);
        double deltaLat = lat2 - lat1;
        double deltaLon = Math.toRadians(longitude2 - longitude1);
        double a = Math.sin(deltaLat / 2) * Math.sin(deltaLat / 2)
                + Math.cos(lat1) * Math.cos(lat2)
                        * Math.sin(deltaLon / 2) * Math.sin(deltaLon / 2);
        return 6_371_000 * 2 * Math.asin(Math.sqrt(Math.min(1, a)));
    }

    private static String value(Map<String, ?> map, String key, String fallback) {
        Object value = map == null ? null : map.get(key);
        return value == null ? fallback : String.valueOf(value).trim();
    }

    private record CatalogPlace(
            UUID id, String provider, String providerPlaceId, Map<String, Object> payload) {}

    private record NearbyPlace(CatalogPlace place, double distanceMeters) {}
}

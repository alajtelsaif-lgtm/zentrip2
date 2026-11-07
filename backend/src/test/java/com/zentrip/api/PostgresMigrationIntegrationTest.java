package com.zentrip.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Real HTTP-controller/JDBC checks against a disposable, loopback-only PostgreSQL database. */
@SpringBootTest(properties = {
        "app.bootstrap.enabled=false", "spring.sql.init.mode=never",
        "google.places.api-key=", "serpapi.key=", "requesty.api-key=",
        "landmarks.duplicate-verifier.api-key=",
        "spring.datasource.hikari.data-source-properties.prepareThreshold=0"
})
@AutoConfigureMockMvc
@EnabledIfEnvironmentVariable(named = "ZENTRIP_POSTGRES_TEST_URL", matches = "jdbc:postgresql://127\\.0\\.0\\.1:.*")
class PostgresMigrationIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate jdbc;
    @Autowired ObjectMapper json;
    @Autowired LandmarkCatalogService landmarkCatalog;
    long userId;
    String token;

    @DynamicPropertySource
    static void localDatabase(DynamicPropertyRegistry properties) {
        String url = System.getenv("ZENTRIP_POSTGRES_TEST_URL");
        if (url == null || !url.startsWith("jdbc:postgresql://127.0.0.1:")) {
            throw new IllegalStateException("These tests may only use a disposable loopback database");
        }
        properties.add("spring.datasource.url", () -> url);
        properties.add("spring.datasource.username", () -> System.getenv("ZENTRIP_POSTGRES_TEST_USER"));
        properties.add("spring.datasource.password", () -> "");
    }

    @BeforeEach
    void customer() {
        token = UUID.randomUUID().toString();
        userId = jdbc.queryForObject("""
                INSERT INTO users (name, email, password)
                VALUES ('Migration Test', ?, 'unused-test-hash') RETURNING id
                """, Long.class, token + "@example.invalid");
        jdbc.update("INSERT INTO api_tokens (user_id, token_hash, expires_at) VALUES (?, ?, ?)",
                userId, TokenAuthFilter.sha256(token), Timestamp.from(Instant.now().plusSeconds(3600)));
    }

    @Test
    @Transactional
    void hotelDestinationCatalogIsAvailableToTheRuntimeRole() {
        jdbc.execute("SET LOCAL ROLE zentrip_api_runtime");
        String code = "TEST" + UUID.randomUUID().toString().replace("-", "")
                .substring(0, 12);
        jdbc.update("""
                INSERT INTO public.hotel_destinations (
                    destination_type, destination_code, parent_code,
                    name_en, name_ar, country_code, country_name_en,
                    country_name_ar, latitude, longitude, search_text
                ) VALUES ('city', ?, '', 'Paris', 'باريس', 'FR',
                    'France', 'فرنسا', 48.8566, 2.3522, 'paris باريس france فرنسا')
                """, code);

        Map<String, Object> row = jdbc.queryForMap("""
                SELECT name_en, name_ar, destination_code
                FROM public.hotel_destinations
                WHERE destination_code = ?
                """, code);
        assertEquals("Paris", row.get("name_en"));
        assertEquals("باريس", row.get("name_ar"));
        assertEquals(code, row.get("destination_code"));
    }

    @Test
    void landmarkCachePersistsTheWholeViewportForThirtyDays() {
        Map<String, Object> request = Map.of(
                "area_kind", "viewport",
                "query", "باريس",
                "lang", "ar",
                "south", 48.7,
                "west", 2.2,
                "north", 48.9,
                "east", 2.5);
        String cacheKey = landmarkCatalog.cacheKey(request);
        Map<String, Object> response = Map.of(
                "attractions", java.util.List.of(Map.of(
                        "id", "P_TEST",
                        "name", "Test landmark",
                        "latitude", 48.85,
                        "longitude", 2.35)),
                "warnings", java.util.List.of());

        landmarkCatalog.cacheArea(cacheKey, request, response);

        Map<String, Object> cached = landmarkCatalog.cachedArea(cacheKey, false);
        assertNotNull(cached);
        assertEquals("Test landmark",
                ((Map<?, ?>) ((java.util.List<?>) cached.get("attractions")).getFirst())
                        .get("name"));
        assertTrue(jdbc.queryForObject("""
                SELECT expires_at > NOW() + INTERVAL '29 days'
                FROM landmark_search_areas WHERE cache_key = ?
                """, Boolean.class, cacheKey));
    }

    @Test
    @Transactional
    void landmarkCatalogTablesAreAccessibleToTheNoBypassRuntimeRole() {
        jdbc.execute("SET LOCAL ROLE zentrip_api_runtime");
        String cacheKey = landmarkCatalog.cacheKey(Map.of(
                "area_kind", "viewport",
                "query", "runtime-role-" + UUID.randomUUID(),
                "lang", "en"));
        Map<String, Object> request = Map.of(
                "area_kind", "viewport",
                "query", "runtime-role-test",
                "lang", "en");

        landmarkCatalog.cacheArea(cacheKey, request, Map.of("attractions", java.util.List.of()));

        assertNotNull(landmarkCatalog.cachedArea(cacheKey, false));
    }

    @Test
    void landmarkIdentityLinksExactWikidataAliasesAndQueuesNearbyUnverifiedPairs() {
        String firstXid = "P" + UUID.randomUUID().toString().replace("-", "");
        String aliasXid = "P" + UUID.randomUUID().toString().replace("-", "");
        String nearXid = "P" + UUID.randomUUID().toString().replace("-", "");
        Map<String, Object> canonical = landmark(
                firstXid, "Q123456789", 32.64, 14.29, "Ancient Site");
        Map<String, Object> exactAlias = landmark(
                aliasXid, "Q123456789", 32.64, 14.29, "Leptis Magna");
        Map<String, Object> nearbyUncertain = landmark(
                nearXid, "", 32.6408, 14.29, "Nearby Museum");

        Map<String, Object> storedCanonical = landmarkCatalog
                .persistAndCanonicalize(java.util.List.of(canonical)).getFirst();
        Map<String, Object> storedAlias = landmarkCatalog
                .persistAndCanonicalize(java.util.List.of(exactAlias)).getFirst();
        Map<String, Object> storedNearby = landmarkCatalog
                .persistAndCanonicalize(java.util.List.of(nearbyUncertain)).getFirst();

        assertEquals(storedCanonical.get("canonical_place_id"),
                storedAlias.get("canonical_place_id"));
        assertEquals(firstXid, storedAlias.get("id"));
        assertNotEquals(storedCanonical.get("canonical_place_id"),
                storedNearby.get("canonical_place_id"));
        assertEquals(2, jdbc.queryForObject("""
                SELECT COUNT(*) FROM landmark_place_aliases
                WHERE canonical_place_id = ?::uuid
                """, Integer.class, storedCanonical.get("canonical_place_id")));
        assertEquals(1, landmarkCatalog.searchCachedPlaces("Leptis", "en", 5).size());
        assertEquals("Leptis Magna",
                landmarkCatalog.searchAliases("Leptis", "en", 5).getFirst().get("label"));
        assertEquals(1, jdbc.queryForObject("""
                SELECT COUNT(*) FROM landmark_merge_candidates
                WHERE status = 'pending'
                  AND distance_meters BETWEEN 50 AND 300
                """, Integer.class));
    }

    private static Map<String, Object> landmark(
            String xid, String wikidataId, double latitude, double longitude, String name) {
        Map<String, Object> place = new java.util.LinkedHashMap<>();
        place.put("id", xid);
        place.put("xid", xid);
        place.put("source_provider", "opentripmap");
        place.put("wikidata_id", wikidataId);
        place.put("name", name);
        place.put("name_en", name);
        place.put("response_language", "en");
        place.put("city", "Khoms");
        place.put("country", "Libya");
        place.put("category", "historical");
        place.put("rating", 2);
        place.put("latitude", latitude);
        place.put("longitude", longitude);
        place.put("image_url", "");
        place.put("description", "");
        return place;
    }

    long listing(String type, String attributes) {
        long partnerId = jdbc.queryForObject("""
                INSERT INTO partners (slug, name, service_type)
                VALUES (?, 'Migration partner', ?) RETURNING id
                """, Long.class, UUID.randomUUID().toString(), type);
        return jdbc.queryForObject("""
                INSERT INTO partner_listings
                    (partner_id, type, title, city, country, price, attributes, available_rooms)
                VALUES (?, ?, 'Migration listing', 'Tripoli', 'Libya', 100, ?::jsonb, 10)
                RETURNING id
                """, Long.class, partnerId, type, attributes);
    }

    JsonNode postJson(String path, Map<String, Object> body, int status) throws Exception {
        MvcResult result = http.perform(post(path).header("Authorization", "Bearer " + token)
                        .contentType("application/json").content(json.writeValueAsString(body)))
                .andExpect(status().is(status)).andReturn();
        return json.readTree(result.getResponse().getContentAsString());
    }

    Map<String, Object> booking(String type, long listing) {
        return Map.of("type", type, "title", "Migration booking", "subtitle", "Test",
                "date", "2035-11-10T10:00:00+02:00", "end_date", "2035-11-12T10:00:00+02:00",
                "partner_listing_id", listing, "price", 1, "rooms", 2);
    }

    @Test
    void adminAttractionPopularityAggregatesCountsAndHandlesUnspecifiedCountries()
            throws Exception {
        jdbc.update("UPDATE users SET role = 'admin' WHERE id = ?", userId);
        String suffix = UUID.randomUUID().toString();
        String country = "Popularity-" + suffix;
        String firstId = "popularity-first-" + suffix;
        String secondId = "popularity-second-" + suffix;
        String unspecifiedId = "popularity-unspecified-" + suffix;
        jdbc.update("""
                INSERT INTO tourist_monuments (id, title, location, description, tags)
                VALUES (?, ?, ?, 'Test attraction', '[]'::jsonb)
                """, firstId, "Popularity place one " + suffix, "Tripoli, " + country);
        jdbc.update("""
                INSERT INTO tourist_monuments (id, title, location, description, tags)
                VALUES (?, ?, ?, 'Test attraction', '[]'::jsonb)
                """, secondId, "Popularity place two " + suffix,
                "Benghazi, " + country.toLowerCase());
        jdbc.update("""
                INSERT INTO tourist_monuments (id, title, location, description, tags)
                VALUES (?, ?, 'Ghadames', 'Test attraction', '[]'::jsonb)
                """, unspecifiedId, "Popularity place unspecified " + suffix);
        jdbc.update("""
                INSERT INTO attraction_visit_counts (attraction_id, visit_count)
                VALUES (?, 4), (?, 6)
                """, firstId, secondId);

        MvcResult result = http.perform(get("/api/admin/attractions/popularity")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andReturn();
        JsonNode response = json.readTree(result.getResponse().getContentAsString());

        JsonNode countryTotal = null;
        for (JsonNode row : response.path("countries")) {
            if (row.path("country").asText().equalsIgnoreCase(country)) {
                countryTotal = row;
                break;
            }
        }
        assertNotNull(countryTotal);
        assertEquals(10, countryTotal.path("visit_count").asInt());

        JsonNode unspecifiedPlace = null;
        for (JsonNode row : response.path("places")) {
            if (row.path("title").asText().equals("Popularity place unspecified " + suffix)) {
                unspecifiedPlace = row;
                break;
            }
        }
        assertNotNull(unspecifiedPlace);
        assertEquals("", unspecifiedPlace.path("country").asText());
        assertEquals(0, unspecifiedPlace.path("visit_count").asInt());
        assertFalse(response.toString().contains("visitor_hash"));
        assertFalse(response.toString().contains("visitor_id"));
    }

    @Test
    void adminPartnerChangesCanBeReversedWithoutDeletingTheirHistory() throws Exception {
        jdbc.update("UPDATE users SET role = 'admin' WHERE id = ?", userId);
        String ownerToken = UUID.randomUUID().toString();
        String email = ownerToken + "@example.invalid";
        long ownerId = jdbc.queryForObject("""
                INSERT INTO users (name, email, password)
                VALUES ('Partner Owner', ?, 'unused-test-hash') RETURNING id
                """, Long.class, email);
        jdbc.update("INSERT INTO api_tokens (user_id, token_hash, expires_at) VALUES (?, ?, ?)",
                ownerId, TokenAuthFilter.sha256(ownerToken),
                Timestamp.from(Instant.now().plusSeconds(3600)));

        JsonNode created = postJson("/api/admin/partners", Map.of(
                "name", "Integration Airline",
                "email", email,
                "service_type", "airline"), 201);
        long partnerId = created.path("partner").path("id").asLong();
        assertTrue(partnerId > 0);
        assertEquals("partner", jdbc.queryForObject(
                "SELECT role FROM users WHERE id = ?", String.class, ownerId));
        assertEquals(partnerId, jdbc.queryForObject(
                "SELECT partner_id FROM users WHERE id = ?", Long.class, ownerId));

        long listingId = jdbc.queryForObject("""
                INSERT INTO partner_listings
                    (partner_id, type, title, city, country, price, attributes)
                VALUES (?, 'flight', 'Preserved flight', 'Tripoli', 'Libya', 120, '{}'::jsonb)
                RETURNING id
                """, Long.class, partnerId);
        http.perform(get("/api/partner/dashboard")
                        .header("Authorization", "Bearer " + ownerToken))
                .andExpect(status().isOk());
        http.perform(get("/api/admin/partners")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.partners[?(@.id == " + partnerId + ")]").exists());

        http.perform(get("/api/admin/dashboard")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.summary.total_user_count").isNumber())
                .andExpect(jsonPath("$.summary.partner_count").isNumber());

        http.perform(delete("/api/admin/partners/" + partnerId)
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
        assertEquals("inactive", jdbc.queryForObject(
                "SELECT status FROM partners WHERE id = ?", String.class, partnerId));
        assertEquals("customer", jdbc.queryForObject(
                "SELECT role FROM users WHERE id = ?", String.class, ownerId));
        assertEquals(partnerId, jdbc.queryForObject(
                "SELECT partner_id FROM users WHERE id = ?", Long.class, ownerId));
        assertEquals(1, jdbc.queryForObject(
                "SELECT COUNT(*) FROM partner_listings WHERE id = ?", Integer.class, listingId));
        http.perform(get("/api/partner/dashboard")
                        .header("Authorization", "Bearer " + ownerToken))
                .andExpect(status().isForbidden());

        http.perform(post("/api/admin/partners/" + partnerId + "/activate")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
        assertEquals("active", jdbc.queryForObject(
                "SELECT status FROM partners WHERE id = ?", String.class, partnerId));
        assertEquals("partner", jdbc.queryForObject(
                "SELECT role FROM users WHERE id = ?", String.class, ownerId));
        http.perform(get("/api/partner/dashboard")
                        .header("Authorization", "Bearer " + ownerToken))
                .andExpect(status().isOk());
    }

    @Test
    void legacyAttractionReviewMapsChosenPlacesAndRetiresOnlyAfterAdminApproval()
            throws Exception {
        jdbc.update("UPDATE users SET role = 'admin' WHERE id = ?", userId);
        long partnerId = jdbc.queryForObject("""
                INSERT INTO partners (slug, name, service_type, status)
                VALUES (?, 'Legacy Attractions', 'attraction', 'active')
                RETURNING id
                """, Long.class, UUID.randomUUID().toString());
        String ownerEmail = UUID.randomUUID() + "@example.invalid";
        long ownerId = jdbc.queryForObject("""
                INSERT INTO users (name, email, password, role, partner_id)
                VALUES ('Attraction Owner', ?, 'unused-test-hash', 'partner', ?)
                RETURNING id
                """, Long.class, ownerEmail, partnerId);
        jdbc.update("""
                INSERT INTO tourist_monuments
                    (id, title, location, description, tags)
                VALUES ('integration-existing-place', 'Existing Place', 'Tripoli, Libya',
                        'Already curated', '[]'::jsonb)
                """);
        long createListingId = jdbc.queryForObject("""
                INSERT INTO partner_listings
                    (partner_id, type, title, city, country, description, image_url,
                     price, active, attributes)
                VALUES (?, 'attraction', 'Old City Museum', 'Tripoli', 'Libya',
                        'Historic museum', 'https://example.invalid/museum.jpg',
                        3.50, TRUE,
                        '{"category":"museum","rating":4.8,"review_count":27,
                          "opening_hours":"9:00-17:00","tags":["History","Artifacts"]}'::jsonb)
                RETURNING id
                """, Long.class, partnerId);
        long omitListingId = jdbc.queryForObject("""
                INSERT INTO partner_listings
                    (partner_id, type, title, city, country, description, attributes)
                VALUES (?, 'attraction', 'Unverified site', 'Tripoli', 'Libya',
                        'Details need research', '{}'::jsonb)
                RETURNING id
                """, Long.class, partnerId);
        long existingListingId = jdbc.queryForObject("""
                INSERT INTO partner_listings
                    (partner_id, type, title, city, country, description, attributes)
                VALUES (?, 'attraction', 'Existing Place Duplicate', 'Tripoli', 'Libya',
                        'Same landmark', '{}'::jsonb)
                RETURNING id
                """, Long.class, partnerId);
        long otherTypeListingId = jdbc.queryForObject("""
                INSERT INTO partner_listings
                    (partner_id, type, title, city, country, description, attributes)
                VALUES (?, 'hotel', 'Legacy hotel', 'Tripoli', 'Libya',
                        'Non-place inventory', '{}'::jsonb)
                RETURNING id
                """, Long.class, partnerId);

        http.perform(get("/api/admin/partners/legacy-attractions")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.partners[?(@.id == " + partnerId + ")].listings.length()")
                        .value(4))
                .andExpect(jsonPath("$.partners[?(@.id == " + partnerId + ")].accounts[0]")
                        .value(ownerEmail));

        http.perform(delete("/api/admin/partners/" + partnerId)
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isConflict());
        assertEquals("active", jdbc.queryForObject(
                "SELECT status FROM partners WHERE id = ?", String.class, partnerId));

        JsonNode approved = postJson("/api/admin/partners/" + partnerId + "/attraction-review",
                Map.of(
                        "approved", true,
                        "listings", java.util.List.of(
                                Map.of("listing_id", createListingId, "action", "create"),
                                Map.of("listing_id", omitListingId, "action", "omit"),
                                Map.of("listing_id", existingListingId,
                                        "action", "existing",
                                        "monument_id", "integration-existing-place"))),
                200);
        assertEquals(2, approved.path("mapped_listing_count").asInt());
        assertEquals(1, approved.path("omitted_listing_count").asInt());

        assertEquals("inactive", jdbc.queryForObject(
                "SELECT status FROM partners WHERE id = ?", String.class, partnerId));
        assertEquals("customer", jdbc.queryForObject(
                "SELECT role FROM users WHERE id = ?", String.class, ownerId));
        assertEquals(4, jdbc.queryForObject(
                "SELECT COUNT(*) FROM partner_listings WHERE partner_id = ?",
                Integer.class, partnerId));
        assertEquals(1, jdbc.queryForObject(
                "SELECT COUNT(*) FROM partner_listings WHERE id = ? AND active = TRUE",
                Integer.class, createListingId));
        assertEquals(1, jdbc.queryForObject(
                "SELECT COUNT(*) FROM partner_listings WHERE id = ?",
                Integer.class, otherTypeListingId));
        assertEquals("Old City Museum", jdbc.queryForObject(
                "SELECT title FROM tourist_monuments WHERE id <> 'integration-existing-place' "
                        + "AND title = 'Old City Museum'",
                String.class));
        assertEquals("[\"History\", \"Artifacts\"]", jdbc.queryForObject(
                "SELECT tags::text FROM tourist_monuments WHERE title = 'Old City Museum'",
                String.class));
        assertEquals(userId, jdbc.queryForObject(
                "SELECT reviewed_by FROM legacy_attraction_partner_reviews WHERE partner_id = ?",
                Long.class, partnerId));

        http.perform(get("/api/admin/partners/legacy-attractions")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.partners[?(@.id == " + partnerId + ")].reviewed_at")
                        .exists());
    }

    @Test
    void registrationReturnsOneGeneratedIdAndValidSession() throws Exception {
        String email = UUID.randomUUID() + "@example.invalid";
        MvcResult result = http.perform(multipart("/api/auth/register")
                        .param("name", "New Customer").param("email", email).param("phone", "123456789")
                        .param("password", "test-password-123").param("password_confirmation", "test-password-123"))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.token").isString()).andReturn();
        String session = json.readTree(result.getResponse().getContentAsString()).get("token").asText();
        http.perform(get("/api/auth/me").header("Authorization", "Bearer " + session))
                .andExpect(status().isOk()).andExpect(jsonPath("$.user.email").value(email));
        assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM users WHERE email = ?", Integer.class, email));
    }

    @Test
    void loginTrimsAndMatchesEmailWithoutCaseSensitivity() throws Exception {
        String password = UUID.randomUUID().toString();
        String email = jdbc.queryForObject(
                "SELECT email FROM users WHERE id = ?", String.class, userId).toUpperCase(java.util.Locale.ROOT);
        jdbc.update("UPDATE users SET email = ?, password = ? WHERE id = ?", email,
                new org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder().encode(password),
                userId);
        JsonNode response = postJson("/api/auth/login",
                Map.of("email", "  " + email.toLowerCase(java.util.Locale.ROOT) + "  ",
                        "password", password), 200);
        assertFalse(response.path("token").asText().isBlank());
    }

    @Test
    void customerBookingHistoryReturnsAllOwnFlightAndStayRecordsOnly() throws Exception {
        long otherUserId = jdbc.queryForObject("""
                INSERT INTO users (name, email, password)
                VALUES ('Other Customer', ?, 'unused-test-hash') RETURNING id
                """, Long.class, UUID.randomUUID() + "@example.invalid");

        long ownHotelId = jdbc.queryForObject("""
                INSERT INTO bookings (
                    user_id, type, status, total_amount, details, title, subtitle,
                    "date", ref_code
                ) VALUES (
                    ?, 'hotel', 'upcoming', 120.00,
                    '{"end_date":"2035-11-12T11:00:00Z","image_url":"https://example.test/stay.jpg","rooms":2}'::jsonb,
                    'Harbor Hotel', 'Tunis', ?, 'HOTEL-OWN'
                ) RETURNING id
                """, Long.class, userId, Timestamp.from(Instant.parse("2035-11-10T14:00:00Z")));
        long ownAttractionId = jdbc.queryForObject("""
                INSERT INTO bookings (
                    user_id, type, status, total_amount, price, title, subtitle, "date", ref_code
                ) VALUES (?, 'attraction', 'upcoming', 25.00, 25.00,
                    'Museum Visit', 'Tunis', ?, 'TOUR-OWN')
                RETURNING id
                """, Long.class, userId, Timestamp.from(Instant.parse("2035-11-08T10:00:00Z")));
        long otherBookingId = jdbc.queryForObject("""
                INSERT INTO bookings (user_id, type, status, total_amount, title, subtitle, "date")
                VALUES (?, 'hotel', 'upcoming', 90.00, 'Private Stay', 'Tunis', ?)
                RETURNING id
                """, Long.class, otherUserId, Timestamp.from(Instant.parse("2035-11-15T14:00:00Z")));

        long ownFlightId = jdbc.queryForObject("""
                INSERT INTO trips (
                    user_id, title, destination, origin_code, origin_city,
                    destination_code, destination_city, departure_date, flight_number
                ) VALUES (?, 'My flight', 'Tunis', 'MJI', 'Misrata',
                    'TUN', 'Tunis', ?, 'ZT410')
                RETURNING id
                """, Long.class, userId, Timestamp.from(Instant.parse("2035-11-07T08:00:00Z")));
        long otherFlightId = jdbc.queryForObject("""
                INSERT INTO trips (user_id, title, destination, departure_date, flight_number)
                VALUES (?, 'Private flight', 'Cairo', ?, 'ZT900')
                RETURNING id
                """, Long.class, otherUserId, Timestamp.from(Instant.parse("2035-11-20T08:00:00Z")));

        JsonNode bookings = json.readTree(http.perform(get("/api/bookings")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString()).path("bookings");
        assertEquals(2, bookings.size());
        assertTrue(java.util.stream.StreamSupport.stream(bookings.spliterator(), false)
                .anyMatch(booking -> booking.path("id").asLong() == ownHotelId));
        assertTrue(java.util.stream.StreamSupport.stream(bookings.spliterator(), false)
                .anyMatch(booking -> booking.path("id").asLong() == ownAttractionId));
        assertFalse(java.util.stream.StreamSupport.stream(bookings.spliterator(), false)
                .anyMatch(booking -> booking.path("id").asLong() == otherBookingId));
        JsonNode hotel = java.util.stream.StreamSupport.stream(bookings.spliterator(), false)
                .filter(booking -> booking.path("id").asLong() == ownHotelId)
                .findFirst().orElseThrow();
        assertEquals(120.00, hotel.path("price").asDouble());
        assertEquals("2", hotel.path("rooms").asText());

        JsonNode trips = json.readTree(http.perform(get("/api/trips")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString()).path("trips");
        assertEquals(1, trips.size());
        assertEquals(ownFlightId, trips.get(0).path("id").asLong());
        assertFalse(java.util.stream.StreamSupport.stream(trips.spliterator(), false)
                .anyMatch(trip -> trip.path("id").asLong() == otherFlightId));
    }

    @Test
    void carBookingReturnsIdAndCancellationRestoresInventory() throws Exception {
        long listing = listing("car", "{\"available_vehicles\":1}");
        JsonNode response = postJson("/api/bookings", booking("car", listing), 201);
        long id = response.path("booking").path("id").asLong();
        assertTrue(id > 0);
        Map<String, Object> notification = jdbc.queryForMap("""
                SELECT user_id, kind, target_type, target_id, booking_ref
                FROM user_notifications WHERE event_key = ?
                """, "booking:" + id);
        assertEquals(userId, ((Number) notification.get("user_id")).longValue());
        assertEquals("booking", notification.get("kind"));
        assertEquals("booking", notification.get("target_type"));
        assertEquals(id, ((Number) notification.get("target_id")).longValue());
        assertEquals("0", jdbc.queryForObject(
                "SELECT attributes ->> 'available_vehicles' FROM partner_listings WHERE id = ?", String.class, listing));
        assertEquals(Instant.parse("2035-11-10T08:00:00Z"), jdbc.queryForObject(
                "SELECT \"date\" FROM bookings WHERE id = ?", Timestamp.class, id).toInstant());
        http.perform(delete("/api/bookings/" + id).header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
        assertEquals("1", jdbc.queryForObject(
                "SELECT attributes ->> 'available_vehicles' FROM partner_listings WHERE id = ?", String.class, listing));
        assertEquals(1, jdbc.queryForObject("SELECT count(*) FROM bookings WHERE id = ?", Integer.class, id));
    }

    @Test
    void hotelBookingAndRepeatedCancellationRestoreRoomsOnlyOnce() throws Exception {
        long listing = listing("hotel", "{}");
        long id = postJson("/api/bookings", booking("hotel", listing), 201)
                .path("booking").path("id").asLong();
        assertEquals(8, jdbc.queryForObject(
                "SELECT available_rooms FROM partner_listings WHERE id = ?", Integer.class, listing));
        for (int i = 0; i < 2; i++) {
            http.perform(delete("/api/bookings/" + id).header("Authorization", "Bearer " + token))
                    .andExpect(status().isOk());
        }
        assertEquals(10, jdbc.queryForObject(
                "SELECT available_rooms FROM partner_listings WHERE id = ?", Integer.class, listing));
    }

    @Test
    void taxiBookingCreatesBothTransferAndSchedule() throws Exception {
        JsonNode response = postJson("/api/transfers", Map.of(
                "provider_name", "Migration taxi", "vehicle_type", "sedan",
                "pickup_location", "Tripoli Airport", "dropoff_location", "Tripoli",
                "pickup_time", "2035-11-10T10:00:00+02:00", "duration_minutes", 60, "price", 50), 201);
        long id = response.path("transfer").path("id").asLong();
        assertTrue(id > 0);
        assertEquals(60, jdbc.queryForObject(
                "SELECT duration_minutes FROM transfer_schedules WHERE transfer_id = ?", Integer.class, id));
        assertEquals(Instant.parse("2035-11-10T08:00:00Z"), jdbc.queryForObject(
                "SELECT pickup_time FROM transfers WHERE id = ?", Timestamp.class, id).toInstant());
    }

    @Test
    void failedPaymentAttemptIsSavedButCannotCreateBookingAndSuccessIsOwnerScoped()
            throws Exception {
        JsonNode failedSession = postJson("/api/payments/checkout",
                Map.of("amount", 25, "currency", "USD"), 200);
        String failedSessionId = failedSession.path("session_id").asText();
        JsonNode failedAttempt = postJson(
                "/api/payments/verify/" + failedSessionId,
                Map.of("paid", false, "amount", 25, "currency", "USD"), 201);
        long failedAttemptId = failedAttempt.path("attempt_id").asLong();

        Map<String, Object> failedBooking = new java.util.HashMap<>(Map.of(
                "type", "attraction",
                "title", "Failed payment attraction",
                "subtitle", "Tripoli",
                "date", "2035-11-12T10:00:00Z",
                "price", 25,
                "ref_code", "ZT-FAILED-PAYMENT"));
        failedBooking.put("payment_attempt_id", failedAttemptId);
        postJson("/api/bookings", failedBooking, 402);
        assertEquals(0, jdbc.queryForObject(
                "SELECT COUNT(*) FROM bookings WHERE user_id = ?", Integer.class, userId));
        assertEquals("failed", jdbc.queryForObject(
                "SELECT status FROM payment_attempts WHERE id = ?",
                String.class, failedAttemptId));

        JsonNode successSession = postJson("/api/payments/checkout",
                Map.of("amount", 25, "currency", "USD"), 200);
        String successSessionId = successSession.path("session_id").asText();
        long successfulAttemptId = postJson(
                "/api/payments/verify/" + successSessionId,
                Map.of("paid", true, "amount", 25, "currency", "USD"), 201)
                .path("attempt_id").asLong();
        Map<String, Object> successfulBooking = new java.util.HashMap<>(failedBooking);
        successfulBooking.put("title", "Successful payment attraction");
        successfulBooking.put("payment_attempt_id", successfulAttemptId);
        long bookingId = postJson("/api/bookings", successfulBooking, 201)
                .path("booking").path("id").asLong();
        assertEquals(bookingId, jdbc.queryForObject(
                "SELECT booking_id FROM payment_attempts WHERE id = ?",
                Long.class, successfulAttemptId));

        String otherToken = UUID.randomUUID().toString();
        long otherUserId = jdbc.queryForObject("""
                INSERT INTO users (name, email, password)
                VALUES ('Other payment user', ?, 'unused-test-hash') RETURNING id
                """, Long.class, otherToken + "@example.invalid");
        jdbc.update("""
                INSERT INTO api_tokens (user_id, token_hash, expires_at)
                VALUES (?, ?, ?)
                """, otherUserId, TokenAuthFilter.sha256(otherToken),
                Timestamp.from(Instant.now().plusSeconds(3600)));
        http.perform(get("/api/payments/verify/" + successSessionId)
                        .header("Authorization", "Bearer " + otherToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.attempted").value(false))
                .andExpect(jsonPath("$.paid").value(false));
    }

    @Test
    @Transactional
    void paymentAttemptRowsCanOnlyBeReadAndChangedByTheirOwner() {
        long otherUserId = jdbc.queryForObject("""
                INSERT INTO users (name, email, password)
                VALUES ('Other payment owner', ?, 'unused-test-hash') RETURNING id
                """, Long.class, UUID.randomUUID() + "@example.invalid");
        long ownAttemptId = jdbc.queryForObject("""
                INSERT INTO payment_attempts (session_id, user_id, amount, currency, status)
                VALUES (?, ?, 12.50, 'USD', 'failed') RETURNING id
                """, Long.class, "own-payment-" + UUID.randomUUID(), userId);
        long otherAttemptId = jdbc.queryForObject("""
                INSERT INTO payment_attempts (session_id, user_id, amount, currency, status)
                VALUES (?, ?, 18.00, 'EUR', 'success') RETURNING id
                """, Long.class, "other-payment-" + UUID.randomUUID(), otherUserId);

        assumeRuntime(userId, "customer", null);
        assertEquals(1, visibleCount(
                "SELECT COUNT(*) FROM payment_attempts WHERE id IN (?, ?)",
                ownAttemptId, otherAttemptId));
        assertEquals(0, jdbc.update(
                "UPDATE payment_attempts SET status = 'failed' WHERE id = ?",
                otherAttemptId));
        jdbc.execute("SAVEPOINT reject_foreign_payment_delete");
        assertThrows(org.springframework.dao.DataAccessException.class,
                () -> jdbc.update(
                        "DELETE FROM payment_attempts WHERE id = ?", otherAttemptId));
        jdbc.execute("ROLLBACK TO SAVEPOINT reject_foreign_payment_delete");

        jdbc.execute("SAVEPOINT reject_foreign_payment_insert");
        assertThrows(org.springframework.dao.DataAccessException.class, () -> jdbc.update("""
                INSERT INTO payment_attempts (session_id, user_id, amount, currency, status)
                VALUES (?, ?, 7.00, 'USD', 'failed')
                """, "forged-payment-" + UUID.randomUUID(), otherUserId));
        jdbc.execute("ROLLBACK TO SAVEPOINT reject_foreign_payment_insert");
        assertEquals(1, visibleCount(
                "SELECT COUNT(*) FROM payment_attempts WHERE id = ?", ownAttemptId));
        assertEquals(0, visibleCount(
                "SELECT COUNT(*) FROM payment_attempts WHERE id = ?", otherAttemptId));
    }

    @Test
    @Transactional
    void duffelTripReturnsPersistedSeatsAndExtrasFromTripHistory() throws Exception {
        String sessionId = postJson("/api/payments/checkout",
                Map.of("amount", 137, "currency", "EUR"), 200)
                .path("session_id").asText();
        long attemptId = postJson("/api/payments/verify/" + sessionId,
                Map.of("paid", true, "amount", 137, "currency", "EUR"), 201)
                .path("attempt_id").asLong();
        Map<String, Object> body = new java.util.HashMap<>();
        body.put("origin_code", "MRA");
        body.put("origin_city", "Misrata");
        body.put("destination_code", "TUN");
        body.put("destination_city", "Tunis");
        body.put("departure_date", "2035-11-10T08:00:00Z");
        body.put("arrival_date", "2035-11-10T10:00:00Z");
        body.put("flight_number", "EA123");
        body.put("airline", "Example Air");
        body.put("is_direct", true);
        body.put("seat_class", "economy");
        body.put("price", 137);
        body.put("booking_ref", "ZT-DUF-SEATS");
        body.put("passenger_count", 2);
        body.put("source", "duffel");
        body.put("duffel_offer_id", "off_test_123");
        body.put("price_currency", "EUR");
        body.put("is_simulated", true);
        body.put("selected_seats", java.util.List.of("12A", "12B"));
        body.put("extras", java.util.List.of("checked_bag", "priority"));
        body.put("payment_attempt_id", attemptId);

        JsonNode created = postJson("/api/trips", body, 201).path("trip");
        long tripId = created.path("id").asLong();
        assertEquals("12A", created.path("selected_seats").get(0).asText());
        assertEquals("checked_bag", created.path("extras").get(0).asText());
        assertEquals(tripId, jdbc.queryForObject(
                "SELECT trip_id FROM payment_attempts WHERE id = ?",
                Long.class, attemptId));

        JsonNode history = json.readTree(http.perform(
                        get("/api/trips").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString());
        JsonNode restored = history.path("trips").get(0);
        assertEquals(tripId, restored.path("id").asLong());
        assertEquals("12B", restored.path("selected_seats").get(1).asText());
        assertEquals("priority", restored.path("extras").get(1).asText());
    }

    @Test
    void flightCancellationPreservesJsonAndRestoresSeatsOnce() throws Exception {
        long listing = listing("flight", "{\"seats_available\":5}");
        long trip = jdbc.queryForObject("""
                INSERT INTO trips (user_id, partner_listing_id, title, destination, details)
                VALUES (?, ?, 'Test flight', 'Tripoli', '{"passenger_count":2,"other":"preserved"}'::jsonb)
                RETURNING id
                """, Long.class, userId, listing);
        for (int i = 0; i < 2; i++) {
            http.perform(delete("/api/trips/" + trip).header("Authorization", "Bearer " + token))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.refund_status").value("pending_airline_review"));
        }
        Map<String, Object> record = jdbc.queryForMap("""
                SELECT status, details ->> 'other' AS other,
                       details ->> 'refund_status' AS refund_status,
                       details ->> 'refund_method' AS refund_method,
                       details ->> 'refund_requested_at' AS refund_requested_at
                FROM trips WHERE id = ?
                """, trip);
        assertEquals("cancelled", record.get("status"));
        assertEquals("preserved", record.get("other"));
        assertEquals("pending_airline_review", record.get("refund_status"));
        assertEquals("original_payment_method", record.get("refund_method"));
        assertNotNull(record.get("refund_requested_at"));
        assertEquals("7", jdbc.queryForObject(
                "SELECT attributes ->> 'seats_available' FROM partner_listings WHERE id = ?", String.class, listing));
    }

    @Test
    void failedBookingRollsBackInventoryReservation() throws Exception {
        long listing = listing("car", "{\"available_vehicles\":1}");
        Map<String, Object> body = new java.util.HashMap<>(booking("car", listing));
        body.put("title", "x".repeat(256)); // PostgreSQL rejects this after inventory is reserved.
        postJson("/api/bookings", body, 500);
        assertEquals("1", jdbc.queryForObject(
                "SELECT attributes ->> 'available_vehicles' FROM partner_listings WHERE id = ?", String.class, listing));
        assertEquals(0, jdbc.queryForObject(
                "SELECT count(*) FROM bookings WHERE user_id = ?", Integer.class, userId));
    }

    @Test
    void publicSearchAndMetadataQueriesExecuteOnPostgres() throws Exception {
        listing("hotel", "{\"latitude\":32.89,\"longitude\":13.19}");
        http.perform(get("/api/hotels/search").param("city", "triPOL"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.hotels").isNotEmpty());
        http.perform(get("/api/hotels/nearby").param("lat", "32.89").param("lon", "13.19")
                        .param("radius", "5")).andExpect(status().isOk())
                .andExpect(jsonPath("$.hotels").isNotEmpty());
        http.perform(get("/api/offers")).andExpect(status().isOk());
        http.perform(get("/api/attractions/search")).andExpect(status().isOk());
    }

    @Test
    void anonymousPlaceVisitsDeduplicateAndRollUpByCountry() throws Exception {
        String firstPlace = "visit-" + UUID.randomUUID();
        String secondPlace = "visit-" + UUID.randomUUID();
        jdbc.update("""
                INSERT INTO tourist_monuments
                    (id, title, location, category, description, image_url, tags)
                VALUES (?, 'Visit fixture one', 'Tripoli, Libya', 'landmark', 'Fixture',
                        'https://example.invalid/visit-fixture-one.jpg', '[]'::jsonb),
                       (?, 'Visit fixture two', 'Benghazi, Libya', 'landmark', 'Fixture',
                        'https://example.invalid/visit-fixture-two.jpg', '[]'::jsonb)
                """, firstPlace, secondPlace);

        assertVisitCounted(firstPlace, "a".repeat(32), true);
        assertVisitCounted(firstPlace, "a".repeat(32), false);
        assertVisitCounted(secondPlace, "b".repeat(32), true);

        JsonNode response = json.readTree(http.perform(get("/api/attractions/search"))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString());
        JsonNode first = findAttraction(response.path("attractions"), firstPlace);
        JsonNode second = findAttraction(response.path("attractions"), secondPlace);

        assertEquals(1, first.path("visit_count").asInt());
        assertEquals(2, first.path("country_visit_count").asInt());
        assertEquals(1, second.path("visit_count").asInt());
        assertEquals(2, second.path("country_visit_count").asInt());
    }

    private void assertVisitCounted(String placeId, String visitorId, boolean expected)
            throws Exception {
        JsonNode response = json.readTree(http.perform(
                        post("/api/attractions/" + placeId + "/visits")
                                .contentType("application/json")
                                .content(json.writeValueAsString(Map.of("visitor_id", visitorId))))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString());
        assertEquals(expected, response.path("counted").asBoolean());
    }

    private static JsonNode findAttraction(JsonNode attractions, String id) {
        for (JsonNode attraction : attractions) {
            if (id.equals(attraction.path("id").asText())) return attraction;
        }
        fail("Place not returned from attraction search: " + id);
        return null;
    }

    @Test
    void partnerListingCreationReturnsOnlyItsGeneratedId() throws Exception {
        long existing = listing("car", "{\"available_vehicles\":1}");
        long partnerId = jdbc.queryForObject(
                "SELECT partner_id FROM partner_listings WHERE id = ?", Long.class, existing);
        jdbc.update("UPDATE users SET role = 'partner', partner_id = ? WHERE id = ?", partnerId, userId);
        JsonNode response = postJson("/api/partner/listings", Map.of(
                "type", "car", "title", "New migration car", "city", "Tripoli",
                "image_url", "https://example.invalid/car.png", "price", 80,
                "attributes", Map.of("available_vehicles", 2)), 200);
        long id = response.path("listing").path("id").asLong();
        assertTrue(id > 0);
        assertEquals(partnerId, jdbc.queryForObject(
                "SELECT partner_id FROM partner_listings WHERE id = ?", Long.class, id));
        http.perform(get("/api/partner/dashboard").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
    }

    @Test
    void flightBookingReservesPassengerInventoryAndReturnsGeneratedId() throws Exception {
        long listing = listing("flight", "{\"seats_available\":5}");
        JsonNode response = postJson("/api/trips", Map.of(
                "origin_code", "MRA", "origin_city", "Misrata",
                "destination_code", "MJI", "destination_city", "Tripoli",
                "departure_date", "2035-11-10T10:00:00+02:00",
                "arrival_date", "2035-11-10T11:00:00+02:00",
                "flight_number", "ZT51", "partner_listing_id", listing, "passenger_count", 2), 201);
        long id = response.path("trip").path("id").asLong();
        assertTrue(id > 0);
        assertEquals("3", jdbc.queryForObject(
                "SELECT attributes ->> 'seats_available' FROM partner_listings WHERE id = ?", String.class, listing));
        http.perform(delete("/api/trips/" + id).header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
        assertEquals("5", jdbc.queryForObject(
                "SELECT attributes ->> 'seats_available' FROM partner_listings WHERE id = ?", String.class, listing));
    }

    @Test
    void soldOutBookingDoesNotCreateReservationOrNegativeInventory() throws Exception {
        long listing = listing("hotel", "{}");
        jdbc.update("UPDATE partner_listings SET available_rooms = 1 WHERE id = ?", listing);
        postJson("/api/bookings", booking("hotel", listing), 409);
        assertEquals(1, jdbc.queryForObject(
                "SELECT available_rooms FROM partner_listings WHERE id = ?", Integer.class, listing));
        assertEquals(0, jdbc.queryForObject(
                "SELECT count(*) FROM bookings WHERE user_id = ?", Integer.class, userId));
    }

    @Test
    void postgresUpsertUpdatesPreferencesInsteadOfDuplicatingThem() throws Exception {
        for (String destination : new String[]{"Tripoli", "Misrata"}) {
            http.perform(put("/api/preferences/travel").header("Authorization", "Bearer " + token)
                            .contentType("application/json").content(json.writeValueAsString(Map.of(
                                    "preferred_destination", destination,
                                    "budget_level", "balanced", "travel_pace", "balanced",
                                    "trip_duration_days", 7, "travelers", 2, "interests", java.util.List.of()))))
                    .andExpect(status().isOk());
        }
        assertEquals(1, jdbc.queryForObject(
                "SELECT count(*) FROM travel_preferences WHERE user_id = ?", Integer.class, userId));
        assertEquals("Misrata", jdbc.queryForObject(
                "SELECT preferred_destination FROM travel_preferences WHERE user_id = ?", String.class, userId));
    }

    @Test
    void staffSummaryAndReservationUnionsWorkWithPostgresTypes() throws Exception {
        jdbc.update("UPDATE users SET role = 'admin' WHERE id = ?", userId);
        for (String path : new String[]{"/api/admin/dashboard", "/api/admin/reservations", "/api/admin/customers"}) {
            http.perform(get(path).header("Authorization", "Bearer " + token)).andExpect(status().isOk());
        }
    }

    @Test
    void seatMapReadsRealFaresCabinsAndLiveHolds() throws Exception {
        long flight = listing("flight", """
                {"seat_layout":"2-2","seat_rows":16,"seats_available":50,
                 "business_price":331,"extra_legroom_rows":[2,9],
                 "cabins":[{"id":"front","name":"Forward cabin","row_start":1,"row_end":8},
                           {"id":"rear","name":"Rear cabin","row_start":9,"row_end":16}]}
                """);
        jdbc.update("""
                INSERT INTO flight_seat_holds
                    (flight_listing_id,user_id,seat_number,status,expires_at)
                VALUES (?,?,'1A','confirmed',NOW()+INTERVAL '15 minutes'),
                       (?,?,'9D','reserved',NOW()+INTERVAL '15 minutes'),
                       (?,?,'9A','reserved',NOW()-INTERVAL '1 minute')
                """, flight, userId, flight, userId, flight, userId);
        http.perform(get("/api/flights/" + flight + "/seats").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.seat_letters.length()").value(4))
                .andExpect(jsonPath("$.row_count").value(16))
                .andExpect(jsonPath("$.occupied_seats.length()").value(2))
                .andExpect(jsonPath("$.fares[0].price").value(100))
                .andExpect(jsonPath("$.fares[0].available_seats").value(49))
                .andExpect(jsonPath("$.fares[1].price").value(331))
                .andExpect(jsonPath("$.fares[1].shared_inventory").value(true))
                .andExpect(jsonPath("$.cabins[0].name").value("Forward cabin"))
                .andExpect(jsonPath("$.cabins[0].total_seats").value(32))
                .andExpect(jsonPath("$.cabins[0].available_seats").value(31))
                .andExpect(jsonPath("$.cabins[1].rows[0]").value(9))
                .andExpect(jsonPath("$.extra_legroom_rows[0]").value(2))
                .andExpect(jsonPath("$.pricing.extra_legroom_fee").value(15));
    }

    @Test
    void seatMapDoesNotInventAdditionalCabinsOrUnpricedClasses() throws Exception {
        long flight = listing("flight", """
                {"seat_layout":"3-3","seat_rows":30,"seats_available":10}
                """);
        http.perform(get("/api/flights/" + flight + "/seats").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.cabins.length()").value(1))
                .andExpect(jsonPath("$.cabins[0].rows.length()").value(30))
                .andExpect(jsonPath("$.cabins[0].total_seats").value(180))
                .andExpect(jsonPath("$.cabins[0].available_seats").value(10))
                .andExpect(jsonPath("$.fares.length()").value(1));
    }

    @Test
    void invalidCabinRangesReturnAnExplicitConfigurationError() throws Exception {
        long flight = listing("flight", """
                {"seat_layout":"2-2","seat_rows":16,"seats_available":64,
                 "cabins":[{"rows":[1,2]},{"rows":[2,3]}]}
                """);
        http.perform(get("/api/flights/" + flight + "/seats").header("Authorization", "Bearer " + token))
                .andExpect(status().isConflict());
        assertEquals(0, jdbc.queryForObject(
                "SELECT count(*) FROM flight_seat_holds WHERE flight_listing_id = ?", Integer.class, flight));
    }

    @Test
    void selectedFareAndConfiguredLegroomUseTheSamePricingAtConfirmation() throws Exception {
        long flight = listing("flight", """
                {"seat_layout":"2-2","seat_rows":16,"seats_available":64,
                 "business_price":331,"extra_legroom_rows":[2],
                 "origin_code":"MRA","origin_city":"Misrata",
                 "destination_code":"MJI","destination_city":"Tripoli",
                 "departure_time":"2035-11-20T10:00:00+02:00",
                 "arrival_time":"2035-11-20T11:00:00+02:00"}
                """);
        postJson("/api/flights/" + flight + "/seats/reserve", Map.of("seats", java.util.List.of("2A")), 200);
        JsonNode confirmed = postJson("/api/bookings/confirm", Map.of(
                "flight_id", flight, "seats", java.util.List.of("2A"), "seat_class", "business",
                "extras", java.util.List.of("flexible_ticket")), 201);
        assertEquals(412.96, confirmed.path("booking").path("total_price").asDouble(), .001);
        assertEquals("Business", jdbc.queryForObject(
                "SELECT seat_class FROM trips WHERE user_id = ?", String.class, userId));
        assertEquals("confirmed", jdbc.queryForObject(
                "SELECT status FROM flight_seat_holds WHERE flight_listing_id = ?", String.class, flight));
        assertEquals(1, jdbc.queryForObject("""
                SELECT COUNT(*) FROM user_notifications
                WHERE user_id = ? AND event_key = ? AND target_type = 'trip'
                """, Integer.class, userId,
                "flight-booking:" + confirmed.path("trip").path("id").asLong()));
    }

    @Test
    @Transactional
    void coreRlsIsEnabledAndSeparatesCustomerPartnerAndAdminData() {
        assertFalse(jdbc.queryForObject("""
                SELECT rolsuper OR rolcanlogin OR rolbypassrls
                FROM pg_roles WHERE rolname = 'zentrip_api_runtime'
                """, Boolean.class));
        assertEquals(28, jdbc.queryForObject("""
                SELECT COUNT(*)
                FROM pg_class c
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE n.nspname = 'public'
                  AND c.relkind = 'r'
                  AND c.relrowsecurity
                  AND c.relname IN (
                      'partners', 'users', 'password_reset_codes', 'partner_listings',
                      'airports', 'user_reviews', 'user_profiles', 'ai_chat_messages',
                      'travel_preferences', 'tourist_monuments',
                      'legacy_attraction_partner_reviews', 'attraction_visit_counts',
                      'attraction_visit_dedup', 'offers', 'offer_catalog_metadata',
                      'trips', 'flight_seat_holds', 'bookings', 'transfers',
                      'transfer_schedules', 'api_tokens', 'hotel_destinations',
                      'landmark_places', 'landmark_place_aliases',
                       'landmark_search_areas', 'landmark_merge_candidates',
                       'user_push_tokens', 'payment_attempts'
                  )
                """, Integer.class));

        long otherUserId = jdbc.queryForObject("""
                INSERT INTO users (name, email, password)
                VALUES ('Other Customer', ?, 'unused-test-hash') RETURNING id
                """, Long.class, UUID.randomUUID() + "@example.invalid");
        long adminId = jdbc.queryForObject("""
                INSERT INTO users (name, email, password, role)
                VALUES ('Admin', ?, 'unused-test-hash', 'admin') RETURNING id
                """, Long.class, UUID.randomUUID() + "@example.invalid");

        long ownListing = listing("hotel", "{}");
        long otherListing = listing("hotel", "{}");
        long ownPartnerId = jdbc.queryForObject(
                "SELECT partner_id FROM partner_listings WHERE id = ?", Long.class, ownListing);
        long otherPartnerId = jdbc.queryForObject(
                "SELECT partner_id FROM partner_listings WHERE id = ?", Long.class, otherListing);
        long partnerUserId = jdbc.queryForObject("""
                INSERT INTO users (name, email, password, role, partner_id)
                VALUES ('Partner User', ?, 'unused-test-hash', 'partner', ?) RETURNING id
                """, Long.class, UUID.randomUUID() + "@example.invalid", ownPartnerId);

        long ownBooking = rlsBooking(userId, ownPartnerId, ownListing);
        long otherBooking = rlsBooking(otherUserId, otherPartnerId, otherListing);
        long ownTrip = rlsTrip(userId, ownPartnerId, ownListing);
        long otherTrip = rlsTrip(otherUserId, otherPartnerId, otherListing);
        jdbc.update("INSERT INTO user_profiles (user_id, photo_url) VALUES (?, ?)",
                userId, "https://example.invalid/a.jpg");
        jdbc.update("INSERT INTO user_profiles (user_id, photo_url) VALUES (?, ?)",
                otherUserId, "https://example.invalid/b.jpg");

        assumeRuntime(userId, "customer", null);
        assertEquals(1, visibleCount("SELECT COUNT(*) FROM bookings WHERE id = ?", ownBooking));
        assertEquals(0, visibleCount("SELECT COUNT(*) FROM bookings WHERE id = ?", otherBooking));
        assertEquals(0, jdbc.update("UPDATE bookings SET status = 'changed' WHERE id = ?", otherBooking));
        assertEquals(0, jdbc.update("DELETE FROM bookings WHERE id = ?", otherBooking));
        assertEquals(1, visibleCount("SELECT COUNT(*) FROM trips WHERE id = ?", ownTrip));
        assertEquals(0, visibleCount("SELECT COUNT(*) FROM trips WHERE id = ?", otherTrip));
        assertEquals(0, jdbc.update("UPDATE trips SET status = 'changed' WHERE id = ?", otherTrip));
        assertEquals(0, jdbc.update("DELETE FROM trips WHERE id = ?", otherTrip));
        assertEquals(1, visibleCount("SELECT COUNT(*) FROM user_profiles WHERE user_id = ?", userId));
        assertEquals(0, visibleCount("SELECT COUNT(*) FROM user_profiles WHERE user_id = ?", otherUserId));
        assertEquals(0, jdbc.update(
                "UPDATE user_profiles SET photo_url = 'https://example.invalid/changed.jpg' WHERE user_id = ?",
                otherUserId));
        assertEquals(0, jdbc.update("DELETE FROM user_profiles WHERE user_id = ?", otherUserId));

        jdbc.execute("RESET ROLE");
        assumeRuntime(partnerUserId, "partner", ownPartnerId);
        assertEquals(1, visibleCount("SELECT COUNT(*) FROM bookings WHERE id = ?", ownBooking));
        assertEquals(0, visibleCount("SELECT COUNT(*) FROM bookings WHERE id = ?", otherBooking));
        assertEquals(0, jdbc.update("UPDATE bookings SET status = 'changed' WHERE id = ?", otherBooking));
        assertEquals(1, visibleCount("SELECT COUNT(*) FROM trips WHERE id = ?", ownTrip));
        assertEquals(0, visibleCount("SELECT COUNT(*) FROM trips WHERE id = ?", otherTrip));
        assertEquals(1, visibleCount("SELECT COUNT(*) FROM partner_listings WHERE id = ?", ownListing));
        assertEquals(0, visibleCount("SELECT COUNT(*) FROM partner_listings WHERE id = ?", otherListing));
        assertEquals(0, jdbc.update(
                "UPDATE partner_listings SET title = 'Not owned' WHERE id = ?", otherListing));
        assertEquals(0, jdbc.update("DELETE FROM partner_listings WHERE id = ?", otherListing));

        jdbc.execute("RESET ROLE");
        assumeRuntime(adminId, "admin", null);
        assertEquals(2, visibleCount(
                "SELECT COUNT(*) FROM bookings WHERE id IN (?, ?)", ownBooking, otherBooking));
        assertEquals(2, visibleCount(
                "SELECT COUNT(*) FROM trips WHERE id IN (?, ?)", ownTrip, otherTrip));
        assertEquals(2, visibleCount(
                "SELECT COUNT(*) FROM user_profiles WHERE user_id IN (?, ?)", userId, otherUserId));
        assertEquals(2, visibleCount(
                "SELECT COUNT(*) FROM partner_listings WHERE id IN (?, ?)", ownListing, otherListing));
    }

    @Test
    void publicRolesHaveNoDirectAccessToVisitCountersOrNewPrivateTables() {
        String[] protectedTables = {
                "attraction_visit_counts", "attraction_visit_dedup",
                "hotel_destinations", "landmark_places", "landmark_place_aliases",
                "landmark_search_areas", "landmark_merge_candidates",
                "legacy_attraction_partner_reviews", "user_push_tokens",
                "payment_attempts"
        };
        for (String table : protectedTables) {
            assertTrue(jdbc.queryForObject("""
                    SELECT relrowsecurity FROM pg_class
                    WHERE oid = to_regclass(?)
                    """, Boolean.class, "public." + table), table);
            for (String role : new String[]{"anon", "authenticated"}) {
                for (String privilege : new String[]{"SELECT", "INSERT", "UPDATE"}) {
                    assertFalse(jdbc.queryForObject(
                            "SELECT has_table_privilege(?, ?, ?)",
                            Boolean.class, role, "public." + table, privilege),
                            role + " must not have direct " + privilege + " on " + table);
                }
            }
        }

        for (String role : new String[]{"anon", "authenticated"}) {
            for (String privilege : new String[]{"SELECT", "INSERT", "UPDATE"}) {
                assertFalse(jdbc.queryForObject(
                        "SELECT has_table_privilege(?, 'public.schema_migrations', ?)",
                        Boolean.class, role, privilege),
                        role + " must not have direct " + privilege + " on schema_migrations");
            }
        }
    }

    @Test
    @Transactional
    void legacyAttractionReviewRowsAreVisibleOnlyToAdminRuntimeContext() {
        long partnerId = jdbc.queryForObject("""
                INSERT INTO partners (slug, name, service_type)
                VALUES (?, 'Review isolation partner', 'attraction') RETURNING id
                """, Long.class, UUID.randomUUID().toString());
        long reviewId = jdbc.queryForObject("""
                INSERT INTO legacy_attraction_partner_reviews
                    (partner_id, reviewed_by, decisions)
                VALUES (?, ?, '{}'::jsonb) RETURNING id
                """, Long.class, partnerId, userId);

        jdbc.execute("SET LOCAL ROLE zentrip_api_runtime");
        jdbc.queryForObject(
                "SELECT set_config('app.user_id', ?, true)",
                String.class, Long.toString(userId));
        jdbc.queryForObject(
                "SELECT set_config('app.auth_role', 'customer', true)", String.class);
        assertEquals(0, jdbc.queryForObject(
                "SELECT COUNT(*) FROM legacy_attraction_partner_reviews WHERE id = ?",
                Integer.class, reviewId));
        jdbc.queryForObject(
                "SELECT set_config('app.auth_role', 'admin', true)", String.class);
        assertEquals(1, jdbc.queryForObject(
                "SELECT COUNT(*) FROM legacy_attraction_partner_reviews WHERE id = ?",
                Integer.class, reviewId));
    }

    @Test
    @Transactional
    void pushTokenApiStoresAndRemovesAUsersOwnDeviceToken() throws Exception {
        String deviceToken = "fcm-" + UUID.randomUUID();
        http.perform(post("/api/users/fcm-token")
                        .header("Authorization", "Bearer " + token)
                        .contentType("application/json")
                        .content(json.writeValueAsString(Map.of(
                                "token", deviceToken, "platform", "android"))))
                .andExpect(status().isOk());

        Map<String, Object> stored = jdbc.queryForMap("""
                SELECT user_id, platform FROM user_push_tokens WHERE token = ?
                """, deviceToken);
        assertEquals(userId, ((Number) stored.get("user_id")).longValue());
        assertEquals("android", stored.get("platform"));

        http.perform(delete("/api/users/fcm-token")
                        .header("Authorization", "Bearer " + token)
                        .contentType("application/json")
                        .content(json.writeValueAsString(Map.of("token", deviceToken))))
                .andExpect(status().isNoContent());
        assertEquals(0, jdbc.queryForObject(
                "SELECT COUNT(*) FROM user_push_tokens WHERE token = ?",
                Integer.class, deviceToken));
    }

    @Test
    @Transactional
    void notificationInboxIsOwnerScopedAndSupportsReadState() throws Exception {
        long otherUserId = jdbc.queryForObject("""
                INSERT INTO users (name, email, password)
                VALUES ('Other Notification Owner', ?, 'unused-test-hash')
                RETURNING id
                """, Long.class, UUID.randomUUID() + "@example.invalid");
        long ownNotificationId = jdbc.queryForObject("""
                INSERT INTO user_notifications
                    (user_id, event_key, kind, title_en, title_ar,
                     body_en, body_ar, target_type, target_id, booking_ref)
                VALUES (?, ?, 'booking', 'Booking confirmed', 'تم تأكيد الحجز',
                        'Your booking is confirmed.', 'تم تأكيد حجزك.',
                        'booking', 501, 'ZT-OWN')
                RETURNING id
                """, Long.class, userId, "test-own-" + UUID.randomUUID());
        long otherNotificationId = jdbc.queryForObject("""
                INSERT INTO user_notifications
                    (user_id, event_key, kind, title_en, title_ar,
                     body_en, body_ar, target_type, target_id, booking_ref)
                VALUES (?, ?, 'booking', 'Other booking', 'حجز آخر',
                        'Private notification.', 'إشعار خاص.',
                        'booking', 502, 'ZT-OTHER')
                RETURNING id
                """, Long.class, otherUserId, "test-other-" + UUID.randomUUID());

        JsonNode listed = json.readTree(http.perform(get("/api/notifications")
                        .param("limit", "10")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString()).path("notifications");
        assertEquals(1, listed.size());
        assertEquals(ownNotificationId, listed.get(0).path("id").asLong());

        http.perform(put("/api/notifications/" + ownNotificationId + "/read")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isNoContent());
        assertNotNull(jdbc.queryForObject(
                "SELECT read_at FROM user_notifications WHERE id = ?",
                Timestamp.class, ownNotificationId));

        http.perform(put("/api/notifications/" + otherNotificationId + "/read")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isNotFound());
        assertEquals(0, jdbc.queryForObject("""
                SELECT COUNT(*) FROM user_notifications
                WHERE id = ? AND read_at IS NOT NULL
                """, Integer.class, otherNotificationId));

        http.perform(put("/api/notifications/read-all")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.updated").value(0));
    }

    @Test
    @Transactional
    void runtimeRoleCannotReadOrDeleteAnotherUsersPushToken() {
        long otherUserId = jdbc.queryForObject("""
                INSERT INTO users (name, email, password)
                VALUES ('Push Token Owner', ?, 'unused-test-hash') RETURNING id
                """, Long.class, UUID.randomUUID() + "@example.invalid");
        String ownToken = "own-" + UUID.randomUUID();
        String otherToken = "other-" + UUID.randomUUID();
        jdbc.update("""
                INSERT INTO user_push_tokens (token, user_id, platform)
                VALUES (?, ?, 'web'), (?, ?, 'ios')
                """, ownToken, userId, otherToken, otherUserId);

        jdbc.execute("SET LOCAL ROLE zentrip_api_runtime");
        jdbc.queryForObject(
                "SELECT set_config('app.user_id', ?, true)",
                String.class, Long.toString(userId));
        jdbc.queryForObject(
                "SELECT set_config('app.auth_role', 'customer', true)", String.class);

        assertEquals(1, jdbc.queryForObject(
                "SELECT COUNT(*) FROM user_push_tokens", Integer.class));
        assertEquals(0, jdbc.update(
                "DELETE FROM user_push_tokens WHERE user_id = ? AND token = ?",
                otherUserId, otherToken));
    }

    private long rlsBooking(long ownerId, long partnerId, long listingId) {
        return jdbc.queryForObject("""
                INSERT INTO bookings (
                    user_id, partner_id, partner_listing_id, type, status,
                    total_amount, title, subtitle, "date"
                ) VALUES (?, ?, ?, 'hotel', 'upcoming', 100, 'RLS stay', 'Test', NOW())
                RETURNING id
                """, Long.class, ownerId, partnerId, listingId);
    }

    private long rlsTrip(long ownerId, long partnerId, long listingId) {
        return jdbc.queryForObject("""
                INSERT INTO trips (user_id, partner_id, partner_listing_id, title, destination)
                VALUES (?, ?, ?, 'RLS trip', 'Tripoli') RETURNING id
                """, Long.class, ownerId, partnerId, listingId);
    }

    private void assumeRuntime(long authenticatedUserId, String role, Long partnerId) {
        jdbc.execute("SET LOCAL ROLE zentrip_api_runtime");
        jdbc.queryForObject("SELECT set_config('app.user_id', ?, TRUE)", String.class,
                Long.toString(authenticatedUserId));
        jdbc.queryForObject("SELECT set_config('app.auth_role', ?, TRUE)", String.class, role);
        jdbc.queryForObject("SELECT set_config('app.partner_id', ?, TRUE)", String.class,
                partnerId == null ? "" : Long.toString(partnerId));
    }

    private int visibleCount(String query, Object... args) {
        return jdbc.queryForObject(query, Integer.class, args);
    }
}

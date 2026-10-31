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
        "spring.datasource.hikari.data-source-properties.prepareThreshold=0"
})
@AutoConfigureMockMvc
@EnabledIfEnvironmentVariable(named = "ZENTRIP_POSTGRES_TEST_URL", matches = "jdbc:postgresql://127\\.0\\.0\\.1:.*")
class PostgresMigrationIntegrationTest {
    @Autowired MockMvc http;
    @Autowired JdbcTemplate jdbc;
    @Autowired ObjectMapper json;
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
    void carBookingReturnsIdAndCancellationRestoresInventory() throws Exception {
        long listing = listing("car", "{\"available_vehicles\":1}");
        JsonNode response = postJson("/api/bookings", booking("car", listing), 201);
        long id = response.path("booking").path("id").asLong();
        assertTrue(id > 0);
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
                INSERT INTO tourist_monuments (id, title, location, category, description, tags)
                VALUES (?, 'Visit fixture one', 'Tripoli, Libya', 'landmark', 'Fixture', '[]'::jsonb),
                       (?, 'Visit fixture two', 'Benghazi, Libya', 'landmark', 'Fixture', '[]'::jsonb)
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
    }
}

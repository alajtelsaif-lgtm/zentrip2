package com.zentrip.api;

import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class AdminControllerTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final AdminController controller = new AdminController(jdbc);

    @Test
    void dashboardRequiresAnAuthenticatedUser() {
        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.dashboard(new MockHttpServletRequest()));

        assertEquals(401, exception.getStatusCode().value());
        verifyNoInteractions(jdbc);
    }

    @Test
    void dashboardRejectsCustomers() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("customer");

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.dashboard(authenticatedRequest()));

        assertEquals(403, exception.getStatusCode().value());
        verify(jdbc).queryForObject(
                "SELECT role FROM users WHERE id = ?", String.class, 7L);
    }

    @Test
    void dashboardReturnsLiveSummaryAndRecentReservationsForAdmins() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");
        Map<String, Object> summary = Map.of(
                "customer_count", 12L,
                "new_customers_30d", 3L,
                "reservation_count", 18L,
                "flight_count", 4L,
                "service_booking_count", 10L,
                "transfer_count", 4L,
                "booked_value", new BigDecimal("530.00"));
        List<Map<String, Object>> reservations = List.of(
                Map.of("id", "booking-5", "type", "hotel", "amount", new BigDecimal("120.00")));
        when(jdbc.queryForMap(any(String.class))).thenReturn(summary);
        when(jdbc.queryForList(any(String.class), eq(8))).thenReturn(reservations);

        Map<String, Object> response = controller.dashboard(authenticatedRequest());

        assertEquals(summary, response.get("summary"));
        assertEquals(reservations, response.get("recent_reservations"));
    }

    @Test
    void attractionPopularityReturnsAggregatedPlaceAndCountryCountsForAdmins() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");
        List<Map<String, Object>> places = List.of(Map.of(
                "title", "Leptis Magna",
                "city", "Khoms",
                "country", "Libya",
                "visit_count", 41L));
        List<Map<String, Object>> countries = List.of(
                Map.of("country", "Libya", "visit_count", 41L),
                Map.of("country", "Unspecified country", "visit_count", 0L));
        when(jdbc.queryForList(contains("FROM tourist_monuments monuments")))
                .thenReturn(places, countries);

        Map<String, Object> response = controller.attractionPopularity(authenticatedRequest());

        assertEquals(places, response.get("places"));
        assertEquals(countries, response.get("countries"));
        verify(jdbc).queryForList(contains("SUM(visit_count)"));
    }

    @Test
    void attractionPopularityRequiresAdministratorRole() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("customer");

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.attractionPopularity(authenticatedRequest()));

        assertEquals(403, exception.getStatusCode().value());
        verify(jdbc, org.mockito.Mockito.never())
                .queryForList(anyString());
    }

    @Test
    void customerListRejectsOutOfRangeLimit() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.customers(101, authenticatedRequest()));

        assertEquals(400, exception.getStatusCode().value());
        verify(jdbc).queryForObject(
                "SELECT role FROM users WHERE id = ?", String.class, 7L);
    }

    @Test
    void partnerManagementRequiresAdministratorRole() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("customer");

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.partners(authenticatedRequest()));

        assertEquals(403, exception.getStatusCode().value());
    }

    @Test
    void partnerDirectoryOmitsPlacesAndDoesNotDependOnLegacyReviewTable() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");
        when(jdbc.queryForList(contains("FROM partners p"))).thenReturn(List.of());

        Map<String, Object> response = controller.partners(authenticatedRequest());

        assertEquals(List.of(), response.get("partners"));
        verify(jdbc).queryForList(contains(
                "WHERE TRIM(LOWER(COALESCE(p.service_type, ''))) <> 'attraction'"));
    }

    @Test
    void legacyPlaceListingDoesNotRequireTheOptionalReviewTable() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");
        when(jdbc.queryForObject(
                "SELECT to_regclass('legacy_attraction_partner_reviews') IS NOT NULL",
                Boolean.class))
                .thenReturn(false);
        when(jdbc.queryForList(contains("WHERE LOWER(p.service_type) = 'attraction'")))
                .thenReturn(List.of());

        Map<String, Object> response =
                controller.legacyAttractionPartners(authenticatedRequest());

        assertEquals(List.of(), response.get("partners"));
        verify(jdbc).queryForList(contains("NULL AS approved_at, NULL AS reviewed_by_name"));
    }

    @Test
    void legacyPlaceReviewFailsSafelyWhenReviewStorageIsMissing() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");
        when(jdbc.queryForObject(
                "SELECT to_regclass('legacy_attraction_partner_reviews') IS NOT NULL",
                Boolean.class))
                .thenReturn(false);

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.reviewAndRetireAttractionPartner(
                        12, Map.of("approved", true), authenticatedRequest()));

        assertEquals(409, exception.getStatusCode().value());
        verify(jdbc, never()).queryForList(contains("FOR UPDATE"));
    }

    @Test
    void addPartnerRejectsUnsupportedServices() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.addPartner(Map.of(
                        "name", "Example partner",
                        "email", "traveler@example.com",
                        "service_type", "attraction"),
                        authenticatedRequest()));

        assertEquals(400, exception.getStatusCode().value());
    }

    @Test
    void monumentManagementRequiresAdministratorRole() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("customer");

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.monuments(authenticatedRequest()));

        assertEquals(403, exception.getStatusCode().value());
        verify(jdbc).queryForObject(
                "SELECT role FROM users WHERE id = ?", String.class, 7L);
    }

    @Test
    void monumentCreateRejectsOutOfRangeRating() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.createMonument(Map.of(
                        "title", "Leptis Magna",
                        "location", "Khoms, Libya",
                        "description", "A Roman city",
                        "rating", 5.1,
                        "review_count", 3000),
                        authenticatedRequest()));

        assertEquals(400, exception.getStatusCode().value());
    }

    @Test
    void monumentCreatePersistsFieldsAndReturnsUuid() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");

        Map<String, Object> response = controller.createMonument(Map.of(
                "title", "Leptis Magna",
                "location", "Khoms, Libya",
                "category_tag", "Historical",
                "description", "Roman city",
                "working_hours", "8:00 AM - 5:00 PM",
                "best_time_to_visit", "Oct - Apr",
                "entry_fee", 5,
                "rating", 4.9,
                "review_count", 3120,
                "tags", List.of("Theatre", "Market")),
                authenticatedRequest());

        @SuppressWarnings("unchecked")
        Map<String, Object> monument = (Map<String, Object>) response.get("monument");
        assertEquals("Leptis Magna", monument.get("title"));
        assertEquals("Khoms, Libya", monument.get("location"));
        assertEquals(36, monument.get("id").toString().length());
        verify(jdbc).update(
                contains("INSERT INTO tourist_monuments"),
                anyString(), eq("Leptis Magna"), eq("Khoms, Libya"),
                eq("Historical"), eq("landmark"), eq(new BigDecimal("4.9")),
                eq(3120), eq("Roman city"), eq("8:00 AM - 5:00 PM"),
                eq("Oct - Apr"), eq(new BigDecimal("5")),
                eq(""), eq("[\"Theatre\",\"Market\"]"), eq(true));
    }

    @Test
    void offerCreateValidatesDurationAndComputesFieldsForTheCatalog() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.createOffer(Map.ofEntries(
                        Map.entry("title", "Istanbul Dream"),
                        Map.entry("location", "Istanbul"),
                        Map.entry("country", "Turkey"),
                        Map.entry("description", "A trip"),
                        Map.entry("price_per_person", 1290),
                        Map.entry("flight_price_per_person", 420),
                        Map.entry("flight_listing_id", 25),
                        Map.entry("hotel_price_per_night", 95),
                        Map.entry("duration_nights", 0),
                        Map.entry("rating", 4.8),
                        Map.entry("review_count", 2340)),
                        authenticatedRequest()));

        assertEquals(400, exception.getStatusCode().value());
    }

    @Test
    void offerListFallsBackUntilFlightLinkMigrationIsApplied() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");
        when(jdbc.queryForObject(contains("pg_attribute"), eq(Boolean.class)))
                .thenReturn(false);
        when(jdbc.queryForList(contains("FROM offers"))).thenReturn(List.of());

        Map<String, Object> response = controller.offers(authenticatedRequest());

        assertEquals(false, response.get("flight_link_schema_ready"));
        assertEquals(List.of(), response.get("offers"));
    }

    @Test
    void offerWriteReturnsMigrationInstructionInsteadOfDatabaseError() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");
        when(jdbc.queryForObject(contains("pg_attribute"), eq(Boolean.class)))
                .thenReturn(false);

        var response = controller.createOffer(Map.ofEntries(
                Map.entry("title", "Istanbul Dream"),
                Map.entry("location", "Istanbul"),
                Map.entry("country", "Turkey"),
                Map.entry("description", "A trip"),
                Map.entry("price_per_person", 1085),
                Map.entry("flight_price_per_person", 420),
                Map.entry("flight_listing_id", 25),
                Map.entry("hotel_price_per_night", 95),
                Map.entry("duration_nights", 7),
                Map.entry("rating", 4.8),
                Map.entry("review_count", 2340)),
                authenticatedRequest());

        assertEquals(409, response.getStatusCode().value());
        assertTrue(response.getBody().get("message").toString()
                .contains("20261107_offer_flight_link.sql"));
    }

    @Test
    void monumentUpdateKeepsExistingItemsEditableWhenValuesAreUnchanged() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");
        when(jdbc.queryForObject(
                "SELECT COUNT(*) FROM tourist_monuments WHERE id = ?",
                Integer.class,
                "monument-1")).thenReturn(1);

        Map<String, Object> response = controller.updateMonument(
                "monument-1",
                Map.of(
                        "title", "Leptis Magna",
                        "location", "Khoms, Libya",
                        "description", "Roman city",
                        "rating", 4.9,
                        "review_count", 3120),
                authenticatedRequest());

        @SuppressWarnings("unchecked")
        Map<String, Object> monument = (Map<String, Object>) response.get("monument");
        assertEquals("monument-1", monument.get("id"));
        assertEquals("Leptis Magna", monument.get("title"));
    }

    @Test
    void offerUpdatePersistsTheCustomBadge() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");
        when(jdbc.queryForObject(contains("pg_attribute"), eq(Boolean.class)))
                .thenReturn(true);
        when(jdbc.queryForObject(
                "SELECT COUNT(*) FROM offers WHERE id = ? AND is_active = TRUE",
                Integer.class,
                "offer-1")).thenReturn(1);
        when(jdbc.queryForList(
                contains("FROM partner_listings l"), eq(25L)))
                .thenReturn(List.of(Map.of("price", new BigDecimal("420"))));

        var response = controller.updateOffer(
                "offer-1",
                Map.ofEntries(
                        Map.entry("title", "Istanbul Dream"),
                        Map.entry("location", "Istanbul"),
                        Map.entry("country", "Turkey"),
                        Map.entry("description", "Explore the city"),
                        Map.entry("price_per_person", 1290),
                        Map.entry("flight_price_per_person", 420),
                        Map.entry("flight_listing_id", 25),
                        Map.entry("hotel_price_per_night", 95),
                        Map.entry("duration_nights", 7),
                        Map.entry("rating", 4.8),
                        Map.entry("review_count", 2340),
                        Map.entry("highlights", List.of("Grand Bazaar")),
                        Map.entry("badge", "Limited-time"),
                        Map.entry("is_featured", true)),
                authenticatedRequest());

        @SuppressWarnings("unchecked")
        Map<String, Object> offer =
                (Map<String, Object>) response.getBody().get("offer");
        assertEquals("offer-1", offer.get("id"));
        assertEquals("Limited-time", offer.get("badge"));
        verify(jdbc).update(
                contains("INSERT INTO offer_catalog_metadata"),
                eq("offer-1"),
                eq("Limited-time"));
    }

    @Test
    void offerFlightPickerListsOnlyActivePartnerFlightsWithAirlineAndPrice() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");
        when(jdbc.queryForList(contains("FROM partner_listings l")))
                .thenReturn(List.of(Map.ofEntries(
                        Map.entry("linked_flight_id", 25L),
                        Map.entry("flight_title", "MRA to MJI"),
                        Map.entry("flight_city", "Tripoli"),
                        Map.entry("flight_country", "Libya"),
                        Map.entry("linked_flight_price", new BigDecimal("175")),
                        Map.entry("flight_active", true),
                        Map.entry("flight_attributes",
                                "{\"origin_code\":\"MRA\",\"destination_code\":\"MJI\","
                                        + "\"flight_number\":\"YL25\"}"),
                        Map.entry("flight_airline", "Libyan Wings"))));

        Map<String, Object> response =
                controller.offerFlightListings(authenticatedRequest());
        @SuppressWarnings("unchecked")
        Map<String, Object> flight =
                (Map<String, Object>) ((List<?>) response.get("flights")).getFirst();

        assertEquals("Libyan Wings", flight.get("airline"));
        assertEquals(25L, flight.get("partner_listing_id"));
        assertEquals("MRA", flight.get("origin_code"));
        assertEquals("MJI", flight.get("destination_code"));
        assertEquals(Boolean.TRUE, flight.get("is_active"));
    }

    @Test
    void deletingOfferDeactivatesItSoSeededOffersStayDeletedAfterRestart() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");
        when(jdbc.update(
                "UPDATE offers SET is_active = FALSE WHERE id = ? AND is_active = TRUE",
                "istanbul-dream")).thenReturn(1);

        Map<String, String> response =
                controller.deleteOffer("istanbul-dream", authenticatedRequest());

        assertEquals("Offer deleted", response.get("message"));
        verify(jdbc).update(
                "UPDATE offers SET is_active = FALSE WHERE id = ? AND is_active = TRUE",
                "istanbul-dream");
    }

    @Test
    void offerListIncludesTheAdminManagedBadgeAndHighlights() {
        when(jdbc.queryForObject("SELECT role FROM users WHERE id = ?", String.class, 7L))
                .thenReturn("admin");
        when(jdbc.queryForList(contains("FROM offers o"))).thenReturn(List.of(Map.ofEntries(
                Map.entry("id", "offer-1"),
                Map.entry("title", "Istanbul Dream"),
                Map.entry("is_featured", true),
                Map.entry("badge", "Limited-time"),
                Map.entry("highlights", "[\"Grand Bazaar\"]"))));

        Map<String, Object> response = controller.offers(authenticatedRequest());
        @SuppressWarnings("unchecked")
        Map<String, Object> offer =
                (Map<String, Object>) ((List<?>) response.get("offers")).getFirst();

        assertEquals("Limited-time", offer.get("badge"));
        assertEquals(List.of("Grand Bazaar"), offer.get("highlights"));
    }

    private static HttpServletRequest authenticatedRequest() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute("authUserId", 7L);
        return request;
    }
}

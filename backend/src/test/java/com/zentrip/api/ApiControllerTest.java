package com.zentrip.api;

import java.math.BigDecimal;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.BadSqlGrammarException;

class ApiControllerTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final ProfilePhotoStorage photoStorage = mock(ProfilePhotoStorage.class);
    private final PasswordResetService passwordResetService = mock(PasswordResetService.class);
    private final OpenTripMapAttractionService openTripMapAttractionService =
            mock(OpenTripMapAttractionService.class);
    private final ApiController controller = new ApiController(
            jdbc, "", photoStorage, passwordResetService, openTripMapAttractionService);

    @BeforeEach
    void stubExistingBookingForeignKeyTargets() {
        when(jdbc.queryForObject(
                eq("SELECT COUNT(*) FROM users WHERE id = ?"), eq(Integer.class), eq(7L)))
                .thenReturn(1);
        when(jdbc.queryForObject(
                eq("SELECT COUNT(*) FROM partners WHERE id = ?"), eq(Integer.class), anyLong()))
                .thenReturn(1);
        when(jdbc.queryForObject(
                eq("SELECT COUNT(*) FROM partner_listings WHERE id = ?"),
                eq(Integer.class), anyLong()))
                .thenReturn(1);
    }

    @Test
    void recentAttractionDestinationRequiresVerifiedCustomerSession() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute("authRole", "partner");
        request.setAttribute("authUserId", 7L);

        Map<String, Object> response = controller.recentAttractionDestination(request);

        assertEquals(null, response.get("destination"));
        verifyNoInteractions(jdbc);
    }

    @Test
    void recentAttractionDestinationUsesOnlyTheAuthenticatedCustomerId() {
        when(jdbc.queryForList(any(String.class), any(Object[].class)))
                .thenReturn(List.of(Map.of(
                        "destination_city", "Rome",
                        "destination_country", "Italy",
                        "created_at", "2026-10-22T10:00:00Z")));
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute("authRole", "customer");
        request.setAttribute("authUserId", 42L);

        Map<String, Object> response = controller.recentAttractionDestination(request);

        assertEquals("Rome", ((Map<?, ?>) response.get("destination")).get("city"));
        assertEquals("Italy", ((Map<?, ?>) response.get("destination")).get("country"));
        verify(jdbc).queryForList(any(String.class), any(Object[].class));
    }

    @Test
    void bookingsReturnsEveryRecordForTheAuthenticatedCustomerWithLegacyPriceFallback() {
        List<Map<String, Object>> rows = List.of(
                Map.ofEntries(
                        Map.entry("id", 81L),
                        Map.entry("type", "hotel"),
                        Map.entry("title", "Harbor Hotel"),
                        Map.entry("subtitle", "Tunis"),
                        Map.entry("date", "2027-04-10T14:00:00Z"),
                        Map.entry("end_date", "2027-04-12T11:00:00Z"),
                        Map.entry("effective_price", new BigDecimal("120.00")),
                        Map.entry("ref_code", "HTL-81"),
                        Map.entry("partner_listing_id", 14L),
                        Map.entry("rooms", "2"),
                        Map.entry("status", "upcoming")),
                Map.of(
                        "id", 80L,
                        "type", "attraction",
                        "title", "Museum Visit",
                        "subtitle", "Tunis",
                        "date", "2027-04-08T10:00:00Z",
                        "end_date", "2027-04-08T11:00:00Z",
                        "effective_price", new BigDecimal("25.00"),
                        "ref_code", "TOUR-80",
                        "status", "upcoming"));
        when(jdbc.queryForList(
                contains("FROM bookings"), eq(7L))).thenReturn(rows);

        Map<String, Object> response = controller.bookings(authenticatedRequest());

        List<?> bookings = (List<?>) response.get("bookings");
        assertEquals(2, bookings.size());
        Map<?, ?> hotel = (Map<?, ?>) bookings.getFirst();
        assertEquals("81", hotel.get("id"));
        assertEquals(new BigDecimal("120.00"), hotel.get("price"));
        assertEquals(14L, hotel.get("partner_listing_id"));
        assertEquals("2", hotel.get("rooms"));
        verify(jdbc).queryForList(
                contains("WHERE user_id = ?"), eq(7L));
    }

    @Test
    void invalidLoginReturnsLaravelValidationResponse() {
        when(jdbc.queryForList("SELECT id, password FROM users WHERE email = ?", "user@example.com"))
                .thenReturn(List.of());

        ResponseEntity<?> response = controller.login(Map.of(
                "email", "user@example.com",
                "password", "incorrect-password"), new MockHttpServletRequest());

        assertEquals(422, response.getStatusCode().value());
        assertEquals(Map.of(
                "message", "The given data was invalid.",
                "errors", Map.of("email", List.of("The provided credentials are incorrect."))),
                response.getBody());
    }

    @Test
    void forgotPasswordReturnsGenericResponseAndRequestsCode() {
        ResponseEntity<?> response = controller.forgotPassword(Map.of("email", " User@Example.com "));

        assertEquals(200, response.getStatusCode().value());
        verify(passwordResetService).requestCode("User@Example.com");
        assertEquals(
                "If an account exists for that email, a reset code has been sent.",
                ((Map<?, ?>) response.getBody()).get("message"));
    }

    @Test
    void forgotPasswordSurfacesMissingMailConfiguration() {
        doThrow(new ResponseStatusException(
                        HttpStatus.SERVICE_UNAVAILABLE, "Mail is not configured"))
                .when(passwordResetService)
                .requestCode("user@example.com");

        ResponseEntity<?> response =
                controller.forgotPassword(Map.of("email", "user@example.com"));

        assertEquals(503, response.getStatusCode().value());
        assertEquals("Mail is not configured", ((Map<?, ?>) response.getBody()).get("message"));
    }

    @Test
    void verificationReturnsValidationErrorForInvalidCode() {
        when(passwordResetService.verifyCode("user@example.com", "000000"))
                .thenReturn(false);

        ResponseEntity<?> response = controller.verifyResetCode(Map.of(
                "email", "user@example.com",
                "code", "000000"));

        assertEquals(422, response.getStatusCode().value());
    }

    @Test
    void passwordResetRequiresMatchingValidCode() {
        when(passwordResetService.resetPassword(
                "user@example.com", "123456", "new-password"))
                .thenReturn(true);

        ResponseEntity<?> response = controller.resetPassword(Map.of(
                "email", "user@example.com",
                "code", "123456",
                "password", "new-password",
                "password_confirmation", "new-password"));

        assertEquals(200, response.getStatusCode().value());
        verify(passwordResetService).resetPassword(
                "user@example.com", "123456", "new-password");
    }

        @Test
        void offersReturnsFieldsAndHighlightsExpectedByFlutter() {
                when(jdbc.queryForList(contains("FROM offers"))).thenReturn(List.of(
                                new java.util.LinkedHashMap<>(Map.ofEntries(
                                                Map.entry("id", "istanbul-dream"),
                                                Map.entry("title", "Istanbul Dream"),
                                                Map.entry("location", "Istanbul"),
                                                Map.entry("country", "Turkey"),
                                                Map.entry("destination_code", "IST"),
                                                Map.entry("description", "Historic city break"),
                                                Map.entry("image_url", "https://example.com/istanbul.jpg"),
                                                Map.entry("price_per_person", new java.math.BigDecimal("1290.00")),
                                                Map.entry("flight_price_per_person", new java.math.BigDecimal("420.00")),
                                                Map.entry("hotel_price_per_night", new java.math.BigDecimal("95.00")),
                                                Map.entry("duration_nights", 7),
                                                Map.entry("rating", new java.math.BigDecimal("4.80")),
                                                Map.entry("review_count", 2340),
                                                Map.entry("highlights", "[\"Blue Mosque\",\"Hagia Sophia\"]"),
                                                Map.entry("is_featured", true),
                                                Map.entry("category", "cultural")))));

                Map<String, Object> response = controller.offers();
                List<?> offers = (List<?>) response.get("offers");
                Map<?, ?> offer = (Map<?, ?>) offers.getFirst();

                assertEquals(1, offers.size());
                assertEquals("istanbul-dream", offer.get("id"));
                assertEquals("IST", offer.get("destination_code"));
                assertEquals(List.of("Blue Mosque", "Hagia Sophia"), offer.get("highlights"));
                assertEquals(true, offer.get("is_featured"));
                assertEquals("Featured Offer", offer.get("badge"));
                assertEquals(new BigDecimal("1085.00"), offer.get("total_price_per_person"));
        }

    @Test
    void monumentSearchReturnsVerifiedProviderPlacesAndCityStatus() {
        when(openTripMapAttractionService.searchAttractionsWithStatus(
                eq("Khoms"), eq("Libya"), eq("en"), eq(""), any(), any(), any(),
                any(), any(), any(), any()))
                .thenReturn(new OpenTripMapAttractionService.SearchOutcome(
                        List.of(Map.of(
                                "id", "N12345",
                                "name", "Leptis Magna",
                                "city", "Khoms",
                                "country", "Libya",
                                "category_tag", "historical",
                                "source_provider", "opentripmap",
                                "wikidata_id", "Q183733")),
                        true, 1, Map.of(), List.of(), List.of(), 1));

        Map<String, Object> response =
                controller.searchMonuments("Khoms", null, "Libya", "en");
        Map<?, ?> monument = (Map<?, ?>) ((List<?>) response.get("attractions")).getFirst();

        assertEquals("Leptis Magna", monument.get("name"));
        assertEquals("Khoms", monument.get("city"));
        assertEquals("Libya", monument.get("country"));
        assertEquals("historical", monument.get("category_tag"));
        assertEquals("Q183733", monument.get("wikidata_id"));
        assertEquals(true, response.get("city_found"));
        assertEquals("opentripmap", response.get("source"));
        assertEquals(List.of("opentripmap"), response.get("providers"));
        verify(openTripMapAttractionService).searchAttractionsWithStatus(
                "Khoms", "Libya", "en", "", null, null, null, null, null, null, null);
    }

    @Test
    void cityNotFoundIsDistinguishedFromAnEmptyLandmarkResult() {
        when(openTripMapAttractionService.searchAttractionsWithStatus(
                eq("No Such City"), eq("Libya"), eq("ar"), eq(""), any(), any(), any(),
                any(), any(), any(), any()))
                .thenReturn(new OpenTripMapAttractionService.SearchOutcome(
                        List.of(), false, 0, Map.of(), List.of(), List.of(), 0));

        Map<String, Object> response =
                controller.searchMonuments("No Such City", null, "Libya", "ar");

        assertEquals("opentripmap", response.get("source"));
        assertEquals(false, response.get("city_found"));
        assertEquals(List.of(), response.get("attractions"));
        verify(openTripMapAttractionService).searchAttractionsWithStatus(
                "No Such City", "Libya", "ar", "", null, null, null, null, null, null, null);
    }

    @Test
    void arabicCitySearchUsesCountryFilteredGeocodingBeforeOpenTripMap() {
        GeoapifyAirportService geocoder = mock(GeoapifyAirportService.class);
        controller.setGeoapifyAirportService(geocoder);
        when(geocoder.resolveLocation("طرابلس", "ly"))
                .thenReturn(new GeoapifyAirportService.GeocodedPlace(
                        "Tripoli", "Tripoli", "Libya", "ly", "Tripoli District",
                        "Tripoli, Libya", "city", "geo-place", null, 32.89, 13.19));
        when(openTripMapAttractionService.searchAttractionsWithStatus(
                eq("Tripoli"), eq("Libya"), eq("ar"), eq(""),
                eq(32.89), eq(13.19),
                isNull(), isNull(), isNull(), isNull(), isNull()))
                .thenReturn(new OpenTripMapAttractionService.SearchOutcome(
                        List.of(Map.of(
                                "id", "P123",
                                "name", "Tripoli landmark",
                                "source_provider", "opentripmap")),
                        true, 1, Map.of(), List.of(), List.of(), 1));

        Map<String, Object> response =
                controller.searchMonuments("طرابلس", null, "ly", "ar");

        assertEquals("opentripmap", response.get("source"));
        assertEquals(1, ((List<?>) response.get("attractions")).size());
        verify(geocoder).resolveLocation("طرابلس", "ly");
        verify(openTripMapAttractionService).searchAttractionsWithStatus(
                "Tripoli", "Libya", "ar", "", 32.89, 13.19,
                null, null, null, null, null);
    }

    @Test
    void attractionSuggestionsUseTheOpenTripMapServerAdapter() {
        when(openTripMapAttractionService.suggestPlaces("Trip", "ar", null, null))
                .thenReturn(List.of(Map.of("label", "طرابلس", "result_type", "city")));

        Map<String, Object> response =
                controller.suggestAttractionPlaces("Trip", "ar");

        assertEquals(1, ((List<?>) response.get("suggestions")).size());
        verify(openTripMapAttractionService).suggestPlaces("Trip", "ar", null, null);
    }

    @Test
    void countryOnlySearchUsesOnlyOpenTripMap() {
        when(openTripMapAttractionService.searchAttractionsWithStatus(
                eq(""), eq("Indonesia"), eq("en"), eq(""), any(), any(), any(),
                any(), any(), any(), any()))
                .thenReturn(new OpenTripMapAttractionService.SearchOutcome(
                        List.of(Map.of("id", "N6789", "name", "Bali place")),
                        true, 1, Map.of(), List.of(), List.of(), 1));

        Map<String, Object> response =
                controller.searchMonuments("", null, "Indonesia", "en");

        assertEquals("opentripmap", response.get("source"));
        verify(openTripMapAttractionService).searchAttractionsWithStatus(
                "", "Indonesia", "en", "", null, null, null, null, null, null, null);
    }

    @Test
    void attractionVisitStoresOnlyAHashAndIncrementsTheCountOnce() {
        String visitorId = "0123456789abcdef0123456789abcdef";
        when(jdbc.queryForObject(
                contains("FROM tourist_monuments"), eq(Boolean.class), eq("place-1")))
                .thenReturn(true);
        when(jdbc.update(
                contains("INSERT INTO attraction_visit_dedup"),
                eq("place-1"), any(String.class)))
                .thenReturn(1);

        Map<String, Object> result = controller.recordAttractionVisit(
                "place-1", Map.of("visitor_id", visitorId));

        assertEquals(Boolean.TRUE, result.get("counted"));
        verify(jdbc).update(
                contains("INSERT INTO attraction_visit_dedup"),
                eq("place-1"),
                org.mockito.ArgumentMatchers.<String>argThat(
                        hash -> hash.matches("^[a-f0-9]{64}$") && !hash.equals(visitorId)));
        verify(jdbc).update(contains("INSERT INTO attraction_visit_counts"), eq("place-1"));
    }

    @Test
    void duplicateAttractionVisitDoesNotIncrementTheAggregate() {
        String visitorId = "0123456789abcdef0123456789abcdef";
        when(jdbc.queryForObject(
                contains("FROM tourist_monuments"), eq(Boolean.class), eq("place-1")))
                .thenReturn(true);
        when(jdbc.update(
                contains("INSERT INTO attraction_visit_dedup"),
                eq("place-1"), any(String.class)))
                .thenReturn(0);

        Map<String, Object> result = controller.recordAttractionVisit(
                "place-1", Map.of("visitor_id", visitorId));

        assertEquals(Boolean.FALSE, result.get("counted"));
        verify(jdbc, never()).update(
                contains("INSERT INTO attraction_visit_counts"), eq("place-1"));
    }

    @Test
    void attractionVisitBlocksBurstsOfDistinctAnonymousVisitors() {
        ApiController rateLimitedController =
                new ApiController(
                        jdbc, "", photoStorage, passwordResetService, openTripMapAttractionService);
        when(jdbc.queryForObject(
                contains("FROM tourist_monuments"), eq(Boolean.class), eq("place-1")))
                .thenReturn(true);
        when(jdbc.update(
                contains("INSERT INTO attraction_visit_dedup"),
                eq("place-1"), any(String.class)))
                .thenReturn(1);

        for (int i = 0; i < 60; i++) {
            String visitorId = String.format("%032x", i + 1);
            Map<String, Object> result = rateLimitedController.recordAttractionVisit(
                    "place-1", Map.of("visitor_id", visitorId));
            assertEquals(Boolean.TRUE, result.get("counted"));
        }

        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> rateLimitedController.recordAttractionVisit(
                        "place-1", Map.of("visitor_id", "00000000000000000000000000000061")));

        assertEquals(HttpStatus.TOO_MANY_REQUESTS, error.getStatusCode());
        verify(jdbc, times(60)).update(
                contains("INSERT INTO attraction_visit_counts"), eq("place-1"));
        verify(jdbc, times(60)).update(
                contains("INSERT INTO attraction_visit_dedup"), eq("place-1"), any(String.class));
    }

    @Test
    void attractionVisitRejectsMalformedVisitorIdentifiersBeforeDatabaseWrites() {
        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> controller.recordAttractionVisit(
                        "place-1", Map.of("visitor_id", "not-a-random-device-token")));

        assertEquals(HttpStatus.UNPROCESSABLE_ENTITY, error.getStatusCode());
        verifyNoInteractions(jdbc);
    }

    @Test
    void duplicateRegistrationEmailReturnsLaravelValidationResponse() {
        when(jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE email = ?", Integer.class, "user@example.com"))
                .thenReturn(1);

        ResponseEntity<?> response = controller.register(
                "Test User", "user@example.com", "123456789", "password123", "password123", null,
                new MockHttpServletRequest());

        assertEquals(422, response.getStatusCode().value());
        assertEquals(Map.of(
                "message", "The given data was invalid.",
                "errors", Map.of("email", List.of("The email has already been taken."))),
                response.getBody());
    }

    @Test
    void rejectsAFlightThatOverlapsAnExistingCustomerTrip() {
        when(jdbc.queryForList(contains("FOR UPDATE"), eq(7L)))
                .thenReturn(List.of(Map.of("id", 7L)));
        when(jdbc.queryForList(contains("FROM trips"), eq(7L)))
                .thenReturn(List.of(Map.of(
                        "departure_date", Timestamp.valueOf("2026-11-10 10:00:00"),
                        "arrival_date", "2026-11-10T17:00",
                        "status", "upcoming")));
        MockHttpServletRequest request = authenticatedRequest();

        ResponseEntity<?> response = controller.createTrip(Map.of(
                "origin_code", "JFK",
                "origin_city", "New York",
                "destination_code", "LHR",
                "destination_city", "London",
                "departure_date", "2026-11-10T10:00:00Z",
                "arrival_date", "2026-11-10T17:00:00Z",
                "flight_number", "ZT100"), request);

        assertEquals(409, response.getStatusCode().value());
        assertEquals(Map.of("message", "FLIGHT_SCHEDULE_CONFLICT"), response.getBody());
        verify(jdbc, never()).update(any(org.springframework.jdbc.core.PreparedStatementCreator.class),
                any(org.springframework.jdbc.support.KeyHolder.class));
    }

    @Test
    void tripInsertBindsOffsetTimestampsAsUtcInstants() throws Exception {
        when(jdbc.queryForList(contains("FOR UPDATE"), eq(7L)))
                .thenReturn(List.of(Map.of("id", 7L)));
        when(jdbc.queryForList(contains("FROM trips"), eq(7L)))
                .thenReturn(List.of());
        when(jdbc.update(any(org.springframework.jdbc.core.PreparedStatementCreator.class),
                any(org.springframework.jdbc.support.KeyHolder.class)))
                .thenAnswer(invocation -> {
                    org.springframework.jdbc.support.KeyHolder holder = invocation.getArgument(1);
                    holder.getKeyList().add(Map.of("GENERATED_KEY", 99L));
                    return 1;
                });
        when(jdbc.queryForMap(contains("SELECT trips.*"), eq(99L)))
                .thenReturn(new java.util.LinkedHashMap<>(Map.of("id", 99L)));

        controller.createTrip(Map.of(
                "origin_code", "MRA",
                "origin_city", "Misrata",
                "destination_code", "MJI",
                "destination_city", "Tripoli",
                "departure_date", "2026-11-10T10:00:00+02:00",
                "arrival_date", "2026-11-10T13:00:00+02:00",
                "return_date", "2026-11-20T08:00:00-05:00",
                "flight_number", "ZT300"), authenticatedRequest());

        org.mockito.ArgumentCaptor<org.springframework.jdbc.core.PreparedStatementCreator> creator =
                org.mockito.ArgumentCaptor.forClass(
                        org.springframework.jdbc.core.PreparedStatementCreator.class);
        verify(jdbc).update(creator.capture(),
                any(org.springframework.jdbc.support.KeyHolder.class));
        java.sql.Connection connection = mock(java.sql.Connection.class);
        java.sql.PreparedStatement statement = mock(java.sql.PreparedStatement.class);
        when(connection.prepareStatement(any(String.class), org.mockito.AdditionalMatchers.aryEq(new String[]{"id"})))
                .thenReturn(statement);
        creator.getValue().createPreparedStatement(connection);

        verify(statement).setObject(10, java.time.OffsetDateTime.parse("2026-11-10T08:00Z"));
        verify(statement).setObject(11, java.time.OffsetDateTime.parse("2026-11-20T13:00Z"));
        verify(statement).setObject(20, "2026-11-10T11:00Z");
    }

    @Test
    void aFlightBookingCannotUseAHotelPartnerListing() {
        when(jdbc.queryForList(contains("FROM partner_listings l"), eq(51L)))
                .thenReturn(List.of(Map.of(
                        "id", 51L,
                        "partner_id", 9L,
                        "type", "hotel",
                        "active", true,
                        "price", 150)));

        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.createTrip(Map.of(
                        "origin_code", "MJI",
                        "origin_city", "Tripoli",
                        "destination_code", "CAI",
                        "destination_city", "Cairo",
                        "departure_date", "2026-11-10T08:00:00",
                        "arrival_date", "2026-11-10T10:00:00",
                        "flight_number", "MANUAL-1",
                        "partner_listing_id", 51), authenticatedRequest()));

        assertEquals(422, error.getStatusCode().value());
        verify(jdbc, never()).update(any(
                org.springframework.jdbc.core.PreparedStatementCreator.class),
                any(org.springframework.jdbc.support.KeyHolder.class));
    }

    @Test
    void aPartnerFlightBookingRequiresEnoughSeatsForEveryPassenger() {
        when(jdbc.queryForList(contains("FROM partner_listings l"), eq(51L)))
                .thenReturn(List.of(Map.of(
                        "id", 51L,
                        "partner_id", 9L,
                        "type", "flight",
                        "active", true,
                        "price", 150)));
        when(jdbc.queryForList(contains("WHERE user_id = ? AND LOWER(status)"), eq(7L)))
                .thenReturn(List.of());

        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.createTrip(Map.of(
                        "origin_code", "MRA",
                        "origin_city", "Misrata",
                        "destination_code", "MJI",
                        "destination_city", "Tripoli",
                        "departure_date", "2026-11-10T08:00:00",
                        "arrival_date", "2026-11-10T10:00:00",
                        "flight_number", "YL-51",
                        "partner_listing_id", 51,
                        "passenger_count", 2), authenticatedRequest()));

        assertEquals(409, error.getStatusCode().value());
        verify(jdbc).update(contains("'{seats_available}'"), eq(2), eq(51L), eq(2));
        verify(jdbc, never()).update(
                any(org.springframework.jdbc.core.PreparedStatementCreator.class),
                any(org.springframework.jdbc.support.KeyHolder.class));
    }

    @Test
    void rejectsAnotherFlightOnTheSameCalendarDateEvenWhenTimesDoNotOverlap() {
        when(jdbc.queryForList(contains("FOR UPDATE"), eq(7L)))
                .thenReturn(List.of(Map.of("id", 7L)));
        when(jdbc.queryForList(contains("FROM trips"), eq(7L)))
                .thenReturn(List.of(Map.of(
                        "departure_date", Timestamp.valueOf("2026-10-17 06:00:00"),
                        "arrival_date", "2026-10-17T08:00",
                        "airline", "First Airline",
                        "status", "upcoming")));

        ResponseEntity<?> response = controller.createTrip(Map.of(
                "origin_code", "JFK",
                "origin_city", "New York",
                "destination_code", "LHR",
                "destination_city", "London",
                "departure_date", "2026-10-17T17:00:00Z",
                "arrival_date", "2026-10-17T20:00:00Z",
                "flight_number", "ZT200",
                "airline", "Different Airline"), authenticatedRequest());

        assertEquals(409, response.getStatusCode().value());
        assertEquals(Map.of("message", "FLIGHT_SCHEDULE_CONFLICT"), response.getBody());
        verify(jdbc, never()).update(any(org.springframework.jdbc.core.PreparedStatementCreator.class),
                any(org.springframework.jdbc.support.KeyHolder.class));
    }

    @Test
    void rejectsFlightDuringExistingRoundTripReturnWindow() {
        when(jdbc.queryForList(contains("FOR UPDATE"), eq(7L)))
                .thenReturn(List.of(Map.of("id", 7L)));
        when(jdbc.queryForList(contains("FROM trips"), eq(7L)))
                .thenReturn(List.of(Map.of(
                        "departure_date", Timestamp.valueOf("2026-11-10 10:00:00"),
                        "arrival_date", "2026-11-10T17:00",
                        "return_date", Timestamp.valueOf("2026-11-20 00:00:00"),
                        "status", "upcoming")));

        ResponseEntity<?> response = controller.createTrip(Map.of(
                "origin_code", "DXB",
                "origin_city", "Dubai",
                "destination_code", "CAI",
                "destination_city", "Cairo",
                "departure_date", "2026-11-15T10:00:00Z",
                "arrival_date", "2026-11-15T13:00:00Z",
                "flight_number", "ZT200"), authenticatedRequest());

        assertEquals(409, response.getStatusCode().value());
        assertEquals(Map.of("message", "FLIGHT_SCHEDULE_CONFLICT"), response.getBody());
        verify(jdbc, never()).update(any(org.springframework.jdbc.core.PreparedStatementCreator.class),
                any(org.springframework.jdbc.support.KeyHolder.class));
    }

        @Test
        void genericBookingEndpointCannotBypassFlightScheduleChecks() {
                ResponseStatusException exception = assertThrows(
                                ResponseStatusException.class,
                                () -> controller.createBooking(Map.of(
                                                "type", "flight",
                                                "title", "New York to London",
                                                "subtitle", "ZT100",
                                                "date", "2026-11-10T10:00:00Z"), authenticatedRequest()));

                assertEquals(422, exception.getStatusCode().value());
                verifyNoInteractions(jdbc);
        }

        @Test
        void flightCancellationKeepsTripAndStartsRefundReview() {
                when(jdbc.queryForList(contains("FOR UPDATE"), eq(12L), eq(7L)))
                                .thenReturn(List.of(Map.of(
                                                "id", 12L,
                                                "status", "upcoming",
                                                                "partner_listing_id", 51L,
                                                                "passenger_count", "2",
                                                                "refund_status", "",
                                                                "refund_method", "")));
                when(jdbc.update(contains("jsonb_build_object"), eq(12L), eq(7L))).thenReturn(1);
                when(jdbc.update(contains("'{seats_available}'"), eq(2), eq(51L)))
                                .thenReturn(1);

                ResponseEntity<?> response = controller.deleteTrip(12L, authenticatedRequest());

                assertEquals(200, response.getStatusCode().value());
                assertEquals(Map.of(
                                "status", "cancelled",
                                "refund_status", "pending_airline_review",
                                "refund_method", "original_payment_method"), response.getBody());
                verify(jdbc).update(
                                contains("'{seats_available}'"), eq(2), eq(51L));
                verify(jdbc, never()).update(contains("DELETE FROM trips"), eq(12L), eq(7L));
        }

        @Test
        void repeatedFlightCancellationDoesNotRestartRefundProcessing() {
                when(jdbc.queryForList(contains("FOR UPDATE"), eq(12L), eq(7L)))
                                .thenReturn(List.of(Map.of(
                                                "id", 12L,
                                                "status", "cancelled",
                                                "partner_listing_id", 51L,
                                                "passenger_count", "2",
                                                "refund_status", "pending_airline_review",
                                                "refund_method", "original_payment_method")));

                ResponseEntity<?> response = controller.deleteTrip(12L, authenticatedRequest());

                assertEquals(200, response.getStatusCode().value());
                assertEquals("pending_airline_review", ((Map<?, ?>) response.getBody()).get("refund_status"));
                verify(jdbc, never()).update(contains("jsonb_build_object"), eq(12L), eq(7L));
                verify(jdbc, never()).update(contains("$.seats_available"), eq(2), eq(51L));
        }

            @Test
            void rejectsHotelBookingThatOverlapsAnExistingStay() {
                when(jdbc.queryForList(contains("FOR UPDATE"), eq(7L)))
                        .thenReturn(List.of(Map.of("id", 7L)));
                when(jdbc.queryForList(contains("FROM bookings"), eq(7L), eq("hotel")))
                        .thenReturn(List.of(Map.of(
                                "title", "City Hotel",
                                "date", Timestamp.valueOf("2026-11-10 15:00:00"),
                                "end_date", "2026-11-14T11:00:00")));

                ResponseEntity<?> response = controller.createBooking(Map.of(
                        "type", "hotel",
                        "title", "Another Hotel",
                        "subtitle", "Cairo",
                        "date", "2026-11-12T15:00:00Z",
                        "end_date", "2026-11-15T11:00:00Z",
                        "price", 350), authenticatedRequest());

                assertEquals(409, response.getStatusCode().value());
                assertEquals(Map.of("message", "BOOKING_SCHEDULE_CONFLICT"), response.getBody());
                verify(jdbc, never()).update(any(org.springframework.jdbc.core.PreparedStatementCreator.class),
                        any(org.springframework.jdbc.support.KeyHolder.class));
            }

    @Test
    void rejectsCarRentalThatOverlapsAnExistingRental() {
        when(jdbc.queryForList(contains("FOR UPDATE"), eq(7L)))
                .thenReturn(List.of(Map.of("id", 7L)));
        when(jdbc.queryForList(contains("FROM bookings"), eq(7L), eq("car")))
                .thenReturn(List.of(Map.of(
                        "title", "Sedan",
                        "date", Timestamp.valueOf("2026-11-10 09:00:00"),
                        "end_date", "2026-11-12T09:00:00")));

        ResponseEntity<?> response = controller.createBooking(Map.of(
                "type", "car",
                "title", "SUV",
                "subtitle", "Airport",
                "date", "2026-11-11T12:00:00Z",
                "end_date", "2026-11-13T12:00:00Z",
                "price", 200), authenticatedRequest());

        assertEquals(409, response.getStatusCode().value());
        assertEquals(Map.of("message", "BOOKING_SCHEDULE_CONFLICT"), response.getBody());
    }

    @Test
    void cancelsOwnedHotelBookingAndRestoresReservedRooms() {
        when(jdbc.queryForList(contains("FROM bookings"), eq(18L), eq(7L)))
                .thenReturn(List.of(Map.of(
                        "status", "upcoming",
                        "type", "hotel",
                        "partner_listing_id", 42L,
                        "hotel_rooms_reserved", 2)));
        when(jdbc.update(contains("UPDATE bookings SET status = 'cancelled'"),
                eq(18L), eq(7L))).thenReturn(1);
        when(jdbc.update(contains("available_rooms + ?"),
                eq(2), eq(2), eq(42L))).thenReturn(1);

        ResponseEntity<?> response = controller.cancelBooking(18L, authenticatedRequest());

        assertEquals(200, response.getStatusCode().value());
        assertEquals(Map.of("status", "cancelled"), response.getBody());
        verify(jdbc).update(contains("UPDATE bookings SET status = 'cancelled'"),
                eq(18L), eq(7L));
        verify(jdbc).update(contains("available_rooms + ?"),
                eq(2), eq(2), eq(42L));
    }

    @Test
    void cannotCancelAnotherUsersBooking() {
        when(jdbc.queryForList(contains("FROM bookings"), eq(18L), eq(7L)))
                .thenReturn(List.of());

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.cancelBooking(18L, authenticatedRequest()));

        assertEquals(404, exception.getStatusCode().value());
        verify(jdbc, never()).update(contains("UPDATE bookings SET status = 'cancelled'"),
                eq(18L), eq(7L));
    }

    @Test
    void completedBookingCannotBeCancelled() {
        when(jdbc.queryForList(contains("FROM bookings"), eq(18L), eq(7L)))
                .thenReturn(List.of(Map.of("status", "completed")));

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.cancelBooking(18L, authenticatedRequest()));

        assertEquals(409, exception.getStatusCode().value());
        verify(jdbc, never()).update(contains("UPDATE bookings SET status = 'cancelled'"),
                eq(18L), eq(7L));
    }

    @Test
    void rejectsOverlappingTaxiBookingsForTheSameCustomer() {
        when(jdbc.queryForList(contains("FOR UPDATE"), eq(7L)))
                .thenReturn(List.of(Map.of("id", 7L)));
        when(jdbc.queryForList(contains("FROM transfers"), eq(7L)))
                .thenReturn(List.of(Map.of(
                        "pickup_time", java.time.OffsetDateTime.parse("2026-11-10T10:00:00Z"),
                        "duration_minutes", 45,
                        "status", "confirmed")));

        ResponseEntity<?> response = controller.createTransfer(Map.of(
                "provider_name", "Zentrip Taxi",
                "vehicle_type", "sedan",
                "pickup_location", "Airport",
                "dropoff_location", "Hotel",
                "pickup_time", "2026-11-10T10:30:00",
                "duration_minutes", 30,
                "price", 35,
                "passengers", 2), authenticatedRequest());

        assertEquals(409, response.getStatusCode().value());
        assertEquals(Map.of("message", "TAXI_SCHEDULE_CONFLICT"), response.getBody());
        verify(jdbc, never()).update(any(org.springframework.jdbc.core.PreparedStatementCreator.class),
                any(org.springframework.jdbc.support.KeyHolder.class));
    }

    @Test
    void bookingDetailsStoreOnlyHttpCoverImages() throws Exception {
        java.time.OffsetDateTime end = java.time.OffsetDateTime.parse("2026-11-12T09:00:00Z");

        String withImage = ApiController.bookingDetailsJson(
                end, " https://example.com/car.jpg ", 2, true);
        String unsafe = ApiController.bookingDetailsJson(
                end, "javascript:alert(1)", 1, false);
        String missing = ApiController.bookingDetailsJson(end, null, 1, false);

        assertTrue(withImage.contains("\"image_url\":\"https://example.com/car.jpg\""));
        assertTrue(withImage.contains("\"end_date\":\"2026-11-12T09:00Z\""));
        assertTrue(withImage.contains("\"rooms\":2"));
        assertTrue(withImage.contains("\"hotel_rooms_reserved\":2"));
        assertTrue(!unsafe.contains("image_url"));
        assertTrue(!missing.contains("image_url"));
    }

    @Test
    void hotelBookingRejectsWhenRequestedRoomsExceedListingInventory() {
        when(jdbc.queryForList(contains("FROM partner_listings l"), eq(42L)))
                .thenReturn(List.of(Map.of(
                        "id", 42L,
                        "partner_id", 9L,
                        "type", "hotel",
                        "active", true,
                        "price", new BigDecimal("120.00"))));
        when(jdbc.queryForList(contains("SELECT id FROM users WHERE id = ? FOR UPDATE"),
                eq(7L)))
                .thenReturn(List.of(Map.of("id", 7L)));
        when(jdbc.queryForList(contains("FROM bookings"), eq(7L), eq("hotel")))
                .thenReturn(List.of());
        when(jdbc.update(
                contains("SET attributes = jsonb_set"),
                eq(2), eq(2), eq(42L), eq(2)))
                .thenReturn(0);

        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.createBooking(Map.of(
                        "type", "hotel",
                        "title", "Al-Masa Hotel",
                        "subtitle", "Tripoli",
                        "date", "2026-11-10T12:00:00Z",
                        "end_date", "2026-11-12T12:00:00Z",
                        "price", 240,
                        "partner_listing_id", 42,
                        "rooms", 2), authenticatedRequest()));

        assertEquals(409, error.getStatusCode().value());
        assertEquals("HOTEL_SOLD_OUT", error.getReason());
        verify(jdbc).update(
                contains("available_rooms >= ?"), eq(2), eq(2), eq(42L), eq(2));
    }

    @Test
    void rejectsDuplicateAttractionTicketForSameCustomerAndDay() {
        when(jdbc.queryForList(contains("FOR UPDATE"), eq(7L)))
                .thenReturn(List.of(Map.of("id", 7L)));
        when(jdbc.queryForList(contains("FROM bookings"), eq(7L), eq("attraction")))
                .thenReturn(List.of(Map.of(
                        "title", "Museum of Cairo",
                        "date", Timestamp.valueOf("2026-11-10 00:00:00"),
                        "end_date", "2026-11-11T00:00:00")));

        ResponseEntity<?> response = controller.createBooking(Map.of(
                "type", "attraction",
                "title", "Museum of Cairo",
                "subtitle", "Cairo",
                "date", "2026-11-10T12:00:00Z",
                "end_date", "2026-11-11T12:00:00Z",
                "price", 25), authenticatedRequest());

        assertEquals(409, response.getStatusCode().value());
        assertEquals(Map.of("message", "BOOKING_SCHEDULE_CONFLICT"), response.getBody());
    }

    @Test
    void seatMapRequiresAnAuthenticatedUser() {
        MockHttpServletRequest request = new MockHttpServletRequest();

        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.flightSeats(42L, request));

        assertEquals(401, error.getStatusCode().value());
        verifyNoInteractions(jdbc);
    }

    @Test
    void seatReservationRejectsSeatsOutsideConfiguredAircraftLayout() {
        Map<String, Object> listing = new java.util.LinkedHashMap<>();
        listing.put("id", 42L);
        listing.put("partner_id", 9L);
        listing.put("title", "Tripoli to Istanbul");
        listing.put("city", "Tripoli");
        listing.put("price", new BigDecimal("180.00"));
        listing.put("partner_name", "Libyan Wings");
        listing.put("attributes", Map.of(
                "seat_layout", "2-2",
                "seat_rows", 16,
                "seats_available", 16));
        when(jdbc.queryForList(contains("FROM partner_listings l"), eq(42L)))
                .thenReturn(List.of(listing));

        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.reserveFlightSeatSelection(
                        42L,
                        Map.of("seats", List.of("1E")),
                        authenticatedRequest()));

        assertEquals(422, error.getStatusCode().value());
        verify(jdbc, never()).update(contains("INSERT INTO flight_seat_holds"),
                eq(42L), eq(7L), eq("1E"));
    }

    @Test
    void flightConfirmationRetryReturnsTheExistingBooking() {
        Map<String, Object> listing = new java.util.LinkedHashMap<>();
        listing.put("id", 42L);
        listing.put("partner_id", 9L);
        listing.put("title", "Tripoli to Istanbul");
        listing.put("city", "Tripoli");
        listing.put("price", new BigDecimal("180.00"));
        listing.put("partner_name", "Libyan Wings");
        listing.put("attributes", Map.of(
                "seat_layout", "2-2",
                "seat_rows", 16,
                "seats_available", 16));
        when(jdbc.queryForList(contains("FROM partner_listings l"), eq(42L)))
                .thenReturn(List.of(listing));
        when(jdbc.queryForList(
                contains("FROM flight_seat_holds h"),
                any(Object[].class)))
                .thenReturn(List.of(Map.of(
                        "seat_number", "1A",
                        "trip_id", 88L,
                        "booking_ref", "ZT-12345678",
                        "price", new BigDecimal("213.36"),
                        "details", Map.of("extras", List.of("extra_baggage")))));
        when(jdbc.queryForMap(contains("FROM trips WHERE id = ?"), eq(88L)))
                .thenReturn(Map.of(
                        "id", 88L,
                        "booking_ref", "ZT-12345678",
                        "price", new BigDecimal("213.36")));

        ResponseEntity<?> response = controller.confirmFlightBooking(Map.of(
                "flight_id", 42,
                "seat_class", "economy",
                "extras", List.of("extra_baggage"),
                "seats", List.of("1A")), authenticatedRequest());

        assertEquals(200, response.getStatusCode().value());
        Map<?, ?> payload = (Map<?, ?>) response.getBody();
        Map<?, ?> booking = (Map<?, ?>) payload.get("booking");
        assertEquals("ZT-12345678", booking.get("reference"));
        assertEquals(List.of("1A"), booking.get("seats"));
        assertEquals(List.of("extra_baggage"), booking.get("extras"));
        verify(jdbc, never()).update(contains("SET attributes = jsonb_set"),
                any(Object[].class));
    }

        @Test
        void updateProfileChangesNameAndPhone() {
                MockHttpServletRequest request = authenticatedRequest();
                when(jdbc.update("UPDATE users SET name = ?, phone = ?, updated_at = NOW() WHERE id = ?",
                                "Updated User", "987654321", 7L)).thenReturn(1);
                when(jdbc.queryForMap(contains("LEFT JOIN partners"), eq(7L)))
                                .thenReturn(new java.util.LinkedHashMap<>(Map.of(
                                                "id", 7L,
                                                "name", "Updated User",
                                                "email", "user@example.com",
                                                "phone", "987654321",
                                                "role", "customer")));

                ResponseEntity<?> response = controller.updateProfile("Updated User", "987654321", null, request);

                assertEquals(200, response.getStatusCode().value());
                Map<?, ?> responseBody = (Map<?, ?>) response.getBody();
                assertNotNull(responseBody);
                Map<?, ?> user = (Map<?, ?>) responseBody.get("user");
                assertNotNull(user);
                assertEquals("Updated User", user.get("name"));
        }

        @Test
        void changePasswordRejectsAnIncorrectCurrentPassword() {
                when(jdbc.queryForList("SELECT password FROM users WHERE id = ?", 7L))
                                .thenReturn(List.of(Map.of("password", new BCryptPasswordEncoder().encode("correct-password"))));
                MockHttpServletRequest request = authenticatedRequest();

                ResponseEntity<?> response = controller.changePassword(Map.of(
                                "current_password", "wrong-password",
                                "password", "new-password",
                                "password_confirmation", "new-password"), request);

                assertEquals(422, response.getStatusCode().value());
        Map<?, ?> responseBody = (Map<?, ?>) response.getBody();
        assertNotNull(responseBody);
        assertTrue(responseBody.containsKey("errors"));
        }

        @Test
        void reviewSubmissionPersistsUserRatingAndUsesServerUserName() {
                when(jdbc.queryForMap(
                                contains("FROM user_reviews r"),
                                eq(7L),
                                eq("partner-42"),
                                eq("hotel")))
                                .thenReturn(Map.of(
                                                "id", "9",
                                                "item_id", "partner-42",
                                                "item_type", "hotel",
                                                "user_name", "Verified Customer",
                                                "rating", new BigDecimal("4.5"),
                                                "comment", "Great stay"));

                Map<String, Object> response = controller.submitReview(Map.of(
                                "item_id", "partner-42",
                                "item_type", "hotel",
                                "user_name", "Forged Name",
                                "rating", 4.5,
                                "comment", "Great stay"), authenticatedRequest());

                Map<?, ?> review = (Map<?, ?>) response.get("review");
                assertEquals("Verified Customer", review.get("user_name"));
                verify(jdbc).update(
                                contains("INSERT INTO user_reviews"),
                                eq(7L),
                                eq("partner-42"),
                                eq("hotel"),
                                eq(new BigDecimal("4.5")),
                                eq("Great stay"));
        }

        private static MockHttpServletRequest authenticatedRequest() {
                MockHttpServletRequest request = new MockHttpServletRequest();
                request.setAttribute("authUserId", 7L);
                return request;
        }
}
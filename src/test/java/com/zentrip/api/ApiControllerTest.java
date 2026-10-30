package com.zentrip.api;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import org.junit.jupiter.api.Test;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

class ApiControllerTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
        private final ProfilePhotoStorage photoStorage = mock(ProfilePhotoStorage.class);
        private final PasswordResetService passwordResetService = mock(PasswordResetService.class);
        private final ApiController controller =
                new ApiController(jdbc, "", photoStorage, passwordResetService);

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
    void monumentSearchMapsAdminCatalogDataToAttractionContract() {
        when(jdbc.queryForList(contains("FROM tourist_monuments"),
                eq("khoms"), eq("%khoms%"), eq(""), eq("")))
                .thenReturn(List.of(Map.ofEntries(
                        Map.entry("id", "monument-1"),
                        Map.entry("title", "Leptis Magna"),
                        Map.entry("location", "Khoms, Libya"),
                        Map.entry("category_tag", "Historical"),
                        Map.entry("category", "landmark"),
                        Map.entry("rating", new BigDecimal("4.90")),
                        Map.entry("review_count", 3120),
                        Map.entry("description", "A Roman city"),
                        Map.entry("working_hours", "8:00 AM - 5:00 PM"),
                        Map.entry("best_time_to_visit", "Oct - Apr"),
                        Map.entry("entry_fee", new BigDecimal("5.00")),
                        Map.entry("image_url", "https://example.com/leptis.jpg"),
                        Map.entry("tags", "[\"Theatre\",\"Market\"]"))));

        Map<String, Object> response = controller.searchMonuments("Khoms", null);
        Map<?, ?> monument = (Map<?, ?>) ((List<?>) response.get("attractions")).getFirst();

        assertEquals("Leptis Magna", monument.get("name"));
        assertEquals("Khoms", monument.get("city"));
        assertEquals("Libya", monument.get("country"));
        assertEquals("Historical", monument.get("category_tag"));
        assertEquals("8:00 AM - 5:00 PM", monument.get("opening_hours"));
        assertEquals(List.of("Theatre", "Market"), monument.get("tags"));
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
        verify(jdbc).update(contains("$.seats_available"), eq(2), eq(51L), eq(2));
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
                when(jdbc.update(contains("JSON_SET"), eq(12L), eq(7L))).thenReturn(1);
                when(jdbc.update(contains("$.seats_available"), eq(2), eq(51L)))
                                .thenReturn(1);

                ResponseEntity<?> response = controller.deleteTrip(12L, authenticatedRequest());

                assertEquals(200, response.getStatusCode().value());
                assertEquals(Map.of(
                                "status", "cancelled",
                                "refund_status", "pending_airline_review",
                                "refund_method", "original_payment_method"), response.getBody());
                verify(jdbc).update(
                                contains("$.seats_available"), eq(2), eq(51L));
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
                verify(jdbc, never()).update(contains("JSON_SET"), eq(12L), eq(7L));
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
                eq(2), eq(2), eq(42L), eq(2))).thenReturn(1);

        ResponseEntity<?> response = controller.cancelBooking(18L, authenticatedRequest());

        assertEquals(200, response.getStatusCode().value());
        assertEquals(Map.of("status", "cancelled"), response.getBody());
        verify(jdbc).update(contains("UPDATE bookings SET status = 'cancelled'"),
                eq(18L), eq(7L));
        verify(jdbc).update(contains("available_rooms + ?"),
                eq(2), eq(2), eq(42L), eq(2));
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
                        "pickup_time", Timestamp.valueOf("2026-11-10 10:00:00"),
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
        java.time.LocalDateTime end = java.time.LocalDateTime.parse("2026-11-12T09:00:00");

        String withImage = ApiController.bookingDetailsJson(
                end, " https://example.com/car.jpg ", 2, true);
        String unsafe = ApiController.bookingDetailsJson(
                end, "javascript:alert(1)", 1, false);
        String missing = ApiController.bookingDetailsJson(end, null, 1, false);

        assertTrue(withImage.contains("\"image_url\":\"https://example.com/car.jpg\""));
        assertTrue(withImage.contains("\"end_date\":\"2026-11-12T09:00\""));
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
                contains("SET attributes = JSON_SET"),
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
        verify(jdbc, never()).update(contains("SET attributes = JSON_SET"),
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
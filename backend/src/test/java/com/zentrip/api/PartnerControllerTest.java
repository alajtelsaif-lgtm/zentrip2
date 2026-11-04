package com.zentrip.api;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.LinkedHashMap;

import org.junit.jupiter.api.Test;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PartnerControllerTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final ProfilePhotoStorage imageStorage = mock(ProfilePhotoStorage.class);
    private final AirportDirectoryService airportDirectoryService =
            mock(AirportDirectoryService.class);
    private final DuffelFlightService duffelFlightService = mock(DuffelFlightService.class);
    private final LiteApiHotelService liteApiHotelService =
            mock(LiteApiHotelService.class);
    private final HotelDestinationCatalogService hotelDestinationCatalogService =
            mock(HotelDestinationCatalogService.class);
    private final PartnerController controller = new PartnerController(
            jdbc,
            imageStorage,
            mock(GooglePlacesRatingSync.class),
            airportDirectoryService,
            duffelFlightService,
            liteApiHotelService,
            hotelDestinationCatalogService,
            mock(ExchangeRateService.class));

    @Test
    void airportSearchDelegatesTheUniversalSearchQuery() {
        Map<String, Object> expected = Map.of(
                "query_type", "city",
                "airports", List.of(Map.of("code", "LHR"), Map.of("code", "LGW")));
        when(airportDirectoryService.search(" London ")).thenReturn(expected);

        assertEquals(expected, controller.searchAirports(" London "));
        verify(airportDirectoryService).search(" London ");
    }

    @Test
    void hotelDestinationSuggestionsUseTheLocalCatalogService() {
        List<Map<String, Object>> expected =
                List.of(Map.of("name", "London", "type", "city"));
        when(hotelDestinationCatalogService.suggest("lo", "ar"))
                .thenReturn(expected);

        assertEquals(
                Map.of("suggestions", expected),
                controller.suggestHotelDestinations("lo", "ar"));
        verify(hotelDestinationCatalogService).suggest("lo", "ar");
    }

    @Test
    void hotelImageUploadRequiresAnAuthenticatedHotelPartnerAndStoresImage() {
        when(jdbc.queryForMap(contains("FROM users u JOIN partners p"), eq(7L)))
                .thenReturn(Map.of(
                        "partner_id", 3L,
                        "name", "Example Hotel",
                        "service_type", "hotel",
                        "slug", "example-hotel"));
        when(imageStorage.store(org.mockito.ArgumentMatchers.any()))
                .thenReturn("/uploads/hotel-photo.jpg");

        MockHttpServletRequest request = authenticatedRequest();
        request.setRequestURI("/api/partner/hotel-images");
        RequestContextHolder.setRequestAttributes(new ServletRequestAttributes(request));
        try {
            Map<String, String> response = controller.uploadHotelImage(
                    new MockMultipartFile(
                            "image", "hotel.jpg", "image/jpeg", new byte[] {1, 2, 3}),
                    request);

            org.junit.jupiter.api.Assertions.assertTrue(
                    response.get("image_url").endsWith("/uploads/hotel-photo.jpg"));
            verify(imageStorage).store(org.mockito.ArgumentMatchers.any());
        } finally {
            RequestContextHolder.resetRequestAttributes();
        }
    }

    @Test
    void nonHotelPartnerCannotUploadHotelImages() {
        when(jdbc.queryForMap(contains("FROM users u JOIN partners p"), eq(7L)))
                .thenReturn(Map.of(
                        "partner_id", 3L,
                        "name", "Example Airline",
                        "service_type", "airline",
                        "slug", "example-airline"));

        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.uploadHotelImage(
                        new MockMultipartFile(
                                "image", "hotel.jpg", "image/jpeg", new byte[] {1}),
                        authenticatedRequest()));

        assertEquals(403, error.getStatusCode().value());
        verify(imageStorage, never()).store(org.mockito.ArgumentMatchers.any());
    }

    @Test
    void hotelListingsRequireAHostedPhoto() {
        when(jdbc.queryForMap(contains("FROM users u JOIN partners p"), eq(7L)))
                .thenReturn(Map.of(
                        "partner_id", 3L,
                        "name", "Example Hotel",
                        "service_type", "hotel"));

        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.createListing(
                        Map.of("type", "hotel", "title", "No Photo", "price", 80),
                        authenticatedRequest()));

        assertEquals(400, error.getStatusCode().value());
        verify(jdbc, never()).update(org.mockito.ArgumentMatchers.any(
                org.springframework.jdbc.core.PreparedStatementCreator.class),
                org.mockito.ArgumentMatchers.any(
                        org.springframework.jdbc.support.KeyHolder.class));
    }

    @Test
    void partnerCannotReadOrUpdateAnotherCompanyListing() {
        when(jdbc.queryForMap(contains("FROM users u JOIN partners p"), eq(7L)))
                .thenReturn(Map.of(
                        "partner_id", 3L,
                        "name", "Example Hotel",
                        "service_type", "hotel"));
        when(jdbc.queryForMap(
                contains("WHERE id = ? AND partner_id = ?"),
                eq(42L),
                eq(3L)))
                .thenThrow(new EmptyResultDataAccessException(1));

        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.updateListing(
                        42L, Map.of("title", "Other company's hotel"), authenticatedRequest()));

        assertEquals(403, error.getStatusCode().value());
        verify(jdbc, never()).update(contains("UPDATE partner_listings SET"));
    }

    @Test
    void partnerReservationsOnlyIncludeRowsLinkedToListingsOwnedByThatPartner() {
        when(jdbc.queryForMap(contains("FROM users u JOIN partners p"), eq(7L)))
                .thenReturn(Map.of(
                        "partner_id", 3L,
                        "name", "Example Hotel",
                        "service_type", "hotel"));
        when(jdbc.queryForList(
                contains("l.id = t.partner_listing_id"),
                eq(3L), eq(3L), eq(3L), eq(50)))
                .thenReturn(List.of());

        Map<String, Object> response =
                controller.partnerReservations(50, authenticatedRequest());

        assertEquals(List.of(), response.get("reservations"));
        verify(jdbc).queryForList(
                contains("l.id = t.partner_listing_id"),
                eq(3L), eq(3L), eq(3L), eq(50));
    }

    @Test
    void publicHotelInventoryIncludesPartnerMetadataAndListingPrice() {
        when(jdbc.queryForList(contains("FROM partner_listings l"), eq("hotel")))
                .thenReturn(List.of(Map.ofEntries(
                        Map.entry("id", 42L),
                        Map.entry("type", "hotel"),
                        Map.entry("title", "Partner Hotel"),
                        Map.entry("city", "Tripoli"),
                        Map.entry("country", "Libya"),
                        Map.entry("partner_name", "Example Hotel"),
                        Map.entry("description", "Sea view"),
                        Map.entry("image_url", "https://example.com/hotel.jpg"),
                        Map.entry("price", new BigDecimal("84.50")),
                        Map.entry("aggregated_rating", new BigDecimal("4.75")),
                        Map.entry("aggregated_review_count", 4),
                        Map.entry("google_rating", new BigDecimal("4.9")),
                        Map.entry("google_review_count", 8240),
                        Map.entry("location_name", "City Center, Tripoli"),
                        Map.entry("google_maps_url", "https://maps.google.com/example"),
                        Map.entry("place_id", "ChIJtestplaceid12345"),
                        Map.entry("amenities", "[\"Gym\",\"Wi-Fi\"]"),
                        Map.entry("tax_and_fees_percentage", new BigDecimal("12.00")),
                        Map.entry("available_rooms", 15),
                        Map.entry("attributes",
                                "{\"stars\":4,\"rating\":1,\"review_count\":99,\"amenities\":[\"wifi\"]}"))));

        Map<String, Object> response = controller.publicInventory("hotel", null);
        Map<?, ?> listing = (Map<?, ?>) ((List<?>) response.get("items")).getFirst();

        assertEquals("partner-42", listing.get("id"));
        assertEquals(42L, listing.get("partner_listing_id"));
        assertEquals("Example Hotel", listing.get("partner_name"));
        assertEquals(new BigDecimal("84.50"), listing.get("price_per_night"));
        assertEquals("https://example.com/hotel.jpg", listing.get("image_url"));
        assertEquals(4, listing.get("stars"));
        assertEquals(4.9,
                ((Number) listing.get("google_rating")).doubleValue(), 0.000001);
        assertEquals(8240, listing.get("google_review_count"));
        assertEquals(4.9, listing.get("rating"));
        assertEquals(8240, listing.get("review_count"));
        assertEquals("City Center, Tripoli", listing.get("location_name"));
        assertEquals(List.of("Gym", "Wi-Fi"), listing.get("amenities"));
        assertEquals(new BigDecimal("12.00"), listing.get("tax_and_fees_percentage"));
        assertEquals(15, listing.get("available_rooms"));
    }

    @Test
    void publicHotelInventoryProvidesSafeRatingAndAvailabilityDefaults() {
        when(jdbc.queryForList(contains("FROM partner_listings l"), eq("hotel")))
                .thenReturn(List.of(Map.ofEntries(
                        Map.entry("id", 43L),
                        Map.entry("type", "hotel"),
                        Map.entry("title", "New Hotel"),
                        Map.entry("city", "Tripoli"),
                        Map.entry("country", "Libya"),
                        Map.entry("partner_name", "Example Hotel"),
                        Map.entry("description", ""),
                        Map.entry("image_url", ""),
                        Map.entry("price", BigDecimal.TEN),
                        Map.entry("attributes", "{}"))));

        Map<String, Object> response = controller.publicInventory("hotel", null);
        Map<?, ?> listing = (Map<?, ?>) ((List<?>) response.get("items")).getFirst();

        assertEquals(0.0, listing.get("google_rating"));
        assertEquals(0, listing.get("google_review_count"));
        assertEquals(0.0, listing.get("rating"));
        assertEquals(0, listing.get("review_count"));
        assertEquals(0, listing.get("available_rooms"));
    }

    @Test
    void hotelLocationAcceptsGoogleMapCoordinatesAndDiscardsPartnerRating() {
        Map<String, Object> attributes = new LinkedHashMap<>(Map.of(
                "location_input", "https://maps.google.com/?q=32.8872%2C13.1913",
                "rating", 5,
                "review_count", 400));

        PartnerController.normalizeHotelLocation(attributes);

        assertEquals(32.8872, (Double) attributes.get("latitude"), 0.000001);
        assertEquals(13.1913, (Double) attributes.get("longitude"), 0.000001);
        org.junit.jupiter.api.Assertions.assertFalse(attributes.containsKey("rating"));
        org.junit.jupiter.api.Assertions.assertFalse(attributes.containsKey("review_count"));
    }

    @Test
    void hotelListingNormalizesCanonicalFieldsAndRejectsManualGoogleRating() {
        Map<String, Object> attributes = new LinkedHashMap<>(Map.ofEntries(
                Map.entry("google_maps_url", "ChIJN1t_tDeuEmsRUsoyG83frY4"),
                Map.entry("amenities", List.of("Gym", "Wi-Fi")),
                Map.entry("tax_and_fees_percentage", 12),
                Map.entry("google_rating", 1.0),
                Map.entry("google_review_count", 1)));

        PartnerController.normalizeHotelListing(
                Map.of("title", "Grand Horizon Hotel"),
                attributes,
                "Misrata",
                "Grand Horizon Hotel");
        PartnerController.normalizeHotelLocation(attributes);

        assertEquals("Grand Horizon Hotel", attributes.get("name"));
        assertEquals("Misrata", attributes.get("location_name"));
        assertEquals("ChIJN1t_tDeuEmsRUsoyG83frY4", attributes.get("place_id"));
        assertEquals(List.of("Gym", "Wi-Fi"), attributes.get("amenities"));
        assertEquals(new BigDecimal("12"), attributes.get("tax_and_fees_percentage"));
        org.junit.jupiter.api.Assertions.assertFalse(attributes.containsKey("google_rating"));
        org.junit.jupiter.api.Assertions.assertFalse(attributes.containsKey("google_review_count"));
    }

    @Test
    void hotelLocationAcceptsGooglePlaceIdWhenCoordinatesAreUnavailable() {
        Map<String, Object> attributes = new LinkedHashMap<>(Map.of(
                "location_input", "ChIJN1t_tDeuEmsRUsoyG83frY4",
                "latitude", 32.8,
                "longitude", 13.2,
                "google_place_id", "old-place-id"));

        PartnerController.normalizeHotelLocation(attributes);

        assertEquals("ChIJN1t_tDeuEmsRUsoyG83frY4",
                attributes.get("google_place_id"));
        assertEquals(false, attributes.containsKey("latitude"));
        assertEquals(false, attributes.containsKey("longitude"));
    }

    @Test
    void hotelLocationAcceptsGoogleMapsShortLink() {
        String link = "https://maps.app.goo.gl/wssdTSk54ERQ3xfn6";
        Map<String, Object> attributes = new LinkedHashMap<>(
                Map.of(
                        "location_input", link,
                        "latitude", 32.8872,
                        "longitude", 13.1913));

        PartnerController.normalizeHotelLocation(attributes);

        assertEquals(link, attributes.get("location_input"));
        assertEquals(32.8872, (Double) attributes.get("latitude"), 0.000001);
        assertEquals(13.1913, (Double) attributes.get("longitude"), 0.000001);
    }

    @Test
    void hotelLocationAcceptsPlusCodeWithCity() {
        String plusCode = "93FP+88V, Misrata";
        Map<String, Object> attributes = new LinkedHashMap<>(
                Map.of("location_input", plusCode));

        PartnerController.normalizeHotelLocation(attributes);

        assertEquals(plusCode, attributes.get("location_input"));
        assertEquals(false, attributes.containsKey("latitude"));
        assertEquals(false, attributes.containsKey("longitude"));
    }

    @Test
    void partnerDashboardLoadsSeededHotelFieldsForTheAuthenticatedPartner() {
        when(jdbc.queryForMap(contains("FROM users u JOIN partners p"), eq(7L)))
                .thenReturn(Map.of(
                        "partner_id", 3L,
                        "name", "Al-Masa Hotel",
                        "service_type", "hotel",
                        "slug", "al-masa-hotel"));
        when(jdbc.queryForList(contains("WHERE partner_id = ?"), eq(3L)))
                .thenReturn(List.of(Map.ofEntries(
                        Map.entry("id", 44L),
                        Map.entry("type", "hotel"),
                        Map.entry("title", "Al-Masa Hotel"),
                        Map.entry("city", "Tripoli"),
                        Map.entry("country", "Libya"),
                        Map.entry("description", "Demo hotel inventory"),
                        Map.entry("image_url", "https://example.com/hotel.jpg"),
                        Map.entry("price", new BigDecimal("120.00")),
                        Map.entry("active", true),
                        Map.entry("attributes", """
                                {"location_input":"32.8872,13.1913",
                                 "latitude":32.8872,"longitude":13.1913,
                                 "room_types":[{"name":"Standard Room",
                                   "price_per_night":120,"rooms_available":12}],
                                 "availability_schedule":[{"available":true}],
                                 "gallery_images":["https://example.com/room.jpg"]}
                                """),
                        Map.entry("aggregated_rating", new BigDecimal("4.5")),
                        Map.entry("aggregated_review_count", 8))));

        Map<String, Object> response = controller.listings(authenticatedRequest());
        Map<?, ?> listing = (Map<?, ?>) ((List<?>) response.get("listings")).getFirst();
        Map<?, ?> attributes = (Map<?, ?>) listing.get("attributes");

        assertEquals(44L, listing.get("id"));
        assertEquals("Al-Masa Hotel", listing.get("title"));
        assertEquals(true, listing.get("active"));
        assertEquals("https://example.com/hotel.jpg", listing.get("image_url"));
        assertEquals(32.8872, attributes.get("latitude"));
        assertEquals(120, ((Map<?, ?>) ((List<?>) attributes.get("room_types"))
                .getFirst()).get("price_per_night"));
        assertEquals(true, ((Map<?, ?>) ((List<?>) attributes
                .get("availability_schedule")).getFirst()).get("available"));
        assertEquals(List.of("https://example.com/room.jpg"),
                attributes.get("gallery_images"));
    }

    @Test
    void hotelLocationRejectsUnrecognizedUrl() {
        Map<String, Object> attributes = new LinkedHashMap<>(
                Map.of("location_input", "https://example.com/location"));

        assertThrows(ResponseStatusException.class,
                () -> PartnerController.normalizeHotelLocation(attributes));
    }

    @Test
    void nearbyHotelsParsesLocationInputAndCalculatesDistanceWithinRadius() {
        when(jdbc.queryForList(contains("WHERE l.type = 'hotel' AND l.active = TRUE")))
                .thenReturn(List.of(Map.ofEntries(
                        Map.entry("id", 42L),
                        Map.entry("type", "hotel"),
                        Map.entry("title", "Nearby Hotel"),
                        Map.entry("city", "Tripoli"),
                        Map.entry("country", "Libya"),
                        Map.entry("partner_name", "Example Hotel"),
                        Map.entry("partner_slug", "example-hotel"),
                        Map.entry("description", "A nearby stay"),
                        Map.entry("image_url", "https://example.com/hotel.jpg"),
                        Map.entry("price", new BigDecimal("84.50")),
                        Map.entry("aggregated_rating", new BigDecimal("4.50")),
                        Map.entry("aggregated_review_count", 2),
                        Map.entry("google_rating", new BigDecimal("4.8")),
                        Map.entry("google_review_count", 42),
                        Map.entry("attributes",
                                "{\"location_input\":\"32.81,13.2\",\"stars\":4}"))));

        Map<String, Object> response = controller.nearbyHotels(32.8, 13.2, null, 50_000);
        Map<?, ?> hotel = (Map<?, ?>) ((List<?>) response.get("hotels")).getFirst();

        double distance = ((Number) hotel.get("distance_meters")).doubleValue();
        org.junit.jupiter.api.Assertions.assertTrue(distance > 1_000 && distance < 1_200);
        assertEquals(32.81, ((Number) hotel.get("latitude")).doubleValue(), 0.000001);
        assertEquals(13.2, ((Number) hotel.get("longitude")).doubleValue(), 0.000001);
        assertEquals(4.8, hotel.get("rating"));
        assertEquals(4.5, hotel.get("user_rating"));
    }

    @Test
    void nearbyHotelsExcludesAndWarnsForListingsWithoutCoordinates() {
        when(jdbc.queryForList(contains("WHERE l.type = 'hotel' AND l.active = TRUE")))
                .thenReturn(List.of(Map.ofEntries(
                        Map.entry("id", 43L),
                        Map.entry("type", "hotel"),
                        Map.entry("title", "Unlocated Hotel"),
                        Map.entry("city", "Tripoli"),
                        Map.entry("country", "Libya"),
                        Map.entry("partner_name", "Example Hotel"),
                        Map.entry("partner_slug", "example-hotel"),
                        Map.entry("description", ""),
                        Map.entry("image_url", ""),
                        Map.entry("price", new BigDecimal("80.00")),
                        Map.entry("aggregated_rating", 0),
                        Map.entry("aggregated_review_count", 0),
                        Map.entry("attributes", "{}"))));

        Map<String, Object> response = controller.nearbyHotels(32.8, 13.2, null, 50_000);

        assertEquals(List.of(), response.get("hotels"));
    }

    @Test
    void nearbyHotelsRejectsInvalidCoordinatesBeforeQueryingDatabase() {
        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.nearbyHotels(91.0, 13.2, null, 5000));

        assertEquals(400, error.getStatusCode().value());
        org.mockito.Mockito.verifyNoInteractions(jdbc);
    }

    @Test
    void nearbyHotelsRejectsMissingLatitudeOrLongitudeBeforeQueryingDatabase() {
        ResponseStatusException missingLatitude = assertThrows(
                ResponseStatusException.class,
                () -> controller.nearbyHotels(null, 13.2, null, 5000));
        ResponseStatusException missingLongitude = assertThrows(
                ResponseStatusException.class,
                () -> controller.nearbyHotels(32.8, null, null, 5000));

        assertEquals(400, missingLatitude.getStatusCode().value());
        assertEquals(400, missingLongitude.getStatusCode().value());
        org.mockito.Mockito.verifyNoInteractions(jdbc);
    }

    @Test
    void publicActiveFlightInventoryExposesSearchableRouteWithoutImages() {
        when(jdbc.queryForList(contains("FROM partner_listings l"), eq("flight")))
                .thenReturn(List.of(Map.ofEntries(
                        Map.entry("id", 25L),
                        Map.entry("type", "flight"),
                        Map.entry("title", "Misrata to Tripoli"),
                        Map.entry("city", "Misrata"),
                        Map.entry("country", "Libya"),
                        Map.entry("partner_name", "Libyan Wings"),
                        Map.entry("partner_slug", "libyan-wings"),
                        Map.entry("description", "Partner flight"),
                        Map.entry("image_url", "https://example.com/should-not-be-used.png"),
                        Map.entry("active", true),
                        Map.entry("price", new BigDecimal("175.00")),
                        Map.entry("attributes", """
                                {"origin_city":"Misrata","origin_code":"MRA",
                                 "destination_city":"Tripoli","destination_code":"MJI",
                                 "flight_number":"MANUAL-204","departure_time":"2026-11-10T08:00:00",
                                 "arrival_time":"2026-11-10T10:00:00","duration_minutes":120,
                                 "seats_available":80}
                                """))));

        Map<String, Object> response = controller.publicInventory("flight", null);
        Map<?, ?> listing = (Map<?, ?>) ((List<?>) response.get("items")).getFirst();

        assertEquals("Misrata", listing.get("origin_city"));
        assertEquals("MRA", listing.get("origin_code"));
        assertEquals("Tripoli", listing.get("destination_city"));
        assertEquals("MJI", listing.get("destination_code"));
        assertEquals("", listing.get("description"));
        assertEquals("YL-25", listing.get("flight_number"));
        assertEquals("YL", listing.get("airline_code"));
        assertEquals("FL-YL-000025", listing.get("listing_code"));
        assertEquals("2026-11-10T08:00:00", listing.get("departure_time"));
        assertEquals("published", listing.get("status"));
        assertEquals(true, listing.get("is_active"));
        assertEquals(null, listing.get("image_url"));
        assertEquals(null, listing.get("airline_logo_url"));
        verify(jdbc).queryForList(
                contains("WHERE l.type = ? AND l.active = TRUE"),
                eq("flight"));
    }

    @Test
    void airportSearchPreservesExactIataQuery() {
        Map<String, Object> expected = Map.of(
                "query_type", "airport_code",
                "airports", List.of(Map.of("code", "MRA")));
        when(airportDirectoryService.search("MRA")).thenReturn(expected);

        assertEquals(expected, controller.searchAirports("MRA"));
        verify(airportDirectoryService).search("MRA");
    }

    @Test
    void flightSearchFiltersPartnerInventoryByRouteDateAndCapacity() {
        when(jdbc.queryForList(contains("WHERE l.type = 'flight'")))
                .thenReturn(List.of(
                        partnerFlight(25L, "MRA", "MJI",
                                "2026-11-10T08:00:00", 3),
                        partnerFlight(26L, "MRA", "MJI",
                                "2026-11-10T09:00:00", 1),
                        partnerFlight(27L, "MRA", "BEN",
                                "2026-11-10T08:00:00", 10),
                        partnerFlight(28L, "MRA", "MJI",
                                "2026-11-11T08:00:00", 10)));

        Map<String, Object> response = controller.searchFlights(
                "mra", "mji", "2026-11-10", null, 2, "economy");

        List<?> flights = (List<?>) response.get("flights");
        assertEquals(1, flights.size());
        assertEquals("MRA", ((Map<?, ?>) flights.getFirst()).get("origin_code"));
        assertEquals("MJI", ((Map<?, ?>) flights.getFirst()).get("destination_code"));
    }

    @Test
    void flexibleFlightSearchIncludesPartnerFlightsFromEachSelectedMonth() {
        java.time.LocalDate firstDate = java.time.LocalDate.now().plusDays(2);
        java.time.YearMonth firstMonth = java.time.YearMonth.from(firstDate);
        java.time.YearMonth secondMonth = firstMonth.plusMonths(1);
        java.time.YearMonth thirdMonth = firstMonth.plusMonths(2);
        java.time.LocalDate secondDate = secondMonth.atDay(5);
        java.time.LocalDate thirdDate = thirdMonth.atDay(7);
        String selectedMonths = String.join(
                ",", firstMonth.toString(), secondMonth.toString(), thirdMonth.toString());
        when(jdbc.queryForList(contains("WHERE l.type = 'flight'")))
                .thenReturn(List.of(
                        partnerFlight(31L, "MRA", "MJI",
                                firstDate + "T08:00:00", 3),
                        partnerFlight(32L, "MRA", "MJI",
                                secondDate + "T09:00:00", 3),
                        partnerFlight(33L, "MRA", "MJI",
                                thirdDate + "T10:00:00", 3),
                        partnerFlight(34L, "MRA", "BEN",
                                firstDate + "T11:00:00", 3)));

        Map<String, Object> response = controller.searchFlexibleFlights(
                "mra", "mji", selectedMonths, "round_trip", 7, 1, "economy", false);

        List<?> flights = (List<?>) response.get("flights");
        assertEquals(3, flights.size());
        assertEquals(List.of(
                firstMonth.toString(), secondMonth.toString(), thirdMonth.toString()),
                response.get("months"));
        assertEquals("partner-31", ((Map<?, ?>) flights.getFirst()).get("id"));
        assertEquals("partner-33", ((Map<?, ?>) flights.getLast()).get("id"));
    }

    @Test
    void flexibleFlightSearchRejectsMoreThanThreeMonthsBeforeQueryingDatabase() {
        String months = java.time.YearMonth.now() + ","
                + java.time.YearMonth.now().plusMonths(1) + ","
                + java.time.YearMonth.now().plusMonths(2) + ","
                + java.time.YearMonth.now().plusMonths(3);

        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.searchFlexibleFlights(
                        "MRA", "MJI", months, "one_way", 7, 1, "economy", false));

        assertEquals(400, error.getStatusCode().value());
        verify(jdbc, never()).queryForList(
                org.mockito.ArgumentMatchers.anyString());
    }

    @Test
    void flexibleWeekendSearchOnlyIncludesFridayDepartures() {
        java.time.LocalDate friday = java.time.LocalDate.now().with(
                java.time.temporal.TemporalAdjusters.next(java.time.DayOfWeek.FRIDAY));
        java.time.LocalDate saturday = friday.plusDays(1);
        String months = java.util.stream.Stream.of(friday, saturday)
                .map(java.time.YearMonth::from)
                .distinct()
                .map(java.time.YearMonth::toString)
                .collect(java.util.stream.Collectors.joining(","));
        when(jdbc.queryForList(contains("WHERE l.type = 'flight'")))
                .thenReturn(List.of(
                        partnerFlight(41L, "MRA", "MJI", friday + "T08:00:00", 3),
                        partnerFlight(42L, "MRA", "MJI", saturday + "T08:00:00", 3)));

        Map<String, Object> response = controller.searchFlexibleFlights(
                "MRA", "MJI", months, "round_trip", 2, 1, "economy", true);

        List<?> flights = (List<?>) response.get("flights");
        assertEquals(1, flights.size());
        assertEquals("partner-41", ((Map<?, ?>) flights.getFirst()).get("id"));
    }

    @Test
    void flightSearchKeepsPartnerResultsWhenDuffelIsUnavailable() {
        when(jdbc.queryForList(contains("WHERE l.type = 'flight'")))
                .thenReturn(List.of(partnerFlight(
                        25L, "MRA", "MJI", "2026-11-10T08:00:00", 3)));
        when(duffelFlightService.isConfigured()).thenReturn(true);
        when(duffelFlightService.searchFlights(
                eq("MRA"),
                eq("MJI"),
                eq(java.time.LocalDate.parse("2026-11-10")),
                isNull(),
                eq(2),
                eq("economy")))
                .thenThrow(new ResponseStatusException(
                        org.springframework.http.HttpStatus.BAD_GATEWAY,
                        "provider unavailable"));

        Map<String, Object> response = controller.searchFlights(
                "MRA", "MJI", "2026-11-10", null, 2, "economy");

        List<?> flights = (List<?>) response.get("flights");
        assertEquals(1, flights.size());
        assertEquals("partner-25", ((Map<?, ?>) flights.getFirst()).get("id"));
    }

    @Test
    void hotelSearchUsesLiteApiAndPreservesProviderOffers() {
        when(jdbc.queryForList(contains("WHERE l.type = 'hotel'")))
                .thenReturn(List.of());
        Map<String, Object> liteApiHotel = Map.of(
                "id", "liteapi-lp123",
                "source", "liteapi",
                "name", "LiteAPI Data Hotel",
                "price", new BigDecimal("125.00"),
                "price_currency", "USD",
                "availability_known", true,
                "available_rooms", 2,
                "offers", List.of(Map.of(
                        "room_name", "Double",
                        "price_per_night", new BigDecimal("125.00"),
                        "stay_total", new BigDecimal("250.00"),
                        "currency", "USD")));
        when(liteApiHotelService.searchHotels(
                "London",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2,
                "USD",
                null,
                null,
                ""))
                .thenReturn(UnifiedInventoryService.SourceOutcome.of(
                        List.of(liteApiHotel)));

        Map<String, Object> response = controller.searchHotels(
                "London",
                "2026-12-01",
                "2026-12-03",
                1,
                2,
                "USD",
                null,
                null,
                null,
                null,
                null,
                null);

        List<?> hotels = (List<?>) response.get("hotels");
        assertEquals(1, hotels.size());
        assertEquals(Map.of(
                "partner", 0L, "liteapi", 1L),
                response.get("sources"));
        assertEquals(List.of(), response.get("warnings"));
        verify(liteApiHotelService).searchHotels(
                "London",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2,
                "USD",
                null,
                null,
                "");
    }

    @Test
    void liteApiAccessFailureKeepsPartnerHotelsVisible() {
        Map<String, Object> partnerHotel = new LinkedHashMap<>(Map.ofEntries(
                Map.entry("id", 17L),
                Map.entry("title", "Partner London Hotel"),
                Map.entry("city", "London"),
                Map.entry("country", "United Kingdom"),
                Map.entry("partner_name", "Local Partner"),
                Map.entry("description", "Partner inventory"),
                Map.entry("image_url", "https://example.test/hotel.jpg"),
                Map.entry("price", new BigDecimal("88.00")),
                Map.entry("attributes", "{}"),
                Map.entry("location_name", "Central London"),
                Map.entry("google_maps_url", ""),
                Map.entry("place_id", ""),
                Map.entry("google_rating", BigDecimal.ZERO),
                Map.entry("google_review_count", 0),
                Map.entry("amenities", List.of("Wi-Fi")),
                Map.entry("tax_and_fees_percentage", BigDecimal.ZERO),
                Map.entry("available_rooms", 3),
                Map.entry("aggregated_rating", BigDecimal.ZERO),
                Map.entry("aggregated_review_count", 0)));
        when(jdbc.queryForList(
                contains("WHERE l.type = 'hotel'"),
                any(Object[].class)))
                .thenReturn(List.of(partnerHotel));
        when(liteApiHotelService.searchHotels(
                eq("London"),
                eq(LocalDate.parse("2026-12-01")),
                eq(LocalDate.parse("2026-12-03")),
                eq(1),
                eq(2),
                eq("USD"),
                isNull(),
                isNull(),
                eq("")))
                .thenReturn(new UnifiedInventoryService.SourceOutcome(
                        List.of(),
                        List.of("LiteAPI access was denied.")));

        Map<String, Object> response = controller.searchHotels(
                "London",
                "2026-12-01",
                "2026-12-03",
                1,
                2,
                "USD",
                null,
                null,
                null,
                null,
                null,
                null);

        List<?> hotels = (List<?>) response.get("hotels");
        assertEquals(1, hotels.size());
        assertEquals("partner", ((Map<?, ?>) hotels.getFirst()).get("source"));
        assertEquals(Map.of("partner", 1L, "liteapi", 0L), response.get("sources"));
        assertEquals(List.of("LiteAPI access was denied."), response.get("warnings"));
    }

    @Test
    void hotelSearchRejectsCurrencyOutsideTheSupportedDisplaySet() {
        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.searchHotels(
                        "London",
                        null,
                        null,
                        1,
                        2,
                        "LYD",
                        null,
                        null,
                        null,
                        null,
                        null,
                        null));

        assertEquals(400, error.getStatusCode().value());
        verify(jdbc, never()).queryForList(org.mockito.ArgumentMatchers.anyString());
    }

    @Test
    void hotelSearchValidatesFiltersBeforeCallingInventorySources() {
        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.searchHotels(
                        "London",
                        null,
                        null,
                        1,
                        2,
                        "USD",
                        new BigDecimal("200"),
                        new BigDecimal("100"),
                        null,
                        null,
                        null,
                        null));

        assertEquals(400, error.getStatusCode().value());
        verify(jdbc, never()).queryForList(org.mockito.ArgumentMatchers.anyString());
    }

    @Test
    void flightSearchRejectsInvalidPassengerCountBeforeDatabaseQuery() {
        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.searchFlights(
                        "MRA", "MJI", "2026-11-10", null, 0, "economy"));

        assertEquals(400, error.getStatusCode().value());
        verify(jdbc, never()).queryForList(
                org.mockito.ArgumentMatchers.anyString());
    }

    private static Map<String, Object> partnerFlight(
            long id, String origin, String destination, String departure, int seats) {
        return Map.ofEntries(
                Map.entry("id", id),
                Map.entry("type", "flight"),
                Map.entry("title", origin + " to " + destination),
                Map.entry("city", "Misrata"),
                Map.entry("country", "Libya"),
                Map.entry("partner_name", "Libyan Wings"),
                Map.entry("partner_slug", "libyan-wings"),
                Map.entry("price", new BigDecimal("175.00")),
                Map.entry("attributes", """
                        {"origin_city":"Misrata","origin_code":"%s",
                         "destination_city":"Tripoli","destination_code":"%s",
                         "departure_time":"%s","arrival_time":"%s",
                         "duration_minutes":120,"seats_available":%d}
                        """.formatted(origin, destination, departure, departure, seats)));
    }

    @Test
    void publicInventoryMapsCustomerContractsForCarsTransfersAndPackages() {
        assertPublicListing("car", Map.of(
                "category", "suv",
                "seats", 5,
                "transmission", "automatic",
                "fuel_type", "hybrid",
                "features", List.of("GPS"),
                "has_ac", true,
                "has_gps", true),
                Map.of(
                        "category", "suv",
                        "price_per_day", new BigDecimal("48.00"),
                        "has_gps", true));
        assertPublicListing("transfer", Map.of(
                "vehicle_type", "minivan",
                "max_passengers", 6,
                "max_luggage", 4,
                "pickup_location", "Tripoli",
                "dropoff_location", "Misrata",
                "pickup_time", "2026-11-10T09:00:00",
                "duration_minutes", 180,
                "included_services", List.of("Wi-Fi")),
                Map.of(
                        "vehicle_type", "minivan",
                        "max_passengers", 6,
                        "pickup_location", "Tripoli",
                        "dropoff_location", "Misrata",
                        "pickup_time", "2026-11-10T09:00:00",
                        "duration_minutes", 180));
        assertPublicListing("package", Map.of(
                "duration_nights", 3,
                "category", "city",
                "highlights", List.of("Old town")),
                Map.of(
                        "location", "Tripoli",
                        "flight_price_per_person", new BigDecimal("48.00"),
                        "duration_nights", 3));
    }

    @Test
    void attractionsAreNotPartnerInventory() {
        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> controller.publicInventory("attraction", null));

        assertEquals(400, exception.getStatusCode().value());
    }

    @Test
    void createRejectsFlightLocationsOutsideTheSharedRegistry() {
        when(jdbc.queryForMap(contains("FROM users u JOIN partners p"), eq(7L)))
                .thenReturn(Map.of(
                        "partner_id", 3L,
                        "name", "Libyan Wings",
                        "service_type", "airline",
                        "slug", "libyan-wings"));

        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.createListing(
                        Map.of(
                                "type", "flight",
                                "title", "Unknown airport route",
                                "city", "Tripoli",
                                "country", "Libya",
                                "price", 100,
                                "attributes", Map.of(
                                        "origin_city", "Tripoli",
                                        "origin_code", "MIP",
                                        "destination_city", "Cairo",
                                        "destination_code", "CAI")),
                        authenticatedRequest()));

        assertEquals(400, error.getStatusCode().value());
    }

    @Test
    void partnerCanCreateOnlyListingsForItsConfiguredSpecialty() {
        when(jdbc.queryForMap(contains("FROM users u JOIN partners p"), eq(7L)))
                .thenReturn(Map.of(
                        "partner_id", 3L,
                        "name", "Libyan Wings",
                        "service_type", "airline",
                        "slug", "libyan-wings"));

        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.createListing(
                        Map.of(
                                "type", "hotel",
                                "title", "Not an airline product",
                                "city", "Tripoli",
                                "country", "Libya",
                                "price", 100),
                        authenticatedRequest()));

        assertEquals(403, error.getStatusCode().value());
        verify(jdbc, never()).update(org.mockito.ArgumentMatchers.any(
                org.springframework.jdbc.core.PreparedStatementCreator.class),
                org.mockito.ArgumentMatchers.any(
                        org.springframework.jdbc.support.KeyHolder.class));
    }

    private void assertPublicListing(
            String type,
            Map<String, Object> attributes,
            Map<String, Object> expected) {
        when(jdbc.queryForList(contains("FROM partner_listings l"), eq(type)))
                .thenReturn(List.of(Map.ofEntries(
                        Map.entry("id", 42L),
                        Map.entry("type", type),
                        Map.entry("title", "Partner " + type),
                        Map.entry("city", "Tripoli"),
                        Map.entry("country", "Libya"),
                        Map.entry("partner_name", "Example Provider"),
                        Map.entry("description", "Partner inventory"),
                        Map.entry("image_url", "https://example.com/item.jpg"),
                        Map.entry("price", new BigDecimal("48.00")),
                        Map.entry("attributes", attributes))));

        Map<String, Object> response = controller.publicInventory(type, null);
        Map<?, ?> listing = (Map<?, ?>) ((List<?>) response.get("items")).getFirst();
        for (Map.Entry<String, Object> field : expected.entrySet()) {
            assertEquals(field.getValue(), listing.get(field.getKey()),
                    type + " field " + field.getKey());
        }
        assertEquals(42L, listing.get("partner_listing_id"));
        assertEquals(true, listing.get("is_active"));
    }

    @Test
    void generatedListingAndFlightCodesOverrideClientValues() {
        Map<String, Object> attributes = new LinkedHashMap<>(Map.of(
                "listing_code", "PARTNER-CHOSEN",
                "flight_number", "MANUAL-123",
                "status", "paused",
                "is_active", false));

        PartnerController.applyGeneratedAttributes(
                attributes,
                "flight",
                405L,
                new PartnerController.PartnerIdentity(
                        5L, "Libyan Wings", "airline", "libyan-wings"),
                true);

        assertEquals("FL-YL-000405", attributes.get("listing_code"));
        assertEquals("YL-405", attributes.get("flight_number"));
        assertEquals("YL", attributes.get("airline_code"));
        assertEquals("published", attributes.get("status"));
        assertEquals(true, attributes.get("is_active"));
    }

    @Test
    void generatedReferencesCoverEverySupportedInventoryType() {
        var partner = new PartnerController.PartnerIdentity(
                5L, "Travel Partner", "travel", "travel-partner");
        Map<String, String> expectedPrefixes = Map.of(
                "flight", "FL-TR-000012",
                "hotel", "HTL-000012",
                "car", "CAR-000012",
                "attraction", "ACT-000012",
                "transfer", "TRF-000012",
                "package", "PKG-000012");

        expectedPrefixes.forEach((type, expected) -> {
            Map<String, Object> attributes = new LinkedHashMap<>();
            PartnerController.applyGeneratedAttributes(
                    attributes, type, 12L, partner, true);
            assertEquals(expected, attributes.get("listing_code"));
        });
    }

    @Test
    void aUserWithoutPartnerRoleIsForbiddenFromPartnerData() {
        when(jdbc.queryForMap(contains("FROM users u JOIN partners p"), eq(7L)))
                .thenThrow(new EmptyResultDataAccessException(1));

        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.listings(authenticatedRequest()));

        assertEquals(403, error.getStatusCode().value());
    }

    private static MockHttpServletRequest authenticatedRequest() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute("authUserId", 7L);
        return request;
    }
}

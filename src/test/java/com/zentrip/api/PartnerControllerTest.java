package com.zentrip.api;

import java.math.BigDecimal;
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
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PartnerControllerTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final ProfilePhotoStorage imageStorage = mock(ProfilePhotoStorage.class);
    private final PartnerController controller = new PartnerController(
            jdbc, imageStorage, mock(GooglePlacesRatingSync.class));

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

        assertEquals(404, error.getStatusCode().value());
        verify(jdbc, never()).update(contains("UPDATE partner_listings SET"));
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

        Map<String, Object> response = controller.nearbyHotels(32.8, 13.2, 50_000);
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

        Map<String, Object> response = controller.nearbyHotels(32.8, 13.2, 50_000);

        assertEquals(List.of(), response.get("hotels"));
    }

    @Test
    void nearbyHotelsRejectsInvalidCoordinatesBeforeQueryingDatabase() {
        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> controller.nearbyHotels(91, 13.2, 5000));

        assertEquals(400, error.getStatusCode().value());
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
    void airportSearchReturnsTheDatabaseDirectoryMatches() {
        when(jdbc.queryForList(
                contains("FROM airports"),
                eq("mra"),
                eq("%mra%"),
                eq("%mra%"),
                eq("%mra%"),
                eq("%mra%"),
                eq("%mra%")))
                .thenReturn(List.of(Map.of(
                        "code", "MRA",
                        "city", "Misrata",
                        "airport_name", "Misrata International Airport",
                        "country", "Libya",
                        "region", "Central Libya")));

        Map<String, Object> response = controller.searchAirports("MRA");

        assertEquals("MRA", ((List<Map<?, ?>>) response.get("airports"))
                .getFirst().get("code"));
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
    void publicInventoryMapsCustomerContractsForCarsAttractionsTransfersAndPackages() {
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
        assertPublicListing("attraction", Map.of(
                "category", "museum",
                "opening_hours", "09:00-17:00",
                "latitude", 32.9,
                "longitude", 13.2,
                "tags", List.of("history")),
                Map.of(
                        "category", "museum",
                        "entry_fee", new BigDecimal("48.00"),
                        "opening_hours", "09:00-17:00"));
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

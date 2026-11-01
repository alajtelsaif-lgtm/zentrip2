package com.zentrip.api;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class DuffelStayServiceTest {
    private static final String SEARCH_URL = "https://api.duffel.com/stays/search";
    private static final String RATES_URL =
            "https://api.duffel.com/stays/search_results/srr-test-result/actions/fetch_all_rates";
    private static final String STAY_RESPONSE = """
            {
              "data": {
                "results": [{
                  "id": "srr-test-result",
                  "cheapest_rate_total_amount": "400.00",
                  "cheapest_rate_currency": "GBP",
                  "accommodation": {
                    "id": "acc-test-hotel",
                    "name": "Example London Hotel",
                    "description": "A central hotel.",
                    "rating": 4,
                    "review_score": 8.8,
                    "review_count": 336,
                    "location": {
                      "geographic_coordinates": {
                        "latitude": 51.5071,
                        "longitude": -0.1416
                      },
                      "address": {
                        "line_one": "100 Clifton Street",
                        "city_name": "London",
                        "country_code": "GB"
                      }
                    },
                    "photos": [{"url": "https://example.com/hotel.jpg"}],
                    "amenities": [{"type": "wifi", "description": "Wi-Fi"}]
                  }
                }]
              }
            }
            """;
    private static final String RATES_RESPONSE = """
            {
              "data": {
                "id": "srr-test-result",
                "expires_at": "2026-12-01T09:00:00Z",
                "check_in_date": "2026-12-01",
                "check_out_date": "2026-12-03",
                "rooms": 2,
                "accommodation": {
                  "rooms": [{
                    "name": "Double room",
                    "beds": [{"type": "double", "count": 1}],
                    "photos": [{"url": "https://example.com/room.jpg"}],
                    "rates": [
                      {
                        "id": "rate-breakfast",
                        "name": "Breakfast included",
                        "total_amount": "400.00",
                        "total_currency": "GBP",
                        "quantity_available": 2,
                        "payment_type": "pay_now",
                        "board_type": "breakfast",
                        "cancellation_timeline": [{
                          "before": "2026-11-30T12:00:00Z",
                          "refund_amount": "400.00",
                          "refund_currency": "GBP"
                        }],
                        "benefits": [{"type": "breakfast"}]
                      },
                      {
                        "id": "rate-room-only",
                        "name": "Room only",
                        "total_amount": "360.00",
                        "total_currency": "GBP",
                        "quantity_available": 1,
                        "payment_type": "pay_now",
                        "board_type": "room_only"
                      }
                    ]
                  }]
                }
              }
            }
            """;

    @Test
    void searchesAndNormalizesDuffelStaysIntoTheSharedHotelContract() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(SEARCH_URL))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header("Authorization", "Bearer unit-test-token"))
                .andExpect(header("Duffel-Version", "v2"))
                .andExpect(jsonPath("$.data.rooms").value(1))
                .andExpect(jsonPath("$.data.guests.length()").value(2))
                .andExpect(jsonPath("$.data.check_in_date").value("2026-12-01"))
                .andExpect(jsonPath(
                        "$.data.location.geographic_coordinates.latitude").value(51.5071))
                .andRespond(withSuccess(STAY_RESPONSE, MediaType.APPLICATION_JSON));

        DuffelStayService service =
                new DuffelStayService("unit-test-token", true, builder);
        List<Map<String, Object>> hotels = service.searchHotels(
                "London",
                51.5071,
                -0.1416,
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2);

        assertEquals(1, hotels.size());
        Map<String, Object> hotel = hotels.getFirst();
        assertEquals("duffel-srr-test-result", hotel.get("id"));
        assertEquals("duffel", hotel.get("source"));
        assertEquals("acc-test-hotel", hotel.get("provider_accommodation_id"));
        assertEquals(new BigDecimal("200.000000"), hotel.get("price_per_night"));
        assertEquals("GBP", hotel.get("price_currency"));
        assertEquals(0, hotel.get("tax_and_fees_percentage"));
        assertEquals(false, hotel.get("availability_known"));
        assertEquals(List.of("Wi-Fi"), hotel.get("amenities"));
        server.verify();
    }

    @Test
    void multipleRoomsDoNotMultiplyAnAlreadyInclusiveProviderTotalAgain() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(SEARCH_URL))
                .andExpect(jsonPath("$.data.rooms").value(2))
                .andRespond(withSuccess(STAY_RESPONSE, MediaType.APPLICATION_JSON));
        DuffelStayService service =
                new DuffelStayService("unit-test-token", true, builder);

        Map<String, Object> hotel = service.searchHotels(
                "London", 51.5071, -0.1416,
                LocalDate.parse("2026-12-01"), LocalDate.parse("2026-12-03"),
                2, 4).getFirst();

        BigDecimal nightlyPerRoom = (BigDecimal) hotel.get("price_per_night");
        assertEquals(0, new BigDecimal("400.00").compareTo(
                nightlyPerRoom.multiply(BigDecimal.valueOf(2 * 2))));
        server.verify();
    }

    @Test
    void providerPermissionFailureLeavesPartnerFallbackAvailable() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(SEARCH_URL))
                .andRespond(withStatus(org.springframework.http.HttpStatus.FORBIDDEN)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body("{\"errors\":[{\"message\":\"private provider detail\"}]}"));

        DuffelStayService service =
                new DuffelStayService("unit-test-token", true, builder);
        DuffelStayService.SearchOutcome outcome = service.searchHotelsWithWarnings(
                "London",
                51.5071,
                -0.1416,
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2);
        assertTrue(outcome.hotels().isEmpty());
        assertTrue(outcome.warnings().getFirst().contains("access was denied"));
        assertFalse(outcome.warnings().getFirst().contains("private provider detail"));
        server.verify();
    }

    @Test
    void disabledProviderDoesNotMakeRequestsEvenWhenTokenExists() {
        DuffelStayService service =
                new DuffelStayService("unit-test-token", false, RestClient.builder());

        assertFalse(service.isConfigured());
        assertTrue(service.searchHotels(
                "London",
                51.5071,
                -0.1416,
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2).isEmpty());
    }

    @Test
    void fetchesAndNormalizesAllRoomRatesForAnOpenedSearchResult() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(RATES_URL))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header("Authorization", "Bearer unit-test-token"))
                .andExpect(header("Duffel-Version", "v2"))
                .andRespond(withSuccess(RATES_RESPONSE, MediaType.APPLICATION_JSON));

        DuffelStayService service =
                new DuffelStayService("unit-test-token", true, builder);

        Map<String, Object> response = service.fetchAllRates("srr-test-result");
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> offers =
                (List<Map<String, Object>>) response.get("offers");
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> roomTypes =
                (List<Map<String, Object>>) response.get("room_types");

        assertEquals("srr-test-result", response.get("provider_search_result_id"));
        assertEquals(1, roomTypes.size());
        assertEquals(2, offers.size());
        assertEquals("Double room", offers.getFirst().get("room_name"));
        assertEquals("GBP", offers.getFirst().get("total_currency"));
        assertEquals(2, offers.getFirst().get("quantity_available"));
        assertEquals(0, new BigDecimal("100.00").compareTo(
                (BigDecimal) offers.getFirst().get("price_per_night")));
        assertTrue(offers.getFirst().containsKey("cancellation_timeline"));
        server.verify();
    }

    @Test
    void searchUsesFetchedRatesAsFinalPriceAndKeepsEveryRoomOffer() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(SEARCH_URL))
                .andRespond(withSuccess(STAY_RESPONSE, MediaType.APPLICATION_JSON));
        server.expect(requestTo(RATES_URL))
                .andRespond(withSuccess(RATES_RESPONSE, MediaType.APPLICATION_JSON));
        DuffelStayService service =
                new DuffelStayService("unit-test-token", true, builder);

        DuffelStayService.SearchOutcome outcome =
                service.searchHotelsWithAllRatesWithWarnings(
                        "London",
                        51.5071,
                        -0.1416,
                        LocalDate.parse("2026-12-01"),
                        LocalDate.parse("2026-12-03"),
                        1,
                        2);

        Map<String, Object> hotel = outcome.hotels().getFirst();
        assertEquals(new BigDecimal("90.000000"), hotel.get("price_per_night"));
        assertEquals("GBP", hotel.get("price_currency"));
        assertEquals(2, ((List<?>) hotel.get("offers")).size());
        assertEquals(1, ((List<?>) hotel.get("room_types")).size());
        assertTrue(outcome.warnings().isEmpty());
        server.verify();
    }

    @Test
    void rateFailureKeepsDuffelResultButDoesNotShowEstimatedSearchPrice() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(SEARCH_URL))
                .andRespond(withSuccess(STAY_RESPONSE, MediaType.APPLICATION_JSON));
        server.expect(requestTo(RATES_URL))
                .andRespond(withStatus(org.springframework.http.HttpStatus.SERVICE_UNAVAILABLE));
        DuffelStayService service =
                new DuffelStayService("unit-test-token", true, builder);

        DuffelStayService.SearchOutcome outcome =
                service.searchHotelsWithAllRatesWithWarnings(
                        "London",
                        51.5071,
                        -0.1416,
                        LocalDate.parse("2026-12-01"),
                        LocalDate.parse("2026-12-03"),
                        1,
                        2);

        Map<String, Object> hotel = outcome.hotels().getFirst();
        assertEquals(null, hotel.get("price_per_night"));
        assertTrue(((List<?>) hotel.get("offers")).isEmpty());
        assertFalse(outcome.warnings().isEmpty());
        server.verify();
    }
}

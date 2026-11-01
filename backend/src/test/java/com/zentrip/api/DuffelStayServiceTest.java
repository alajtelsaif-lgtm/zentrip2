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
        assertEquals(new BigDecimal("200.00"), hotel.get("price_per_night"));
        assertEquals("GBP", hotel.get("price_currency"));
        assertEquals(0, hotel.get("tax_and_fees_percentage"));
        assertEquals(false, hotel.get("availability_known"));
        assertEquals(List.of("Wi-Fi"), hotel.get("amenities"));
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
        assertTrue(service.searchHotels(
                "London",
                51.5071,
                -0.1416,
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2).isEmpty());
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
}

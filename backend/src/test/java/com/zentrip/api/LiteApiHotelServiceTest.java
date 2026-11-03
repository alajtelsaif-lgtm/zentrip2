package com.zentrip.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class LiteApiHotelServiceTest {
    private static final String BASE_URL = "https://liteapi.test/v3.0";
    private static final String API_KEY = "test-liteapi-key";

    @Test
    void searchesRatesAndNormalizesTheHotelWithoutChangingBookingFlow() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(BASE_URL + "/hotels/rates"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header("X-API-Key", API_KEY))
                .andExpect(content().json("""
                        {
                          "checkin":"2026-12-01",
                          "checkout":"2026-12-03",
                          "currency":"EUR",
                          "guestNationality":"LY",
                          "occupancies":[{"rooms":1,"adults":2}],
                          "cityName":"Paris"
                        }
                        """, false))
                .andRespond(withSuccess(responseBody(), MediaType.APPLICATION_JSON));

        LiteApiHotelService service = new LiteApiHotelService(
                API_KEY, BASE_URL, "LY", builder);
        UnifiedInventoryService.SourceOutcome result = service.searchHotels(
                "Paris",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2,
                "EUR",
                null,
                null);

        assertEquals(1, result.items().size());
        assertTrue(result.warnings().isEmpty());
        Map<String, Object> hotel = result.items().getFirst();
        assertEquals("liteapi-lp-123", hotel.get("id"));
        assertEquals("liteapi", hotel.get("source"));
        assertEquals("Paris Central Hotel", hotel.get("name"));
        assertEquals(new BigDecimal("210.0000"), hotel.get("price_per_night"));
        assertEquals(BigDecimal.ZERO, hotel.get("tax_and_fees_percentage"));
        assertEquals("EUR", hotel.get("price_currency_code"));
        assertEquals(1, hotel.get("available_rooms"));
        assertEquals(List.of("Free Wi-Fi", "Breakfast"),
                hotel.get("amenities"));
        Map<?, ?> offer = (Map<?, ?>) ((List<?>) hotel.get("offers")).getFirst();
        assertEquals(0, ((BigDecimal) offer.get("stay_total"))
                .compareTo(new BigDecimal("420.00")));
        assertFalse(offer.containsKey("rateKey"));
        assertFalse(hotel.containsKey("booking_ref"));
        server.verify();
    }

    @Test
    void sendsPerRoomOccupanciesAndCoordinatesForMapBasedSearches() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(BASE_URL + "/hotels/rates"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(content().json("""
                        {
                          "occupancies":[{"rooms":1,"adults":2},
                                         {"rooms":1,"adults":1}],
                          "latitude":48.8566,
                          "longitude":2.3522,
                          "radius":20000
                        }
                        """, false))
                .andRespond(withSuccess("""
                        {"data":[],"hotels":[]}
                        """, MediaType.APPLICATION_JSON));

        LiteApiHotelService service = new LiteApiHotelService(
                API_KEY, BASE_URL, "LY", builder);
        UnifiedInventoryService.SourceOutcome result = service.searchHotels(
                "Paris",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                2,
                3,
                "EUR",
                48.8566,
                2.3522);

        assertTrue(result.items().isEmpty());
        assertTrue(result.warnings().isEmpty());
        server.verify();
    }

    @Test
    void returnsAUseful403WarningWithoutLeakingTheConfiguredKey() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(BASE_URL + "/hotels/rates"))
                .andExpect(header("X-API-Key", API_KEY))
                .andRespond(withStatus(HttpStatus.FORBIDDEN)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body("""
                                {"error":{"code":"access_denied",
                                          "message":"Rates access is not enabled"}}
                                """));

        LiteApiHotelService service = new LiteApiHotelService(
                API_KEY, BASE_URL, "LY", builder);
        UnifiedInventoryService.SourceOutcome result = service.searchHotels(
                "Paris",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2,
                "EUR",
                null,
                null);

        assertTrue(result.items().isEmpty());
        assertEquals(List.of("LiteAPI access was denied for hotel rates."),
                result.warnings());
        assertFalse(result.warnings().toString().contains(API_KEY));
        server.verify();
    }

    @Test
    void explainsHowToRecoverWhenLiteApiRejectsACityOnlySearch() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(BASE_URL + "/hotels/rates"))
                .andRespond(withStatus(HttpStatus.BAD_REQUEST)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body("""
                                {"error":{"code":"4000","message":"bad request"}}
                                """));

        LiteApiHotelService service = new LiteApiHotelService(
                API_KEY, BASE_URL, "LY", builder);
        UnifiedInventoryService.SourceOutcome result = service.searchHotels(
                "London",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2,
                "GBP",
                null,
                null);

        assertTrue(result.items().isEmpty());
        assertEquals(List.of(
                "LiteAPI rejected this destination. Select a destination suggestion and retry."),
                result.warnings());
        server.verify();
    }

    private static String responseBody() {
        return """
                {
                  "data":[{
                    "hotelId":"lp-123",
                    "roomTypes":[{
                      "name":"Double Room",
                      "offerRetailRate":[{"amount":420.00,"currency":"EUR"}],
                      "rates":[{
                        "boardName":"Breakfast included",
                        "retailRate":{"total":[{"amount":420.00,"currency":"EUR"}]}
                      }]
                    }]
                  }],
                  "hotels":[{
                    "id":"lp-123",
                    "name":"Paris Central Hotel",
                    "main_photo":"https://images.example.test/paris-hotel.jpg",
                    "thumbnail":"https://images.example.test/paris-hotel-thumb.jpg",
                    "address":"10 Rue Exemple",
                    "city_name":"Paris",
                    "country_code":"FR",
                    "latitude":48.8566,
                    "longitude":2.3522,
                    "rating":4.6,
                    "stars":4,
                    "review_count":318,
                    "tags":["Free Wi-Fi","Breakfast"],
                    "story":"A centrally located hotel."
                  }]
                }
                """;
    }
}

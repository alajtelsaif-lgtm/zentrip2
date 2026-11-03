package com.zentrip.api;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.test.web.client.ExpectedCount;
import org.springframework.web.client.RestClient;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class HotelbedsHotelServiceTest {
    private static final String API_KEY = "unit-test-api-key";
    private static final String API_SECRET = "unit-test-api-secret";
    private static final long SIGNATURE_TIMESTAMP = 1_800_000_000L;
    private static final String BASE_URL = "https://hotelbeds.test";
    private static final GeoapifyAirportService.GeocodedPlace PARIS =
            new GeoapifyAirportService.GeocodedPlace(
                    "Paris, France",
                    "Paris",
                    "France",
                    "FR",
                    "",
                    "Paris, France",
                    "city",
                    "paris-test",
                    "",
                    48.8566,
                    2.3522);

    @Test
    void searchSignsRequestsAndNormalizesHotelbedsRatesAndContent() {
        GeoapifyAirportService geocoder = mock(GeoapifyAirportService.class);
        when(geocoder.resolveLocation("Paris")).thenReturn(PARIS);
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder)
                .ignoreExpectOrder(true)
                .build();
        HotelbedsHotelService service = service(geocoder, builder);

        server.expect(ExpectedCount.twice(), requestTo(BASE_URL + "/hotel-api/1.0/hotels"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header("Api-key", API_KEY))
                .andExpect(header("X-Signature", expectedSignature()))
                .andExpect(content().json("""
                        {
                          "stay": {
                            "checkIn": "2026-12-01",
                            "checkOut": "2026-12-03"
                          },
                          "occupancies": [
                            {"rooms": 1, "adults": 2, "children": 0}
                          ],
                          "geolocation": {
                            "latitude": 48.8566,
                            "longitude": 2.3522,
                            "radius": 20,
                            "unit": "km"
                          },
                          "filter": {
                            "maxHotels": 30,
                            "maxRooms": 1,
                            "maxRatesPerRoom": 5
                          },
                          "language": "ENG"
                        }
                        """))
                .andRespond(withSuccess("""
                        {
                          "hotels": {
                            "hotels": [{
                              "code": 123,
                              "name": "Central Paris Hotel",
                              "categoryCode": "4EST",
                              "latitude": 48.8566,
                              "longitude": 2.3522,
                              "rooms": [{
                                "name": "Double Room",
                                "rates": [{
                                  "rateKey": "must-not-be-returned",
                                  "rateType": "BOOKABLE",
                                  "rateClass": "NOR",
                                  "net": "420.00",
                                  "sellingRate": "420.00",
                                  "currency": "EUR",
                                  "rooms": 1,
                                  "allotment": 3,
                                  "boardName": "Breakfast"
                                }]
                              }]
                            }]
                          }
                        }
                        """, MediaType.APPLICATION_JSON));
        server.expect(request -> org.junit.jupiter.api.Assertions.assertTrue(
                        request.getURI().toString().contains(
                                BASE_URL + "/hotel-content-api/1.0/hotels?")))
                .andExpect(method(HttpMethod.GET))
                .andExpect(header("Api-key", API_KEY))
                .andExpect(header("X-Signature", expectedSignature()))
                .andRespond(withSuccess("""
                        {
                          "hotels": [{
                            "code": 123,
                            "description": {"content": "A central hotel."},
                            "address": {"content": "10 Rue de Rivoli"},
                            "city": {"content": "Paris"},
                            "country": {"description": {"content": "France"}},
                            "category": {"code": "4EST"},
                            "coordinates": {"latitude": 48.8566, "longitude": 2.3522},
                            "images": [{
                              "path": "000/1.jpg"
                            }],
                            "facilities": [{
                              "description": {"content": "Free Wi-Fi"}
                            }]
                          }]
                        }
                        """, MediaType.APPLICATION_JSON));

        UnifiedInventoryService.SourceOutcome outcome = service.searchHotels(
                "Paris",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2);

        assertEquals(List.of(), outcome.warnings());
        assertEquals(1, outcome.items().size());
        Map<String, Object> hotel = outcome.items().getFirst();
        assertEquals("hotelbeds", hotel.get("source"));
        assertEquals("123", hotel.get("provider_accommodation_id"));
        assertEquals(new BigDecimal("210.00"), hotel.get("price_per_night"));
        assertEquals("EUR", hotel.get("price_currency"));
        assertEquals(4, hotel.get("stars"));
        assertEquals("A central hotel.", hotel.get("description"));
        assertEquals("https://photos.hotelbeds.com/giata/bigger/000/1.jpg",
                hotel.get("image_url"));
        assertEquals(List.of("Free Wi-Fi"), hotel.get("amenities"));
        assertEquals(3, hotel.get("available_rooms"));
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> offers =
                (List<Map<String, Object>>) hotel.get("offers");
        assertEquals(new BigDecimal("420.00"), offers.getFirst().get("stay_total"));
        assertFalse(offers.getFirst().containsKey("rateKey"));
        assertTrue(offers.getFirst().containsKey("price_per_night"));
        UnifiedInventoryService.SourceOutcome cachedOutcome = service.searchHotels(
                "Paris",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2);
        assertEquals(1, cachedOutcome.items().size());
        server.verify();
    }

    @Test
    void forbiddenAvailabilityReturnsWarningWithoutExposingCredentials() {
        GeoapifyAirportService geocoder = mock(GeoapifyAirportService.class);
        when(geocoder.resolveLocation("Paris")).thenReturn(PARIS);
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        HotelbedsHotelService service = service(geocoder, builder);

        server.expect(requestTo(BASE_URL + "/hotel-api/1.0/hotels"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header("Api-key", API_KEY))
                .andExpect(header("X-Signature", expectedSignature()))
                .andRespond(withStatus(HttpStatus.FORBIDDEN)
                        .contentType(MediaType.APPLICATION_JSON)
                        .header("X-Request-Id", "hb-request-123")
                        .body("""
                                {"error":{"code":"ACCESS_DENIED",
                                "message":"Hotel availability is not enabled"}}
                                """));

        UnifiedInventoryService.SourceOutcome outcome = service.searchHotels(
                "Paris",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2);

        assertTrue(outcome.items().isEmpty());
        assertTrue(outcome.warnings().getFirst().contains("access was denied"));
        assertFalse(outcome.warnings().getFirst().contains(API_KEY));
        assertFalse(outcome.warnings().getFirst().contains(API_SECRET));
        server.verify();
    }

    @Test
    void unauthorizedAvailabilityExplainsCredentialOrEnvironmentMismatch() {
        GeoapifyAirportService geocoder = mock(GeoapifyAirportService.class);
        when(geocoder.resolveLocation("Paris")).thenReturn(PARIS);
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        HotelbedsHotelService service = service(geocoder, builder);

        server.expect(requestTo(BASE_URL + "/hotel-api/1.0/hotels"))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header("Api-key", API_KEY))
                .andExpect(header("X-Signature", expectedSignature()))
                .andRespond(withStatus(HttpStatus.UNAUTHORIZED)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body("""
                                {"error":{"code":"INVALID_SIGNATURE",
                                "message":"The API signature is invalid"}}
                                """));

        UnifiedInventoryService.SourceOutcome outcome = service.searchHotels(
                "Paris",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2);

        assertTrue(outcome.items().isEmpty());
        assertTrue(outcome.warnings().getFirst().contains("authentication failed"));
        assertFalse(outcome.warnings().getFirst().contains(API_KEY));
        assertFalse(outcome.warnings().getFirst().contains(API_SECRET));
        server.verify();
    }

    private static HotelbedsHotelService service(
            GeoapifyAirportService geocoder,
            RestClient.Builder builder) {
        return new HotelbedsHotelService(
                API_KEY,
                API_SECRET,
                BASE_URL,
                geocoder,
                builder,
                Clock.fixed(Instant.ofEpochSecond(SIGNATURE_TIMESTAMP), ZoneOffset.UTC));
    }

    private static String expectedSignature() {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(
                    (API_KEY + API_SECRET + SIGNATURE_TIMESTAMP)
                            .getBytes(StandardCharsets.UTF_8));
            return java.util.HexFormat.of().formatHex(digest);
        } catch (java.security.NoSuchAlgorithmException exception) {
            throw new AssertionError(exception);
        }
    }
}

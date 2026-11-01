package com.zentrip.api;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Map;

import static org.hamcrest.Matchers.containsString;
import static org.springframework.http.HttpMethod.GET;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.queryParam;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

@ExtendWith(OutputCaptureExtension.class)
class RapidApiHotelServiceTest {
    @Test
    void resolvesDestinationSearchesHotelsAndNormalizesTheStayPrice() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(containsString("/api/v1/hotels/searchDestination")))
                .andExpect(method(GET))
                .andExpect(queryParam("query", "Tripoli"))
                .andExpect(header("x-rapidapi-host", "booking-com15.p.rapidapi.com"))
                .andExpect(header("x-rapidapi-key", "test-rapidapi-key"))
                .andRespond(withSuccess(
                        """
                        {"data":[{"dest_id":"-1234","dest_type":"city","name":"Tripoli","country":"Libya"}]}
                        """,
                        MediaType.APPLICATION_JSON));
        server.expect(requestTo(containsString("/api/v1/hotels/searchHotels")))
                .andExpect(method(GET))
                .andExpect(queryParam("dest_id", "-1234"))
                .andExpect(queryParam("arrival_date", "2026-12-01"))
                .andExpect(queryParam("departure_date", "2026-12-03"))
                .andExpect(queryParam("room_qty", "1"))
                .andExpect(queryParam("adults", "2"))
                .andExpect(queryParam("currency_code", "USD"))
                .andExpect(header("x-rapidapi-host", "booking-com15.p.rapidapi.com"))
                .andExpect(header("x-rapidapi-key", "test-rapidapi-key"))
                .andRespond(withSuccess(
                        """
                        {
                          "status": true,
                          "data": {
                            "hotels": [{
                              "hotel_id": 987,
                              "hotel_name": "Tripoli Test Hotel",
                              "address": "Tripoli, Libya",
                              "city": "Tripoli",
                              "country": "Libya",
                              "photo_main_url": "https://images.example.test/hotel.jpg",
                              "review_score": 8.4,
                              "review_nr": 90,
                              "price_breakdown": {
                                "gross_price": {"value": 240, "currency": "USD"}
                              },
                              "latitude": 32.89,
                              "longitude": 13.19
                            }]
                          }
                        }
                        """,
                        MediaType.APPLICATION_JSON));

        RapidApiHotelService service =
                new RapidApiHotelService("test-rapidapi-key", true, builder);
        RapidApiHotelService.SearchOutcome outcome = service.searchHotelsWithWarnings(
                "Tripoli",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2,
                "USD");

        assertTrue(outcome.warnings().isEmpty());
        assertEquals(1, outcome.hotels().size());
        Map<String, Object> hotel = outcome.hotels().getFirst();
        assertEquals("rapidapi-987", hotel.get("id"));
        assertEquals("rapidapi", hotel.get("source"));
        assertEquals("Booking.com", hotel.get("partner_name"));
        assertEquals(new BigDecimal("120.00"), hotel.get("price_per_night"));
        assertEquals("USD", hotel.get("price_currency"));
        assertEquals("https://images.example.test/hotel.jpg", hotel.get("image_url"));
        assertEquals(false, hotel.get("availability_known"));
        server.verify();
    }

    @Test
    void providerAccessFailureLogsSafeResponseDetailsAndReturnsWarning(
            CapturedOutput output) {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(containsString("/api/v1/hotels/searchDestination")))
                .andRespond(withStatus(HttpStatus.FORBIDDEN)
                        .header("x-rapidapi-request-id", "test-request-id")
                        .contentType(MediaType.APPLICATION_JSON)
                        .body(
                                "{\"code\":\"API_SUBSCRIPTION_REQUIRED\","
                                        + "\"error\":\"not subscribed\","
                                        + "\"x-rapidapi-key\":\"test-rapidapi-key\"}"));

        RapidApiHotelService service =
                new RapidApiHotelService("test-rapidapi-key", true, builder);
        RapidApiHotelService.SearchOutcome outcome = service.searchHotelsWithWarnings(
                "Tripoli",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2,
                "USD");

        assertTrue(outcome.hotels().isEmpty());
        assertTrue(outcome.warnings().getFirst().contains("access was denied"));
        assertFalse(outcome.warnings().getFirst().contains("test-rapidapi-key"));
        assertTrue(output.getOut().contains("status=403"));
        assertTrue(output.getOut().contains("API_SUBSCRIPTION_REQUIRED"));
        assertTrue(output.getOut().contains("not subscribed"));
        assertTrue(output.getOut().contains("test-request-id"));
        assertTrue(output.getOut().contains("x-rapidapi-key=[MASKED]"));
        assertFalse(output.getOut().contains("test-rapidapi-key"));
        server.verify();
    }

    @Test
    void failedCitySearchFallsBackToDocumentedCoordinateSearch() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(containsString("/api/v1/hotels/searchDestination")))
                .andRespond(withSuccess(
                        """
                        {"data":[{"dest_id":"-1234","dest_type":"city","name":"London","country":"UK"}]}
                        """,
                        MediaType.APPLICATION_JSON));
        server.expect(requestTo(containsString("/api/v1/hotels/searchHotels?")))
                .andExpect(queryParam("dest_id", "-1234"))
                .andRespond(withSuccess(
                        "{\"status\":false,\"message\":\"\"}",
                        MediaType.APPLICATION_JSON));
        server.expect(requestTo(containsString(
                        "/api/v1/hotels/searchHotelsByCoordinates?")))
                .andExpect(queryParam("arrival_date", "2026-12-01"))
                .andExpect(queryParam("departure_date", "2026-12-03"))
                .andExpect(queryParam("latitude", "51.5072"))
                .andExpect(queryParam("longitude", "-0.1276"))
                .andExpect(queryParam("radius", "50"))
                .andExpect(queryParam("room_qty", "1"))
                .andExpect(queryParam("adults", "2"))
                .andExpect(queryParam("languagecode", "en"))
                .andRespond(withSuccess(
                        """
                        {"status":true,"data":{"hotels":[{
                          "hotel_id":456,
                          "hotel_name":"Coordinate Test Hotel",
                          "price_per_night":95,
                          "price_currency":"USD"
                        }]}}
                        """,
                        MediaType.APPLICATION_JSON));

        RapidApiHotelService service =
                new RapidApiHotelService("test-rapidapi-key", true, builder);
        RapidApiHotelService.SearchOutcome outcome = service.searchHotelsWithWarnings(
                "London",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2,
                "USD",
                51.5072,
                -0.1276);

        assertTrue(outcome.warnings().isEmpty());
        assertEquals(1, outcome.hotels().size());
        assertEquals("Coordinate Test Hotel", outcome.hotels().getFirst().get("name"));
        assertEquals("rapidapi", outcome.hotels().getFirst().get("source"));
        assertEquals(new BigDecimal("95"), outcome.hotels().getFirst().get("price_per_night"));
        server.verify();
    }

    @Test
    void missingKeySkipsNetworkCallsAndReturnsConfigurationWarning() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        RapidApiHotelService service = new RapidApiHotelService("", true, builder);

        RapidApiHotelService.SearchOutcome outcome = service.searchHotelsWithWarnings(
                "Tripoli",
                LocalDate.parse("2026-12-01"),
                LocalDate.parse("2026-12-03"),
                1,
                2,
                "USD");

        assertFalse(service.isConfigured());
        assertTrue(outcome.hotels().isEmpty());
        assertTrue(outcome.warnings().getFirst().contains("not configured"));
        server.verify();
    }
}

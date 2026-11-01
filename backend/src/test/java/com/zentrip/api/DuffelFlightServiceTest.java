package com.zentrip.api;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class DuffelFlightServiceTest {
    private static final String OFFER_REQUEST_URL =
            "https://api.duffel.com/air/offer_requests"
                    + "?return_offers=true&supplier_timeout=10000";

    @Test
    void sendsOneWayAndReturnSlicesAndNormalizesProviderOffer() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(OFFER_REQUEST_URL))
                .andExpect(method(HttpMethod.POST))
                .andExpect(header("Duffel-Version", "v2"))
                .andExpect(header("Authorization", "Bearer unit-test-token"))
                .andExpect(content().string(org.hamcrest.Matchers.allOf(
                        org.hamcrest.Matchers.containsString("\"origin\":\"MJI\""),
                        org.hamcrest.Matchers.containsString("\"destination\":\"TUN\""),
                        org.hamcrest.Matchers.containsString("\"departure_date\":\"2026-11-08\""),
                        org.hamcrest.Matchers.containsString("\"departure_date\":\"2026-11-15\""),
                        org.hamcrest.Matchers.containsString("\"cabin_class\":\"economy\""))))
                .andRespond(withSuccess("""
                        {
                          "data": {
                            "offers": [{
                              "id": "off_example",
                              "total_amount": "150.50",
                              "total_currency": "USD",
                              "available_seats": 3,
                              "owner": {"name": "Example Air", "iata_code": "EX"},
                              "slices": [{
                                "duration": "PT2H15M",
                                "segments": [{
                                  "departing_at": "2026-11-08T09:00:00",
                                  "arriving_at": "2026-11-08T11:15:00",
                                  "marketing_carrier_flight_number": "EX123",
                                  "origin": {
                                    "iata_code": "MJI",
                                    "city_name": "Misrata"
                                  },
                                  "destination": {
                                    "iata_code": "TUN",
                                    "city_name": "Tunis"
                                  }
                                }]
                              }]
                            }]
                          }
                        }
                        """, MediaType.APPLICATION_JSON));

        DuffelFlightService service =
                new DuffelFlightService("unit-test-token", true, builder);
        List<Map<String, Object>> flights = service.searchFlights(
                "MJI",
                "TUN",
                LocalDate.parse("2026-11-08"),
                LocalDate.parse("2026-11-15"),
                2,
                "economy");

        assertEquals(1, flights.size());
        Map<String, Object> flight = flights.get(0);
        assertEquals("duffel-off_example", flight.get("id"));
        assertEquals("duffel", flight.get("source"));
        assertEquals("off_example", flight.get("duffel_offer_id"));
        assertEquals("Example Air", flight.get("airline"));
        assertEquals("EX123", flight.get("flight_number"));
        assertEquals("Misrata", flight.get("origin_city"));
        assertEquals("Tunis", flight.get("destination_city"));
        assertEquals("USD", flight.get("price_currency"));
        assertEquals(true, flight.get("price_is_total"));
        assertEquals(135, flight.get("duration_minutes"));
        assertEquals(null, flight.get("partner_listing_id"));
        server.verify();
    }

    @Test
    void doesNotCallProviderWhenAccessTokenIsMissing() {
        DuffelFlightService service = new DuffelFlightService(
                " ", true, RestClient.builder());

        assertFalse(service.isConfigured());
        assertTrue(service.searchFlights(
                "MJI", "TUN", LocalDate.now(), null, 1, "economy").isEmpty());
    }

    @Test
    void flexibleSearchCreatesOneProviderRequestPerDepartureDate() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        String response = """
                {
                  "data": {
                    "offers": [{
                      "id": "off_flexible",
                      "total_amount": "150.50",
                      "total_currency": "USD",
                      "owner": {"name": "Example Air", "iata_code": "EX"},
                      "slices": [{
                        "segments": [{
                          "departing_at": "2026-11-08T09:00:00",
                          "arriving_at": "2026-11-08T11:15:00",
                          "origin": {"iata_code": "MJI", "city_name": "Misrata"},
                          "destination": {"iata_code": "TUN", "city_name": "Tunis"}
                        }]
                      }]
                    }]
                  }
                }
                """;
        server.expect(requestTo(OFFER_REQUEST_URL))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withSuccess(response, MediaType.APPLICATION_JSON));
        server.expect(requestTo(OFFER_REQUEST_URL))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withSuccess(response, MediaType.APPLICATION_JSON));
        DuffelFlightService service =
                new DuffelFlightService("unit-test-token", true, builder);

        List<Map<String, Object>> flights = service.searchFlightsForDates(
                "MJI",
                "TUN",
                List.of(LocalDate.parse("2026-11-08"), LocalDate.parse("2026-11-09")),
                7,
                1,
                "economy");

        assertEquals(2, flights.size());
        assertEquals("duffel", flights.getFirst().get("source"));
        server.verify();
    }

    @Test
    void disabledProviderDoesNotUseConfiguredToken() {
        DuffelFlightService service = new DuffelFlightService(
                "unit-test-token", false, RestClient.builder());

        assertFalse(service.isConfigured());
        assertTrue(service.searchFlights(
                "MJI", "TUN", LocalDate.now(), null, 1, "economy").isEmpty());
    }

    @Test
    void providerErrorsAreReturnedAsSanitizedGatewayFailures() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(OFFER_REQUEST_URL))
                .andRespond(withStatus(org.springframework.http.HttpStatus.UNAUTHORIZED)
                        .contentType(MediaType.APPLICATION_JSON)
                        .body("{\"errors\":[{\"message\":\"private provider detail\"}]}"));

        DuffelFlightService service =
                new DuffelFlightService("unit-test-token", true, builder);
        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> service.searchFlights(
                        "MJI", "TUN", LocalDate.now(), null, 1, "economy"));

        assertEquals(502, error.getStatusCode().value());
        assertFalse(error.getReason().contains("private provider detail"));
        server.verify();
    }
}

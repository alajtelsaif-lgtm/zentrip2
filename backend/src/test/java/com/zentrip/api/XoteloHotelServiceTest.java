package com.zentrip.api;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.math.BigDecimal;

import static org.hamcrest.Matchers.containsString;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.queryParam;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class XoteloHotelServiceTest {
    @Test
    void readsPublicXoteloHotelDataWithoutChangingItsNonBookingStatus() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(containsString("/api/list?")))
                .andExpect(queryParam("location_key", "g297930"))
                .andExpect(queryParam("limit", "20"))
                .andRespond(withSuccess(
                        """
                        {"error":null,"result":{"list":[{
                          "name":"Example Phuket Hotel",
                          "key":"g297930-d123",
                          "url":"https://www.tripadvisor.com/Hotel_Review-example",
                          "review_summary":{"rating":4.8,"count":150},
                          "price_ranges":{"minimum":71,"maximum":250},
                          "geo":{"latitude":7.89,"longitude":98.29},
                          "image":"https://images.example.test/hotel.jpg"
                        }]}}
                        """,
                        MediaType.APPLICATION_JSON));

        XoteloHotelService service =
                new XoteloHotelService("{\"Phuket\":\"g297930\"}", builder);
        XoteloHotelService.SearchOutcome outcome = service.searchHotels("Phuket");

        assertTrue(outcome.warnings().isEmpty());
        assertEquals(1, outcome.hotels().size());
        var hotel = outcome.hotels().getFirst();
        assertEquals("xotelo", hotel.get("source"));
        assertEquals("Example Phuket Hotel", hotel.get("name"));
        assertEquals("g297930-d123", hotel.get("provider_accommodation_id"));
        assertEquals(new BigDecimal("71.0"), hotel.get("price_per_night"));
        assertEquals(new BigDecimal("4.8"), hotel.get("review_score"));
        assertEquals(false, hotel.get("availability_known"));
        assertTrue(hotel.containsKey("tripadvisor_url"));
        assertFalse(hotel.containsKey("partner_id"));
        server.verify();
    }

    @Test
    void skipsUnmappedCitiesWithoutCallingXotelo() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        XoteloHotelService service = new XoteloHotelService("{}", builder);

        XoteloHotelService.SearchOutcome outcome = service.searchHotels("Tripoli");

        assertTrue(outcome.hotels().isEmpty());
        assertTrue(outcome.warnings().isEmpty());
        server.verify();
    }

    @Test
    void usesOnlyTheVerifiedDefaultLocationKeyWhenNoMapIsConfigured() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(containsString("/api/list?")))
                .andExpect(queryParam("location_key", "g297930"))
                .andRespond(withSuccess(
                        """
                        {"error":null,"result":{"list":[{
                          "name":"Default-key Hotel",
                          "key":"g297930-d456",
                          "price_ranges":{"minimum":100,"maximum":200}
                        }]}}
                        """,
                        MediaType.APPLICATION_JSON));

        XoteloHotelService service = new XoteloHotelService("{}", builder);
        XoteloHotelService.SearchOutcome outcome = service.searchHotels("Phuket");

        assertEquals(1, outcome.hotels().size());
        assertEquals("Default-key Hotel", outcome.hotels().getFirst().get("name"));
        server.verify();
    }
}

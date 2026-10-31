package com.zentrip.api;

import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;
import static org.junit.jupiter.api.Assertions.*;

class FlightSeatConfigurationTest {
    private Map<String, Object> listing(String layout, int rows, int available, Map<String, Object> attributes) {
        return Map.of("seat_layout", layout, "row_count", rows, "seats_available", available,
                "price", 138, "attributes", attributes);
    }

    @Test
    void actualLayoutAndUnpricedFaresAreNotFabricated() {
        Map<String, Object> result = FlightSeatConfiguration.response(
                listing("2-2", 16, 25, Map.of("business_price", 331)), List.of("1A"), 2);
        assertEquals(List.of("A", "B", "C", "D"), result.get("seat_letters"));
        List<?> cabins = (List<?>) result.get("cabins");
        assertEquals(1, cabins.size());
        assertEquals(64, ((Map<?, ?>) cabins.getFirst()).get("total_seats"));
        List<?> fares = (List<?>) result.get("fares");
        assertEquals(2, fares.size());
        assertEquals(23, ((Map<?, ?>) fares.getFirst()).get("available_seats"));
        assertEquals(true, ((Map<?, ?>) fares.getFirst()).get("shared_inventory"));
        assertEquals(Set.of(1, 7, 8), result.get("extra_legroom_rows"));
    }

    @Test
    void configuredCabinsUseActualRowRangesAndOccupiedSeats() {
        Map<String, Object> attributes = Map.of("cabins", List.of(
                Map.of("id", "front", "name", "Forward cabin", "row_start", 1, "row_end", 2),
                Map.of("id", "rear", "name", "Rear cabin", "rows", List.of(3, 4))));
        Map<String, Object> result = FlightSeatConfiguration.response(
                listing("3-3", 4, 22, attributes), List.of("1A", "4F"), 0);
        List<?> cabins = (List<?>) result.get("cabins");
        assertEquals(2, cabins.size());
        assertEquals(12, ((Map<?, ?>) cabins.getFirst()).get("total_seats"));
        assertEquals(11, ((Map<?, ?>) cabins.getFirst()).get("available_seats"));
        assertEquals(List.of(3, 4), ((Map<?, ?>) cabins.getLast()).get("rows"));
    }

    @Test
    void overlappingAndIncompleteCabinsFailExplicitly() {
        for (List<?> cabins : List.of(
                List.of(Map.of("rows", List.of(1, 2)), Map.of("rows", List.of(2, 3, 4))),
                List.of(Map.of("rows", List.of(1, 2))))) {
            assertThrows(ResponseStatusException.class, () -> FlightSeatConfiguration.response(
                    listing("3-3", 4, 24, Map.of("cabins", cabins)), List.of(), 0));
        }
    }

    @Test
    void inventoryNeverExceedsPhysicalSeatsOrGoesNegative() {
        for (int inventory : List.of(1000, 0, -1)) {
            Map<String, Object> result = FlightSeatConfiguration.response(
                    listing("2-2", 1, inventory, Map.of()), List.of("1A", "1B"), 3);
            Map<?, ?> fare = (Map<?, ?>) ((List<?>) result.get("fares")).getFirst();
            assertEquals(inventory > 0 ? 2 : 0, fare.get("available_seats"));
        }
    }

    @Test
    void configuredExtraLegroomAndPricingAreAuthoritative() {
        Map<String, Object> listing = listing("2-2", 16, 64, Map.of("extra_legroom_rows", List.of(2, 9)));
        assertEquals(Set.of(2, 9), FlightSeatConfiguration.premiumRows(listing));
        Map<?, ?> pricing = (Map<?, ?>) FlightSeatConfiguration.response(listing, List.of(), 0).get("pricing");
        assertEquals(FlightSeatConfiguration.LEGROOM_FEE, pricing.get("extra_legroom_fee"));
        assertEquals(FlightSeatConfiguration.TAX_RATE, pricing.get("tax_rate"));
        assertEquals(FlightSeatConfiguration.BOOKING_FEE, pricing.get("booking_fee"));
        assertEquals(FlightSeatConfiguration.EXTRAS, pricing.get("extras"));
    }
}

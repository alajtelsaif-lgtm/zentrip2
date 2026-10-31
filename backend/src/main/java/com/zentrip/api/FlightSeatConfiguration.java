package com.zentrip.api;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.IntStream;

import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

/** A read-only projection of the existing listing and its live seat inventory. */
final class FlightSeatConfiguration {
    static final BigDecimal LEGROOM_FEE = new BigDecimal("15");
    static final BigDecimal TAX_RATE = new BigDecimal("0.12");
    static final BigDecimal BOOKING_FEE = new BigDecimal("12");
    static final Map<String, BigDecimal> EXTRAS = Map.of(
            "extra_baggage", new BigDecimal("18"),
            "flexible_ticket", new BigDecimal("12"));

    private FlightSeatConfiguration() {}

    static Map<String, Object> response(
            Map<String, Object> listing, List<String> occupied, int activeHolds) {
        int rowCount = count(listing.get("row_count"));
        List<String> letters = "2-2".equals(listing.get("seat_layout"))
                ? List.of("A", "B", "C", "D") : List.of("A", "B", "C", "D", "E", "F");
        Map<?, ?> attributes = attributes(listing);
        Set<String> occupiedSet = new LinkedHashSet<>(occupied);
        int physicalAvailable = 0;
        for (int row = 1; row <= rowCount; row++) {
            for (String letter : letters) {
                if (!occupiedSet.contains(row + letter)) physicalAvailable++;
            }
        }
        int available = Math.min(physicalAvailable,
                Math.max(0, count(listing.get("seats_available")) - activeHolds));
        List<Map<String, Object>> fares = new ArrayList<>();
        for (String id : List.of("economy", "business", "first")) {
            Object raw = id.equals("economy") ? listing.get("price") : attributes.get(id + "_price");
            if (raw == null || raw.toString().isBlank()) continue;
            BigDecimal price;
            try {
                price = new BigDecimal(raw.toString());
            } catch (NumberFormatException exception) {
                throw invalid("Invalid flight fare");
            }
            if (price.signum() <= 0) continue;
            fares.add(Map.of("id", id, "label", Character.toUpperCase(id.charAt(0)) + id.substring(1),
                    "price", price, "available_seats", available, "shared_inventory", true));
        }
        if (fares.isEmpty()) throw invalid("No priced fares are available for this flight");

        List<?> configured;
        if (attributes.get("cabins") == null) {
            configured = List.of(Map.of("id", "1", "name", "Cabin 1", "row_start", 1, "row_end", rowCount));
        } else if (attributes.get("cabins") instanceof List<?> values && !values.isEmpty()) {
            configured = values;
        } else {
            throw invalid("Invalid flight cabin configuration");
        }
        Set<Integer> assignedRows = new LinkedHashSet<>();
        Set<String> cabinIds = new LinkedHashSet<>();
        List<Map<String, Object>> cabins = new ArrayList<>();
        for (Object raw : configured) {
            if (!(raw instanceof Map<?, ?> cabin)) throw invalid("Invalid flight cabin configuration");
            List<Integer> rows;
            if (cabin.get("rows") instanceof List<?> values) {
                rows = values.stream().map(FlightSeatConfiguration::count).sorted().toList();
            } else {
                int first = count(cabin.get("row_start"));
                int last = count(cabin.get("row_end"));
                if (first < 1 || last < first || last > rowCount) {
                    throw invalid("Invalid flight cabin row range");
                }
                rows = IntStream.rangeClosed(first, last).boxed().toList();
            }
            if (rows.isEmpty() || rows.stream().anyMatch(r -> r < 1 || r > rowCount)) {
                throw invalid("Invalid flight cabin row range");
            }
            for (int row : rows) {
                if (!assignedRows.add(row)) throw invalid("Flight cabins cannot overlap");
            }
            String id = cabin.get("id") == null ? Integer.toString(cabins.size() + 1) : cabin.get("id").toString();
            if (id.isBlank() || !cabinIds.add(id)) throw invalid("Flight cabin IDs must be unique");
            String name = cabin.get("name") == null ? "Cabin " + (cabins.size() + 1) : cabin.get("name").toString();
            int free = 0;
            for (int row : rows) {
                for (String letter : letters) {
                    if (!occupiedSet.contains(row + letter)) free++;
                }
            }
            cabins.add(Map.of("id", id, "name", name, "rows", rows,
                    "total_seats", rows.size() * letters.size(), "available_seats", Math.min(free, available)));
        }
        if (assignedRows.size() != rowCount) throw invalid("Flight cabins must cover every aircraft row");
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("occupied_seats", occupied);
        result.put("seat_layout", listing.get("seat_layout"));
        result.put("row_count", rowCount);
        result.put("seat_letters", letters);
        result.put("extra_legroom_rows", premiumRows(listing));
        result.put("fares", fares);
        result.put("cabins", cabins);
        result.put("pricing", Map.of("extra_legroom_fee", LEGROOM_FEE, "tax_rate", TAX_RATE,
                "booking_fee", BOOKING_FEE, "extras", EXTRAS));
        return result;
    }

    static Set<Integer> premiumRows(Map<String, Object> listing) {
        int rowCount = count(listing.get("row_count"));
        Object configured = attributes(listing).get("extra_legroom_rows");
        if (configured != null) {
            if (!(configured instanceof List<?> values)) throw invalid("Invalid extra legroom rows");
            Set<Integer> result = new LinkedHashSet<>();
            for (Object value : values) {
                int row = count(value);
                if (row < 1 || row > rowCount) throw invalid("Invalid extra legroom row");
                result.add(row);
            }
            return result;
        }
        List<Integer> defaults = "2-2".equals(listing.get("seat_layout"))
                ? List.of(1, 7, 8) : List.of(1, 11, 12);
        Set<Integer> result = new LinkedHashSet<>();
        defaults.stream().filter(row -> row <= rowCount).forEach(result::add);
        return result;
    }

    private static Map<?, ?> attributes(Map<String, Object> listing) {
        return listing.get("attributes") instanceof Map<?, ?> values ? values : Map.of();
    }

    private static int count(Object value) {
        try {
            return Integer.parseInt(value.toString());
        } catch (RuntimeException exception) {
            throw invalid("Invalid flight seat configuration");
        }
    }

    private static ResponseStatusException invalid(String message) {
        return new ResponseStatusException(HttpStatus.CONFLICT, message);
    }
}

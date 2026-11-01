package com.zentrip.api;

import com.fasterxml.jackson.databind.JsonNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class DuffelFlightService {
    private static final Logger LOG = LoggerFactory.getLogger(DuffelFlightService.class);
    private static final String API_BASE_URL = "https://api.duffel.com";
    private static final String OFFER_REQUEST_PATH =
            "/air/offer_requests?return_offers=true&supplier_timeout=10000";

    private final String accessToken;
    private final RestClient restClient;

    public DuffelFlightService(
            @Value("${duffel.access-token:}") String accessToken,
            RestClient.Builder restClientBuilder) {
        this.accessToken = accessToken == null ? "" : accessToken.trim();
        this.restClient = restClientBuilder.baseUrl(API_BASE_URL).build();
    }

    public boolean isConfigured() {
        return !accessToken.isBlank();
    }

    public List<Map<String, Object>> searchFlights(
            String origin,
            String destination,
            LocalDate departureDate,
            LocalDate returnDate,
            int adults,
            String cabinClass) {
        if (!isConfigured()) return List.of();

        List<Map<String, Object>> slices = new ArrayList<>();
        slices.add(slice(origin, destination, departureDate));
        if (returnDate != null) slices.add(slice(destination, origin, returnDate));

        Map<String, Object> requestData = new LinkedHashMap<>();
        requestData.put("slices", slices);
        requestData.put("passengers", java.util.Collections.nCopies(
                adults, Map.of("type", "adult")));
        requestData.put("cabin_class", cabinClass);

        try {
            JsonNode response = restClient.post()
                    .uri(OFFER_REQUEST_PATH)
                    .header("Authorization", "Bearer " + accessToken)
                    .header("Duffel-Version", "v2")
                    .accept(MediaType.APPLICATION_JSON)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("data", requestData))
                    .retrieve()
                    .body(JsonNode.class);

            JsonNode offers = response == null
                    ? null
                    : response.path("data").path("offers");
            if (offers == null || !offers.isArray()) return List.of();

            List<Map<String, Object>> flights = new ArrayList<>();
            for (JsonNode offer : offers) {
                Map<String, Object> flight = normalizeOffer(offer);
                if (flight != null) flights.add(flight);
            }
            return List.copyOf(flights);
        } catch (RestClientResponseException exception) {
            LOG.warn("Duffel flight offer search failed with HTTP status {}",
                    exception.getStatusCode().value());
            String message = exception.getStatusCode().value() == 401
                    || exception.getStatusCode().value() == 403
                    ? "Duffel rejected the configured access token. Replace "
                            + "DUFFEL_ACCESS_TOKEN in Replit Secrets."
                    : "The flight provider could not complete this search";
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY,
                    message);
        } catch (RestClientException exception) {
            LOG.warn("Duffel flight offer search could not reach the provider");
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY,
                    "The flight provider could not complete this search");
        }
    }

    private static Map<String, Object> slice(
            String origin, String destination, LocalDate departureDate) {
        return Map.of(
                "origin", origin,
                "destination", destination,
                "departure_date", departureDate.toString());
    }

    private static Map<String, Object> normalizeOffer(JsonNode offer) {
        String offerId = text(offer, "id");
        String amount = text(offer, "total_amount");
        String currency = text(offer, "total_currency");
        JsonNode slices = offer.path("slices");
        if (offerId.isBlank() || amount.isBlank() || currency.isBlank()
                || !slices.isArray() || slices.isEmpty()) {
            return null;
        }

        JsonNode outbound = slices.get(0);
        JsonNode segments = outbound.path("segments");
        if (!segments.isArray() || segments.isEmpty()) return null;
        JsonNode first = segments.get(0);
        JsonNode last = segments.get(segments.size() - 1);
        String departureTime = text(first, "departing_at");
        String arrivalTime = text(last, "arriving_at");
        JsonNode origin = first.path("origin");
        JsonNode destination = last.path("destination");
        String originCode = text(origin, "iata_code");
        String destinationCode = text(destination, "iata_code");
        if (departureTime.isBlank() || arrivalTime.isBlank()
                || originCode.isBlank() || destinationCode.isBlank()) {
            return null;
        }

        BigDecimal price;
        try {
            price = new BigDecimal(amount);
        } catch (NumberFormatException exception) {
            return null;
        }

        JsonNode owner = offer.path("owner");
        JsonNode marketingCarrier = first.path("marketing_carrier");
        JsonNode operatingCarrier = first.path("operating_carrier");
        String airline = firstNonBlank(
                text(owner, "name"),
                text(marketingCarrier, "name"),
                text(operatingCarrier, "name"));
        if (airline.isBlank()) return null;
        String airlineCode = firstNonBlank(
                text(owner, "iata_code"),
                text(marketingCarrier, "iata_code"),
                text(operatingCarrier, "iata_code"));
        String flightNumber = firstNonBlank(
                text(first, "marketing_carrier_flight_number"),
                text(first, "operating_carrier_flight_number"));
        int stops = Math.max(0, segments.size() - 1);

        Map<String, Object> flight = new LinkedHashMap<>();
        flight.put("id", "duffel-" + offerId);
        flight.put("source", "duffel");
        flight.put("duffel_offer_id", offerId);
        flight.put("airline", airline);
        flight.put("airline_code", airlineCode);
        flight.put("flight_number", flightNumber);
        flight.put("origin_code", originCode);
        flight.put("origin_city", firstNonBlank(
                text(origin, "city_name"), text(origin, "name")));
        flight.put("destination_code", destinationCode);
        flight.put("destination_city", firstNonBlank(
                text(destination, "city_name"), text(destination, "name")));
        flight.put("departure_time", departureTime);
        flight.put("arrival_time", arrivalTime);
        flight.put("duration_minutes", durationMinutes(
                outbound, departureTime, arrivalTime));
        flight.put("is_direct", stops == 0);
        flight.put("stops", stops);
        flight.put("economy_price", price);
        flight.put("price_currency", currency);
        flight.put("price_is_total", true);
        flight.put("seats_available", integerOrUnknown(offer.path("available_seats")));
        flight.put("airline_logo_url", null);
        flight.put("partner_listing_id", null);
        flight.put("is_active", true);
        flight.put("aircraft_name", "");
        flight.put("seat_layout", "");
        flight.put("seat_rows", 0);
        return flight;
    }

    private static int durationMinutes(
            JsonNode slice, String departureTime, String arrivalTime) {
        String duration = text(slice, "duration");
        if (!duration.isBlank()) {
            try {
                return Math.max(0, Math.toIntExact(Duration.parse(duration).toMinutes()));
            } catch (DateTimeParseException | ArithmeticException ignored) {
                // Compute duration from the segment timestamps when the provider value is invalid.
            }
        }
        try {
            return Math.max(0, Math.toIntExact(Duration.between(
                    OffsetDateTime.parse(departureTime).toInstant(),
                    OffsetDateTime.parse(arrivalTime).toInstant()).toMinutes()));
        } catch (DateTimeParseException | ArithmeticException ignored) {
            try {
                return Math.max(0, Math.toIntExact(Duration.between(
                        LocalDateTime.parse(departureTime),
                        LocalDateTime.parse(arrivalTime)).toMinutes()));
            } catch (DateTimeParseException | ArithmeticException invalidTimestamp) {
                return 0;
            }
        }
    }

    private static int integerOrUnknown(JsonNode value) {
        if (value == null || value.isMissingNode() || value.isNull()) return -1;
        if (value.isInt() || value.isLong()) return value.asInt(-1);
        return value.asText().isBlank() ? -1 : parseInteger(value.asText());
    }

    private static int parseInteger(String value) {
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException exception) {
            return -1;
        }
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) return value;
        }
        return "";
    }

    private static String text(JsonNode object, String field) {
        JsonNode value = object == null ? null : object.get(field);
        if (value == null || value.isNull() || value.isMissingNode()) return "";
        return value.asText("").trim();
    }
}

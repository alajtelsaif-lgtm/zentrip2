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
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class DuffelStayService {
    private static final Logger LOG = LoggerFactory.getLogger(DuffelStayService.class);
    private static final String API_BASE_URL = "https://api.duffel.com";
    private static final String SEARCH_PATH = "/stays/search";
    private static final String FETCH_RATES_PATH =
            "/stays/search_results/%s/actions/fetch_all_rates";

    private final boolean enabled;
    private final String accessToken;
    private final RestClient restClient;

    public DuffelStayService(
            @Value("${duffel.access-token:}") String accessToken,
            @Value("${duffel.enabled:true}") boolean enabled,
            RestClient.Builder restClientBuilder) {
        this.enabled = enabled;
        this.accessToken = enabled && accessToken != null ? accessToken.trim() : "";
        this.restClient = restClientBuilder.baseUrl(API_BASE_URL).build();
    }

    public boolean isConfigured() {
        return enabled && !accessToken.isBlank();
    }

    public List<Map<String, Object>> searchHotels(
            String city,
            double latitude,
            double longitude,
            LocalDate checkIn,
            LocalDate checkOut,
            int rooms,
            int guests) {
        return searchHotelsWithWarnings(
                city, latitude, longitude, checkIn, checkOut, rooms, guests).hotels();
    }

    public SearchOutcome searchHotelsWithWarnings(
            String city,
            double latitude,
            double longitude,
            LocalDate checkIn,
            LocalDate checkOut,
            int rooms,
            int guests) {
        long nights = checkIn == null || checkOut == null
                ? 0
                : java.time.temporal.ChronoUnit.DAYS.between(checkIn, checkOut);
        if (!isConfigured()
                || !validCoordinate(latitude, -90, 90)
                || !validCoordinate(longitude, -180, 180)
                || checkIn == null || checkOut == null || nights < 1 || nights > 99
                || rooms < 1 || rooms > 10 || guests < 1 || guests > 20) {
            return new SearchOutcome(List.of(), List.of());
        }

        Map<String, Object> location = Map.of(
                "radius", 5,
                "geographic_coordinates", Map.of(
                        "latitude", latitude,
                        "longitude", longitude));
        List<Map<String, String>> guestsList = Collections.nCopies(
                guests, Map.of("type", "adult"));
        Map<String, Object> requestData = new LinkedHashMap<>();
        requestData.put("location", location);
        requestData.put("check_in_date", checkIn.toString());
        requestData.put("check_out_date", checkOut.toString());
        requestData.put("rooms", rooms);
        requestData.put("guests", guestsList);

        try {
            JsonNode response = restClient.post()
                    .uri(SEARCH_PATH)
                    .header("Authorization", "Bearer " + accessToken)
                    .header("Duffel-Version", "v2")
                    .accept(MediaType.APPLICATION_JSON)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("data", requestData))
                    .retrieve()
                    .body(JsonNode.class);
            JsonNode results = response == null
                    ? null
                    : response.path("data").path("results");
            if (results == null || !results.isArray()) {
                return new SearchOutcome(List.of(), List.of());
            }

            List<Map<String, Object>> hotels = new ArrayList<>();
            for (JsonNode result : results) {
                Map<String, Object> hotel = normalizeResult(result, city, nights, rooms);
                if (hotel != null) hotels.add(hotel);
            }
            return new SearchOutcome(List.copyOf(hotels), List.of());
        } catch (RestClientResponseException exception) {
            int statusCode = exception.getStatusCode().value();
            LOG.warn("Duffel stays search failed with HTTP status {}", statusCode);
            String warning = statusCode == HttpStatus.TOO_MANY_REQUESTS.value()
                    ? "Duffel Stays is temporarily rate-limiting searches."
                    : "Duffel hotel results are temporarily unavailable.";
            return new SearchOutcome(List.of(), List.of(warning));
        } catch (RestClientException exception) {
            LOG.warn("Duffel stays search could not reach the provider");
            return new SearchOutcome(
                    List.of(), List.of("Duffel hotel results are temporarily unavailable."));
        }
    }

    public record SearchOutcome(
            List<Map<String, Object>> hotels,
            List<String> warnings) {
        public SearchOutcome {
            hotels = List.copyOf(hotels);
            warnings = List.copyOf(warnings);
        }
    }

    /**
     * Search results contain only a best-effort cheapest rate. Fetch the current complete
     * room/rate inventory only after a traveler opens a specific Duffel result.
     */
    public Map<String, Object> fetchAllRates(String searchResultId) {
        if (!isConfigured()) {
            throw new ResponseStatusException(
                    HttpStatus.SERVICE_UNAVAILABLE, "Hotel provider is not configured");
        }

        try {
            JsonNode response = restClient.post()
                    .uri(FETCH_RATES_PATH.formatted(searchResultId))
                    .header("Authorization", "Bearer " + accessToken)
                    .header("Duffel-Version", "v2")
                    .accept(MediaType.APPLICATION_JSON)
                    .contentType(MediaType.APPLICATION_JSON)
                    .retrieve()
                    .body(JsonNode.class);

            JsonNode result = response == null ? null : response.path("data");
            if (result == null || result.isMissingNode() || result.isNull()) {
                throw new ResponseStatusException(
                        HttpStatus.BAD_GATEWAY, "Hotel provider returned no rate details");
            }

            int roomsRequested = Math.max(1, result.path("rooms").asInt(1));
            long nights = stayNights(result);
            List<Map<String, Object>> roomTypes = new ArrayList<>();
            List<Map<String, Object>> offers = new ArrayList<>();
            JsonNode rawRooms = result.path("accommodation").path("rooms");
            if (rawRooms.isArray()) {
                for (JsonNode rawRoom : rawRooms) {
                    String roomName = text(rawRoom, "name");
                    List<String> photos = photoUrls(rawRoom.path("photos"));
                    List<Map<String, Object>> rates = new ArrayList<>();
                    JsonNode rawRates = rawRoom.path("rates");
                    if (rawRates.isArray()) {
                        for (JsonNode rawRate : rawRates) {
                            Map<String, Object> rate = normalizeRate(
                                    rawRate, roomName, nights, roomsRequested);
                            if (rate != null) {
                                rates.add(rate);
                                offers.add(rate);
                            }
                        }
                    }
                    if (rates.isEmpty()) continue;

                    Map<String, Object> room = new LinkedHashMap<>();
                    room.put("name", roomName);
                    room.put("beds", jsonValue(rawRoom.path("beds")));
                    room.put("photos", photos);
                    room.put("rates", List.copyOf(rates));
                    roomTypes.add(room);
                }
            }

            Map<String, Object> normalized = new LinkedHashMap<>();
            normalized.put("source", "duffel");
            normalized.put("provider_search_result_id", text(result, "id"));
            normalized.put("expires_at", text(result, "expires_at"));
            normalized.put("rooms_requested", roomsRequested);
            normalized.put("check_in_date", text(result, "check_in_date"));
            normalized.put("check_out_date", text(result, "check_out_date"));
            normalized.put("room_types", List.copyOf(roomTypes));
            normalized.put("offers", List.copyOf(offers));
            return normalized;
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (RestClientResponseException exception) {
            LOG.warn("Duffel stay rate retrieval failed with HTTP status {}",
                    exception.getStatusCode().value());
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY, "The hotel provider could not load room rates");
        } catch (RestClientException exception) {
            LOG.warn("Duffel stay rate retrieval could not reach the provider");
            throw new ResponseStatusException(
                    HttpStatus.BAD_GATEWAY, "The hotel provider could not load room rates");
        }
    }

    private static Map<String, Object> normalizeRate(
            JsonNode rate, String roomName, long nights, int roomsRequested) {
        String rateId = text(rate, "id");
        String currency = firstNonBlank(
                text(rate, "total_currency"), text(rate, "currency"));
        BigDecimal total = decimalValue(rate.path("total_amount"));
        if (rateId.isBlank() || currency.isBlank() || total == null || total.signum() < 0) {
            return null;
        }

        Map<String, Object> normalized = new LinkedHashMap<>();
        normalized.put("id", rateId);
        normalized.put("rate_id", rateId);
        normalized.put("room_name", roomName);
        normalized.put("name", text(rate, "name"));
        normalized.put("description", text(rate, "description"));
        normalized.put("total_amount", total);
        normalized.put("total_currency", currency.toUpperCase(java.util.Locale.ROOT));
        normalized.put("price_per_night", total.divide(
                BigDecimal.valueOf(Math.max(1, nights) * roomsRequested),
                6,
                RoundingMode.HALF_UP));
        normalized.put("price_currency", currency.toUpperCase(java.util.Locale.ROOT));
        normalized.put("due_at_accommodation_amount",
                decimalValue(rate.path("due_at_accommodation_amount")));
        normalized.put("due_at_accommodation_currency",
                text(rate, "due_at_accommodation_currency"));
        normalized.put("quantity_available", integerOrZero(rate.path("quantity_available")));
        normalized.put("payment_type", text(rate, "payment_type"));
        normalized.put("board_type", text(rate, "board_type"));
        normalized.put("expires_at", text(rate, "expires_at"));
        normalized.put("cancellation_timeline",
                jsonValue(rate.path("cancellation_timeline")));
        normalized.put("benefits", jsonValue(rate.path("benefits")));
        normalized.put("conditions", jsonValue(rate.path("conditions")));
        return normalized;
    }

    private static long stayNights(JsonNode result) {
        try {
            LocalDate checkIn = LocalDate.parse(text(result, "check_in_date"));
            LocalDate checkOut = LocalDate.parse(text(result, "check_out_date"));
            long nights = java.time.temporal.ChronoUnit.DAYS.between(checkIn, checkOut);
            return nights > 0 ? nights : 1;
        } catch (java.time.DateTimeException exception) {
            return 1;
        }
    }

    private static List<String> photoUrls(JsonNode photos) {
        if (!photos.isArray()) return List.of();
        List<String> urls = new ArrayList<>();
        for (JsonNode photo : photos) {
            String url = text(photo, "url");
            if (!url.isBlank()) urls.add(url);
        }
        return List.copyOf(urls);
    }

    private static Object jsonValue(JsonNode node) {
        if (node == null || node.isMissingNode() || node.isNull()) return null;
        if (node.isObject()) {
            Map<String, Object> values = new LinkedHashMap<>();
            node.fields().forEachRemaining(entry ->
                    values.put(entry.getKey(), jsonValue(entry.getValue())));
            return values;
        }
        if (node.isArray()) {
            List<Object> values = new ArrayList<>();
            node.forEach(value -> values.add(jsonValue(value)));
            return java.util.Collections.unmodifiableList(values);
        }
        if (node.isNumber()) return node.numberValue();
        if (node.isBoolean()) return node.booleanValue();
        return node.asText();
    }

    private static BigDecimal decimalValue(JsonNode node) {
        if (node == null || node.isMissingNode() || node.isNull()) return null;
        try {
            return new BigDecimal(node.asText());
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static Map<String, Object> normalizeResult(
            JsonNode result, String requestedCity, long nights, int rooms) {
        String searchResultId = text(result, "id");
        JsonNode accommodation = result.path("accommodation");
        String accommodationId = text(accommodation, "id");
        String name = text(accommodation, "name");
        String totalAmountText = firstNonBlank(
                text(result, "cheapest_rate_total_amount"),
                text(result, "cheapest_rate_public_amount"));
        String currency = firstNonBlank(
                text(result, "cheapest_rate_currency"),
                text(result, "cheapest_rate_public_currency"));
        if (searchResultId.isBlank() || name.isBlank()
                || totalAmountText.isBlank() || currency.isBlank()) {
            return null;
        }

        BigDecimal totalAmount;
        try {
            totalAmount = new BigDecimal(totalAmountText);
        } catch (NumberFormatException exception) {
            return null;
        }
        if (totalAmount.signum() < 0) return null;

        JsonNode address = accommodation.path("location").path("address");
        JsonNode coordinates = accommodation.path("location")
                .path("geographic_coordinates");
        List<String> galleryImages = new ArrayList<>();
        JsonNode photos = accommodation.path("photos");
        if (photos.isArray()) {
            for (JsonNode photo : photos) {
                String url = text(photo, "url");
                if (!url.isBlank()) galleryImages.add(url);
            }
        }
        List<String> amenities = new ArrayList<>();
        JsonNode amenityNodes = accommodation.path("amenities");
        if (amenityNodes.isArray()) {
            for (JsonNode amenity : amenityNodes) {
                String description = firstNonBlank(
                        text(amenity, "description"), text(amenity, "type"));
                if (!description.isBlank()) amenities.add(description);
            }
        }

        Double reviewScore = decimalOrNull(accommodation.path("review_score"));
        int reviewCount = integerOrZero(accommodation.path("review_count"));
        int hotelStars = Math.max(0, Math.min(5,
                integerOrZero(accommodation.path("rating"))));
        BigDecimal nightlyAmount = totalAmount.divide(
                BigDecimal.valueOf(nights * rooms), 6, RoundingMode.HALF_UP);
        Map<String, Object> hotel = new LinkedHashMap<>();
        hotel.put("id", "duffel-" + searchResultId);
        hotel.put("source", "duffel");
        hotel.put("provider_search_result_id", searchResultId);
        hotel.put("provider_accommodation_id", accommodationId);
        hotel.put("name", name);
        hotel.put("city", firstNonBlank(text(address, "city_name"), requestedCity));
        hotel.put("country", text(address, "country_code"));
        hotel.put("location_name", text(address, "line_one"));
        hotel.put("latitude", decimalOrNull(coordinates.path("latitude")));
        hotel.put("longitude", decimalOrNull(coordinates.path("longitude")));
        hotel.put("description", text(accommodation, "description"));
        hotel.put("image_url", galleryImages.isEmpty() ? null : galleryImages.getFirst());
        hotel.put("gallery_images", galleryImages);
        hotel.put("amenities", amenities);
        hotel.put("stars", hotelStars);
        // The legacy model displays a five-point rating; Duffel supplies a ten-point score.
        hotel.put("rating", reviewScore == null ? 0 : reviewScore / 2.0);
        hotel.put("review_score", reviewScore);
        hotel.put("rating_source", "duffel");
        hotel.put("review_count", reviewCount);
        hotel.put("price_per_night", nightlyAmount);
        hotel.put("price_currency", currency.toUpperCase(java.util.Locale.ROOT));
        hotel.put("tax_and_fees_percentage", 0);
        hotel.put("available_rooms", null);
        hotel.put("availability_known", false);
        hotel.put("room_types", List.of());
        hotel.put("offers", List.of());
        hotel.put("is_active", true);
        hotel.put("status", "published");
        hotel.put("partner_listing_id", null);
        return hotel;
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node == null ? null : node.get(field);
        return value == null || value.isNull() ? "" : value.asText("").trim();
    }

    private static String firstNonBlank(String first, String second) {
        return first == null || first.isBlank() ? second : first;
    }

    private static Double decimalOrNull(JsonNode node) {
        if (node == null || node.isMissingNode() || node.isNull()) return null;
        try {
            double value = node.isNumber()
                    ? node.doubleValue()
                    : Double.parseDouble(node.asText());
            return Double.isFinite(value) ? value : null;
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static int integerOrZero(JsonNode node) {
        Double value = decimalOrNull(node);
        return value == null ? 0 : value.intValue();
    }

    private static boolean validCoordinate(double value, double minimum, double maximum) {
        return Double.isFinite(value) && value >= minimum && value <= maximum;
    }
}

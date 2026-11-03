package com.zentrip.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.net.URI;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

/**
 * Read-only LiteAPI hotel data and rate search.
 *
 * The application keeps its own simulated booking and payment flow. This
 * service deliberately does not call LiteAPI prebook, book, or cancellation
 * endpoints and does not expose provider rate identifiers to the client.
 */
@Service
public class LiteApiHotelService {
    private static final Logger LOG =
            LoggerFactory.getLogger(LiteApiHotelService.class);
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final int MAX_HOTELS = 100;
    private static final int MAX_OFFERS_PER_HOTEL = 5;
    private static final int DEFAULT_RADIUS_METERS = 20_000;

    private final String apiKey;
    private final String guestNationality;
    private final RestClient client;

    public LiteApiHotelService(
            @Value("${liteapi.api-key:}") String apiKey,
            @Value("${liteapi.base-url:https://api.liteapi.travel/v3.0}")
                    String baseUrl,
            @Value("${liteapi.guest-nationality:LY}") String guestNationality,
            RestClient.Builder builder) {
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.guestNationality = guestNationality == null
                ? ""
                : guestNationality.trim().toUpperCase(Locale.ROOT);
        this.client = builder.clone()
                .baseUrl(validateBaseUrl(baseUrl))
                .build();
    }

    public UnifiedInventoryService.SourceOutcome searchHotels(
            String city,
            LocalDate checkIn,
            LocalDate checkOut,
            int rooms,
            int guests,
            String currency,
            Double latitude,
            Double longitude) {
        String normalizedCity = city == null ? "" : city.trim();
        if (normalizedCity.isBlank()) {
            return UnifiedInventoryService.SourceOutcome.of(List.of());
        }
        if (apiKey.isBlank()) {
            return unavailable("LiteAPI hotel search is not configured.");
        }
        if (!guestNationality.matches("[A-Z]{2}")) {
            return unavailable(
                    "LiteAPI requires a two-letter guest nationality setting.");
        }
        if (checkIn == null || checkOut == null
                || !checkOut.isAfter(checkIn)
                || ChronoUnit.DAYS.between(checkIn, checkOut) > 99
                || rooms < 1 || rooms > 10
                || guests < rooms || guests > 20) {
            return unavailable(
                    "LiteAPI hotel search requires valid dates and at least one adult per room.");
        }
        String normalizedCurrency;
        try {
            normalizedCurrency = UnifiedInventoryService.validateCurrency(currency);
        } catch (RuntimeException exception) {
            return unavailable("LiteAPI hotel search received an unsupported currency.");
        }

        try {
            JsonNode response = client.post()
                    .uri("/hotels/rates")
                    .headers(this::applyAuthentication)
                    .contentType(MediaType.APPLICATION_JSON)
                    .accept(MediaType.APPLICATION_JSON)
                    .body(searchRequest(
                            normalizedCity,
                            checkIn,
                            checkOut,
                            rooms,
                            guests,
                            normalizedCurrency,
                            latitude,
                            longitude))
                    .retrieve()
                    .body(JsonNode.class);
            if (response == null) {
                return unavailable("LiteAPI returned an empty hotel response.");
            }
            JsonNode error = response.path("error");
            if (!error.isMissingNode() && !error.isNull()) {
                String message = safeMessage(firstText(
                        error, "message", "description"));
                LOG.warn("LiteAPI hotel rates returned an error code={} message={}",
                        firstText(error, "code", "errorCode"), message);
                return unavailable("LiteAPI hotel search is temporarily unavailable.");
            }

            Map<String, JsonNode> hotelDetails = indexHotelDetails(response);
            long nights = ChronoUnit.DAYS.between(checkIn, checkOut);
            List<Map<String, Object>> hotels = new ArrayList<>();
            for (JsonNode result : array(response.path("data"))) {
                String hotelId = firstText(result, "hotelId", "id");
                if (hotelId.isBlank()) continue;
                JsonNode details = hotelDetails.getOrDefault(
                        hotelId, JSON.getNodeFactory().nullNode());
                Map<String, Object> normalized = normalizeHotel(
                        hotelId,
                        result,
                        details,
                        normalizedCity,
                        nights,
                        rooms,
                        normalizedCurrency);
                if (normalized != null) hotels.add(normalized);
                if (hotels.size() >= MAX_HOTELS) break;
            }
            return UnifiedInventoryService.SourceOutcome.of(hotels);
        } catch (RestClientResponseException exception) {
            logProviderFailure(exception);
            int status = exception.getStatusCode().value();
            String warning = switch (status) {
                case 401 -> "LiteAPI authentication failed. Verify the API key and environment.";
                case 403 -> "LiteAPI access was denied for hotel rates.";
                case 400 -> "LiteAPI rejected this destination. Select a destination suggestion and retry.";
                default -> "LiteAPI hotel search is temporarily unavailable.";
            };
            return unavailable(warning);
        } catch (ResourceAccessException exception) {
            LOG.warn("LiteAPI hotel search timed out or could not connect");
            return unavailable("LiteAPI hotel search is temporarily unavailable.");
        } catch (RestClientException | IllegalArgumentException exception) {
            LOG.warn("LiteAPI hotel search failed ({})",
                    exception.getClass().getSimpleName());
            return unavailable("LiteAPI hotel search is temporarily unavailable.");
        }
    }

    private void applyAuthentication(HttpHeaders headers) {
        headers.set("X-API-Key", apiKey);
    }

    private Map<String, Object> searchRequest(
            String city,
            LocalDate checkIn,
            LocalDate checkOut,
            int rooms,
            int guests,
            String currency,
            Double latitude,
            Double longitude) {
        Map<String, Object> request = new LinkedHashMap<>();
        request.put("checkin", checkIn.toString());
        request.put("checkout", checkOut.toString());
        request.put("currency", currency);
        request.put("guestNationality", guestNationality);
        request.put("occupancies", occupancies(rooms, guests));
        request.put("timeout", 6);
        request.put("maxRatesPerHotel", 1);
        request.put("limit", MAX_HOTELS);
        request.put("sort", List.of(Map.of(
                "field", "price",
                "direction", "ascending")));

        if (validCoordinates(latitude, longitude)) {
            request.put("latitude", latitude);
            request.put("longitude", longitude);
            request.put("radius", DEFAULT_RADIUS_METERS);
        } else {
            request.put("cityName", city);
        }
        return request;
    }

    private static List<Map<String, Object>> occupancies(int rooms, int guests) {
        List<Map<String, Object>> result = new ArrayList<>(rooms);
        int baseAdultsPerRoom = guests / rooms;
        int extraAdults = guests % rooms;
        for (int room = 0; room < rooms; room++) {
            Map<String, Object> occupancy = new LinkedHashMap<>();
            occupancy.put("rooms", 1);
            occupancy.put("adults", baseAdultsPerRoom + (room < extraAdults ? 1 : 0));
            result.add(occupancy);
        }
        return result;
    }

    private static boolean validCoordinates(Double latitude, Double longitude) {
        return latitude != null && longitude != null
                && Double.isFinite(latitude) && Double.isFinite(longitude)
                && latitude >= -90 && latitude <= 90
                && longitude >= -180 && longitude <= 180;
    }

    private static Map<String, JsonNode> indexHotelDetails(JsonNode response) {
        JsonNode source = response.path("hotels");
        if (source.isObject()) source = source.path("hotels");
        Map<String, JsonNode> indexed = new LinkedHashMap<>();
        for (JsonNode hotel : array(source)) {
            String id = firstText(hotel, "id", "hotelId");
            if (!id.isBlank()) indexed.putIfAbsent(id, hotel);
        }
        return indexed;
    }

    private static Map<String, Object> normalizeHotel(
            String hotelId,
            JsonNode rateResult,
            JsonNode details,
            String requestedCity,
            long nights,
            int rooms,
            String requestedCurrency) {
        List<Map<String, Object>> offers = new ArrayList<>();
        for (JsonNode roomType : array(rateResult.path("roomTypes"))) {
            Money total = offerTotal(roomType, requestedCurrency);
            if (total == null || total.amount().signum() < 0) continue;
            BigDecimal divisor = BigDecimal.valueOf(nights * rooms);
            BigDecimal nightly = total.amount().divide(
                    divisor, 4, RoundingMode.HALF_UP);
            Map<String, Object> offer = new LinkedHashMap<>();
            offer.put("source", "liteapi");
            offer.put("room_name", firstText(roomType, "name", "roomTypeId"));
            offer.put("board_name", firstRateText(roomType, "boardName", "boardType"));
            offer.put("price_per_night", nightly);
            offer.put("stay_total", total.amount());
            offer.put("total_amount", total.amount());
            offer.put("currency", total.currency());
            offer.put("price_currency", total.currency());
            offer.put("conditions", cancellationText(roomType));
            offers.add(offer);
        }
        offers.sort(Comparator.comparing(
                offer -> (BigDecimal) offer.get("stay_total")));
        if (offers.isEmpty()) return null;
        if (offers.size() > MAX_OFFERS_PER_HOTEL) {
            offers = new ArrayList<>(offers.subList(0, MAX_OFFERS_PER_HOTEL));
        }

        @SuppressWarnings("unchecked")
        Map<String, Object> cheapest = offers.getFirst();
        String currency = text(cheapest.get("currency"));
        BigDecimal nightlyPrice = (BigDecimal) cheapest.get("price_per_night");
        String name = firstText(details, "name");
        if (name.isBlank()) name = firstText(rateResult, "name");
        if (name.isBlank()) name = "Hotel";
        String address = firstText(details, "address");
        String city = firstText(details, "city_name");
        if (city.isBlank()) city = requestedCity;
        String image = firstText(details, "main_photo", "thumbnail");
        List<String> gallery = new ArrayList<>();
        addIfPresent(gallery, firstText(details, "main_photo"));
        addIfPresent(gallery, firstText(details, "thumbnail"));

        Map<String, Object> hotel = new LinkedHashMap<>();
        hotel.put("id", "liteapi-" + hotelId);
        hotel.put("source", "liteapi");
        hotel.put("provider_accommodation_id", hotelId);
        hotel.put("name", name);
        hotel.put("city", city);
        hotel.put("country", firstText(details, "country_code"));
        hotel.put("location_name", address);
        hotel.put("address", address);
        hotel.put("price_per_night", nightlyPrice);
        hotel.put("price_currency", currency);
        hotel.put("price_currency_code", currency);
        hotel.put("tax_and_fees_percentage", BigDecimal.ZERO);
        hotel.put("available_rooms", rooms);
        hotel.put("availability_known", true);
        hotel.put("image_url", image);
        hotel.put("gallery_images", gallery);
        hotel.put("description", firstText(details, "story"));
        hotel.put("stars", integer(details.path("stars")));
        hotel.put("rating", decimal(details.path("rating")));
        hotel.put("review_score", decimal(details.path("rating")));
        hotel.put("google_review_count", integer(details.path("review_count")));
        hotel.put("rating_source", "liteapi");
        hotel.put("latitude", decimal(details.path("latitude")));
        hotel.put("longitude", decimal(details.path("longitude")));
        hotel.put("amenities", strings(details.path("tags")));
        hotel.put("offers", offers);
        hotel.put("status", "published");
        hotel.put("active", true);
        return hotel;
    }

    private static Money offerTotal(JsonNode roomType, String currency) {
        Money offer = money(roomType.path("offerRetailRate"), currency);
        if (offer != null) return offer;

        JsonNode rates = roomType.path("rates");
        BigDecimal total = BigDecimal.ZERO;
        int count = 0;
        for (JsonNode rate : array(rates)) {
            Money rateTotal = money(rate.path("retailRate").path("total"), currency);
            if (rateTotal == null) return null;
            if (count > 0 && !rateTotal.currency().equalsIgnoreCase(currency)) {
                return null;
            }
            total = total.add(rateTotal.amount());
            count++;
        }
        return count == 0 ? null : new Money(total, currency);
    }

    private static Money money(JsonNode values, String preferredCurrency) {
        JsonNode candidates = values.isArray() ? values : JSON.getNodeFactory().arrayNode();
        Money fallback = null;
        for (JsonNode item : candidates) {
            BigDecimal amount = decimal(item.path("amount"));
            String currency = firstText(item, "currency").toUpperCase(Locale.ROOT);
            if (amount == null || !currency.matches("[A-Z]{3}")) continue;
            Money current = new Money(amount, currency);
            if (currency.equalsIgnoreCase(preferredCurrency)) return current;
            if (fallback == null) fallback = current;
        }
        return fallback;
    }

    private static String firstRateText(
            JsonNode roomType, String... fields) {
        for (JsonNode rate : array(roomType.path("rates"))) {
            String value = firstText(rate, fields);
            if (!value.isBlank()) return value;
        }
        return "";
    }

    private static String cancellationText(JsonNode roomType) {
        for (JsonNode rate : array(roomType.path("rates"))) {
            JsonNode policies = rate.path("cancellationPolicies")
                    .path("cancelPolicyInfos");
            if (!policies.isArray() || policies.isEmpty()) continue;
            JsonNode policy = policies.get(0);
            String deadline = firstText(policy, "cancelTime");
            String amount = firstText(policy, "amount");
            if (!deadline.isBlank()) return "Cancel by " + deadline
                    + (amount.isBlank() ? "" : " (fee " + amount + ")");
        }
        return firstRateText(roomType, "remarks");
    }

    private static List<JsonNode> array(JsonNode node) {
        return node != null && node.isArray()
                ? iterable(node)
                : List.of();
    }

    private static List<JsonNode> iterable(JsonNode node) {
        List<JsonNode> values = new ArrayList<>();
        node.forEach(values::add);
        return values;
    }

    private static List<String> strings(JsonNode node) {
        List<String> values = new ArrayList<>();
        if (node != null && node.isArray()) {
            node.forEach(value -> {
                String text = value.isTextual()
                        ? value.asText().trim()
                        : firstText(value, "name", "label", "tag");
                addIfPresent(values, text);
            });
        }
        return List.copyOf(values);
    }

    private static void addIfPresent(List<String> values, String value) {
        if (value != null && !value.isBlank() && !values.contains(value)) {
            values.add(value);
        }
    }

    private static BigDecimal decimal(JsonNode node) {
        if (node == null || node.isMissingNode() || node.isNull()) return null;
        if (node.isNumber()) return node.decimalValue();
        try {
            return new BigDecimal(node.asText().trim());
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static int integer(JsonNode node) {
        BigDecimal value = decimal(node);
        return value == null ? 0 : value.intValue();
    }

    private static String firstText(JsonNode node, String... fields) {
        for (String field : fields) {
            JsonNode value = node == null ? null : node.path(field);
            if (value == null || value.isMissingNode() || value.isNull()) continue;
            String text = value.asText("").trim();
            if (!text.isBlank()) return text;
        }
        return "";
    }

    private void logProviderFailure(RestClientResponseException exception) {
        JsonNode body = null;
        try {
            String responseBody = exception.getResponseBodyAsString();
            if (!responseBody.isBlank()) body = JSON.readTree(responseBody);
        } catch (Exception ignored) {
            // Keep provider response parsing best-effort and never log raw bodies.
        }
        JsonNode error = body == null ? null : body.path("error");
        String code = firstText(error, "code", "errorCode");
        String message = safeMessage(firstText(error, "message", "description"));
        HttpHeaders headers = exception.getResponseHeaders();
        String requestId = headers == null
                ? ""
                : firstNonBlank(
                        headers.getFirst("X-Request-Id"),
                        headers.getFirst("X-Request-ID"),
                        headers.getFirst("X-Correlation-Id"));
        int status = exception.getStatusCode().value();
        LOG.warn("LiteAPI hotel rates failed: status={}, errorCode={}, message={}, requestId={}",
                status, code, message, requestId);
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) return value.trim();
        }
        return "";
    }

    private static String text(Object value) {
        return value == null ? "" : value.toString().trim();
    }

    private String safeMessage(String message) {
        if (message == null || message.isBlank()) return "No provider message returned";
        String safe = message.replaceAll("[\\r\\n]+", " ");
        if (!apiKey.isBlank()) safe = safe.replace(apiKey, "[redacted]");
        return safe.substring(0, Math.min(safe.length(), 240));
    }

    private static UnifiedInventoryService.SourceOutcome unavailable(String warning) {
        return new UnifiedInventoryService.SourceOutcome(List.of(), List.of(warning));
    }

    private static String validateBaseUrl(String configured) {
        String value = configured == null || configured.isBlank()
                ? "https://api.liteapi.travel/v3.0"
                : configured.trim();
        URI uri = URI.create(value);
        if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null) {
            throw new IllegalArgumentException("LiteAPI base URL must use HTTPS");
        }
        return value.replaceAll("/+$", "");
    }

    private record Money(BigDecimal amount, String currency) {}
}

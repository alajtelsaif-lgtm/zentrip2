package com.zentrip.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
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
 * Read-only Hotelbeds hotel availability and content search.
 * Hotel reservations continue through Zentrip's simulated booking flow.
 */
@Service
public class HotelbedsHotelService {
    private static final Logger LOG =
            LoggerFactory.getLogger(HotelbedsHotelService.class);
    private static final int MAX_HOTELS = 30;
    private static final int MAX_OFFERS_PER_HOTEL = 5;
    private static final int SEARCH_RADIUS_KM = 20;
    private static final ObjectMapper JSON = new ObjectMapper();

    private final String apiKey;
    private final String apiSecret;
    private final GeoapifyAirportService geocoder;
    private final RestClient client;
    private final Clock clock;

    public HotelbedsHotelService(
            @Value("${hotelbeds.api-key:}") String apiKey,
            @Value("${hotelbeds.api-secret:}") String apiSecret,
            @Value("${hotelbeds.base-url:https://api.test.hotelbeds.com}") String baseUrl,
            GeoapifyAirportService geocoder,
            RestClient.Builder restClientBuilder) {
        this(apiKey, apiSecret, baseUrl, geocoder, restClientBuilder, Clock.systemUTC());
    }

    HotelbedsHotelService(
            String apiKey,
            String apiSecret,
            String baseUrl,
            GeoapifyAirportService geocoder,
            RestClient.Builder restClientBuilder,
            Clock clock) {
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.apiSecret = apiSecret == null ? "" : apiSecret.trim();
        this.geocoder = geocoder;
        this.clock = clock;
        this.client = restClientBuilder.baseUrl(normalizeBaseUrl(baseUrl)).build();
    }

    public UnifiedInventoryService.SourceOutcome searchHotels(
            String city,
            LocalDate checkIn,
            LocalDate checkOut,
            int rooms,
            int guests) {
        String normalizedCity = city == null ? "" : city.trim();
        if (normalizedCity.isBlank()) {
            return UnifiedInventoryService.SourceOutcome.of(List.of());
        }
        if (apiKey.isBlank() || apiSecret.isBlank()) {
            return unavailable("Hotelbeds hotel search is not configured.");
        }
        if (checkIn == null || checkOut == null
                || !checkOut.isAfter(checkIn)
                || ChronoUnit.DAYS.between(checkIn, checkOut) > 99
                || rooms < 1 || rooms > 10
                || guests < 1 || guests > 20) {
            return unavailable(
                    "Hotelbeds availability requires valid stay dates and guest counts.");
        }

        GeoapifyAirportService.GeocodedPlace location =
                geocoder == null ? null : geocoder.resolveLocation(normalizedCity);
        if (location == null) {
            return unavailable(
                    "Hotelbeds could not resolve that destination. Try a city and country.");
        }

        try {
            JsonNode response = client.post()
                    .uri("/hotel-api/1.0/hotels")
                    .headers(this::applyAuthentication)
                    .contentType(MediaType.APPLICATION_JSON)
                    .accept(MediaType.APPLICATION_JSON)
                    .body(availabilityRequest(
                            checkIn, checkOut, rooms, guests, location))
                    .retrieve()
                    .body(JsonNode.class);
            if (response == null) {
                return unavailable("Hotelbeds returned an empty availability response.");
            }
            JsonNode providerError = response.path("error");
            if (!providerError.isMissingNode() && !providerError.isNull()) {
                LOG.warn("Hotelbeds availability returned an error code={} message={}",
                        firstText(providerError, "code", "errorCode"),
                        safeMessage(firstText(providerError, "message", "description")));
                return unavailable("Hotelbeds hotel inventory is temporarily unavailable.");
            }

            List<JsonNode> availabilityHotels =
                    hotelNodes(response.path("hotels"));
            if (availabilityHotels.isEmpty()) {
                return UnifiedInventoryService.SourceOutcome.of(List.of());
            }
            List<JsonNode> hotelDetails = fetchHotelDetails(availabilityHotels);
            Map<String, JsonNode> detailsByCode = new LinkedHashMap<>();
            for (JsonNode detail : hotelDetails) {
                String code = firstText(detail, "code", "hotelCode");
                if (!code.isBlank()) detailsByCode.putIfAbsent(code, detail);
            }

            List<Map<String, Object>> hotels = new ArrayList<>();
            for (JsonNode availabilityHotel : availabilityHotels) {
                String code = firstText(availabilityHotel, "code", "hotelCode");
                JsonNode detail = detailsByCode.getOrDefault(code, JSON.nullNode());
                Map<String, Object> normalized = normalizeHotel(
                        availabilityHotel, detail, normalizedCity, location,
                        checkIn, checkOut, rooms);
                if (normalized != null) hotels.add(normalized);
                if (hotels.size() >= MAX_HOTELS) break;
            }
            return new UnifiedInventoryService.SourceOutcome(hotels, List.of());
        } catch (RestClientResponseException exception) {
            logProviderFailure("availability search", exception);
            String warning = exception.getStatusCode().value() == 403
                    || exception.getStatusCode().value() == 401
                    ? "Hotelbeds access was denied. Verify the API key, API secret, and account access."
                    : "Hotelbeds hotel inventory is temporarily unavailable.";
            return unavailable(warning);
        } catch (ResourceAccessException exception) {
            LOG.warn("Hotelbeds availability search timed out or could not connect");
            return unavailable("Hotelbeds hotel inventory is temporarily unavailable.");
        } catch (RestClientException | IllegalArgumentException exception) {
            LOG.warn("Hotelbeds availability search failed ({})",
                    exception.getClass().getSimpleName());
            return unavailable("Hotelbeds hotel inventory is temporarily unavailable.");
        }
    }

    private List<JsonNode> fetchHotelDetails(List<JsonNode> availabilityHotels) {
        List<String> codes = availabilityHotels.stream()
                .map(hotel -> firstText(hotel, "code", "hotelCode"))
                .filter(code -> code.matches("\\d{1,10}"))
                .distinct()
                .limit(MAX_HOTELS)
                .toList();
        if (codes.isEmpty()) return List.of();
        try {
            JsonNode response = client.get()
                    .uri(uri -> uri.path("/hotel-content-api/1.0/hotels")
                            .queryParam("codes", String.join(",", codes))
                            .queryParam("fields", "all")
                            .queryParam("language", "ENG")
                            .queryParam("useSecondaryLanguage", "true")
                            .queryParam("from", 1)
                            .queryParam("to", MAX_HOTELS)
                            .build())
                    .headers(this::applyAuthentication)
                    .accept(MediaType.APPLICATION_JSON)
                    .retrieve()
                    .body(JsonNode.class);
            if (response == null) return List.of();
            return hotelNodes(response);
        } catch (RestClientResponseException exception) {
            logProviderFailure("hotel content lookup", exception);
            return List.of();
        } catch (RestClientException exception) {
            LOG.warn("Hotelbeds hotel content lookup failed ({})",
                    exception.getClass().getSimpleName());
            return List.of();
        }
    }

    private Map<String, Object> availabilityRequest(
            LocalDate checkIn,
            LocalDate checkOut,
            int rooms,
            int guests,
            GeoapifyAirportService.GeocodedPlace location) {
        Map<String, Object> request = new LinkedHashMap<>();
        request.put("stay", Map.of(
                "checkIn", checkIn.toString(),
                "checkOut", checkOut.toString()));
        request.put("occupancies", List.of(Map.of(
                "rooms", rooms,
                "adults", guests,
                "children", 0)));
        request.put("geolocation", Map.of(
                "latitude", location.latitude(),
                "longitude", location.longitude(),
                "radius", SEARCH_RADIUS_KM,
                "unit", "km"));
        request.put("filter", Map.of(
                "maxHotels", MAX_HOTELS,
                "maxRooms", rooms,
                "maxRatesPerRoom", MAX_OFFERS_PER_HOTEL));
        request.put("language", "ENG");
        return request;
    }

    private Map<String, Object> normalizeHotel(
            JsonNode availabilityHotel,
            JsonNode detail,
            String searchedCity,
            GeoapifyAirportService.GeocodedPlace searchedLocation,
            LocalDate checkIn,
            LocalDate checkOut,
            int requestedRooms) {
        String code = firstText(availabilityHotel, "code", "hotelCode");
        if (!code.matches("\\d{1,10}")) return null;
        String name = firstText(availabilityHotel, "name", "hotelName");
        if (name.isBlank()) name = firstText(detail, "name");
        if (name.isBlank()) return null;

        long nights = ChronoUnit.DAYS.between(checkIn, checkOut);
        List<Map<String, Object>> offers = extractOffers(
                availabilityHotel, nights, requestedRooms);
        if (offers.isEmpty()) return null;
        offers.sort(Comparator.comparing(
                offer -> (BigDecimal) offer.get("price_per_night")));

        Map<String, Object> lowestOffer = offers.getFirst();
        String address = content(detail.path("address"));
        String city = content(detail.path("city"));
        if (city.isBlank()) city = searchedLocation.city();
        if (city.isBlank()) city = searchedCity;
        JsonNode countryNode = detail.path("country");
        String country = firstText(countryNode, "description", "name", "code");
        if (country.isBlank()) country = searchedLocation.country();
        String locationName = address.isBlank() ? city : address + ", " + city;

        List<String> images = extractImages(detail.path("images"));
        String image = images.isEmpty() ? "" : images.getFirst();
        List<String> amenities = extractAmenities(detail.path("facilities"));
        String description = content(detail.path("description"));
        int stars = stars(firstText(availabilityHotel, "categoryCode", "category")
                .isBlank()
                ? firstText(detail.path("category"), "code", "description")
                : firstText(availabilityHotel, "categoryCode", "category"));

        int availableRooms = offers.stream()
                .mapToInt(offer -> ((Number) offer.get("available_rooms")).intValue())
                .max()
                .orElse(requestedRooms);
        BigDecimal nightly = (BigDecimal) lowestOffer.get("price_per_night");
        String currency = (String) lowestOffer.get("currency");
        Double latitude = decimal(availabilityHotel.path("latitude"));
        Double longitude = decimal(availabilityHotel.path("longitude"));
        if (latitude == null) latitude = decimal(detail.path("coordinates").path("latitude"));
        if (longitude == null) longitude = decimal(detail.path("coordinates").path("longitude"));
        if (latitude == null) latitude = searchedLocation.latitude();
        if (longitude == null) longitude = searchedLocation.longitude();

        Map<String, Object> hotel = new LinkedHashMap<>();
        hotel.put("id", "hotelbeds-" + code);
        hotel.put("source", "hotelbeds");
        hotel.put("partner_name", "Hotelbeds");
        hotel.put("provider_accommodation_id", code);
        hotel.put("name", name);
        hotel.put("title", name);
        hotel.put("city", city);
        hotel.put("country", country);
        hotel.put("location_name", locationName);
        hotel.put("image_url", image.isBlank() ? null : image);
        hotel.put("gallery_images", images);
        hotel.put("latitude", latitude);
        hotel.put("longitude", longitude);
        hotel.put("price", nightly);
        hotel.put("price_per_night", nightly);
        hotel.put("price_currency", currency);
        hotel.put("currency", currency);
        hotel.put("tax_and_fees_percentage", BigDecimal.ZERO);
        hotel.put("stars", stars);
        hotel.put("rating_source", "hotelbeds_category");
        hotel.put("availability_known", true);
        hotel.put("available_rooms", availableRooms);
        hotel.put("description", description);
        hotel.put("amenities", amenities);
        hotel.put("room_types", offers.stream()
                .map(offer -> Map.<String, Object>of(
                        "name", offer.get("room_name"),
                        "room_name", offer.get("room_name")))
                .distinct()
                .toList());
        hotel.put("offers", offers);
        hotel.put("partner_listing_id", null);
        return hotel;
    }

    private List<Map<String, Object>> extractOffers(
            JsonNode hotel,
            long nights,
            int requestedRooms) {
        List<Map<String, Object>> offers = new ArrayList<>();
        JsonNode rooms = hotel.path("rooms");
        if (!rooms.isArray()) return offers;
        for (JsonNode room : rooms) {
            String roomName = firstText(room, "name", "roomName", "code", "roomCode");
            JsonNode rates = room.path("rates");
            if (!rates.isArray()) continue;
            for (JsonNode rate : rates) {
                BigDecimal total = decimalValue(rate.path("sellingRate"));
                if (total == null || total.signum() <= 0) {
                    total = decimalValue(rate.path("net"));
                }
                String currency = firstText(rate, "currency");
                if (total == null || total.signum() <= 0
                        || !currency.matches("(?i)[a-z]{3}")) continue;
                int rateRooms = positiveInt(rate.path("rooms"), requestedRooms);
                BigDecimal nightly = total.divide(
                        BigDecimal.valueOf(Math.max(1, nights) * rateRooms),
                        2,
                        RoundingMode.HALF_UP);
                int allotment = positiveInt(rate.path("allotment"), rateRooms);
                String board = firstText(rate, "boardName", "boardCode");
                String rateClass = firstText(rate, "rateClass", "rateType");
                Map<String, Object> offer = new LinkedHashMap<>();
                offer.put("id", roomName + "-" + offers.size());
                offer.put("room_name", roomName.isBlank() ? "Room" : roomName);
                offer.put("name", board.isBlank() ? rateClass : board);
                offer.put("price", nightly);
                offer.put("price_per_night", nightly);
                offer.put("stay_total", total);
                offer.put("currency", currency.toUpperCase(Locale.ROOT));
                offer.put("source", "hotelbeds");
                offer.put("rooms", rateRooms);
                offer.put("available_rooms", allotment);
                offer.put("rate_type", firstText(rate, "rateType"));
                offer.put("conditions", cancellationDescription(
                        rate.path("cancellationPolicies")));
                // Hotelbeds rateKey is intentionally not propagated. This integration
                // is read-only and booking remains inside Zentrip's simulator.
                offers.add(offer);
            }
        }
        offers.sort(Comparator.comparing(
                offer -> (BigDecimal) offer.get("price_per_night")));
        return offers.stream().limit(MAX_OFFERS_PER_HOTEL).toList();
    }

    private void applyAuthentication(HttpHeaders headers) {
        headers.set("Api-key", apiKey);
        headers.set("X-Signature", signature());
    }

    private String signature() {
        try {
            String material = apiKey + apiSecret + clock.instant().getEpochSecond();
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(material.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (java.security.NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }

    private void logProviderFailure(String operation, RestClientResponseException exception) {
        String requestId = "";
        if (exception.getResponseHeaders() != null) {
            requestId = firstNonBlank(
                    exception.getResponseHeaders().getFirst("X-Request-Id"),
                    exception.getResponseHeaders().getFirst("X-Request-ID"),
                    exception.getResponseHeaders().getFirst("X-Correlation-Id"));
        }
        String code = "";
        String message = "";
        try {
            JsonNode body = JSON.readTree(exception.getResponseBodyAsString());
            JsonNode error = body.path("error");
            if (error.isMissingNode() || error.isNull()) error = body;
            code = firstText(error, "code", "errorCode", "statusCode");
            message = safeMessage(firstText(error, "message", "description", "error"));
        } catch (Exception ignored) {
            // Keep provider errors safe and useful even if the response is not JSON.
        }
        LOG.warn(
                "Hotelbeds {} failed: status={}, errorCode={}, message={}, requestId={}",
                operation,
                exception.getStatusCode().value(),
                code,
                message,
                requestId);
    }

    private static List<JsonNode> hotelNodes(JsonNode container) {
        JsonNode values = container.path("hotels");
        if (!values.isArray()) values = container.path("hotel");
        if (!values.isArray() && container.isArray()) values = container;
        if (!values.isArray()) return List.of();
        List<JsonNode> results = new ArrayList<>();
        values.forEach(results::add);
        return results;
    }

    private static List<String> extractImages(JsonNode images) {
        if (!images.isArray()) return List.of();
        LinkedHashSet<String> urls = new LinkedHashSet<>();
        for (JsonNode image : images) {
            String path = firstText(image, "path", "url");
            if (path.startsWith("http://")) path = "https://" + path.substring(7);
            if (path.startsWith("https://")) urls.add(path);
            if (urls.size() >= 8) break;
        }
        return List.copyOf(urls);
    }

    private static List<String> extractAmenities(JsonNode facilities) {
        if (!facilities.isArray()) return List.of();
        LinkedHashSet<String> values = new LinkedHashSet<>();
        for (JsonNode facility : facilities) {
            String description = content(facility.path("description"));
            if (description.isBlank()) description = firstText(facility, "description", "name");
            if (!description.isBlank()) values.add(description);
            if (values.size() >= 20) break;
        }
        return List.copyOf(values);
    }

    private static String cancellationDescription(JsonNode policies) {
        if (!policies.isArray() || policies.isEmpty()) return "";
        JsonNode policy = policies.get(0);
        String from = firstText(policy, "from");
        String amount = firstText(policy, "amount");
        String currency = firstText(policy, "currency");
        if (!amount.isBlank()) {
            return "Cancellation fee " + amount
                    + (currency.isBlank() ? "" : " " + currency)
                    + (from.isBlank() ? "" : " from " + from);
        }
        return firstText(policy, "description");
    }

    private static String content(JsonNode node) {
        if (node == null || node.isMissingNode() || node.isNull()) return "";
        if (node.isTextual()) return node.asText("").trim();
        return firstText(node, "content", "name", "description");
    }

    private static int stars(String category) {
        if (category == null) return 0;
        for (int index = 0; index < category.length(); index++) {
            char character = category.charAt(index);
            if (character >= '1' && character <= '5') return character - '0';
        }
        return 0;
    }

    private static BigDecimal decimalValue(JsonNode value) {
        if (value == null || value.isMissingNode() || value.isNull()) return null;
        try {
            BigDecimal parsed = new BigDecimal(value.asText());
            return parsed.signum() >= 0 ? parsed : null;
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static Double decimal(JsonNode value) {
        if (value == null || value.isMissingNode() || value.isNull()) return null;
        try {
            double parsed = value.isNumber()
                    ? value.doubleValue() : Double.parseDouble(value.asText());
            return Double.isFinite(parsed) ? parsed : null;
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static int positiveInt(JsonNode value, int fallback) {
        if (value != null && value.canConvertToInt()) {
            int parsed = value.asInt();
            if (parsed > 0) return parsed;
        }
        return Math.max(1, fallback);
    }

    private static String firstText(JsonNode node, String... fields) {
        if (node == null || node.isMissingNode() || node.isNull()) return "";
        for (String field : fields) {
            JsonNode value = node.path(field);
            if (value.isValueNode() && !value.asText("").isBlank()) {
                return value.asText("").trim();
            }
        }
        return "";
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) return value.trim();
        }
        return "";
    }

    private static String safeMessage(String message) {
        if (message == null) return "";
        return message.replaceAll("[\\r\\n\\t]+", " ")
                .replaceAll("\\s{2,}", " ")
                .trim()
                .substring(0, Math.min(240, message.trim().length()));
    }

    private static String normalizeBaseUrl(String value) {
        String baseUrl = value == null || value.isBlank()
                ? "https://api.test.hotelbeds.com"
                : value.trim().replaceAll("/+$", "");
        if (!baseUrl.startsWith("https://")) {
            throw new IllegalArgumentException("Hotelbeds base URL must use HTTPS");
        }
        return baseUrl;
    }

    private static UnifiedInventoryService.SourceOutcome unavailable(String warning) {
        return new UnifiedInventoryService.SourceOutcome(List.of(), List.of(warning));
    }
}

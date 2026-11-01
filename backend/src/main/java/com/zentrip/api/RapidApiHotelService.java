package com.zentrip.api;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;

@Service
public class RapidApiHotelService {
    private static final Logger LOG = LoggerFactory.getLogger(RapidApiHotelService.class);
    private static final String API_HOST = "booking-com15.p.rapidapi.com";
    private static final String API_BASE_URL = "https://" + API_HOST;
    private static final String DESTINATION_PATH = "/api/v1/hotels/searchDestination";
    private static final String SEARCH_PATH = "/api/v1/hotels/searchHotels";
    private static final ObjectMapper ERROR_JSON = new ObjectMapper();

    private final String apiKey;
    private final RestClient restClient;

    public RapidApiHotelService(
            @Value("${rapidapi.key:}") String apiKey,
            @Value("${rapidapi.enabled:true}") boolean enabled,
            RestClient.Builder restClientBuilder) {
        this.apiKey = enabled && apiKey != null ? apiKey.trim() : "";
        this.restClient = restClientBuilder.baseUrl(API_BASE_URL).build();
    }

    public boolean isConfigured() {
        return !apiKey.isBlank();
    }

    public SearchOutcome searchHotelsWithWarnings(
            String city,
            LocalDate checkIn,
            LocalDate checkOut,
            int rooms,
            int guests,
            String currency) {
        String normalizedCity = city == null ? "" : city.trim();
        long nights = checkIn == null || checkOut == null
                ? 0
                : ChronoUnit.DAYS.between(checkIn, checkOut);
        if (normalizedCity.isBlank() || checkIn == null || checkOut == null
                || nights < 1 || nights > 99 || rooms < 1 || rooms > 10
                || guests < 1 || guests > 20) {
            return new SearchOutcome(List.of(), List.of());
        }
        if (!isConfigured()) {
            return new SearchOutcome(
                    List.of(),
                    List.of("Booking.com RapidAPI hotel search is not configured."));
        }

        String operation = "destination lookup";
        try {
            JsonNode destinationResponse = get(
                    DESTINATION_PATH, Map.of("query", normalizedCity));
            JsonNode destination = selectDestination(destinationResponse, normalizedCity);
            String destinationId = firstText(
                    destination, "dest_id", "destId", "destination_id", "destinationId");
            if (destinationId.isBlank()) {
                return new SearchOutcome(
                        List.of(),
                        List.of("Booking.com RapidAPI could not resolve that destination."));
            }

            operation = "hotel search";
            Map<String, String> params = new LinkedHashMap<>();
            params.put("page_number", "1");
            params.put("arrival_date", checkIn.toString());
            params.put("departure_date", checkOut.toString());
            params.put("dest_id", destinationId);
            params.put("room_qty", Integer.toString(rooms));
            params.put("adults", Integer.toString(guests));
            params.put("currency_code", normalizeCurrency(currency));
            params.put("temperature_unit", "c");
            params.put("units", "metric");

            JsonNode searchResponse = get(SEARCH_PATH, params);
            List<JsonNode> results = arrayAt(
                    searchResponse,
                    "data.hotels",
                    "data.results",
                    "data.result.hotels",
                    "data.results.hotels",
                    "data.result",
                    "data",
                    "hotels",
                    "results",
                    "result.hotels",
                    "result.results",
                    "result",
                    "properties");
            if (results.isEmpty()) {
                String providerStatus = firstText(searchResponse, "status", "success");
                String providerMessage = sanitizeProviderMessage(
                        firstText(searchResponse, "message", "error.message", "error"),
                        apiKey);
                LOG.info(
                        "Booking.com RapidAPI hotel search returned no parsed results: status={}, message={}, responseFields={}, dataShape={}",
                        providerStatus.isBlank() ? "unavailable" : providerStatus,
                        providerMessage.isBlank() ? "none" : providerMessage,
                        objectFields(searchResponse),
                        nodeShape(nodeAt(searchResponse, "data")));
            }
            List<Map<String, Object>> hotels = new ArrayList<>();
            for (JsonNode result : results) {
                Map<String, Object> hotel = normalizeHotel(
                        result,
                        normalizedCity,
                        text(destination, "country", "country_name", "countryName"),
                        nights,
                        rooms,
                        normalizeCurrency(currency));
                if (hotel != null) hotels.add(hotel);
            }
            return new SearchOutcome(List.copyOf(hotels), List.of());
        } catch (RestClientResponseException exception) {
            logProviderFailure(operation, exception);
            int status = exception.getStatusCode().value();
            String warning = switch (status) {
                case 401, 403 ->
                        "Booking.com RapidAPI access was denied. Check the RapidAPI subscription and key.";
                case 429 -> "Booking.com RapidAPI is temporarily rate-limiting hotel searches.";
                default -> "Booking.com hotel results are temporarily unavailable.";
            };
            return new SearchOutcome(List.of(), List.of(warning));
        } catch (RestClientException exception) {
            LOG.warn("Booking.com RapidAPI {} could not reach the provider", operation);
            return new SearchOutcome(
                    List.of(),
                    List.of("Booking.com hotel results are temporarily unavailable."));
        }
    }

    private JsonNode get(String path, Map<String, String> params) {
        return restClient.get()
                .uri(builder -> {
                    var uri = builder.path(path);
                    params.forEach((name, value) -> uri.queryParam(name, value));
                    return uri.build();
                })
                .header("x-rapidapi-host", API_HOST)
                .header("x-rapidapi-key", apiKey)
                .accept(MediaType.APPLICATION_JSON)
                .retrieve()
                .body(JsonNode.class);
    }

    private static JsonNode selectDestination(JsonNode response, String city) {
        List<JsonNode> candidates = arrayAt(
                response,
                "data",
                "data.destinations",
                "data.results",
                "data.result",
                "destinations",
                "results",
                "suggestions");
        String query = city.trim().toLowerCase(Locale.ROOT);
        JsonNode best = null;
        int bestScore = Integer.MIN_VALUE;
        for (JsonNode candidate : candidates) {
            String id = firstText(
                    candidate, "dest_id", "destId", "destination_id", "destinationId");
            if (id.isBlank()) continue;
            String name = text(candidate, "name", "city_name", "cityName", "label");
            String type = text(candidate, "dest_type", "destType", "type")
                    .toLowerCase(Locale.ROOT);
            String normalizedName = name.toLowerCase(Locale.ROOT);
            int score = type.contains("city") ? 5 : 0;
            if (normalizedName.equals(query)) score += 10;
            else if (!normalizedName.isBlank() && normalizedName.contains(query)) score += 3;
            if (score > bestScore) {
                best = candidate;
                bestScore = score;
            }
        }
        return best;
    }

    private static Map<String, Object> normalizeHotel(
            JsonNode hotel,
            String searchedCity,
            String searchedCountry,
            long nights,
            int rooms,
            String requestedCurrency) {
        String name = text(
                hotel, "hotel_name", "hotelName", "name", "title", "property.name");
        if (name.isBlank()) return null;

        String providerId = firstText(
                hotel, "hotel_id", "hotelId", "id", "property_id", "property.id");
        if (providerId.isBlank()) {
            providerId = Integer.toUnsignedString(
                    (name + "|" + text(hotel, "address", "property.address")).hashCode());
        }
        String city = firstText(
                hotel, "city", "city_name", "cityName", "property.city");
        if (city.isBlank()) city = searchedCity;
        String country = firstText(
                hotel, "country", "country_name", "countryName", "property.country");
        if (country.isBlank()) country = searchedCountry;
        String address = text(
                hotel, "address", "address_trans", "addressTrans",
                "location.address", "property.address");

        String currency = normalizeCurrency(firstText(
                hotel,
                "currency_code",
                "currencyCode",
                "price_currency",
                "priceCurrency",
                "price_breakdown.gross_price.currency",
                "priceBreakdown.grossPrice.currency",
                "composite_price_breakdown.gross_amount.currency",
                "compositePriceBreakdown.grossAmount.currency",
                "currency"));
        if (currency.isBlank()) currency = requestedCurrency;

        BigDecimal pricePerNight = firstDecimal(
                hotel,
                "price_per_night",
                "pricePerNight",
                "per_night_price",
                "price_per_day",
                "pricePerDay");
        BigDecimal totalPrice = firstDecimal(
                hotel,
                "min_total_price",
                "minTotalPrice",
                "total_price",
                "totalPrice",
                "price_breakdown.gross_price.value",
                "priceBreakdown.grossPrice.value",
                "composite_price_breakdown.gross_amount.value",
                "compositePriceBreakdown.grossAmount.value",
                "gross_price.value",
                "grossPrice.value");
        if (pricePerNight == null && totalPrice != null && nights > 0 && rooms > 0) {
            pricePerNight = totalPrice.divide(
                    BigDecimal.valueOf(nights * rooms), 2, RoundingMode.HALF_UP);
        }

        List<String> images = stringsAt(
                hotel, "gallery_images", "galleryImages", "photoUrls", "photo_urls", "photos");
        String image = firstText(
                hotel,
                "photo_main_url",
                "photoMainUrl",
                "main_photo_url",
                "mainPhotoUrl",
                "image_url",
                "imageUrl",
                "image",
                "thumbnail_url",
                "thumbnailUrl");
        if (!isHttpImage(image) && !images.isEmpty()) image = images.getFirst();
        if (!isHttpImage(image)) image = "";
        images = images.stream().filter(RapidApiHotelService::isHttpImage)
                .distinct().limit(12).toList();
        if (images.isEmpty() && !image.isBlank()) images = List.of(image);

        Map<String, Object> normalized = new LinkedHashMap<>();
        normalized.put("id", "rapidapi-" + providerId);
        normalized.put("source", "rapidapi");
        normalized.put("partner_name", "Booking.com");
        normalized.put("provider_accommodation_id", providerId);
        normalized.put("name", name);
        normalized.put("title", name);
        normalized.put("city", city);
        normalized.put("country", country);
        normalized.put("address", address);
        normalized.put("location_name", address.isBlank() ? city : address);
        normalized.put("latitude", firstDecimal(hotel, "latitude", "lat", "property.latitude"));
        normalized.put("longitude", firstDecimal(hotel, "longitude", "lon", "lng", "property.longitude"));
        normalized.put("image_url", image.isBlank() ? null : image);
        normalized.put("gallery_images", images);
        normalized.put("price_per_night", pricePerNight);
        normalized.put("price", pricePerNight);
        normalized.put("total_price", totalPrice);
        normalized.put("price_currency", currency);
        normalized.put("currency", currency);
        normalized.put("tax_and_fees_percentage", BigDecimal.ZERO);
        normalized.put("review_score", firstDecimal(
                hotel, "review_score", "reviewScore", "review_rating", "reviewRating"));
        normalized.put("review_count", firstInteger(
                hotel, "review_nr", "reviewCount", "review_count"));
        normalized.put("rating_source", "booking_com");
        normalized.put("stars", firstInteger(hotel, "class", "stars", "star_rating", "propertyClass"));
        normalized.put("description", text(
                hotel, "description", "hotel_description", "hotelDescription"));
        normalized.put("amenities", stringsAt(hotel, "amenities", "facilities"));
        normalized.put("available_rooms", firstInteger(
                hotel, "available_rooms", "availableRooms", "rooms_available"));
        normalized.put("availability_known", false);
        normalized.put("offers", List.of());
        normalized.put("room_types", List.of());
        return normalized;
    }

    private static List<JsonNode> arrayAt(JsonNode root, String... paths) {
        if (root == null || root.isMissingNode() || root.isNull()) return List.of();
        if (root.isArray()) {
            List<JsonNode> values = new ArrayList<>();
            root.forEach(values::add);
            return values;
        }
        for (String path : paths) {
            JsonNode candidate = nodeAt(root, path);
            if (candidate.isArray()) {
                List<JsonNode> values = new ArrayList<>();
                candidate.forEach(values::add);
                return values;
            }
        }
        return List.of();
    }

    private static List<String> stringsAt(JsonNode root, String... paths) {
        for (String path : paths) {
            JsonNode values = nodeAt(root, path);
            if (!values.isArray()) continue;
            LinkedHashSet<String> result = new LinkedHashSet<>();
            values.forEach(value -> {
                String text = value.isValueNode()
                        ? value.asText()
                        : firstText(value, "url", "src", "name", "label", "title");
                if (!text.isBlank()) result.add(text.trim());
            });
            return result.stream().limit(40).toList();
        }
        return List.of();
    }

    private static JsonNode nodeAt(JsonNode root, String path) {
        JsonNode current = root;
        for (String part : path.split("\\.")) {
            if (current == null || current.isNull() || current.isMissingNode()) {
                return com.fasterxml.jackson.databind.node.MissingNode.getInstance();
            }
            current = current.path(part);
        }
        return current;
    }

    private static String firstText(JsonNode root, String... paths) {
        for (String path : paths) {
            JsonNode value = nodeAt(root, path);
            if (!value.isMissingNode() && !value.isNull() && value.isValueNode()) {
                String text = value.asText().trim();
                if (!text.isBlank()) return text;
            }
        }
        return "";
    }

    private static String text(JsonNode root, String... paths) {
        return firstText(root, paths);
    }

    private static BigDecimal firstDecimal(JsonNode root, String... paths) {
        String value = firstText(root, paths);
        if (value.isBlank()) return null;
        try {
            BigDecimal parsed = new BigDecimal(value);
            return parsed.signum() >= 0 ? parsed : null;
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static Integer firstInteger(JsonNode root, String... paths) {
        BigDecimal value = firstDecimal(root, paths);
        return value == null ? null : value.setScale(0, RoundingMode.HALF_UP).intValue();
    }

    private static String normalizeCurrency(String value) {
        String normalized = value == null ? "" : value.trim().toUpperCase(Locale.ROOT);
        return normalized.matches("[A-Z]{3}") ? normalized : "";
    }

    private static boolean isHttpImage(String value) {
        return value != null && value.trim().matches("(?i)^https://\\S+$");
    }

    private void logProviderFailure(
            String operation, RestClientResponseException exception) {
        String requestId = exception.getResponseHeaders() == null
                ? ""
                : firstHeader(
                        exception.getResponseHeaders().getFirst("x-rapidapi-request-id"),
                        exception.getResponseHeaders().getFirst("x-request-id"));
        String body = exception.getResponseBodyAsString();
        String errorCode = providerErrorField(
                body, "code", "errorCode", "error_code", "error.code", "type");
        String message = providerErrorField(
                body, "message", "error.message", "error_description", "detail", "error");
        if (message.isBlank()) message = body;
        message = sanitizeProviderMessage(message, apiKey);
        LOG.warn(
                "Booking.com RapidAPI {} failed: status={}, errorCode={}, message={}, requestId={}, x-rapidapi-key=[MASKED]",
                operation,
                exception.getStatusCode().value(),
                errorCode.isBlank() ? "unavailable" : sanitizeProviderMessage(errorCode, apiKey),
                message.isBlank() ? "No provider error message was returned" : message,
                requestId.isBlank() ? "unavailable" : requestId);
    }

    private static String providerErrorField(String body, String... paths) {
        if (body == null || body.isBlank()) return "";
        try {
            return firstText(ERROR_JSON.readTree(body), paths);
        } catch (Exception ignored) {
            return "";
        }
    }

    private static String sanitizeProviderMessage(String value, String apiKey) {
        if (value == null || value.isBlank()) return "";
        String safe = value;
        if (apiKey != null && !apiKey.isBlank()) {
            safe = safe.replace(apiKey, "[MASKED]");
        }
        safe = safe
                .replaceAll(
                        "(?i)(x-rapidapi-key\\s*[:=]\\s*[\"']?)[^\\s,}\"']+",
                        "$1[MASKED]")
                .replaceAll(
                        "(?i)(authorization\\s*[:=]\\s*[\"']?bearer\\s+)[^\\s,}\"']+",
                        "$1[MASKED]")
                .replaceAll("[\\r\\n\\t]+", " ")
                .trim();
        return safe.length() > 400 ? safe.substring(0, 400) : safe;
    }

    private static String firstHeader(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) return value.trim();
        }
        return "";
    }

    private static String objectFields(JsonNode node) {
        if (node == null || !node.isObject()) return "";
        List<String> fields = new ArrayList<>();
        node.fieldNames().forEachRemaining(fields::add);
        return String.join(",", fields.stream().limit(30).toList());
    }

    private static String nodeShape(JsonNode node) {
        if (node == null || node.isMissingNode()) return "missing";
        if (node.isNull()) return "null";
        if (node.isObject()) return "object[" + objectFields(node) + "]";
        if (node.isArray()) return "array[" + node.size() + "]";
        return node.getNodeType().name().toLowerCase(Locale.ROOT);
    }

    public record SearchOutcome(
            List<Map<String, Object>> hotels,
            List<String> warnings) {
        public SearchOutcome {
            hotels = hotels == null ? List.of() : List.copyOf(hotels);
            warnings = warnings == null ? List.of() : List.copyOf(warnings);
        }
    }
}

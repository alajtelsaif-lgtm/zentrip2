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

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * Read-only hotel discovery from Xotelo. Xotelo does not create reservations;
 * returned records continue through Zentrip's existing simulated checkout.
 */
@Service
public class XoteloHotelService {
    private static final Logger LOG = LoggerFactory.getLogger(XoteloHotelService.class);
    private static final String API_BASE_URL = "https://data.xotelo.com/api";
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final Map<String, String> VERIFIED_DEFAULT_LOCATION_KEYS =
            Map.of("phuket", "g297930");

    private final RestClient restClient;
    private final Map<String, String> locationKeys;

    public XoteloHotelService(
            @Value("${xotelo.location-keys:{}}") String locationKeysJson,
            RestClient.Builder restClientBuilder) {
        this.restClient = restClientBuilder.baseUrl(API_BASE_URL).build();
        this.locationKeys = parseLocationKeys(locationKeysJson);
    }

    public SearchOutcome searchHotels(String city) {
        String normalizedCity = city == null ? "" : city.trim();
        if (normalizedCity.isBlank()) return new SearchOutcome(List.of(), List.of());

        String locationKey = locationKeyFor(normalizedCity);
        if (locationKey == null) {
            // No city-to-Tripadvisor-key lookup exists in Xotelo's free direct API.
            return new SearchOutcome(List.of(), List.of());
        }

        try {
            JsonNode response = restClient.get()
                    .uri(uri -> uri.path("/list")
                            .queryParam("location_key", locationKey)
                            .queryParam("offset", 0)
                            .queryParam("limit", 20)
                            .queryParam("sort", "best_value")
                            .build())
                    .accept(MediaType.APPLICATION_JSON)
                    .retrieve()
                    .body(JsonNode.class);

            if (response == null || !response.path("error").isNull()
                    && !response.path("error").isMissingNode()) {
                String message = response == null
                        ? "empty response"
                        : response.path("error").toString();
                LOG.warn("Xotelo hotel-data lookup failed for configured destination: {}", message);
                return new SearchOutcome(
                        List.of(),
                        List.of("Xotelo hotel information is temporarily unavailable."));
            }

            JsonNode listings = response.path("result").path("list");
            if (!listings.isArray()) {
                return new SearchOutcome(List.of(), List.of());
            }
            List<Map<String, Object>> hotels = new ArrayList<>();
            for (JsonNode listing : listings) {
                Map<String, Object> hotel = normalize(listing, normalizedCity);
                if (hotel != null) hotels.add(hotel);
            }
            return new SearchOutcome(List.copyOf(hotels), List.of());
        } catch (RestClientException exception) {
            LOG.warn("Xotelo hotel-data lookup failed for configured destination", exception);
            return new SearchOutcome(
                    List.of(),
                    List.of("Xotelo hotel information is temporarily unavailable."));
        }
    }

    private String locationKeyFor(String city) {
        String exact = locationKeys.get(city.toLowerCase(Locale.ROOT));
        if (exact != null) return exact;
        String normalized = city.trim().toLowerCase(Locale.ROOT);
        for (Map.Entry<String, String> entry : locationKeys.entrySet()) {
            if (entry.getKey().equals(normalized)) return entry.getValue();
        }
        return null;
    }

    private static Map<String, String> parseLocationKeys(String json) {
        Map<String, String> keys =
                new LinkedHashMap<>(VERIFIED_DEFAULT_LOCATION_KEYS);
        if (json == null || json.isBlank()) return Map.copyOf(keys);
        try {
            JsonNode root = JSON.readTree(json);
            if (root == null || !root.isObject()) return Map.copyOf(keys);
            Iterator<Map.Entry<String, JsonNode>> fields = root.fields();
            while (fields.hasNext()) {
                Map.Entry<String, JsonNode> field = fields.next();
                String city = field.getKey().trim().toLowerCase(Locale.ROOT);
                String key = field.getValue().asText("").trim();
                if (!city.isBlank() && key.matches("[A-Za-z0-9_-]{2,80}")) {
                    keys.put(city, key);
                }
            }
            return Map.copyOf(keys);
        } catch (Exception exception) {
            LOG.warn("Ignoring invalid XOTELO_LOCATION_KEYS_JSON; expected a city-to-key JSON object");
            return Map.copyOf(keys);
        }
    }

    private static Map<String, Object> normalize(JsonNode listing, String searchedCity) {
        String name = text(listing, "name");
        String providerKey = text(listing, "key");
        if (name.isBlank() || providerKey.isBlank()) return null;

        JsonNode reviews = listing.path("review_summary");
        JsonNode range = listing.path("price_ranges");
        JsonNode geo = listing.path("geo");
        BigDecimal minimum = decimal(range.path("minimum"));
        BigDecimal maximum = decimal(range.path("maximum"));
        if (minimum == null || minimum.signum() <= 0) return null;
        String image = text(listing, "image");
        if (!image.startsWith("https://") && !image.startsWith("http://")) image = "";

        Map<String, Object> hotel = new LinkedHashMap<>();
        hotel.put("id", "xotelo-" + providerKey);
        hotel.put("source", "xotelo");
        hotel.put("partner_name", "Xotelo");
        hotel.put("provider_accommodation_id", providerKey);
        hotel.put("name", name);
        hotel.put("title", name);
        hotel.put("city", searchedCity);
        hotel.put("country", "");
        hotel.put("location_name", searchedCity);
        hotel.put("image_url", image.isBlank() ? null : image);
        hotel.put("gallery_images", image.isBlank() ? List.of() : List.of(image));
        hotel.put("latitude", decimal(geo.path("latitude")));
        hotel.put("longitude", decimal(geo.path("longitude")));
        // This is a displayed estimate, not confirmed availability or a partner rate.
        hotel.put("price", minimum);
        hotel.put("price_per_night", minimum);
        hotel.put("price_range_minimum", minimum);
        hotel.put("price_range_maximum", maximum);
        hotel.put("price_currency", "USD");
        hotel.put("currency", "USD");
        hotel.put("tax_and_fees_percentage", BigDecimal.ZERO);
        hotel.put("review_score", decimal(reviews.path("rating")));
        hotel.put("rating", decimal(reviews.path("rating")));
        hotel.put("review_count", integer(reviews.path("count")));
        hotel.put("rating_source", "tripadvisor");
        hotel.put("availability_known", false);
        hotel.put("available_rooms", 0);
        hotel.put("description", "");
        hotel.put("amenities", List.of());
        hotel.put("room_types", List.of());
        hotel.put("offers", List.of());
        hotel.put("partner_listing_id", null);
        hotel.put("tripadvisor_url", text(listing, "url"));
        return hotel;
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node == null ? null : node.get(field);
        return value == null || value.isNull() ? "" : value.asText("").trim();
    }

    private static BigDecimal decimal(JsonNode value) {
        if (value == null || value.isNull() || !value.isNumber()) return null;
        double number = value.asDouble();
        return Double.isFinite(number) ? BigDecimal.valueOf(number) : null;
    }

    private static Integer integer(JsonNode value) {
        return value == null || !value.isIntegralNumber() ? null : value.asInt();
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

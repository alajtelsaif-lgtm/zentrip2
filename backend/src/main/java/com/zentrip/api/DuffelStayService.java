package com.zentrip.api;

import com.fasterxml.jackson.databind.JsonNode;
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
        long nights = checkIn == null || checkOut == null
                ? 0
                : java.time.temporal.ChronoUnit.DAYS.between(checkIn, checkOut);
        if (!isConfigured()
                || !validCoordinate(latitude, -90, 90)
                || !validCoordinate(longitude, -180, 180)
                || checkIn == null || checkOut == null || nights < 1 || nights > 99
                || rooms < 1 || rooms > 10 || guests < 1 || guests > 20) {
            return List.of();
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
            if (results == null || !results.isArray()) return List.of();

            List<Map<String, Object>> hotels = new ArrayList<>();
            for (JsonNode result : results) {
                Map<String, Object> hotel = normalizeResult(result, city, nights, rooms);
                if (hotel != null) hotels.add(hotel);
            }
            return List.copyOf(hotels);
        } catch (RestClientResponseException exception) {
            LOG.warn("Duffel stays search failed with HTTP status {}",
                    exception.getStatusCode().value());
            return List.of();
        } catch (RestClientException exception) {
            LOG.warn("Duffel stays search could not reach the provider");
            return List.of();
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
        hotel.put("review_count", reviewCount);
        hotel.put("price_per_night", nightlyAmount);
        hotel.put("price_currency", currency.toUpperCase(java.util.Locale.ROOT));
        hotel.put("tax_and_fees_percentage", 0);
        hotel.put("available_rooms", null);
        hotel.put("availability_known", false);
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

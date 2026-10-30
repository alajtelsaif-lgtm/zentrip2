package com.zentrip.api;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Service
public class GooglePlacesRatingSync {
    private static final Logger LOG =
            LoggerFactory.getLogger(GooglePlacesRatingSync.class);
    private static final String PLACES_API = "https://places.googleapis.com/v1";
    private static final String SEARCH_FIELDS = "places.id";
    private static final String DETAIL_FIELDS = "id,rating,userRatingCount";

    private final JdbcTemplate jdbc;
    private final RestClient http;
    private final String apiKey;

    public GooglePlacesRatingSync(
            JdbcTemplate jdbc,
            RestClient.Builder builder,
            @Value("${google.places.api-key:}") String apiKey) {
        this.jdbc = jdbc;
        this.http = builder.build();
        this.apiKey = apiKey.trim();
    }

    @Async
    public void refreshAsync(
            long listingId,
            String hotelName,
            String locationName,
            String googleMapsUrl,
            String placeId) {
        if (apiKey.isBlank()) {
            LOG.warn("Google Places rating sync skipped for hotel listing {}: "
                    + "GOOGLE_PLACES_API_KEY is not configured", listingId);
            return;
        }
        LOG.info("Starting Google Places rating sync for hotel listing {} "
                + "(placeIdPresent={}, mapsUrlPresent={})",
                listingId,
                placeId != null && !placeId.isBlank(),
                googleMapsUrl != null && !googleMapsUrl.isBlank());
        try {
            String resolvedPlaceId = firstNonBlank(
                    placeId, extractPlaceId(googleMapsUrl));
            if (resolvedPlaceId.isBlank()) {
                resolvedPlaceId = searchPlaceId(hotelName, locationName);
            }
            if (resolvedPlaceId.isBlank()) {
                LOG.warn("Google Places rating sync found no place for hotel listing {}",
                        listingId);
                return;
            }
            Map<?, ?> details = http.get()
                    .uri(PLACES_API + "/places/{placeId}", resolvedPlaceId)
                    .header("X-Goog-Api-Key", apiKey)
                    .header("X-Goog-FieldMask", DETAIL_FIELDS)
                    .retrieve()
                    .body(Map.class);
            if (details == null
                    || !(details.get("rating") instanceof Number rating)
                    || !(details.get("userRatingCount") instanceof Number count)) {
                LOG.warn("Google Places returned no rating/count for hotel listing {}",
                        listingId);
                return;
            }
            int updated = jdbc.update("""
                    UPDATE partner_listings
                    SET place_id = ?, google_rating = ?, google_review_count = ?,
                        attributes = JSON_SET(
                            attributes,
                            '$.place_id', ?,
                            '$.google_rating', ?,
                            '$.google_review_count', ?
                        ),
                        updated_at = NOW()
                    WHERE id = ? AND type = 'hotel'
                    """,
                    resolvedPlaceId,
                    rating.doubleValue(),
                    count.intValue(),
                    resolvedPlaceId,
                    rating.doubleValue(),
                    count.intValue(),
                    listingId);
            if (updated != 1) {
                LOG.warn("Google Places rating sync could not update hotel listing {}",
                        listingId);
                return;
            }
            LOG.info("Google Places rating sync completed for hotel listing {} "
                    + "(rating={}, reviewCount={})",
                    listingId, rating.doubleValue(), count.intValue());
        } catch (RestClientResponseException exception) {
            LOG.error("Google Places rating sync failed for hotel listing {} "
                    + "with HTTP status {}: {}",
                    listingId,
                    exception.getStatusCode().value(),
                    responseErrorDetails(exception));
        } catch (RestClientException exception) {
            LOG.error("Google Places rating sync failed for hotel listing {}: {}",
                    listingId, exception.getMessage());
        } catch (DataAccessException exception) {
            LOG.error("Google Places rating sync could not persist values "
                    + "for hotel listing {}", listingId, exception);
        }
    }

    private String searchPlaceId(String hotelName, String locationName) {
        String query = (hotelName + " " + locationName).trim();
        if (query.isBlank()) return "";
        Map<?, ?> response = http.post()
                .uri(PLACES_API + "/places:searchText")
                .header("X-Goog-Api-Key", apiKey)
                .header("X-Goog-FieldMask", SEARCH_FIELDS)
                .body(Map.of("textQuery", query))
                .retrieve()
                .body(Map.class);
        if (response == null || !(response.get("places") instanceof List<?> places)) {
            return "";
        }
        for (Object place : places) {
            if (place instanceof Map<?, ?> fields
                    && fields.get("id") instanceof String id
                    && !id.isBlank()) {
                return id;
            }
        }
        return "";
    }

    private static String extractPlaceId(String value) {
        if (value == null || value.isBlank()) return "";
        String input = value.trim();
        if (input.startsWith("ChIJ")
                || input.matches("[A-Za-z0-9_-]{10,255}")) {
            return input;
        }
        Matcher query = Pattern.compile(
                "(?:place_id|query_place_id)=([^&!]+)", Pattern.CASE_INSENSITIVE)
                .matcher(input);
        if (query.find()) return query.group(1).trim();
        Matcher path = Pattern.compile("!1s(ChIJ[A-Za-z0-9_-]+)").matcher(input);
        if (path.find()) return path.group(1);
        return "";
    }

    private static String firstNonBlank(String first, String second) {
        return first != null && !first.isBlank() ? first.trim() : second;
    }

    private static String responseErrorDetails(RestClientResponseException exception) {
        String details = exception.getResponseBodyAsString()
                .replaceAll("\\p{Cntrl}", " ")
                .trim();
        if (details.isBlank()) return exception.getStatusText();
        return details.length() <= 1000 ? details : details.substring(0, 1000);
    }
}

package com.zentrip.api;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

@Component
public class GooglePlacesRatingStartupSync {
    private static final Logger LOG =
            LoggerFactory.getLogger(GooglePlacesRatingStartupSync.class);

    private final JdbcTemplate jdbc;
    private final GooglePlacesRatingSync sync;
    private final String apiKey;

    public GooglePlacesRatingStartupSync(
            JdbcTemplate jdbc,
            GooglePlacesRatingSync sync,
            @Value("${google.places.api-key:}") String apiKey) {
        this.jdbc = jdbc;
        this.sync = sync;
        this.apiKey = apiKey.trim();
    }

    @EventListener(ApplicationReadyEvent.class)
    public void refreshSeededHotelsMissingGoogleRatings() {
        if (apiKey.isBlank()) {
            LOG.warn("Google Places startup sync skipped: "
                    + "GOOGLE_PLACES_API_KEY is not configured");
            return;
        }
        jdbc.query("""
                SELECT id, title, location_name, google_maps_url, place_id
                FROM partner_listings
                WHERE type = 'hotel' AND active = TRUE
                  AND (google_rating IS NULL OR google_rating = 0
                       OR google_review_count IS NULL OR google_review_count = 0)
                """, (row, index) -> {
            sync.refreshAsync(
                    row.getLong("id"),
                    row.getString("title"),
                    row.getString("location_name"),
                    row.getString("google_maps_url"),
                    row.getString("place_id"));
            return null;
        });
    }
}

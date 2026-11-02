package com.zentrip.api;

import java.util.List;
import java.util.Map;

/**
 * Boundary for landmark discovery providers. The rest of the API consumes
 * normalized place maps and does not depend on OpenTripMap-specific HTTP details.
 */
public interface LandmarkProvider {
    List<Map<String, Object>> searchAttractions(
            String city, String country, String language);

    OpenTripMapAttractionService.SearchOutcome searchAttractionsWithStatus(
            String city, String country, String language);

    OpenTripMapAttractionService.SearchOutcome searchAttractionsWithStatus(
            String city,
            String country,
            String language,
            String category,
            Double latitude,
            Double longitude,
            Double south,
            Double west,
            Double north,
            Double east,
            String xid);

    List<Map<String, Object>> searchAtCoordinates(
            double latitude,
            double longitude,
            String city,
            String country,
            String language);

    List<Map<String, Object>> searchAtCoordinates(
            double latitude,
            double longitude,
            String city,
            String country,
            String language,
            String category);

    List<Map<String, Object>> searchNearby(
            double latitude,
            double longitude,
            double radiusMeters,
            String category,
            String language);

    List<Map<String, Object>> suggestPlaces(
            String query,
            String language,
            Double contextLatitude,
            Double contextLongitude);
}

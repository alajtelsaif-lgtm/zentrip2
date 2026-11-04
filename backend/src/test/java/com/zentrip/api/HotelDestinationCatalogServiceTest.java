package com.zentrip.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

class HotelDestinationCatalogServiceTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final GeoapifyAirportService geoapify = mock(GeoapifyAirportService.class);
    private final HotelDestinationCatalogService service =
            new HotelDestinationCatalogService(jdbc, geoapify);

    @Test
    void returnsEnglishAndArabicNamesFromTheLocalCatalog() {
        when(jdbc.queryForObject(
                eq("SELECT to_regclass('public.hotel_destinations') IS NOT NULL"),
                eq(Boolean.class)))
                .thenReturn(true);
        when(jdbc.queryForList(anyString(), any(Object[].class)))
                .thenReturn(List.of(Map.of(
                        "destination_type", "city",
                        "destination_code", "LON",
                        "name_en", "London",
                        "name_ar", "لندن",
                        "country_code", "GB",
                        "country_name_en", "United Kingdom",
                        "country_name_ar", "المملكة المتحدة",
                        "latitude", 51.5072,
                        "longitude", -0.1276)));

        List<Map<String, Object>> suggestions = service.suggest("lo", "ar");

        assertEquals(1, suggestions.size());
        assertEquals("London", suggestions.getFirst().get("name"));
        assertEquals("لندن", suggestions.getFirst().get("localized_name"));
        assertEquals("LON", suggestions.getFirst().get("destination_code"));
        assertEquals("GB", suggestions.getFirst().get("country_code"));
        assertEquals("المملكة المتحدة",
                suggestions.getFirst().get("country_name_localized"));
    }

    @Test
    void usesAResolvedCityInsteadOfAnOpenTripMapGeonameOrHardcodedMatch() {
        when(jdbc.queryForObject(
                eq("SELECT to_regclass('public.hotel_destinations') IS NOT NULL"),
                eq(Boolean.class)))
                .thenReturn(false);
        when(geoapify.resolveCity("New York", ""))
                .thenReturn(new GeoapifyAirportService.GeocodedPlace(
                        "New York",
                        "New York",
                        "United States",
                        "us",
                        "New York",
                        "New York, NY, USA",
                        "city",
                        "geoapify-new-york",
                        null,
                        40.7127281,
                        -74.0060152));

        List<Map<String, Object>> suggestions = service.suggest("New York", "en");

        assertEquals(1, suggestions.size());
        assertEquals("New York", suggestions.getFirst().get("name"));
        assertEquals("US", suggestions.getFirst().get("country_code"));
        assertEquals("geoapify-new-york", suggestions.getFirst().get("place_id"));
        assertEquals(40.7127281, suggestions.getFirst().get("latitude"));
        assertEquals(-74.0060152, suggestions.getFirst().get("longitude"));
    }

    @Test
    void doesNotInventAPopularDestinationWhenGeocodingReturnsNothing() {
        when(jdbc.queryForObject(
                eq("SELECT to_regclass('public.hotel_destinations') IS NOT NULL"),
                eq(Boolean.class)))
                .thenReturn(false);
        when(geoapify.resolveCity(anyString(), anyString())).thenReturn(null);

        assertEquals(List.of(), service.suggest("Somewhere", "en"));
    }

    @Test
    void returnsCoordinatesAndCountryForGeoapifyCitySuggestions() {
        when(jdbc.queryForObject(
                eq("SELECT to_regclass('public.hotel_destinations') IS NOT NULL"),
                eq(Boolean.class)))
                .thenReturn(false);
        when(geoapify.resolveCity("Zürich", ""))
                .thenReturn(new GeoapifyAirportService.GeocodedPlace(
                        "Zurich", "Zurich", "Switzerland", "CH", "Zurich",
                        "Zurich, Switzerland", "city", "geoapify-zurich",
                        null, 47.3769, 8.5417));

        List<Map<String, Object>> suggestions = service.suggest("Zürich", "en");

        assertEquals(1, suggestions.size());
        assertEquals("CH", suggestions.getFirst().get("country_code"));
        assertEquals(47.3769, suggestions.getFirst().get("latitude"));
        assertEquals(8.5417, suggestions.getFirst().get("longitude"));
    }
}

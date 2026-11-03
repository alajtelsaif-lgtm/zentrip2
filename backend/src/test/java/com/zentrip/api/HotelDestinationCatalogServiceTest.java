package com.zentrip.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
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
    private final OpenTripMapAttractionService openTripMap =
            mock(OpenTripMapAttractionService.class);
    private final HotelDestinationCatalogService service =
            new HotelDestinationCatalogService(jdbc, openTripMap);

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
                        "country_name_en", "United Kingdom",
                        "country_name_ar", "المملكة المتحدة",
                        "latitude", 51.5072,
                        "longitude", -0.1276)));

        List<Map<String, Object>> suggestions = service.suggest("lo", "ar");

        assertEquals(1, suggestions.size());
        assertEquals("London", suggestions.getFirst().get("name"));
        assertEquals("لندن", suggestions.getFirst().get("localized_name"));
        assertEquals("LON", suggestions.getFirst().get("destination_code"));
        assertEquals("المملكة المتحدة",
                suggestions.getFirst().get("country_name_localized"));
    }

    @Test
    void usesOpenTripMapThenPopularCitiesWhenCatalogIsNotInstalled() {
        when(jdbc.queryForObject(
                eq("SELECT to_regclass('public.hotel_destinations') IS NOT NULL"),
                eq(Boolean.class)))
                .thenReturn(false);
        when(openTripMap.suggestDestination("par", "en")).thenReturn(null);

        List<Map<String, Object>> suggestions = service.suggest("par", "en");

        assertTrue(suggestions.stream().anyMatch(
                suggestion -> "Paris".equals(suggestion.get("name"))));
    }

    @Test
    void popularFallbackSupportsEnglishAndArabicPrefixes() {
        when(jdbc.queryForObject(
                eq("SELECT to_regclass('public.hotel_destinations') IS NOT NULL"),
                eq(Boolean.class)))
                .thenReturn(false);
        when(openTripMap.suggestDestination(anyString(), anyString()))
                .thenReturn(null);

        assertPopular("lo", "en", "London");
        assertPopular("par", "en", "Paris");
        assertPopular("دب", "ar", "Dubai");
        assertPopular("القا", "ar", "Cairo");
    }

    private void assertPopular(String query, String language, String expectedName) {
        assertTrue(service.suggest(query, language).stream().anyMatch(
                suggestion -> expectedName.equals(suggestion.get("name"))));
    }

    @Test
    void returnsCoordinatesForAnOpenTripMapGeonameFallback() {
        when(jdbc.queryForObject(
                eq("SELECT to_regclass('public.hotel_destinations') IS NOT NULL"),
                eq(Boolean.class)))
                .thenReturn(false);
        when(openTripMap.suggestDestination("Zürich", "en"))
                .thenReturn(new OpenTripMapAttractionService.DestinationSuggestion(
                        "Zurich", "Switzerland", 47.3769, 8.5417));

        List<Map<String, Object>> suggestions = service.suggest("Zürich", "en");

        assertEquals(1, suggestions.size());
        assertEquals(47.3769, suggestions.getFirst().get("latitude"));
        assertEquals(8.5417, suggestions.getFirst().get("longitude"));
    }
}

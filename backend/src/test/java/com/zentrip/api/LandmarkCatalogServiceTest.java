package com.zentrip.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.server.ResponseStatusException;
import org.junit.jupiter.api.Test;

class LandmarkCatalogServiceTest {
    @Test
    void nameSimilarityNormalizesPunctuationAndArabicDiacritics() {
        assertEquals(1.0,
                LandmarkCatalogService.nameSimilarity(
                        "Red-Castle Museum", "Red Castle Museum"),
                0.0);
        assertEquals(1.0,
                LandmarkCatalogService.nameSimilarity(
                        "قَلْعَةُ طرابلس", "قلعة طرابلس"),
                0.0);
    }

    @Test
    void nameSimilaritySeparatesTyposFromDifferentPlaceNames() {
        assertTrue(LandmarkCatalogService.nameSimilarity(
                "Red Castle Museum", "Red Castle Mseum") >= 0.85);
        assertTrue(LandmarkCatalogService.nameSimilarity(
                "Red Castle Museum", "Saray al Hamra") < 0.85);
        assertEquals(0.0, LandmarkCatalogService.nameSimilarity("", "Leptis Magna"));
    }

    @Test
    void paginatedCatalogReturnsOnlyCanonicalRootsAndTheirAliases() {
        JdbcTemplate jdbc = catalogJdbc();
        when(jdbc.queryForObject(
                contains("SELECT COUNT(*)"), eq(Number.class), any(Object[].class)))
                .thenReturn(1L);
        when(jdbc.queryForList(
                contains("FROM landmark_places p"), any(Object[].class)))
                .thenReturn(List.of(Map.of(
                        "canonical_place_id", "c0a8019e-0000-4000-8000-000000000001",
                        "provider", "opentripmap",
                        "provider_place_id", "N12345",
                        "payload", "{\"name\":\"Leptis Magna\"}",
                        "names", "{\"en\":\"Leptis Magna\"}",
                        "aliases_json", "[\"Leptis Magna\",\"Saray al Hamra\"]",
                        "sources_json", "[\"opentripmap\"]")));
        LandmarkCatalogService service = service(jdbc);

        Map<String, Object> response =
                service.listCanonicalPlaces("", "", "", "", "en", 40, 0);

        assertEquals(1L, response.get("total_count"));
        assertEquals(false, response.get("has_more"));
        Map<?, ?> place = (Map<?, ?>) ((List<?>) response.get("places")).getFirst();
        assertEquals("Leptis Magna", place.get("canonical_name"));
        assertEquals(List.of("Leptis Magna", "Saray al Hamra"), place.get("aliases"));
        assertEquals("N12345", place.get("id"));
        assertEquals("opentripmap", place.get("source_provider"));
        verify(jdbc).queryForList(contains("p.canonical_place_id IS NULL"),
                any(Object[].class));
    }

    @Test
    void ingestRejectsUnsupportedProvidersBeforeWritingRecords() {
        JdbcTemplate jdbc = catalogJdbc();
        LandmarkCatalogService service = service(jdbc);
        Map<String, Object> record = Map.of(
                "xid", "N12345",
                "name", "Example Place",
                "latitude", 32.64,
                "longitude", 14.29);

        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> service.ingestBatch("google_maps", List.of(record)));

        assertEquals(HttpStatus.UNPROCESSABLE_ENTITY, error.getStatusCode());
        verify(jdbc, never()).update(anyString(), any(Object[].class));
    }

    private static JdbcTemplate catalogJdbc() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(contains("to_regclass"), eq(Boolean.class)))
                .thenReturn(true);
        return jdbc;
    }

    private static LandmarkCatalogService service(JdbcTemplate jdbc) {
        return new LandmarkCatalogService(
                jdbc, new ObjectMapper(), mock(LandmarkDuplicateVerifier.class));
    }
}

package com.zentrip.api;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import org.junit.jupiter.api.Test;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.web.server.ResponseStatusException;

class TravelPreferencesControllerTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final TravelPreferencesController controller = new TravelPreferencesController(jdbc);

    @Test
    void requiresAnAuthenticatedUser() {
        assertThrows(ResponseStatusException.class,
                () -> controller.get(new MockHttpServletRequest()));
    }

    @Test
    void returnsDefaultsWhenUserHasNoSavedPreferences() {
        MockHttpServletRequest request = authenticatedRequest();
        when(jdbc.queryForList(anyString(), eq(7L))).thenReturn(List.of());

        Map<String, Object> preferences = controller.get(request);

        assertEquals("balanced", preferences.get("budget_level"));
        assertEquals("balanced", preferences.get("travel_pace"));
        assertEquals(7, preferences.get("trip_duration_days"));
        assertEquals(1, preferences.get("travelers"));
        assertEquals(List.of(), preferences.get("interests"));
    }

    @Test
    void savesAndReturnsValidatedPreferences() {
        MockHttpServletRequest request = authenticatedRequest();
        when(jdbc.update(anyString(), eq(7L), eq("budget"), eq("relaxed"), eq(5),
                eq(2), eq("food,beaches"), eq("Bali"))).thenReturn(1);
        when(jdbc.queryForList(anyString(), eq(7L))).thenReturn(List.of(Map.of(
                "budget_level", "budget",
                "travel_pace", "relaxed",
                "trip_duration_days", 5,
                "travelers", 2,
                "interests", "food,beaches",
                "preferred_destination", "Bali")));

        Map<String, Object> response = controller.save(Map.of(
                "budget_level", "budget",
                "travel_pace", "relaxed",
                "trip_duration_days", 5,
                "travelers", 2,
                "interests", List.of("food", "beaches"),
                "preferred_destination", "Bali"), request);

        @SuppressWarnings("unchecked")
        Map<String, Object> preferences = (Map<String, Object>) response.get("preferences");
        assertEquals("Bali", preferences.get("preferred_destination"));
        assertEquals(List.of("food", "beaches"), preferences.get("interests"));
    }

    private static MockHttpServletRequest authenticatedRequest() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute("authUserId", 7L);
        return request;
    }
}
package com.zentrip.api;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import org.junit.jupiter.api.Test;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.web.server.ResponseStatusException;

class UserSavedDataControllerTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final UserSavedDataController controller = new UserSavedDataController(jdbc);

    private static MockHttpServletRequest customer() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute("authUserId", 7L);
        return request;
    }

    @Test
    void requiresAnAuthenticatedUser() {
        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> controller.favorites(new MockHttpServletRequest()));
        assertEquals(401, error.getStatusCode().value());
    }

    @Test
    void reportsMissingMigrationInsteadOfFailingWithSqlErrors() {
        when(jdbc.queryForObject(
                eq("SELECT to_regclass('public.user_favorites') IS NOT NULL"),
                eq(Boolean.class))).thenReturn(false);
        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> controller.favorites(customer()));
        assertEquals(503, error.getStatusCode().value());
    }

    @Test
    void settingsAcceptOnlyKnownKeysAndNormalizeValues() {
        Map<String, Object> clean = UserSavedDataController.validatedSettings(Map.of(
                "notif_trip", true, "locale", "AR", "currency", "lyd", "theme", "Dark"));
        assertEquals(Map.of("notif_trip", true, "locale", "ar",
                "currency", "LYD", "theme", "dark"), clean);

        assertThrows(ResponseStatusException.class,
                () -> UserSavedDataController.validatedSettings(Map.of("role", "admin")));
        assertThrows(ResponseStatusException.class,
                () -> UserSavedDataController.validatedSettings(Map.of("notif_trip", "yes")));
        assertThrows(ResponseStatusException.class,
                () -> UserSavedDataController.validatedSettings(Map.of("currency", "BTC")));
        assertThrows(ResponseStatusException.class,
                () -> UserSavedDataController.validatedSettings(Map.of()));
    }

    @Test
    void priceAlertsRejectBadInput() {
        when(jdbc.queryForObject(
                eq("SELECT to_regclass('public.user_price_alerts') IS NOT NULL"),
                eq(Boolean.class))).thenReturn(true);
        assertThrows(ResponseStatusException.class, () -> controller.savePriceAlert(
                Map.of("origin_code", "T", "destination_code", "IST",
                        "departure_date", "2035-12-01", "reference_price_usd", 10),
                customer()));
        assertThrows(ResponseStatusException.class, () -> controller.savePriceAlert(
                Map.of("origin_code", "TIP", "destination_code", "IST",
                        "departure_date", "tomorrow", "reference_price_usd", 10),
                customer()));
        assertThrows(ResponseStatusException.class, () -> controller.savePriceAlert(
                Map.of("origin_code", "TIP", "destination_code", "IST",
                        "departure_date", "2035-12-01", "reference_price_usd", -5),
                customer()));
    }
}

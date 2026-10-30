package com.zentrip.api;

import org.junit.jupiter.api.Test;
import org.springframework.boot.ApplicationArguments;
import org.springframework.jdbc.core.JdbcTemplate;
import org.mockito.ArgumentCaptor;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AdminRoleBootstrapTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final ApplicationArguments args = mock(ApplicationArguments.class);

    @Test
    void addsAndBackfillsHotelListingColumnsForExistingDatabases() {
        when(jdbc.queryForObject(
                contains("information_schema.COLUMNS"),
                eq(Integer.class),
                anyString(),
                anyString()))
                .thenAnswer(invocation ->
                        "partner_listings".equals(invocation.getArgument(2)) ? 0 : 1);

        new AdminRoleBootstrap(jdbc, "", "").run(args);

        verify(jdbc).execute(
                "ALTER TABLE partner_listings ADD COLUMN location_name VARCHAR(512) NULL");
        verify(jdbc).execute(
                "ALTER TABLE partner_listings ADD COLUMN google_maps_url VARCHAR(2048) NULL");
        verify(jdbc).execute(
                "ALTER TABLE partner_listings ADD COLUMN place_id VARCHAR(255) NULL");
        verify(jdbc).execute(
                "ALTER TABLE partner_listings ADD COLUMN google_rating "
                        + "DECIMAL(2,1) NOT NULL DEFAULT 0.0");
        verify(jdbc).execute(
                "ALTER TABLE partner_listings ADD COLUMN google_review_count "
                        + "INTEGER NOT NULL DEFAULT 0");
        verify(jdbc).execute(
                "ALTER TABLE partner_listings ADD COLUMN amenities JSONB NULL");
        verify(jdbc).execute(
                "ALTER TABLE partner_listings ADD COLUMN tax_and_fees_percentage "
                        + "DECIMAL(5,2) NOT NULL DEFAULT 12.00");
        verify(jdbc).execute(
                "ALTER TABLE partner_listings ADD COLUMN available_rooms "
                        + "INTEGER NOT NULL DEFAULT 0");
        ArgumentCaptor<String> statements = ArgumentCaptor.forClass(String.class);
        verify(jdbc, times(9)).execute(statements.capture());
        assertTrue(statements.getAllValues().stream()
                .anyMatch(sql -> sql.contains("UPDATE partner_listings")));
    }

    @Test
    void promotesOnlyTheConfiguredExistingAccount() {
        when(jdbc.queryForObject(
                contains("information_schema.COLUMNS"),
                eq(Integer.class),
                anyString(),
                anyString()))
                .thenReturn(1);
        when(jdbc.queryForObject(
                "SELECT COUNT(*) FROM users WHERE email = ?",
                Integer.class,
                "admin@example.com"))
                .thenReturn(1);

        new AdminRoleBootstrap(jdbc, "admin@example.com", "").run(args);

        verify(jdbc).update(
                "UPDATE users SET role = 'admin', partner_id = NULL WHERE email = ?",
                "admin@example.com");
        verify(jdbc).update("UPDATE users SET role = 'customer', partner_id = NULL WHERE role = 'partner'");
        verify(jdbc).update("UPDATE partners SET status = 'inactive'");
    }

    @Test
    void failsClearlyWhenConfiguredAdminAccountDoesNotExist() {
        when(jdbc.queryForObject(
                contains("information_schema.COLUMNS"),
                eq(Integer.class),
                anyString(),
                anyString()))
                .thenReturn(1);
        when(jdbc.queryForObject(
                "SELECT COUNT(*) FROM users WHERE email = ?",
                Integer.class,
                "missing@example.com"))
                .thenReturn(0);

        assertThrows(
                IllegalStateException.class,
                () -> new AdminRoleBootstrap(jdbc, "missing@example.com", "").run(args));

        verify(jdbc, never()).update(
                "UPDATE users SET role = 'admin', partner_id = NULL WHERE email = ?",
                "missing@example.com");
    }

    @Test
    void promotesOnlyConfiguredPartnerAndDeactivatesRemovedCompanies() {
        when(jdbc.queryForObject(
                contains("information_schema.COLUMNS"),
                eq(Integer.class),
                anyString(),
                anyString()))
                .thenReturn(1);
        when(jdbc.queryForObject(
                "SELECT COUNT(*) FROM users WHERE email = ?",
                Integer.class,
                "libyanwings@zentrip.ly"))
                .thenReturn(1);
        when(jdbc.queryForObject(
                "SELECT id FROM partners WHERE slug = ?",
                Long.class,
                "libyan-wings"))
                .thenReturn(8L);

        new AdminRoleBootstrap(
                jdbc,
                "",
                "libyanwings@zentrip.ly|libyan-wings|Libyan Wings|airline")
                .run(args);

        verify(jdbc).update(
                "UPDATE users SET role = 'customer', partner_id = NULL WHERE role = 'partner'");
        verify(jdbc).update(
                "UPDATE partners SET status = 'inactive' WHERE slug NOT IN (?)",
                "libyan-wings");
        verify(jdbc).update(
                "UPDATE users SET role = 'partner', partner_id = ? WHERE email = ?",
                8L,
                "libyanwings@zentrip.ly");
    }

    @Test
    void configuresHotelAndCarPartnerAccountsWithTheirServicePermissions() {
        when(jdbc.queryForObject(
                contains("information_schema.COLUMNS"),
                eq(Integer.class),
                anyString(),
                anyString()))
                .thenReturn(1);
        when(jdbc.queryForObject(
                "SELECT COUNT(*) FROM users WHERE email = ?",
                Integer.class,
                "almasahotel@zentrip.ly"))
                .thenReturn(1);
        when(jdbc.queryForObject(
                "SELECT COUNT(*) FROM users WHERE email = ?",
                Integer.class,
                "zentripcarrental@zentrip.com"))
                .thenReturn(1);
        when(jdbc.queryForObject(
                "SELECT id FROM partners WHERE slug = ?",
                Long.class,
                "al-masa-hotel"))
                .thenReturn(21L);
        when(jdbc.queryForObject(
                "SELECT id FROM partners WHERE slug = ?",
                Long.class,
                "zentrip-car-rental"))
                .thenReturn(22L);

        new AdminRoleBootstrap(
                jdbc,
                "",
                "almasahotel@zentrip.ly|al-masa-hotel|Al-Masa Hotel|hotel;"
                        + "zentripcarrental@zentrip.com|zentrip-car-rental|Zentrip Car Rental|car")
                .run(args);

        verify(jdbc).update(
                "UPDATE users SET role = 'partner', partner_id = ? WHERE email = ?",
                21L,
                "almasahotel@zentrip.ly");
        verify(jdbc).update(
                "UPDATE users SET role = 'partner', partner_id = ? WHERE email = ?",
                22L,
                "zentripcarrental@zentrip.com");
        verify(jdbc).update(
                contains("INSERT INTO partners (slug, name, service_type, status)"),
                eq("al-masa-hotel"),
                eq("Al-Masa Hotel"),
                eq("hotel"));
        verify(jdbc).update(
                contains("INSERT INTO partners (slug, name, service_type, status)"),
                eq("zentrip-car-rental"),
                eq("Zentrip Car Rental"),
                eq("car"));
    }

    @Test
    void rejectsUnregisteredPartnerWithoutChangingExistingRoles() {
        when(jdbc.queryForObject(
                contains("information_schema.COLUMNS"),
                eq(Integer.class),
                anyString(),
                anyString()))
                .thenReturn(1);
        when(jdbc.queryForObject(
                "SELECT COUNT(*) FROM users WHERE email = ?",
                Integer.class,
                "missing@zentrip.ly"))
                .thenReturn(0);

        assertThrows(
                IllegalStateException.class,
                () -> new AdminRoleBootstrap(
                        jdbc,
                        "",
                        "missing@zentrip.ly|missing|Missing|hotel").run(args));

        verify(jdbc, never()).update(contains("UPDATE users SET role = 'customer'"));
    }
}

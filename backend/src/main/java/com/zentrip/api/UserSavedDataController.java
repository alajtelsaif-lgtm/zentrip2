package com.zentrip.api;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

import jakarta.servlet.http.HttpServletRequest;

/**
 * Per-user data that used to live only on the device: favorites, flight
 * price alerts and app settings. Every query is scoped to the authenticated
 * user; RLS enforces the same rule in the database.
 */
@RestController
@RequestMapping("/api")
public class UserSavedDataController {
    private static final Logger LOG = LoggerFactory.getLogger(UserSavedDataController.class);
    static final String MIGRATION_REQUIRED =
            "Saved-data storage migration 20261115_user_saved_data is required";
    private static final int MAX_FAVORITES = 500;
    private static final int MAX_PRICE_ALERTS = 100;
    private static final Set<String> BOOLEAN_SETTINGS = Set.of(
            "notif_trip", "notif_promo", "notif_zen", "notif_general");
    private static final Set<String> LOCALES = Set.of("en", "ar");
    private static final Set<String> CURRENCIES = Set.of("USD", "EUR", "GBP", "LYD");
    private static final Set<String> THEMES = Set.of("system", "light", "dark");

    private final JdbcTemplate jdbc;
    private final ObjectMapper json = new ObjectMapper();

    public UserSavedDataController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    // ── Favorites ────────────────────────────────────────────────────────

    @GetMapping("/favorites")
    public Map<String, Object> favorites(HttpServletRequest request) {
        long userId = requireUserId(request);
        requireTable("user_favorites");
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT item_id AS id, item_type AS type, title, subtitle,
                       image_url, latitude, longitude, created_at
                FROM public.user_favorites
                WHERE user_id = ?
                ORDER BY created_at DESC, item_id
                """, userId);
        return Map.of("favorites", rows);
    }

    @PostMapping("/favorites")
    public ResponseEntity<Map<String, Object>> saveFavorite(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        requireTable("user_favorites");
        String id = bounded(body.get("id"), "id", 512, true);
        String type = bounded(body.get("type"), "type", 32, true);
        String title = bounded(body.get("title"), "title", 255, true);
        String subtitle = bounded(body.get("subtitle"), "subtitle", 512, false);
        String imageUrl = bounded(body.get("image_url"), "image_url", 2048, false);
        Double latitude = coordinate(body.get("latitude"), "latitude", 90);
        Double longitude = coordinate(body.get("longitude"), "longitude", 180);

        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM public.user_favorites WHERE user_id = ? AND item_id <> ?",
                Integer.class, userId, id);
        if (count != null && count >= MAX_FAVORITES) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "You can save up to " + MAX_FAVORITES + " favorites");
        }
        jdbc.update("""
                INSERT INTO public.user_favorites
                    (user_id, item_id, item_type, title, subtitle, image_url, latitude, longitude)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (user_id, item_id) DO UPDATE SET
                    item_type = EXCLUDED.item_type,
                    title = EXCLUDED.title,
                    subtitle = EXCLUDED.subtitle,
                    image_url = EXCLUDED.image_url,
                    latitude = EXCLUDED.latitude,
                    longitude = EXCLUDED.longitude
                """, userId, id, type, title, subtitle, emptyToNull(imageUrl), latitude, longitude);
        Map<String, Object> saved = new LinkedHashMap<>();
        saved.put("id", id);
        saved.put("type", type);
        saved.put("title", title);
        saved.put("subtitle", subtitle);
        saved.put("image_url", emptyToNull(imageUrl));
        saved.put("latitude", latitude);
        saved.put("longitude", longitude);
        return ResponseEntity.ok(Map.of("favorite", saved));
    }

    @DeleteMapping("/favorites")
    public ResponseEntity<Void> removeFavorite(
            @RequestParam("id") String itemId,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        requireTable("user_favorites");
        jdbc.update("DELETE FROM public.user_favorites WHERE user_id = ? AND item_id = ?",
                userId, itemId);
        return ResponseEntity.noContent().build();
    }

    // ── Price alerts ─────────────────────────────────────────────────────

    @GetMapping("/price-alerts")
    public Map<String, Object> priceAlerts(HttpServletRequest request) {
        long userId = requireUserId(request);
        requireTable("user_price_alerts");
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, origin_code, destination_code, departure_date,
                       reference_price_usd, created_at
                FROM public.user_price_alerts
                WHERE user_id = ?
                ORDER BY created_at DESC, id DESC
                """, userId);
        return Map.of("price_alerts", rows.stream().map(UserSavedDataController::alertPayload).toList());
    }

    @PostMapping("/price-alerts")
    public ResponseEntity<Map<String, Object>> savePriceAlert(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        requireTable("user_price_alerts");
        String origin = airportCode(body.get("origin_code"), "origin_code");
        String destination = airportCode(body.get("destination_code"), "destination_code");
        LocalDate departure = date(body.get("departure_date"));
        BigDecimal price = price(body.get("reference_price_usd"));

        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM public.user_price_alerts
                WHERE user_id = ?
                  AND NOT (origin_code = ? AND destination_code = ? AND departure_date = ?)
                """, Integer.class, userId, origin, destination, departure);
        if (count != null && count >= MAX_PRICE_ALERTS) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "You can track up to " + MAX_PRICE_ALERTS + " price alerts");
        }
        List<Map<String, Object>> rows = jdbc.queryForList("""
                INSERT INTO public.user_price_alerts
                    (user_id, origin_code, destination_code, departure_date, reference_price_usd)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (user_id, origin_code, destination_code, departure_date)
                DO UPDATE SET updated_at = public.user_price_alerts.updated_at
                RETURNING id, origin_code, destination_code, departure_date,
                          reference_price_usd, created_at
                """, userId, origin, destination, departure, price);
        return ResponseEntity.ok(Map.of("price_alert", alertPayload(rows.getFirst())));
    }

    @PatchMapping("/price-alerts/{alertId}")
    public ResponseEntity<Map<String, Object>> updatePriceAlert(
            @PathVariable long alertId,
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        requireTable("user_price_alerts");
        BigDecimal price = price(body.get("reference_price_usd"));
        List<Map<String, Object>> rows = jdbc.queryForList("""
                UPDATE public.user_price_alerts
                SET reference_price_usd = ?, updated_at = NOW()
                WHERE id = ? AND user_id = ?
                RETURNING id, origin_code, destination_code, departure_date,
                          reference_price_usd, created_at
                """, price, alertId, userId);
        if (rows.isEmpty()) return ResponseEntity.notFound().build();
        return ResponseEntity.ok(Map.of("price_alert", alertPayload(rows.getFirst())));
    }

    @DeleteMapping("/price-alerts/{alertId}")
    public ResponseEntity<Void> removePriceAlert(
            @PathVariable long alertId,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        requireTable("user_price_alerts");
        jdbc.update("DELETE FROM public.user_price_alerts WHERE id = ? AND user_id = ?",
                alertId, userId);
        return ResponseEntity.noContent().build();
    }

    // ── Settings ─────────────────────────────────────────────────────────

    @GetMapping("/settings")
    public Map<String, Object> settings(HttpServletRequest request) {
        long userId = requireUserId(request);
        requireTable("user_settings");
        List<String> rows = jdbc.queryForList(
                "SELECT settings::text FROM public.user_settings WHERE user_id = ?",
                String.class, userId);
        return Map.of("settings", rows.isEmpty() ? Map.of() : parse(rows.getFirst()));
    }

    @PutMapping("/settings")
    public Map<String, Object> saveSettings(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        requireTable("user_settings");
        Map<String, Object> changes = validatedSettings(body);
        String changesJson = write(changes);
        String merged = jdbc.queryForObject("""
                INSERT INTO public.user_settings (user_id, settings)
                VALUES (?, ?::jsonb)
                ON CONFLICT (user_id) DO UPDATE SET
                    settings = public.user_settings.settings || EXCLUDED.settings,
                    updated_at = NOW()
                RETURNING settings::text
                """, String.class, userId, changesJson);
        return Map.of("settings", parse(merged));
    }

    static Map<String, Object> validatedSettings(Map<String, Object> body) {
        if (body == null || body.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "No settings provided");
        }
        Map<String, Object> clean = new LinkedHashMap<>();
        for (Map.Entry<String, Object> entry : body.entrySet()) {
            String key = entry.getKey();
            Object value = entry.getValue();
            if (BOOLEAN_SETTINGS.contains(key)) {
                if (!(value instanceof Boolean flag)) throw invalid(key + " must be true or false");
                clean.put(key, flag);
            } else if ("locale".equals(key)) {
                String locale = text(value).toLowerCase(Locale.ROOT);
                if (!LOCALES.contains(locale)) throw invalid("locale must be en or ar");
                clean.put(key, locale);
            } else if ("currency".equals(key)) {
                String currency = text(value).toUpperCase(Locale.ROOT);
                if (!CURRENCIES.contains(currency)) throw invalid("Unsupported currency");
                clean.put(key, currency);
            } else if ("theme".equals(key)) {
                String theme = text(value).toLowerCase(Locale.ROOT);
                if (!THEMES.contains(theme)) throw invalid("theme must be system, light or dark");
                clean.put(key, theme);
            } else {
                throw invalid("Unknown setting: " + key);
            }
        }
        return clean;
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private void requireTable(String table) {
        Boolean exists;
        try {
            exists = jdbc.queryForObject(
                    "SELECT to_regclass('public." + table + "') IS NOT NULL", Boolean.class);
        } catch (DataAccessException exception) {
            LOG.warn("Could not check saved-data migration status", exception);
            return;
        }
        if (Boolean.FALSE.equals(exists)) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, MIGRATION_REQUIRED);
        }
    }

    private static Map<String, Object> alertPayload(Map<String, Object> row) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("id", row.get("id") instanceof Number n ? n.longValue() : row.get("id"));
        payload.put("origin_code", text(row.get("origin_code")).trim());
        payload.put("destination_code", text(row.get("destination_code")).trim());
        payload.put("departure_date", text(row.get("departure_date")));
        Object price = row.get("reference_price_usd");
        payload.put("reference_price_usd",
                price instanceof Number n ? n.doubleValue() : Double.parseDouble(text(price)));
        payload.put("created_at", text(row.get("created_at")));
        return payload;
    }

    private Map<String, Object> parse(String value) {
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> parsed = json.readValue(value, Map.class);
            return parsed;
        } catch (JsonProcessingException exception) {
            LOG.warn("Ignoring unreadable user settings", exception);
            return Map.of();
        }
    }

    private String write(Map<String, Object> value) {
        try {
            return json.writeValueAsString(value);
        } catch (JsonProcessingException exception) {
            throw new IllegalStateException(exception);
        }
    }

    private static String bounded(Object value, String field, int max, boolean required) {
        String text = text(value).trim();
        if (required && text.isEmpty()) throw invalid(field + " is required");
        if (text.length() > max) throw invalid(field + " must be " + max + " characters or fewer");
        return text;
    }

    private static Double coordinate(Object value, String field, double limit) {
        if (value == null || text(value).isBlank()) return null;
        double number;
        try {
            number = value instanceof Number n ? n.doubleValue() : Double.parseDouble(text(value));
        } catch (NumberFormatException exception) {
            throw invalid(field + " must be a number");
        }
        if (!Double.isFinite(number) || Math.abs(number) > limit) {
            throw invalid(field + " is out of range");
        }
        return number;
    }

    private static String airportCode(Object value, String field) {
        String code = text(value).trim().toUpperCase(Locale.ROOT);
        if (!code.matches("[A-Z0-9]{2,8}")) throw invalid(field + " must be an airport or city code");
        return code;
    }

    private static LocalDate date(Object value) {
        String raw = text(value).trim();
        if (raw.length() >= 10) raw = raw.substring(0, 10);
        try {
            return LocalDate.parse(raw);
        } catch (DateTimeParseException exception) {
            throw invalid("departure_date must be YYYY-MM-DD");
        }
    }

    private static BigDecimal price(Object value) {
        BigDecimal price;
        try {
            price = new BigDecimal(text(value).trim());
        } catch (NumberFormatException exception) {
            throw invalid("reference_price_usd must be a number");
        }
        if (price.signum() < 0 || price.compareTo(new BigDecimal("9999999999")) > 0) {
            throw invalid("reference_price_usd is out of range");
        }
        return price.setScale(2, java.math.RoundingMode.HALF_UP);
    }

    private static String emptyToNull(String value) {
        return value == null || value.isEmpty() ? null : value;
    }

    private static String text(Object value) {
        return value == null ? "" : value.toString();
    }

    private static ResponseStatusException invalid(String message) {
        return new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, message);
    }

    private static long requireUserId(HttpServletRequest request) {
        Object userId = request.getAttribute("authUserId");
        if (!(userId instanceof Number number)) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Unauthenticated");
        }
        return number.longValue();
    }
}

package com.zentrip.api;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.UUID;
import java.util.Map;

@RestController
@RequestMapping("/api/admin")
public class AdminController {
    private static final ObjectMapper JSON = new ObjectMapper();
    private final JdbcTemplate jdbc;

    public AdminController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/dashboard")
    public Map<String, Object> dashboard(HttpServletRequest request) {
        requireAdminId(request);
        Map<String, Object> summary = jdbc.queryForMap("""
                SELECT
                    (SELECT COUNT(*) FROM users WHERE role = 'customer') AS customer_count,
                    (SELECT COUNT(*) FROM users
                        WHERE role = 'customer' AND created_at >= NOW() - INTERVAL '30 day')
                        AS new_customers_30d,
                    (SELECT COUNT(*) FROM bookings WHERE LOWER(status) <> 'cancelled')
                      + (SELECT COUNT(*) FROM trips WHERE LOWER(status) <> 'cancelled')
                      + (SELECT COUNT(*) FROM transfers WHERE LOWER(status) <> 'cancelled')
                        AS reservation_count,
                    (SELECT COUNT(*) FROM trips WHERE LOWER(status) <> 'cancelled')
                        AS flight_count,
                    (SELECT COUNT(*) FROM bookings WHERE LOWER(status) <> 'cancelled')
                        AS service_booking_count,
                    (SELECT COUNT(*) FROM transfers WHERE LOWER(status) <> 'cancelled')
                        AS transfer_count,
                    COALESCE((SELECT SUM(total_amount) FROM bookings
                        WHERE LOWER(status) <> 'cancelled'), 0)
                      + COALESCE((SELECT SUM(price) FROM trips
                        WHERE LOWER(status) <> 'cancelled'), 0)
                      + COALESCE((SELECT SUM(price) FROM transfers
                        WHERE LOWER(status) <> 'cancelled'), 0)
                        AS booked_value
                """);
        return Map.of(
                "summary", summary,
                "recent_reservations", recentReservations(8));
    }

    @GetMapping("/reservations")
    public Map<String, Object> reservations(
            @RequestParam(defaultValue = "50") int limit,
            HttpServletRequest request) {
        requireAdminId(request);
        validateLimit(limit);
        return Map.of("reservations", recentReservations(limit));
    }

    @GetMapping("/customers")
    public Map<String, Object> customers(
            @RequestParam(defaultValue = "50") int limit,
            HttpServletRequest request) {
        requireAdminId(request);
        validateLimit(limit);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT u.id, u.name, u.email, u.phone, u.created_at,
                    (SELECT COUNT(*) FROM bookings b WHERE b.user_id = u.id)
                      + (SELECT COUNT(*) FROM trips t WHERE t.user_id = u.id)
                      + (SELECT COUNT(*) FROM transfers x WHERE x.user_id = u.id)
                      AS reservation_count
                FROM users u
                WHERE u.role = 'customer'
                ORDER BY u.created_at DESC
                LIMIT ?
                """, limit);
        return Map.of("customers", rows);
    }

    @GetMapping("/monuments")
    public Map<String, Object> monuments(HttpServletRequest request) {
        requireAdminId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, title, location, category_tag, category, rating,
                       review_count, description, working_hours,
                       best_time_to_visit, entry_fee, image_url, tags, is_active
                FROM tourist_monuments
                ORDER BY sort_order ASC, title ASC
                """);
        return Map.of("monuments", rows.stream().map(AdminController::monumentPayload).toList());
    }

    @PostMapping("/monuments")
    @Transactional
    public Map<String, Object> createMonument(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        requireAdminId(request);
        Map<String, Object> monument = validateMonument(body);
        String id = UUID.randomUUID().toString();
        jdbc.update("""
                INSERT INTO tourist_monuments (
                    id, title, location, category_tag, category, rating,
                    review_count, description, working_hours, best_time_to_visit,
                    entry_fee, image_url, tags, is_active
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                id,
                monument.get("title"),
                monument.get("location"),
                monument.get("category_tag"),
                monument.get("category"),
                monument.get("rating"),
                monument.get("review_count"),
                monument.get("description"),
                monument.get("working_hours"),
                monument.get("best_time_to_visit"),
                monument.get("entry_fee"),
                monument.get("image_url"),
                jsonList(monument.get("tags")),
                monument.get("is_active"));
        monument.put("id", id);
        return Map.of("monument", monument);
    }

    @PutMapping("/monuments/{id}")
    @Transactional
    public Map<String, Object> updateMonument(
            @PathVariable String id,
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        requireAdminId(request);
        Map<String, Object> monument = validateMonument(body);
        requireCatalogItem(
                "SELECT COUNT(*) FROM tourist_monuments WHERE id = ?", id, "Monument not found");
        int updated = jdbc.update("""
                UPDATE tourist_monuments
                SET title = ?, location = ?, category_tag = ?, category = ?,
                    rating = ?, review_count = ?, description = ?,
                    working_hours = ?, best_time_to_visit = ?, entry_fee = ?,
                    image_url = ?, tags = ?, is_active = ?
                WHERE id = ?
                """,
                monument.get("title"),
                monument.get("location"),
                monument.get("category_tag"),
                monument.get("category"),
                monument.get("rating"),
                monument.get("review_count"),
                monument.get("description"),
                monument.get("working_hours"),
                monument.get("best_time_to_visit"),
                monument.get("entry_fee"),
                monument.get("image_url"),
                jsonList(monument.get("tags")),
                monument.get("is_active"),
                id);
        if (updated == 0
                && !catalogItemExists(
                        "SELECT COUNT(*) FROM tourist_monuments WHERE id = ?", id)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Monument not found");
        }
        monument.put("id", id);
        return Map.of("monument", monument);
    }

    @DeleteMapping("/monuments/{id}")
    @Transactional
    public Map<String, String> deleteMonument(
            @PathVariable String id,
            HttpServletRequest request) {
        requireAdminId(request);
        if (jdbc.update("DELETE FROM tourist_monuments WHERE id = ?", id) == 0) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Monument not found");
        }
        return Map.of("message", "Monument deleted");
    }

    @GetMapping("/offers")
    public Map<String, Object> offers(HttpServletRequest request) {
        requireAdminId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT o.id, o.title, o.location, o.country, o.destination_code,
                       o.description, o.image_url, o.price_per_person,
                       o.flight_price_per_person, o.hotel_price_per_night,
                       o.duration_nights, o.rating, o.review_count, o.highlights,
                       o.is_featured, o.category, o.is_active,
                       COALESCE(m.badge, '') AS badge
                FROM offers o
                LEFT JOIN offer_catalog_metadata m ON m.offer_id = o.id
                WHERE o.is_active = TRUE
                ORDER BY o.is_featured DESC, o.sort_order ASC, o.title ASC
                """);
        return Map.of("offers", rows.stream().map(AdminController::offerPayload).toList());
    }

    @PostMapping("/offers")
    @Transactional
    public Map<String, Object> createOffer(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        requireAdminId(request);
        Map<String, Object> offer = validateOffer(body);
        String id = UUID.randomUUID().toString();
        jdbc.update("""
                INSERT INTO offers (
                    id, title, location, country, destination_code, description,
                    image_url, price_per_person, flight_price_per_person,
                    hotel_price_per_night, duration_nights, rating, review_count,
                    highlights, is_featured, category, is_active
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                id,
                offer.get("title"),
                offer.get("location"),
                offer.get("country"),
                offer.get("destination_code"),
                offer.get("description"),
                offer.get("image_url"),
                offer.get("price_per_person"),
                offer.get("flight_price_per_person"),
                offer.get("hotel_price_per_night"),
                offer.get("duration_nights"),
                offer.get("rating"),
                offer.get("review_count"),
                jsonList(offer.get("highlights")),
                offer.get("is_featured"),
                offer.get("category"),
                offer.get("is_active"));
        jdbc.update("""
                INSERT INTO offer_catalog_metadata (offer_id, badge)
                VALUES (?, ?)
                """, id, offer.get("badge"));
        offer.put("id", id);
        return Map.of("offer", offer);
    }

    @PutMapping("/offers/{id}")
    @Transactional
    public Map<String, Object> updateOffer(
            @PathVariable String id,
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        requireAdminId(request);
        Map<String, Object> offer = validateOffer(body);
        requireCatalogItem(
                "SELECT COUNT(*) FROM offers WHERE id = ? AND is_active = TRUE",
                id,
                "Offer not found");
        int updated = jdbc.update("""
                UPDATE offers
                SET title = ?, location = ?, country = ?, destination_code = ?,
                    description = ?, image_url = ?, price_per_person = ?,
                    flight_price_per_person = ?, hotel_price_per_night = ?,
                    duration_nights = ?, rating = ?, review_count = ?,
                    highlights = ?, is_featured = ?, category = ?, is_active = ?
                WHERE id = ?
                """,
                offer.get("title"),
                offer.get("location"),
                offer.get("country"),
                offer.get("destination_code"),
                offer.get("description"),
                offer.get("image_url"),
                offer.get("price_per_person"),
                offer.get("flight_price_per_person"),
                offer.get("hotel_price_per_night"),
                offer.get("duration_nights"),
                offer.get("rating"),
                offer.get("review_count"),
                jsonList(offer.get("highlights")),
                offer.get("is_featured"),
                offer.get("category"),
                offer.get("is_active"),
                id);
        if (updated == 0
                && !catalogItemExists(
                        "SELECT COUNT(*) FROM offers WHERE id = ? AND is_active = TRUE", id)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Offer not found");
        }
        jdbc.update("""
                INSERT INTO offer_catalog_metadata (offer_id, badge)
                VALUES (?, ?)
                ON DUPLICATE KEY UPDATE badge = VALUES(badge)
                """, id, offer.get("badge"));
        offer.put("id", id);
        return Map.of("offer", offer);
    }

    @DeleteMapping("/offers/{id}")
    @Transactional
    public Map<String, String> deleteOffer(
            @PathVariable String id,
            HttpServletRequest request) {
        requireAdminId(request);
        if (jdbc.update(
                "UPDATE offers SET is_active = FALSE WHERE id = ? AND is_active = TRUE",
                id) == 0) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Offer not found");
        }
        return Map.of("message", "Offer deleted");
    }

    private static Map<String, Object> validateMonument(Map<String, Object> body) {
        Map<String, Object> monument = new LinkedHashMap<>();
        monument.put("title", requiredText(body, "title", 255));
        monument.put("location", requiredText(body, "location", 255));
        monument.put("category_tag", optionalText(body, "category_tag", 100));
        monument.put("category", optionalText(body, "category", 40, "landmark"));
        monument.put("rating", rating(body.get("rating")));
        monument.put("review_count", nonNegativeInt(body.get("review_count"), "review_count"));
        monument.put("description", requiredText(body, "description", 10000));
        monument.put("working_hours", optionalText(body, "working_hours", 255));
        monument.put("best_time_to_visit", optionalText(body, "best_time_to_visit", 255));
        monument.put("entry_fee", optionalMoney(body.get("entry_fee"), "entry_fee"));
        monument.put("image_url", optionalText(body, "image_url", 2048));
        monument.put("tags", stringList(body.get("tags"), "tags"));
        monument.put("is_active", booleanValue(body.get("is_active"), true));
        return monument;
    }

    private static Map<String, Object> validateOffer(Map<String, Object> body) {
        Map<String, Object> offer = new LinkedHashMap<>();
        offer.put("title", requiredText(body, "title", 255));
        offer.put("location", requiredText(body, "location", 255));
        offer.put("country", requiredText(body, "country", 255));
        offer.put("destination_code", optionalText(body, "destination_code", 10));
        offer.put("description", requiredText(body, "description", 10000));
        offer.put("image_url", optionalText(body, "image_url", 2048));
        offer.put("price_per_person", nonNegativeMoney(body.get("price_per_person"), "price_per_person"));
        offer.put("flight_price_per_person", nonNegativeMoney(
                body.get("flight_price_per_person"), "flight_price_per_person"));
        offer.put("hotel_price_per_night", nonNegativeMoney(
                body.get("hotel_price_per_night"), "hotel_price_per_night"));
        int nights = nonNegativeInt(body.get("duration_nights"), "duration_nights");
        if (nights < 1 || nights > 365) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "duration_nights must be between 1 and 365");
        }
        offer.put("duration_nights", nights);
        offer.put("rating", rating(body.get("rating")));
        offer.put("review_count", nonNegativeInt(body.get("review_count"), "review_count"));
        offer.put("highlights", stringList(body.get("highlights"), "highlights"));
        offer.put("badge", optionalText(body, "badge", 100));
        offer.put("is_featured", booleanValue(
                body.getOrDefault("is_featured", body.get("badge")), false));
        offer.put("category", optionalText(body, "category", 40, "city"));
        offer.put("is_active", booleanValue(body.get("is_active"), true));
        return offer;
    }

    private static Map<String, Object> monumentPayload(Map<String, Object> row) {
        Map<String, Object> payload = new LinkedHashMap<>(row);
        payload.put("name", row.get("title"));
        payload.put("city", firstLocationPart(row.get("location"), 0));
        payload.put("country", firstLocationPart(row.get("location"), 1));
        payload.put("tags", parseStringList(row.get("tags")));
        return payload;
    }

    private static Map<String, Object> offerPayload(Map<String, Object> row) {
        Map<String, Object> payload = new LinkedHashMap<>(row);
        payload.put("highlights", parseStringList(row.get("highlights")));
        String badge = text(row.get("badge")).trim();
        boolean featured = Boolean.TRUE.equals(row.get("is_featured"))
                || "1".equals(String.valueOf(row.get("is_featured")))
                || "true".equalsIgnoreCase(String.valueOf(row.get("is_featured")));
        payload.put("badge", badge.isEmpty() && featured ? "Featured Offer" : badge);
        return payload;
    }

    private static String firstLocationPart(Object value, int index) {
        String[] parts = String.valueOf(value == null ? "" : value).split(",", 2);
        if (index >= parts.length) return "";
        return parts[index].trim();
    }

    private static String requiredText(Map<String, Object> body, String key, int maxLength) {
        String value = text(body.get(key)).trim();
        if (value.isEmpty() || value.length() > maxLength) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, key + " is required");
        }
        return value;
    }

    private static String optionalText(
            Map<String, Object> body, String key, int maxLength) {
        return optionalText(body, key, maxLength, "");
    }

    private static String optionalText(
            Map<String, Object> body, String key, int maxLength, String fallback) {
        String value = body.get(key) == null ? fallback : text(body.get(key)).trim();
        if (value.length() > maxLength) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, key + " is too long");
        }
        return value;
    }

    private static java.math.BigDecimal rating(Object raw) {
        java.math.BigDecimal value = nonNegativeMoney(raw, "rating");
        if (value.compareTo(java.math.BigDecimal.valueOf(5)) > 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "rating must be at most 5");
        }
        return value;
    }

    private static java.math.BigDecimal nonNegativeMoney(Object raw, String key) {
        java.math.BigDecimal value = decimal(raw, key);
        if (value.signum() < 0 || value.precision() > 10 || value.scale() > 2) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, key + " is invalid");
        }
        return value;
    }

    private static java.math.BigDecimal optionalMoney(Object raw, String key) {
        return raw == null || String.valueOf(raw).isBlank()
                ? null
                : nonNegativeMoney(raw, key);
    }

    private static java.math.BigDecimal decimal(Object raw, String key) {
        try {
            return new java.math.BigDecimal(String.valueOf(raw));
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, key + " must be numeric");
        }
    }

    private static int nonNegativeInt(Object raw, String key) {
        try {
            int value = Integer.parseInt(String.valueOf(raw));
            if (value < 0) throw new NumberFormatException();
            return value;
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, key + " must be a non-negative integer");
        }
    }

    private static boolean booleanValue(Object raw, boolean fallback) {
        if (raw == null) return fallback;
        if (raw instanceof Boolean value) return value;
        if ("true".equalsIgnoreCase(String.valueOf(raw))
                || "1".equals(String.valueOf(raw))) return true;
        if ("false".equalsIgnoreCase(String.valueOf(raw))
                || "0".equals(String.valueOf(raw))
                || String.valueOf(raw).isBlank()) return false;
        throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Boolean value is invalid");
    }

    private static List<String> stringList(Object raw, String key) {
        if (raw == null) return List.of();
        if (!(raw instanceof List<?> values)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, key + " must be a list");
        }
        List<String> result = new ArrayList<>();
        for (Object value : values) {
            String text = String.valueOf(value).trim();
            if (!text.isEmpty() && !result.contains(text)) result.add(text);
            if (result.size() > 100) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, key + " has too many items");
            }
        }
        return List.copyOf(result);
    }

    private static List<String> parseStringList(Object raw) {
        if (raw instanceof List<?> values) {
            return values.stream().map(String::valueOf).toList();
        }
        if (raw == null) return List.of();
        try {
            return JSON.readValue(raw.toString(), new TypeReference<List<String>>() {});
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalStateException("Stored catalog tags are invalid JSON", exception);
        }
    }

    private static String jsonList(Object raw) {
        try {
            return JSON.writeValueAsString(raw);
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalArgumentException("Catalog tags could not be encoded", exception);
        }
    }

    private static String text(Object value) {
        return value == null ? "" : String.valueOf(value);
    }

    private List<Map<String, Object>> recentReservations(int limit) {
        return jdbc.queryForList("""
                SELECT *
                FROM (
                    SELECT CONCAT('flight-', t.id) AS id, 'Flight' AS type,
                        t.title, u.name AS customer_name,
                        COALESCE(t.departure_date, t.created_at) AS reservation_date,
                        COALESCE(t.price, 0) AS amount, t.status, t.created_at
                    FROM trips t JOIN users u ON u.id = t.user_id
                    UNION ALL
                    SELECT CONCAT('booking-', b.id) AS id, b.type,
                        COALESCE(b.title, b.subtitle, 'Booking') AS title,
                        u.name AS customer_name,
                        COALESCE(b.date, b.created_at) AS reservation_date,
                        COALESCE(b.total_amount, b.price, 0) AS amount,
                        b.status, b.created_at
                    FROM bookings b JOIN users u ON u.id = b.user_id
                    UNION ALL
                    SELECT CONCAT('transfer-', x.id) AS id, 'Transfer' AS type,
                        CONCAT(x.pickup_location, ' to ', x.dropoff_location) AS title,
                        u.name AS customer_name, x.pickup_time AS reservation_date,
                        x.price AS amount, x.status, x.created_at
                    FROM transfers x JOIN users u ON u.id = x.user_id
                ) reservations
                ORDER BY created_at DESC
                LIMIT ?
                """, limit);
    }

    private static void validateLimit(int limit) {
        if (limit < 1 || limit > 100) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "limit must be between 1 and 100");
        }
    }

    private void requireCatalogItem(String query, String id, String message) {
        if (!catalogItemExists(query, id)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, message);
        }
    }

    private boolean catalogItemExists(String query, String id) {
        Integer count = jdbc.queryForObject(query, Integer.class, id);
        return count != null && count > 0;
    }

    private long requireAdminId(HttpServletRequest request) {
        Object userId = request.getAttribute("authUserId");
        if (!(userId instanceof Number number)) {
            throw new ResponseStatusException(
                    HttpStatus.UNAUTHORIZED, "Unauthenticated");
        }
        String role = jdbc.queryForObject(
                "SELECT role FROM users WHERE id = ?",
                String.class,
                number.longValue());
        if (!"admin".equalsIgnoreCase(role)) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "Administrator access required");
        }
        return number.longValue();
    }
}

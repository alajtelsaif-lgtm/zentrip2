package com.zentrip.api;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.text.Normalizer;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.HexFormat;
import java.util.concurrent.TimeUnit;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.BadSqlGrammarException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCreator;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;
import org.springframework.web.util.UriComponentsBuilder;

import jakarta.servlet.http.HttpServletRequest;

@RestController
@RequestMapping("/api")
public class ApiController {
    private static final Logger LOG = LoggerFactory.getLogger(ApiController.class);
    private final JdbcTemplate jdbc;
    private final ProfilePhotoStorage profilePhotoStorage;
    private final PasswordResetService passwordResetService;
    private final LandmarkProvider openTripMapAttractionService;
    private LandmarkCatalogService landmarkCatalogService;
    private GeoapifyAirportService geoapifyAirportService;
    private final PasswordEncoder passwords = new BCryptPasswordEncoder();
    private final RestClient http = RestClient.create();
    private final String serpApiKey;
    private static final ObjectMapper JSON = new ObjectMapper();
    private final VisitBurstRateLimiter visitBurstRateLimiter = new VisitBurstRateLimiter();

    public ApiController(JdbcTemplate jdbc,
                         @Value("${serpapi.key:}") String serpApiKey,
                         ProfilePhotoStorage profilePhotoStorage,
                         PasswordResetService passwordResetService,
                           LandmarkProvider openTripMapAttractionService) {
        this.jdbc = jdbc;
        this.serpApiKey = serpApiKey;
        this.profilePhotoStorage = profilePhotoStorage;
        this.passwordResetService = passwordResetService;
        this.openTripMapAttractionService = openTripMapAttractionService;
    }

    @Autowired
    public void setLandmarkCatalogService(LandmarkCatalogService catalogService) {
        this.landmarkCatalogService = catalogService;
    }

    @Autowired
    public void setGeoapifyAirportService(GeoapifyAirportService geocoder) {
        this.geoapifyAirportService = geocoder;
    }

    @PostMapping("/auth/register")
    @Transactional
    public ResponseEntity<?> register(@RequestParam String name,
                                      @RequestParam String email,
                                      @RequestParam String phone,
                                      @RequestParam String password,
                                      @RequestParam("password_confirmation") String confirmation,
                                      @RequestParam(value = "photo", required = false) MultipartFile photo,
                                      HttpServletRequest request) {
        if (name.isBlank() || !email.contains("@") || password.length() < 8 || !password.equals(confirmation)) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "Invalid registration details");
        }
        setLocalRlsSetting("app.auth_email", email.trim().toLowerCase(Locale.ROOT));
        if (jdbc.queryForObject("SELECT COUNT(*) FROM users WHERE email = ?", Integer.class, email) > 0) {
            return ResponseEntity.unprocessableEntity().body(validationError(
                    "email", "The email has already been taken."));
        }
        String photoUrl = profilePhotoStorage.store(photo);
        long id = insert("INSERT INTO users (name, email, phone, password, created_at, updated_at) VALUES (?, ?, ?, ?, NOW(), NOW())",
                name, email, phone, passwords.encode(password));
        if (photoUrl != null) saveProfilePhotoUrl(id, photoUrl);
        return ResponseEntity.status(HttpStatus.CREATED).body(authPayload(id, request));
    }

    @PostMapping("/auth/login")
    public ResponseEntity<?> login(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        String email = text(body.get("email")).trim();
        String password = text(body.get("password"));
        setLocalRlsSetting("app.auth_email", email.toLowerCase(Locale.ROOT));
        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT id, password FROM users WHERE email = ?", email);
        if (rows.isEmpty()) {
            rows = jdbc.queryForList("""
                    SELECT id, password FROM users WHERE LOWER(email) = LOWER(?)
                    ORDER BY id LIMIT 2
                    """, email);
        }
        if (rows.size() != 1 ||
                !passwords.matches(password, text(rows.getFirst().get("password")))) {
            return ResponseEntity.unprocessableEntity().body(validationError(
                    "email", "The provided credentials are incorrect."));
        }
        return ResponseEntity.ok(authPayload(number(rows.getFirst().get("id")), request));
    }

    @PostMapping("/auth/forgot-password")
    public ResponseEntity<?> forgotPassword(@RequestBody Map<String, Object> body) {
        String email = text(body.get("email")).trim();
        if (!email.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) {
            return ResponseEntity.unprocessableEntity().body(validationError(
                    "email", "Enter a valid email address."));
        }
        try {
            passwordResetService.requestCode(email);
        } catch (ResponseStatusException exception) {
            return ResponseEntity.status(exception.getStatusCode()).body(Map.of(
                    "message", text(exception.getReason())));
        }
        return ResponseEntity.ok(Map.of(
                "message", "If an account exists for that email, a reset code has been sent."));
    }

    @PostMapping("/auth/verify-code")
    public ResponseEntity<?> verifyResetCode(@RequestBody Map<String, Object> body) {
        String email = text(body.get("email")).trim();
        String code = text(body.get("code")).trim();
        if (!email.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) {
            return ResponseEntity.unprocessableEntity().body(validationError(
                    "email", "Enter a valid email address."));
        }
        if (!passwordResetService.verifyCode(email, code)) {
            return ResponseEntity.unprocessableEntity().body(validationError(
                    "code", "The code is invalid or expired."));
        }
        return ResponseEntity.ok(Map.of("message", "The reset code is valid."));
    }

    @PostMapping("/auth/reset-password")
    public ResponseEntity<?> resetPassword(@RequestBody Map<String, Object> body) {
        String email = text(body.get("email")).trim();
        String code = text(body.get("code")).trim();
        String password = text(body.get("password"));
        String confirmation = text(body.get("password_confirmation"));
        if (!email.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) {
            return ResponseEntity.unprocessableEntity().body(validationError(
                    "email", "Enter a valid email address."));
        }
        if (password.length() < 8) {
            return ResponseEntity.unprocessableEntity().body(validationError(
                    "password", "The password must be at least 8 characters."));
        }
        if (!password.equals(confirmation)) {
            return ResponseEntity.unprocessableEntity().body(validationError(
                    "password", "The password confirmation does not match."));
        }
        if (!passwordResetService.resetPassword(email, code, password)) {
            return ResponseEntity.unprocessableEntity().body(validationError(
                    "code", "The code is invalid or expired."));
        }
        return ResponseEntity.ok(Map.of("message", "Password reset successfully."));
    }

    @GetMapping("/auth/me")
    public Map<String, Object> me(HttpServletRequest request) {
        long userId = requireUserId(request);
        return Map.of("user", userPayload(userId, request));
    }

    @PostMapping("/users/fcm-token")
    public ResponseEntity<?> registerFcmToken(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        requireUserId(request);
        String token = text(body.get("token")).trim();
        String platform = text(body.get("platform")).trim().toLowerCase(Locale.ROOT);
        if (token.isBlank() || token.length() > 4096
                || !Set.of("android", "ios", "web").contains(platform)) {
            return ResponseEntity.badRequest().body(validationError(
                    "token", "A valid FCM token and platform are required."));
        }
        Boolean registered = jdbc.queryForObject(
                "SELECT public.zentrip_register_user_push_token(?, ?)",
                Boolean.class, token, platform);
        if (!Boolean.TRUE.equals(registered)) {
            return ResponseEntity.unprocessableEntity().body(validationError(
                    "token", "The FCM token could not be registered."));
        }
        return ResponseEntity.ok(Map.of("message", "Notification token registered."));
    }

    @DeleteMapping("/users/fcm-token")
    public ResponseEntity<Void> removeFcmToken(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        String token = text(body.get("token")).trim();
        if (token.isBlank() || token.length() > 4096) {
            return ResponseEntity.badRequest().build();
        }
        jdbc.update(
                "DELETE FROM public.user_push_tokens WHERE user_id = ? AND token = ?",
                userId, token);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/notifications")
    public Map<String, Object> userNotifications(
            @RequestParam(defaultValue = "50") int limit,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        if (!userNotificationsTableAvailable()) {
            throw new ResponseStatusException(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Notification storage migration is required");
        }
        int boundedLimit = Math.max(1, Math.min(limit, 100));
        List<Map<String, Object>> notifications = jdbc.queryForList("""
                SELECT id, kind, title_en, title_ar, body_en, body_ar,
                       target_type, target_id, booking_ref, created_at,
                       (read_at IS NOT NULL) AS is_read
                FROM public.user_notifications
                WHERE user_id = ?
                ORDER BY created_at DESC, id DESC
                LIMIT ?
                """, userId, boundedLimit);
        return Map.of("notifications", notifications);
    }

    @PutMapping("/notifications/{notificationId}/read")
    public ResponseEntity<?> markNotificationRead(
            @PathVariable long notificationId,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        if (!userNotificationsTableAvailable()) {
            throw new ResponseStatusException(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Notification storage migration is required");
        }
        int updated = jdbc.update("""
                UPDATE public.user_notifications
                SET read_at = COALESCE(read_at, NOW())
                WHERE id = ? AND user_id = ?
                """, notificationId, userId);
        if (updated == 0) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.noContent().build();
    }

    @PutMapping("/notifications/read-all")
    public Map<String, Object> markAllNotificationsRead(
            HttpServletRequest request) {
        long userId = requireUserId(request);
        if (!userNotificationsTableAvailable()) {
            throw new ResponseStatusException(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Notification storage migration is required");
        }
        int updated = jdbc.update("""
                UPDATE public.user_notifications
                SET read_at = NOW()
                WHERE user_id = ? AND read_at IS NULL
                """, userId);
        return Map.of("updated", updated);
    }

    @PostMapping("/profile")
    public ResponseEntity<?> updateProfile(
            @RequestParam(value = "name", required = false) String name,
            @RequestParam(value = "phone", required = false) String phone,
            @RequestParam(value = "photo", required = false) MultipartFile photo,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        String normalizedName = text(name).trim();
        String normalizedPhone = text(phone).trim();
        if (normalizedName.isBlank() || normalizedName.length() > 255) {
            return ResponseEntity.unprocessableEntity().body(validationError("name", "The name field is required and must not exceed 255 characters."));
        }
        if (normalizedPhone.isBlank() || normalizedPhone.length() > 20) {
            return ResponseEntity.unprocessableEntity().body(validationError("phone", "The phone field is required and must not exceed 20 characters."));
        }

        String photoUrl = profilePhotoStorage.store(photo);
        jdbc.update("UPDATE users SET name = ?, phone = ?, updated_at = NOW() WHERE id = ?",
                normalizedName, normalizedPhone, userId);
        if (photoUrl != null) saveProfilePhotoUrl(userId, photoUrl);
        return ResponseEntity.ok(Map.of("user", userPayload(userId, request)));
    }

    @PutMapping("/profile/password")
    public ResponseEntity<?> changePassword(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        String currentPassword = text(body.get("current_password"));
        String newPassword = text(body.get("password"));
        String confirmation = text(body.get("password_confirmation"));
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT password FROM users WHERE id = ?", userId);
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        if (!passwords.matches(currentPassword, text(rows.getFirst().get("password")))) {
            return ResponseEntity.unprocessableEntity().body(validationError(
                    "current_password", "The current password is incorrect."));
        }
        if (newPassword.length() < 8) {
            return ResponseEntity.unprocessableEntity().body(validationError(
                    "password", "The password must be at least 8 characters."));
        }
        if (!newPassword.equals(confirmation)) {
            return ResponseEntity.unprocessableEntity().body(validationError(
                    "password", "The password confirmation does not match."));
        }

        jdbc.update("UPDATE users SET password = ?, updated_at = NOW() WHERE id = ?",
                passwords.encode(newPassword), userId);
        String currentTokenHash = (String) request.getAttribute("authTokenHash");
        if (currentTokenHash != null) {
            jdbc.update("DELETE FROM api_tokens WHERE user_id = ? AND token_hash <> ?", userId, currentTokenHash);
        }
        return ResponseEntity.ok(Map.of("message", "Password updated successfully"));
    }

    @PostMapping("/auth/logout")
    public Map<String, String> logout(HttpServletRequest request) {
        String tokenHash = (String) request.getAttribute("authTokenHash");
        requireUserId(request);
        jdbc.update("DELETE FROM api_tokens WHERE token_hash = ?", tokenHash);
        return Map.of("message", "Logged out successfully");
    }

    @PostMapping("/reviews")
    @Transactional
    public Map<String, Object> submitReview(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        String itemId = text(body.get("item_id")).trim();
        String itemType = text(body.get("item_type")).trim().toLowerCase(Locale.ROOT);
        String comment = text(body.get("comment")).trim();
        BigDecimal rating;
        try {
            rating = new BigDecimal(text(body.get("rating")));
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "Rating must be between 1 and 5");
        }
        if (itemId.isBlank() || itemId.length() > 100
                || !List.of("hotel", "car", "attraction", "package")
                        .contains(itemType)
                || rating.compareTo(BigDecimal.ONE) < 0
                || rating.compareTo(BigDecimal.valueOf(5)) > 0
                || rating.scale() > 1
                || comment.length() > 2000) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "Invalid review details");
        }
        jdbc.update("""
                INSERT INTO user_reviews (user_id, item_id, item_type, rating, comment)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT (user_id, item_type, item_id)
                DO UPDATE SET
                    rating = EXCLUDED.rating,
                    comment = EXCLUDED.comment,
                    updated_at = NOW()
                """, userId, itemId, itemType, rating, comment);
        Map<String, Object> review = jdbc.queryForMap("""
                SELECT CAST(r.id AS CHAR) AS id, r.item_id, r.item_type,
                       u.name AS user_name, r.rating, r.comment, r.created_at
                FROM user_reviews r
                JOIN users u ON u.id = r.user_id
                WHERE r.user_id = ? AND r.item_id = ? AND r.item_type = ?
                """, userId, itemId, itemType);
        return Map.of("review", review);
    }

    @GetMapping("/reviews")
    public Map<String, Object> reviews(
            @RequestParam("item_id") String itemId,
            HttpServletRequest request) {
        requireUserId(request);
        List<Map<String, Object>> reviews = jdbc.queryForList("""
                SELECT CAST(r.id AS CHAR) AS id, r.item_id, r.item_type,
                       u.name AS user_name, r.rating, r.comment, r.created_at
                FROM user_reviews r
                JOIN users u ON u.id = r.user_id
                WHERE r.item_id = ?
                ORDER BY r.created_at DESC, r.id DESC
                """, itemId);
        return Map.of("reviews", reviews);
    }

    @GetMapping("/offers")
    public Map<String, Object> offers() {
        List<Map<String, Object>> payload = jdbc.queryForList("""
                SELECT o.id, o.title, o.location, o.country, o.destination_code,
                       o.description, o.image_url, o.price_per_person,
                       o.flight_price_per_person, o.hotel_price_per_night,
                       o.duration_nights, o.rating, o.review_count,
                       o.highlights, o.is_featured, o.category,
                       o.flight_listing_id, COALESCE(m.badge, '') AS badge,
                       fl.id AS linked_flight_id, fl.title AS flight_title,
                       fl.city AS flight_city, fl.country AS flight_country,
                       fl.price AS linked_flight_price, fl.active AS flight_active,
                       fl.attributes AS flight_attributes, p.name AS flight_airline
                FROM offers o
                LEFT JOIN offer_catalog_metadata m ON m.offer_id = o.id
                LEFT JOIN partner_listings fl ON fl.id = o.flight_listing_id
                LEFT JOIN partners p ON p.id = fl.partner_id
                WHERE o.is_active = TRUE
                ORDER BY o.is_featured DESC, o.sort_order ASC, o.title ASC
                """).stream().map(row -> {
                    Map<String, Object> offer = new LinkedHashMap<>(row);
                    offer.put("highlights", parseHighlights(row.get("highlights")));
                    Map<String, Object> flight = offerFlightPayload(row);
                    offer.put("flight", flight.isEmpty() ? null : flight);
                    String badge = row.get("badge") == null ? "" : row.get("badge").toString();
                    boolean featured = Boolean.TRUE.equals(row.get("is_featured"))
                            || "1".equals(String.valueOf(row.get("is_featured")))
                            || "true".equalsIgnoreCase(String.valueOf(row.get("is_featured")));
                    offer.put("badge", badge.isEmpty() && featured ? "Featured Offer" : badge);
                    Object linkedPrice = row.get("linked_flight_price");
                    Object flightPrice = linkedPrice == null
                            ? row.get("flight_price_per_person") : linkedPrice;
                    BigDecimal total = new BigDecimal(String.valueOf(
                            flightPrice == null ? 0 : flightPrice))
                            .add(new BigDecimal(String.valueOf(
                                    row.getOrDefault("hotel_price_per_night", 0)))
                                    .multiply(new BigDecimal(String.valueOf(
                                            row.getOrDefault("duration_nights", 0)))));
                    offer.put("flight_price_per_person", flightPrice);
                    offer.put("price_per_person", total);
                    offer.put("total_price_per_person", total);
                    return offer;
                }).toList();
        return Map.of("offers", payload);
    }

    private Map<String, Object> offerFlightPayload(Map<String, Object> row) {
        Object rawId = row.get("linked_flight_id");
        if (!(rawId instanceof Number number)) return Map.of();
        long id = number.longValue();
        Map<String, Object> attributes = flightAttributes(row.get("flight_attributes"));
        Map<String, Object> flight = new LinkedHashMap<>(attributes);
        flight.put("id", "partner-" + id);
        flight.put("partner_listing_id", id);
        flight.put("title", row.get("flight_title"));
        flight.put("city", row.get("flight_city"));
        flight.put("country", row.get("flight_country"));
        flight.put("airline", row.get("flight_airline"));
        flight.put("origin_city", value(attributes, "origin_city",
                text(row.get("flight_city"))));
        flight.put("destination_city", value(attributes, "destination_city", ""));
        flight.put("airline_code", value(attributes, "airline_code", ""));
        flight.put("flight_number", value(attributes, "flight_number", ""));
        flight.put("economy_price", row.get("linked_flight_price"));
        flight.put("airline_logo_url", value(attributes, "airline_logo_url", ""));
        flight.put("source", "partner");
        flight.put("is_active", Boolean.TRUE.equals(row.get("flight_active")));
        flight.put("status", Boolean.TRUE.equals(row.get("flight_active"))
                ? "published" : "inactive");
        return flight;
    }

    @GetMapping("/attractions/search")
    public Map<String, Object> searchMonuments(
            @RequestParam(defaultValue = "") String city,
            @RequestParam(required = false) String category,
            @RequestParam(defaultValue = "") String country,
            @RequestParam(defaultValue = "en") String lang,
            @RequestParam(required = false) String query,
            @RequestParam(required = false) Double lat,
            @RequestParam(required = false) Double lon,
            @RequestParam(name = "bbox_south", required = false) Double bboxSouth,
            @RequestParam(name = "bbox_west", required = false) Double bboxWest,
            @RequestParam(name = "bbox_north", required = false) Double bboxNorth,
            @RequestParam(name = "bbox_east", required = false) Double bboxEast,
            @RequestParam(name = "place_id", required = false) String placeId,
            @RequestParam(defaultValue = "40") int limit,
            @RequestParam(defaultValue = "0") int offset,
            @RequestParam(defaultValue = "false") boolean diagnostics) {
        String categoryFilter = category == null ? "" : category.trim();
        if (query != null && !query.isBlank() && landmarkCatalogService != null) {
            List<Map<String, Object>> matches =
                    landmarkCatalogService.searchCachedPlaces(query, lang, 100);
            if (!matches.isEmpty()) {
                int safeLimit = Math.min(100, Math.max(1, limit));
                int safeOffset = Math.max(0, offset);
                List<Map<String, Object>> page = safeOffset >= matches.size()
                        ? List.of()
                        : matches.subList(safeOffset, Math.min(matches.size(), safeOffset + safeLimit));
                Map<String, Object> response = new LinkedHashMap<>();
                response.put("attractions", page);
                response.put("source", "opentripmap");
                response.put("providers", List.of("opentripmap"));
                response.put("total_count", matches.size());
                response.put("limit", safeLimit);
                response.put("offset", safeOffset);
                response.put("has_more", safeOffset + page.size() < matches.size());
                response.put("warnings", List.of());
                response.put("candidate_count", matches.size());
                response.put("city_found", true);
                return response;
            }
            if (city == null || city.isBlank()) city = query.trim();
        }
        return discoveredAttractions(
                city, country, lang, categoryFilter, lat, lon,
                bboxSouth, bboxWest, bboxNorth, bboxEast, placeId,
                limit, offset, diagnostics);
    }

    public Map<String, Object> searchMonuments(
            String city, String category, String country, String lang) {
        return discoveredAttractions(
                city, country, lang, category == null ? "" : category.trim(),
                null, null, null, null, null, null, null, 40, 0, false);
    }

    @GetMapping("/attractions/suggestions")
    public Map<String, Object> suggestAttractionPlaces(
            @RequestParam(defaultValue = "") String query,
            @RequestParam(defaultValue = "en") String lang,
            @RequestParam(required = false) Double lat,
            @RequestParam(required = false) Double lon) {
        String cacheKey = null;
        Map<String, Object> cacheRequest = new LinkedHashMap<>();
        cacheRequest.put("area_kind", "suggestions");
        cacheRequest.put("query", query == null ? "" : query.trim());
        cacheRequest.put("lang", lang);
        cacheRequest.put("lat", lat);
        cacheRequest.put("lon", lon);
        if (landmarkCatalogService != null) {
            cacheKey = landmarkCatalogService.cacheKey(cacheRequest);
            Map<String, Object> cached = landmarkCatalogService.cachedArea(cacheKey, false);
            if (cached != null && cached.get("suggestions") instanceof List<?>) return cached;
        }

        List<Map<String, Object>> databaseSuggestions = landmarkCatalogService == null
                ? List.of()
                : landmarkCatalogService.searchAliases(query, lang, 12);
        List<Map<String, Object>> providerSuggestions;
        try {
            providerSuggestions = openTripMapAttractionService.suggestPlaces(
                    query, lang, lat, lon);
        } catch (ResponseStatusException exception) {
            if (exception.getStatusCode().value() != 503 || databaseSuggestions.isEmpty()) {
                throw exception;
            }
            providerSuggestions = List.of();
        }
        Map<String, Map<String, Object>> unique = new LinkedHashMap<>();
        for (Map<String, Object> suggestion : databaseSuggestions) {
            unique.putIfAbsent(suggestionIdentity(suggestion), suggestion);
        }
        for (Map<String, Object> suggestion : providerSuggestions) {
            unique.putIfAbsent(suggestionIdentity(suggestion), suggestion);
        }
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("suggestions", List.copyOf(unique.values()));
        response.put("source", "opentripmap");
        response.put("providers", List.of("opentripmap"));
        if (landmarkCatalogService != null && cacheKey != null) {
            landmarkCatalogService.cacheArea(cacheKey, cacheRequest, response);
        }
        return response;
    }

    private static String suggestionIdentity(Map<String, Object> suggestion) {
        String id = text(suggestion.get("place_id"));
        if (id != null && !id.isBlank()) return id;
        return normalizeAttractionText(suggestion.get("label")) + "|"
                + suggestion.getOrDefault("latitude", "") + "|"
                + suggestion.getOrDefault("longitude", "");
    }

    public Map<String, Object> suggestAttractionPlaces(String query, String lang) {
        return suggestAttractionPlaces(query, lang, null, null);
    }

    @GetMapping("/attractions/map")
    public Map<String, Object> searchAttractionMap(
            @RequestParam double south,
            @RequestParam double west,
            @RequestParam double north,
            @RequestParam double east,
            @RequestParam(defaultValue = "8") int zoom,
            @RequestParam(defaultValue = "") String category,
            @RequestParam(name = "min_rate", defaultValue = "0") int minRate,
            @RequestParam(defaultValue = "en") String lang,
            @RequestParam(defaultValue = "100") int limit,
            @RequestParam(defaultValue = "0") int offset) {
        if (south < -90 || north > 90 || south >= north
                || west < -180 || west > 180 || east < -180 || east > 180
                || minRate < 0 || minRate > 3 || zoom < 0 || zoom > 24) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "Invalid map bounds or filter values.");
        }
        Map<String, Object> response = discoveredAttractions(
                "", "", lang, category, null, null,
                south, west, north, east, null,
                Math.min(100, Math.max(1, limit)), Math.max(0, offset), false,
                "viewport", zoom, minRate);
        response.put("map_zoom", zoom);
        response.put("clusters", zoom < 7
                ? clusterAttractions(response.get("attractions"), zoom)
                : List.of());
        return response;
    }

    private static List<Map<String, Object>> clusterAttractions(Object rawPlaces, int zoom) {
        if (!(rawPlaces instanceof List<?> places) || places.isEmpty()) return List.of();
        double cellSize = 0.6 / Math.pow(2, Math.max(0, zoom - 2));
        Map<String, List<Map<String, Object>>> buckets = new LinkedHashMap<>();
        for (Object raw : places) {
            if (!(raw instanceof Map<?, ?> place)) continue;
            Double latitude = toDouble(place.get("latitude"));
            Double longitude = toDouble(place.get("longitude"));
            if (latitude == null || longitude == null) continue;
            String key = (int) Math.floor(latitude / cellSize) + ":"
                    + (int) Math.floor(longitude / cellSize);
            Map<String, Object> copy = new LinkedHashMap<>();
            place.forEach((placeKey, value) ->
                    copy.put(String.valueOf(placeKey), value));
            buckets.computeIfAbsent(key, ignored -> new ArrayList<>()).add(copy);
        }
        List<Map<String, Object>> clusters = new ArrayList<>();
        for (List<Map<String, Object>> bucket : buckets.values()) {
            if (bucket.size() < 2) continue;
            double latitude = bucket.stream()
                    .mapToDouble(place -> toDouble(place.get("latitude"))).average().orElse(0);
            double longitude = bucket.stream()
                    .mapToDouble(place -> toDouble(place.get("longitude"))).average().orElse(0);
            Map<String, Object> cluster = new LinkedHashMap<>();
            cluster.put("latitude", latitude);
            cluster.put("longitude", longitude);
            cluster.put("count", bucket.size());
            cluster.put("places", bucket);
            clusters.add(cluster);
        }
        return List.copyOf(clusters);
    }

    private static Double toDouble(Object value) {
        if (value instanceof Number number) return number.doubleValue();
        if (value == null) return null;
        try {
            return Double.parseDouble(String.valueOf(value));
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    @GetMapping("/attractions/recent-destination")
    public Map<String, Object> recentAttractionDestination(HttpServletRequest request) {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("destination", null);
        Object rawRole = request.getAttribute("authRole");
        String role = rawRole == null ? "" : String.valueOf(rawRole)
                .replace("ROLE_", "").toLowerCase(Locale.ROOT);
        Object rawUserId = request.getAttribute("authUserId");
        if (!"customer".equals(role) || rawUserId == null) return response;

        long userId;
        try {
            userId = Long.parseLong(String.valueOf(rawUserId));
        } catch (NumberFormatException exception) {
            return response;
        }

        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT destination_city, destination_country, created_at
                FROM (
                    SELECT
                        COALESCE(
                            NULLIF(t.destination_city, ''),
                            NULLIF(split_part(t.destination, ',', 1), ''),
                            NULLIF(t.details ->> 'destination_city', '')
                        ) AS destination_city,
                        COALESCE(
                            NULLIF(t.details ->> 'destination_country', ''),
                            NULLIF(t.details ->> 'country', ''),
                            NULLIF(NULLIF(TRIM(split_part(t.destination, ',', 2)), ''), '')
                        ) AS destination_country,
                        t.created_at
                    FROM trips t
                    WHERE t.user_id = ?
                      AND COALESCE(LOWER(t.status), '') NOT IN
                          ('cancelled', 'canceled', 'completed')

                    UNION ALL

                    SELECT
                        COALESCE(
                            NULLIF(b.details ->> 'arrival_city', ''),
                            NULLIF(b.details ->> 'destination_city', ''),
                            NULLIF(b.details ->> 'destination_airport_city', ''),
                            NULLIF(b.details ->> 'hotel_city', ''),
                            NULLIF(b.details ->> 'city', ''),
                            NULLIF(split_part(COALESCE(b.subtitle, ''), ',', 1), ''),
                            NULLIF(b.subtitle, '')
                        ) AS destination_city,
                        COALESCE(
                            NULLIF(b.details ->> 'arrival_country', ''),
                            NULLIF(b.details ->> 'destination_country', ''),
                            NULLIF(b.details ->> 'country', ''),
                            NULLIF(NULLIF(TRIM(split_part(COALESCE(b.subtitle, ''), ',', 2)), ''), '')
                        ) AS destination_country,
                        b.created_at
                    FROM bookings b
                    WHERE b.user_id = ?
                      AND LOWER(COALESCE(b.type, '')) IN
                          ('flight', 'hotel', 'package', 'attraction')
                      AND COALESCE(LOWER(b.status), '') NOT IN
                          ('cancelled', 'canceled', 'completed')
                ) recent
                WHERE NULLIF(TRIM(destination_city), '') IS NOT NULL
                ORDER BY created_at DESC
                LIMIT 1
                """, userId, userId);
        if (!rows.isEmpty()) {
            Map<String, Object> row = rows.getFirst();
            Map<String, Object> destination = new LinkedHashMap<>();
            destination.put("city", row.get("destination_city"));
            destination.put("country", row.get("destination_country"));
            Object createdAt = row.get("created_at");
            destination.put("created_at", createdAt == null ? null : createdAt.toString());
            response.put("destination", destination);
        }
        return response;
    }

    private Map<String, Object> discoveredAttractions(
            String city,
            String country,
            String language,
            String category,
            Double latitude,
            Double longitude,
            Double bboxSouth,
            Double bboxWest,
            Double bboxNorth,
            Double bboxEast,
            String placeId,
            int requestedLimit,
            int requestedOffset,
            boolean diagnostics) {
        return discoveredAttractions(
                city, country, language, category, latitude, longitude,
                bboxSouth, bboxWest, bboxNorth, bboxEast, placeId,
                requestedLimit, requestedOffset, diagnostics,
                "destination", null, 0);
    }

    private Map<String, Object> discoveredAttractions(
            String city,
            String country,
            String language,
            String category,
            Double latitude,
            Double longitude,
            Double bboxSouth,
            Double bboxWest,
            Double bboxNorth,
            Double bboxEast,
            String placeId,
            int requestedLimit,
            int requestedOffset,
            boolean diagnostics,
            String areaKind,
            Integer zoom,
            int minimumRate) {
        if (isBlankString(city) && isBlankString(country)
                && latitude == null && longitude == null
                && bboxSouth == null && bboxWest == null && bboxNorth == null
                && bboxEast == null && isBlankString(placeId)) {
            return curatedAttractionsPage(category, requestedLimit, requestedOffset);
        }
        Map<String, Object> cacheRequest = new LinkedHashMap<>();
        cacheRequest.put("area_kind", areaKind);
        cacheRequest.put("city", city);
        cacheRequest.put("country", country);
        cacheRequest.put("lang", language);
        cacheRequest.put("category", category);
        cacheRequest.put("lat", latitude);
        cacheRequest.put("lon", longitude);
        cacheRequest.put("south", bboxSouth);
        cacheRequest.put("west", bboxWest);
        cacheRequest.put("north", bboxNorth);
        cacheRequest.put("east", bboxEast);
        cacheRequest.put("place_id", placeId);
        cacheRequest.put("limit", requestedLimit);
        cacheRequest.put("offset", requestedOffset);
        cacheRequest.put("diagnostics", diagnostics);
        cacheRequest.put("zoom", zoom);
        cacheRequest.put("min_rate", minimumRate);
        String cacheKey = landmarkCatalogService == null
                ? null : landmarkCatalogService.cacheKey(cacheRequest);
        Map<String, Object> staleCache = null;
        if (landmarkCatalogService != null && cacheKey != null) {
            Map<String, Object> freshCache =
                    landmarkCatalogService.cachedArea(cacheKey, false);
            if (freshCache != null) return freshCache;
            staleCache = landmarkCatalogService.cachedArea(cacheKey, true);
        }
        OpenTripMapAttractionService.SearchOutcome outcome =
                searchLandmarks(city, country, language, category, latitude, longitude,
                        bboxSouth, bboxWest, bboxNorth, bboxEast, placeId, staleCache);
        if (outcome == null) return staleCache;
        List<Map<String, Object>> discovered = landmarkCatalogService == null
                ? outcome.places()
                : landmarkCatalogService.persistAndCanonicalize(outcome.places());
        if (minimumRate > 0) {
            discovered = discovered.stream()
                    .filter(place -> {
                        Double rating = toDouble(place.get("rating"));
                        return rating != null && rating >= minimumRate;
                    })
                    .toList();
        }
        int totalCount = discovered.size();
        int limit = Math.min(100, Math.max(1, requestedLimit));
        int offset = Math.max(0, requestedOffset);
        List<Map<String, Object>> page = offset >= totalCount ? List.of()
                : discovered.subList(offset, Math.min(totalCount, offset + limit));
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("attractions", page);
        response.put("source", "opentripmap");
        response.put("providers", List.of("opentripmap"));
        response.put("total_count", totalCount);
        response.put("limit", limit);
        response.put("offset", offset);
        response.put("has_more", offset + page.size() < totalCount);
        response.put("dropped_by_reason", outcome.droppedByReason());
        response.put("dropped_count", outcome.droppedByReason().values().stream()
                .mapToInt(Integer::intValue).sum());
        response.put("warnings", outcome.warnings());
        response.put("candidate_count", outcome.candidateCount());
        response.put("city_found", outcome.cityFound());
        if (diagnostics) {
            response.put("dropped_items", outcome.droppedItems().stream()
                    .map(item -> {
                        Map<String, Object> rejected = new LinkedHashMap<>();
                        rejected.put("name", item.name());
                        rejected.put("id", item.id());
                        rejected.put("category", item.category());
                        rejected.put("source", item.source());
                        rejected.put("reason", item.reason());
                        return rejected;
                    })
                    .toList());
        }
        if (landmarkCatalogService != null && cacheKey != null) {
            landmarkCatalogService.cacheArea(cacheKey, cacheRequest, response);
        }
        return response;
    }

    private Map<String, Object> curatedAttractionsPage(
            String category, int requestedLimit, int requestedOffset) {
        List<Map<String, Object>> all = curatedAttractions("", "").stream()
                .filter(place -> isBlankString(category)
                        || category.equalsIgnoreCase(String.valueOf(place.get("category"))))
                .toList();
        int limit = Math.min(100, Math.max(1, requestedLimit));
        int offset = Math.max(0, requestedOffset);
        List<Map<String, Object>> page = offset >= all.size()
                ? List.of()
                : all.subList(offset, Math.min(all.size(), offset + limit));
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("attractions", page);
        response.put("source", "database");
        response.put("providers", List.of("database"));
        response.put("total_count", all.size());
        response.put("limit", limit);
        response.put("offset", offset);
        response.put("has_more", offset + page.size() < all.size());
        response.put("warnings", List.of());
        response.put("candidate_count", all.size());
        response.put("city_found", true);
        return response;
    }

    private OpenTripMapAttractionService.SearchOutcome searchLandmarks(
            String city, String country, String language, String category,
            Double latitude, Double longitude, Double south, Double west,
            Double north, Double east, String placeId, Map<String, Object> staleCache) {
        try {
            if (containsArabic(city) && !isBlankString(country)
                    && geoapifyAirportService != null) {
                OpenTripMapAttractionService.SearchOutcome localized =
                        searchAtGeocodedCity(city, country, language, category,
                                south, west, north, east, placeId);
                if (localized != null) return localized;
            }
            OpenTripMapAttractionService.SearchOutcome outcome =
                    openTripMapAttractionService.searchAttractionsWithStatus(
                    city, country, language, category, latitude, longitude,
                    south, west, north, east, placeId);
            if (outcome.cityFound() || isBlankString(city)
                    || isBlankString(country) || geoapifyAirportService == null) {
                return outcome;
            }
            OpenTripMapAttractionService.SearchOutcome geocoded =
                    searchAtGeocodedCity(city, country, language, category,
                            south, west, north, east, placeId);
            return geocoded == null ? outcome : geocoded;
        } catch (ResponseStatusException exception) {
            if (exception.getStatusCode().value() != 503 || staleCache == null) {
                throw exception;
            }
            List<String> warnings = new ArrayList<>();
            Object previousWarnings = staleCache.get("warnings");
            if (previousWarnings instanceof List<?> values) {
                values.stream().map(String::valueOf).forEach(warnings::add);
            }
            warnings.add("OpenTripMap is unavailable; showing previously cached landmarks.");
            staleCache.put("warnings", warnings.stream().distinct().toList());
            staleCache.put("cache_stale", true);
            return null;
        }
    }

    private OpenTripMapAttractionService.SearchOutcome searchAtGeocodedCity(
            String city, String country, String language, String category,
            Double south, Double west, Double north, Double east, String placeId) {
        String countryHint = country.trim();
        String geocodeQuery = city.trim();
        if (!countryHint.matches("(?i)[a-z]{2}")) {
            // Keep a full country name attached to the city to reduce
            // ambiguous homonym resolution; never geocode an unqualified city.
            geocodeQuery += ", " + countryHint;
            countryHint = "";
        }
        GeoapifyAirportService.GeocodedPlace location =
                geoapifyAirportService.resolveLocation(geocodeQuery, countryHint);
        if (location == null) return null;
        return openTripMapAttractionService.searchAttractionsWithStatus(
                firstNonBlank(location.city(), location.name(), city),
                firstNonBlank(location.country(), country),
                language,
                category,
                location.latitude(),
                location.longitude(),
                south,
                west,
                north,
                east,
                placeId);
    }

    private static boolean containsArabic(String value) {
        return value != null && value.codePoints().anyMatch(codePoint ->
                Character.UnicodeScript.of(codePoint) == Character.UnicodeScript.ARABIC);
    }

    private static String firstNonBlank(String first, String second, String fallback) {
        if (first != null && !first.isBlank()) return first;
        if (second != null && !second.isBlank()) return second;
        return fallback;
    }

    private static String firstNonBlank(String first, String fallback) {
        return firstNonBlank(first, null, fallback);
    }

    @GetMapping("/attractions/nearby")
    public Map<String, Object> nearbyAttractions(
            @RequestParam double lat,
            @RequestParam double lng,
            @RequestParam(defaultValue = "5000") double radius,
            @RequestParam(required = false) String category,
            @RequestParam(defaultValue = "en") String lang) {
        List<Map<String, Object>> attractions =
                openTripMapAttractionService.searchNearby(
                        lat, lng, radius, category, lang);
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("attractions", attractions);
        response.put("source", "opentripmap");
        response.put("providers", List.of("opentripmap"));
        return response;
    }

    private List<Map<String, Object>> curatedAttractions(String city, String country) {
        String cityFilter = city == null ? "" : city.trim();
        String countryFilter = country == null ? "" : country.trim();
        List<Map<String, Object>> rows = jdbc.queryForList("""
                WITH country_visits AS (
                    SELECT LOWER(TRIM(split_part(related.location, ',', -1))) AS country,
                           COUNT(DISTINCT dedup.visitor_hash) AS country_visit_count
                    FROM tourist_monuments related
                    JOIN attraction_visit_dedup dedup
                        ON dedup.attraction_id = related.id
                    WHERE related.is_active = TRUE
                      AND POSITION(',' IN related.location) > 0
                    GROUP BY LOWER(TRIM(split_part(related.location, ',', -1)))
                )
                SELECT
                    monument.id,
                    monument.title,
                    monument.location,
                    COALESCE(NULLIF(TRIM(split_part(monument.location, ',', 1)), ''),
                             monument.location) AS city,
                    CASE WHEN POSITION(',' IN monument.location) > 0
                         THEN TRIM(split_part(monument.location, ',', -1))
                         ELSE '' END AS country,
                    monument.category,
                    monument.category_tag,
                    monument.rating,
                    monument.review_count,
                    monument.description,
                    monument.working_hours,
                    monument.best_time_to_visit,
                    monument.entry_fee,
                    monument.image_url,
                    monument.tags::text AS tags_json,
                    COALESCE(visits.visit_count, 0) AS visit_count,
                    COALESCE(country_visits.country_visit_count, 0) AS country_visit_count
                FROM tourist_monuments monument
                LEFT JOIN attraction_visit_counts visits
                    ON visits.attraction_id = monument.id
                LEFT JOIN country_visits
                    ON POSITION(',' IN monument.location) > 0
                   AND country_visits.country =
                       LOWER(TRIM(split_part(monument.location, ',', -1)))
                WHERE monument.is_active = TRUE
                  AND NULLIF(TRIM(monument.image_url), '') IS NOT NULL
                  AND (? = '' OR LOWER(TRIM(split_part(monument.location, ',', 1))) =
                                  LOWER(TRIM(?)))
                  AND (? = '' OR (POSITION(',' IN monument.location) > 0
                      AND LOWER(TRIM(split_part(monument.location, ',', -1))) =
                          LOWER(TRIM(?))))
                ORDER BY monument.sort_order, monument.rating DESC, monument.title
                """, cityFilter, cityFilter, countryFilter, countryFilter);
        return rows.stream().map(ApiController::mapCuratedAttraction).toList();
    }

    private static Map<String, Object> mapCuratedAttraction(Map<String, Object> row) {
        Map<String, Object> place = new LinkedHashMap<>();
        String name = text(row.get("title"));
        place.put("id", row.get("id"));
        place.put("name", name);
        place.put("name_en", name);
        place.put("city", row.get("city"));
        place.put("country", row.get("country"));
        place.put("location", row.get("location"));
        place.put("description", row.get("description"));
        place.put("category", row.get("category"));
        place.put("category_tag", row.get("category_tag"));
        place.put("rating", row.get("rating"));
        place.put("review_count", row.get("review_count"));
        place.put("visit_count", row.get("visit_count"));
        place.put("country_visit_count", row.get("country_visit_count"));
        place.put("entry_fee", row.get("entry_fee"));
        place.put("image_url", row.get("image_url"));
        place.put("latitude", 0);
        place.put("longitude", 0);
        place.put("opening_hours", row.get("working_hours"));
        place.put("best_time_to_visit", row.get("best_time_to_visit"));
        place.put("tags", parseAttractionTags(row.get("tags_json")));
        place.put("source_provider", "database");
        return place;
    }

    private static List<String> parseAttractionTags(Object rawTags) {
        if (rawTags == null) return List.of();
        try {
            Object parsed = JSON.readValue(String.valueOf(rawTags), Object.class);
            if (parsed instanceof List<?> values) {
                return values.stream().filter(value -> value != null)
                        .map(String::valueOf).toList();
            }
            return List.of();
        } catch (Exception exception) {
            throw new IllegalStateException("Stored attraction tags are invalid JSON", exception);
        }
    }

    private static List<Map<String, Object>> mergeCuratedAttractions(
            List<Map<String, Object>> discovered,
            List<Map<String, Object>> curated) {
        List<Map<String, Object>> merged = new ArrayList<>();
        Map<String, Map<String, Object>> byIdentity = new LinkedHashMap<>();
        for (Map<String, Object> item : discovered) {
            Map<String, Object> copy = new LinkedHashMap<>(item);
            String identity = attractionNameLocationKey(copy);
            merged.add(copy);
            if (identity != null) byIdentity.putIfAbsent(identity, copy);
        }
        for (Map<String, Object> item : curated) {
            String identity = attractionNameLocationKey(item);
            Map<String, Object> existing = identity == null ? null : byIdentity.get(identity);
            if (existing != null) {
                existing.put("visit_count", item.get("visit_count"));
                existing.put("country_visit_count", item.get("country_visit_count"));
                continue;
            }
            merged.add(item);
            if (identity != null) byIdentity.put(identity, item);
        }
        return merged;
    }

    private static String attractionNameLocationKey(Map<String, Object> place) {
        String name = normalizeAttractionText(place.getOrDefault("name", place.get("title")));
        if (name.isBlank()) return null;
        String city = normalizeAttractionText(place.get("city"));
        String country = normalizeAttractionText(place.get("country"));
        return name + "|" + city + "|" + country;
    }

    private static boolean isBlankString(String value) {
        return value == null || value.isBlank();
    }

    private static String normalizeAttractionText(Object value) {
        String text = value == null ? "" : String.valueOf(value).trim().toLowerCase(Locale.ROOT);
        return Normalizer.normalize(text, Normalizer.Form.NFD)
                .replaceAll("\\p{M}+", "")
                .replaceAll("[^\\p{L}\\p{N}]+", " ")
                .trim();
    }

    @PostMapping("/attractions/{id}/visits")
    @Transactional
    public Map<String, Object> recordAttractionVisit(
            @PathVariable String id,
            @RequestBody Map<String, Object> body) {
        String visitorId = text(body.get("visitor_id")).trim();
        if (id.isBlank() || id.length() > 64
                || !visitorId.matches("^[a-f0-9]{32}$")) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "Invalid place visit details");
        }
        Boolean active = jdbc.queryForObject(
                "SELECT EXISTS (SELECT 1 FROM tourist_monuments WHERE id = ? AND is_active = TRUE)",
                Boolean.class, id);
        if (!Boolean.TRUE.equals(active)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Place not found");
        }
        if (!visitBurstRateLimiter.tryAcquire()) {
            throw new ResponseStatusException(
                    HttpStatus.TOO_MANY_REQUESTS, "Too many place visits; try again shortly");
        }

        String visitorHash = sha256(visitorId);
        jdbc.update("""
                DELETE FROM attraction_visit_dedup
                WHERE counted_at < NOW() - INTERVAL '48 hours'
                """);
        int inserted = jdbc.update("""
                INSERT INTO attraction_visit_dedup (attraction_id, visitor_hash)
                VALUES (?, ?)
                ON CONFLICT (attraction_id, visitor_hash) DO NOTHING
                """, id, visitorHash);
        if (inserted > 0) {
            jdbc.update("""
                    INSERT INTO attraction_visit_counts (attraction_id, visit_count)
                    VALUES (?, 1)
                    ON CONFLICT (attraction_id)
                    DO UPDATE SET visit_count = attraction_visit_counts.visit_count + 1
                    """, id);
        }
        return Map.of("counted", inserted > 0);
    }

    private static final class VisitBurstRateLimiter {
        private static final int CAPACITY = 60;
        private static final double REFILL_TOKENS_PER_NANO =
                (double) CAPACITY / TimeUnit.MINUTES.toNanos(1);

        private double availableTokens = CAPACITY;
        private long lastRefillNanos = System.nanoTime();

        synchronized boolean tryAcquire() {
            long now = System.nanoTime();
            long elapsedNanos = Math.max(0, now - lastRefillNanos);
            availableTokens = Math.min(
                    CAPACITY, availableTokens + elapsedNanos * REFILL_TOKENS_PER_NANO);
            lastRefillNanos = now;
            if (availableTokens < 1) {
                return false;
            }
            availableTokens -= 1;
            return true;
        }
    }

    private static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is not available", exception);
        }
    }

    private static List<String> parseHighlights(Object raw) {
        if (raw instanceof List<?> list) {
            return list.stream().map(Object::toString).toList();
        }
        if (raw == null) return List.of();
        try {
            return JSON.readValue(
                    raw.toString(),
                    JSON.getTypeFactory().constructCollectionType(List.class, String.class));
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            return List.of();
        }
    }

    @GetMapping("/trips")
    public Map<String, Object> trips(HttpServletRequest request) {
        long userId = requireUserId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT trips.*,
                   details ->> 'arrival_date' AS arrival_date,
                   details ->> 'source' AS source,
                   details ->> 'duffel_offer_id' AS duffel_offer_id,
                   details ->> 'price_currency' AS price_currency,
                   details ->> 'is_simulated' AS is_simulated,
                   ARRAY(SELECT jsonb_array_elements_text(COALESCE(
                       details -> 'selected_seats', details -> 'seat_numbers',
                       '[]'::jsonb))) AS selected_seats,
                   ARRAY(SELECT jsonb_array_elements_text(COALESCE(
                       details -> 'extras', '[]'::jsonb))) AS extras,
                   details ->> 'refund_status' AS refund_status,
                   details ->> 'refund_method' AS refund_method
            FROM trips WHERE user_id = ? ORDER BY created_at DESC
            """, userId);
        return Map.of("trips", rows.stream()
                .map(ApiController::normalizeTripHistoryRow)
                .toList());
    }

    @PostMapping("/trips")
    @Transactional
    public ResponseEntity<?> createTrip(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        long userId = requireUserId(request);
        Long paymentAttemptId = lockSuccessfulPaymentAttempt(body, userId);
        String originCode = required(body, "origin_code");
        String originCity = required(body, "origin_city");
        String destinationCode = required(body, "destination_code");
        String destinationCity = required(body, "destination_city");
        OffsetDateTime departure = flightDateTime(required(body, "departure_date"));
        OffsetDateTime arrival = flightDateTime(required(body, "arrival_date"));
        OffsetDateTime returnDate = nullableFlightDateTime(body.get("return_date"));
        if (!arrival.isAfter(departure)) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "arrival_date must be after departure_date");
        }
        if (returnDate != null && returnDate.isBefore(departure)) {
            throw new ResponseStatusException(
                HttpStatus.UNPROCESSABLE_ENTITY, "return_date must not be before departure_date");
        }
        int passengerCount = integer(body.get("passenger_count"), 1);
        if (passengerCount < 1) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "passenger_count must be at least 1");
        }
        String flightNumber = required(body, "flight_number");
        PartnerListingAttribution attribution =
                partnerListingAttribution(body.get("partner_listing_id"), "flight");
        BigDecimal price = partnerBookingPrice(
                attribution, "flight", departure, arrival, decimal(body.get("price")));
        Map<String, Object> providerDetails = new java.util.HashMap<>();
        if ("duffel".equalsIgnoreCase(value(body, "source", ""))) {
            providerDetails.put("source", "duffel");
            providerDetails.put(
                    "duffel_offer_id", value(body, "duffel_offer_id", flightNumber));
            providerDetails.put(
                    "price_currency", value(body, "price_currency", "USD").toUpperCase());
            providerDetails.put("is_simulated", true);
            providerDetails.put("selected_seats", stringList(body.get("selected_seats")));
            providerDetails.put("extras", stringList(body.get("extras")));
        }
        String providerDetailsJson = JSON.valueToTree(providerDetails).toString();
        jdbc.queryForList("SELECT id FROM users WHERE id = ? FOR UPDATE", userId);
        if (hasFlightScheduleConflict(userId, departure, arrival, returnDate)) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("message", "FLIGHT_SCHEDULE_CONFLICT"));
        }
        reserveFlightSeats(attribution.listingId(), passengerCount);
        long id = insert("""
                INSERT INTO trips (user_id, partner_id, partner_listing_id, title, destination, origin_code, origin_city, destination_code,
                destination_city, departure_date, return_date, flight_number, airline, airline_logo_url,
                is_direct, seat_class, price, booking_ref, status, details, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, jsonb_build_object('arrival_date', ?, 'passenger_count', ?) || ?::jsonb, NOW(), NOW())
                """, userId, attribution.partnerId(), attribution.listingId(),
                originCity + " to " + destinationCity, destinationCity, originCode, originCity,
                destinationCode, destinationCity, departure,
                returnDate,
                flightNumber, body.get("airline"), body.get("airline_logo_url"), bool(body.get("is_direct"), true),
                value(body, "seat_class", "Economy"), price, body.get("booking_ref"),
                "upcoming", arrival.toString(), passengerCount, providerDetailsJson);
        if (paymentAttemptId != null) {
            linkPaymentAttemptToTrip(paymentAttemptId, userId, id);
        }
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("trip", tripRow(id)));
    }

    @GetMapping("/flights/{flightId}/seats")
    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    public Map<String, Object> flightSeats(
            @PathVariable long flightId,
            HttpServletRequest request) {
        requireUserId(request);
        Map<String, Object> listing = flightListing(flightId, false);
        List<String> occupied = occupiedFlightSeats(flightId);
        Integer holds = jdbc.queryForObject("""
                SELECT COUNT(*) FROM flight_seat_holds
                WHERE flight_listing_id = ? AND status = 'reserved' AND expires_at > NOW()
                """, Integer.class, flightId);
        return FlightSeatConfiguration.response(listing, occupied, holds == null ? 0 : holds);
    }

    @PostMapping("/flights/{flightId}/seats/reserve")
    @Transactional
    public Map<String, Object> reserveFlightSeatSelection(
            @PathVariable long flightId,
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        Map<String, Object> listing = flightListing(flightId, true);
        List<String> seats = validatedFlightSeats(body.get("seats"), listing);

        jdbc.update("""
                DELETE FROM flight_seat_holds
                WHERE flight_listing_id = ? AND status = 'reserved'
                  AND expires_at <= NOW()
                """, flightId);
        jdbc.update("""
                DELETE FROM flight_seat_holds
                WHERE flight_listing_id = ? AND user_id = ? AND status = 'reserved'
                """, flightId, userId);

        Set<String> occupied = new LinkedHashSet<>(occupiedFlightSeats(flightId));
        if (seats.stream().anyMatch(occupied::contains)) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "One or more selected seats are already taken");
        }
        int activeHolds = jdbc.queryForObject("""
                SELECT COUNT(*) FROM flight_seat_holds
                WHERE flight_listing_id = ? AND status = 'reserved'
                  AND expires_at > NOW()
                """, Integer.class, flightId);
        int availableSeats = integer(listing.get("seats_available"), 0);
        if (availableSeats < activeHolds + seats.size()) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Not enough seats remain on this flight");
        }

        for (String seat : seats) {
            jdbc.update("""
                    INSERT INTO flight_seat_holds
                        (flight_listing_id, user_id, seat_number, status, expires_at, created_at, updated_at)
                    VALUES (?, ?, ?, 'reserved', NOW() + INTERVAL '15 minutes', NOW(), NOW())
                    """, flightId, userId, seat);
        }
        return Map.of(
                "occupied_seats", occupiedFlightSeats(flightId),
                "expires_in_seconds", 900);
    }

    @DeleteMapping("/flights/{flightId}/seats/reserve")
    @Transactional
    public Map<String, Object> releaseFlightSeatSelection(
            @PathVariable long flightId,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        flightListing(flightId, false);
        int released = jdbc.update("""
                DELETE FROM flight_seat_holds
                WHERE flight_listing_id = ? AND user_id = ? AND status = 'reserved'
                """, flightId, userId);
        return Map.of("released", released > 0);
    }

    @PostMapping("/bookings/confirm")
    @Transactional
    public ResponseEntity<?> confirmFlightBooking(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        long flightId;
        try {
            flightId = Long.parseLong(required(body, "flight_id"));
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "Invalid flight_id");
        }
        Map<String, Object> listing = flightListing(flightId, true);
        List<String> seats = validatedFlightSeats(body.get("seats"), listing);
        String packageOfferId = text(body.get("offer_id")).trim();
        Map<String, Object> packageOffer = packageOfferId.isEmpty()
                ? null : packageOfferForFlight(packageOfferId, flightId);
        List<String> extras = validatedFlightExtras(body.get("extras"));
        String seatClass = value(body, "seat_class", "economy")
                .trim().toLowerCase(Locale.ROOT);
        if (!Set.of("economy", "business", "first").contains(seatClass)) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "Unsupported seat_class");
        }

        ResponseEntity<?> existingConfirmation =
                existingSeatConfirmation(flightId, userId, seats);
        if (existingConfirmation != null) return existingConfirmation;
        Long paymentAttemptId = lockSuccessfulPaymentAttempt(body, userId);

        for (String seat : seats) {
            List<String> held = jdbc.queryForList("""
                    SELECT seat_number FROM flight_seat_holds
                    WHERE flight_listing_id = ? AND user_id = ? AND seat_number = ?
                      AND status = 'reserved' AND expires_at > NOW()
                    FOR UPDATE
                    """, String.class, flightId, userId, seat);
            if (held.size() != 1) {
                throw new ResponseStatusException(
                        HttpStatus.CONFLICT, "Seat reservation expired. Please select seats again.");
            }
        }

        Map<String, Object> attributes = flightAttributes(listing.get("attributes"));
        String originCode = requiredAttribute(attributes, "origin_code");
        String originCity = requiredAttribute(attributes, "origin_city");
        String destinationCode = requiredAttribute(attributes, "destination_code");
        String destinationCity = requiredAttribute(attributes, "destination_city");
        OffsetDateTime departure = flightDateTime(
                requiredAttribute(attributes, "departure_time"));
        OffsetDateTime arrival = flightDateTime(
                requiredAttribute(attributes, "arrival_time"));
        OffsetDateTime returnDate = nullableFlightDateTime(body.get("return_date"));
        if (!arrival.isAfter(departure)) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "Flight arrival must follow departure");
        }
        if (returnDate != null && returnDate.isBefore(departure)) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "return_date must not precede departure_date");
        }

        jdbc.queryForList("SELECT id FROM users WHERE id = ? FOR UPDATE", userId);
        if (hasFlightScheduleConflict(userId, departure, arrival, returnDate)) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("message", "FLIGHT_SCHEDULE_CONFLICT"));
        }

        BigDecimal baseFare = flightFare(listing, seatClass);
        BigDecimal seatFees = BigDecimal.valueOf(
                seats.stream().filter(seat -> isPremiumSeat(seat, listing)).count())
                .multiply(FlightSeatConfiguration.LEGROOM_FEE);
        BigDecimal extraFees = extras.stream()
                .map(ApiController::flightExtraPrice)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal totalPrice = baseFare.multiply(BigDecimal.valueOf(seats.size()))
                .add(seatFees)
                .add(extraFees)
                .multiply(BigDecimal.ONE.add(FlightSeatConfiguration.TAX_RATE))
                .add(FlightSeatConfiguration.BOOKING_FEE)
                .setScale(2, RoundingMode.HALF_UP);
        BigDecimal packageStayTotal = BigDecimal.ZERO;
        if (packageOffer != null) {
            BigDecimal hotelNightly = decimal(packageOffer.get("hotel_price_per_night"));
            int nights = integer(packageOffer.get("duration_nights"), 1);
            packageStayTotal = hotelNightly
                    .multiply(BigDecimal.valueOf((long) nights * seats.size()))
                    .setScale(2, RoundingMode.HALF_UP);
            OffsetDateTime stayEnd = departure.plusDays(nights);
            if (hasBookingScheduleConflict(
                    userId, "package", text(packageOffer.get("title")), departure, stayEnd)) {
                return ResponseEntity.status(HttpStatus.CONFLICT)
                        .body(Map.of("message", "BOOKING_SCHEDULE_CONFLICT"));
            }
            totalPrice = totalPrice.add(packageStayTotal)
                    .setScale(2, RoundingMode.HALF_UP);
        }

        reserveFlightSeats(flightId, seats.size());
        String reference = "ZT-" + UUID.randomUUID().toString()
                .substring(0, 8).toUpperCase(Locale.ROOT);
        String airline = text(listing.get("partner_name"));
        String flightNumber = value(attributes.get("flight_number"), "");
        String airlineLogoUrl = text(attributes.get("airline_logo_url"));
        boolean isDirect = bool(attributes.get("is_direct"), true);
        String seatClassLabel = Character.toUpperCase(seatClass.charAt(0))
                + seatClass.substring(1);
        Map<String, Object> details = new LinkedHashMap<>();
        details.put("arrival_date", arrival.toString());
        details.put("passenger_count", seats.size());
        details.put("seat_numbers", seats);
        details.put("extras", extras);
        if (packageOffer != null) {
            details.put("offer_id", packageOfferId);
            details.put("package_title", text(packageOffer.get("title")));
            details.put("hotel_price_per_night",
                    decimal(packageOffer.get("hotel_price_per_night")));
            details.put("package_nights",
                    integer(packageOffer.get("duration_nights"), 1));
            details.put("hotel_total", packageStayTotal);
        }
        String detailsJson;
        try {
            detailsJson = JSON.writeValueAsString(details);
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalStateException("Could not encode flight booking details", exception);
        }

        long tripId = insert("""
                INSERT INTO trips
                    (user_id, partner_id, partner_listing_id, title, destination,
                     origin_code, origin_city, destination_code, destination_city,
                     departure_date, return_date, flight_number, airline, airline_logo_url,
                     is_direct, seat_class, price, booking_ref, status, details, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'upcoming',
                        CAST(? AS JSON), NOW(), NOW())
                """,
                userId, number(listing.get("partner_id")), flightId,
                originCity + " to " + destinationCity, destinationCity,
                originCode, originCity, destinationCode, destinationCity,
                departure,
                returnDate,
                flightNumber, airline,
                airlineLogoUrl.isBlank() ? null : airlineLogoUrl,
                isDirect, seatClassLabel, totalPrice, reference, detailsJson);
        Long packageBookingId = null;
        if (packageOffer != null) {
            Map<String, Object> packageDetails = new LinkedHashMap<>();
            packageDetails.put("trip_id", tripId);
            packageDetails.put("offer_id", packageOfferId);
            packageDetails.put("flight_listing_id", flightId);
            packageDetails.put("airline", airline);
            packageDetails.put("flight_number", flightNumber);
            packageDetails.put("seats", seats);
            packageDetails.put("seat_class", seatClassLabel);
            packageDetails.put("hotel_price_per_night",
                    decimal(packageOffer.get("hotel_price_per_night")));
            packageDetails.put("duration_nights",
                    integer(packageOffer.get("duration_nights"), 1));
            packageDetails.put("hotel_total", packageStayTotal);
            packageDetails.put("image_url", packageOffer.get("image_url"));
            packageDetails.put("start_date", departure.toString());
            packageDetails.put("end_date", departure.plusDays(
                    integer(packageOffer.get("duration_nights"), 1)).toString());
            String packageDetailsJson;
            try {
                packageDetailsJson = JSON.writeValueAsString(packageDetails);
            } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
                throw new IllegalStateException(
                        "Could not encode package booking details", exception);
            }
            packageBookingId = insert("""
                    INSERT INTO bookings
                        (user_id, partner_id, partner_listing_id, trip_id, type, status,
                         total_amount, title, subtitle, "date", price, ref_code, details,
                         created_at, updated_at)
                    VALUES (?, ?, ?, ?, 'package', 'upcoming', ?, ?, ?, ?, ?, ?,
                            CAST(? AS JSONB), NOW(), NOW())
                    """,
                    userId,
                    number(listing.get("partner_id")),
                    flightId,
                    tripId,
                    totalPrice,
                    text(packageOffer.get("title")),
                    text(packageOffer.get("location")) + ", "
                            + text(packageOffer.get("country")),
                    departure,
                    totalPrice,
                    reference,
                    packageDetailsJson);
        }
        if (paymentAttemptId != null) {
            linkPaymentAttemptToTrip(paymentAttemptId, userId, tripId);
        }
        String confirmationSql = """
                UPDATE flight_seat_holds
                SET status = 'confirmed', booking_ref = ?, trip_id = ?, updated_at = NOW()
                WHERE flight_listing_id = ? AND user_id = ? AND seat_number IN (%s)
                  AND status = 'reserved' AND expires_at > NOW()
                """.formatted(String.join(",", java.util.Collections.nCopies(seats.size(), "?")));
        int confirmed = jdbc.update(
                confirmationSql,
                buildSeatConfirmationArgs(reference, tripId, flightId, userId, seats));
        if (confirmed != seats.size()) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Seat reservation expired during confirmation");
        }

        String flightRoute = originCity + " to " + destinationCity;
        String flightRouteArabic = "من " + originCity + " إلى " + destinationCity;
        String notificationTitle = packageOffer == null
                ? "Flight booking confirmed" : "Travel package booking confirmed";
        String notificationTitleArabic = packageOffer == null
                ? "تم تأكيد حجز الرحلة" : "تم تأكيد حجز الباقة السياحية";
        String notificationMessage = packageOffer == null
                ? "Your flight " + flightRoute + " is confirmed. Reference: " + reference + "."
                : "Your package " + text(packageOffer.get("title"))
                        + " and flight " + flightRoute
                        + " are confirmed. Reference: " + reference + ".";
        String notificationMessageArabic = packageOffer == null
                ? "تم تأكيد رحلتك " + flightRouteArabic + ". رقم الحجز: " + reference + "."
                : "تم تأكيد باقتك " + text(packageOffer.get("title"))
                        + " ورحلتك " + flightRouteArabic
                        + ". رقم الحجز: " + reference + ".";
        insertUserNotification(
                userId,
                (packageOffer == null ? "flight-booking:" + tripId
                        : "package-booking:" + packageBookingId),
                "booking",
                notificationTitle,
                notificationTitleArabic,
                notificationMessage,
                notificationMessageArabic,
                packageOffer == null ? "trip" : "booking",
                packageOffer == null ? tripId : packageBookingId,
                reference);

        Map<String, Object> booking = new LinkedHashMap<>();
        booking.put("reference", reference);
        booking.put("seats", seats);
        booking.put("extras", extras);
        booking.put("total_price", totalPrice);
        if (packageBookingId != null) {
            booking.put("package_booking_id", packageBookingId);
            booking.put("hotel_total", packageStayTotal);
        }
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                "booking", booking,
                "trip", tripRow(tripId)));
    }

    private Map<String, Object> packageOfferForFlight(String offerId, long flightId) {
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, title, location, country, image_url,
                       hotel_price_per_night, duration_nights, flight_listing_id
                FROM offers
                WHERE id = ? AND is_active = TRUE
                FOR SHARE
                """, offerId);
        if (rows.isEmpty()) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND, "Travel offer is unavailable");
        }
        Map<String, Object> offer = rows.getFirst();
        Object linkedFlight = offer.get("flight_listing_id");
        if (!(linkedFlight instanceof Number number)
                || number.longValue() != flightId) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY,
                    "The selected flight is not linked to this offer");
        }
        return offer;
    }

    private ResponseEntity<?> existingSeatConfirmation(
            long flightId,
            long userId,
            List<String> seats) {
        String sql = """
                SELECT h.seat_number, h.trip_id, t.booking_ref, t.price, t.details
                FROM flight_seat_holds h
                JOIN trips t ON t.id = h.trip_id AND t.user_id = h.user_id
                WHERE h.flight_listing_id = ? AND h.user_id = ?
                  AND h.seat_number IN (%s) AND h.status = 'confirmed'
                FOR UPDATE
                """.formatted(String.join(",", java.util.Collections.nCopies(seats.size(), "?")));
        List<Object> args = new ArrayList<>();
        args.add(flightId);
        args.add(userId);
        args.addAll(seats);
        List<Map<String, Object>> rows = jdbc.queryForList(sql, args.toArray());
        if (rows.isEmpty()) return null;
        if (rows.size() != seats.size()) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Some selected seats are already booked");
        }

        Map<String, Object> existing = rows.getFirst();
        String tripId = text(existing.get("trip_id"));
        Set<String> confirmedSeats = new LinkedHashSet<>();
        for (Map<String, Object> row : rows) {
            if (!tripId.equals(text(row.get("trip_id")))
                    || !text(existing.get("booking_ref"))
                            .equals(text(row.get("booking_ref")))) {
                throw new ResponseStatusException(
                        HttpStatus.CONFLICT, "Selected seats belong to different bookings");
            }
            confirmedSeats.add(text(row.get("seat_number")));
        }
        if (!confirmedSeats.equals(new LinkedHashSet<>(seats))) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Selected seats do not match the confirmed booking");
        }

        long existingTripId = number(existing.get("trip_id"));
        Map<String, Object> existingDetails = flightAttributes(existing.get("details"));
        Object existingExtras = existingDetails.get("extras");
        return ResponseEntity.ok(Map.of(
                "booking", Map.of(
                        "reference", text(existing.get("booking_ref")),
                        "seats", seats,
                        "total_price", decimal(existing.get("price")),
                        "extras", existingExtras instanceof List<?> ? existingExtras : List.of()),
                "trip", tripRow(existingTripId)));
    }

    private Map<String, Object> flightListing(long flightId, boolean lock) {
        if (lock) {
            jdbc.queryForObject(
                    "SELECT public.zentrip_lock_flight_listing(?)",
                    Boolean.class,
                    flightId);
        }
        String sql = """
                SELECT l.id, l.partner_id, l.title, l.city, l.price, l.attributes,
                       p.name AS partner_name
                FROM partner_listings l
                JOIN partners p ON p.id = l.partner_id AND p.status = 'active'
                WHERE l.id = ? AND l.type = 'flight' AND l.active = TRUE
                """;
        List<Map<String, Object>> rows = jdbc.queryForList(sql, flightId);
        if (rows.isEmpty()) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND, "Flight listing not found");
        }
        Map<String, Object> listing = new LinkedHashMap<>(rows.getFirst());
        Map<String, Object> attributes = flightAttributes(listing.get("attributes"));
        String seatLayout = normalizedSeatLayout(attributes);
        int defaultRows = seatLayout.startsWith("2-") ? 16 : 30;
        int rowCount = integer(
                attributes.get("seat_rows"),
                integer(attributes.get("row_count"), defaultRows));
        if (rowCount < 1 || rowCount > 30) {
            throw new ResponseStatusException(
                    HttpStatus.INTERNAL_SERVER_ERROR, "Invalid seat row configuration");
        }
        int seatsAvailable = integer(attributes.get("seats_available"), 0);
        listing.put("attributes", attributes);
        listing.put("seat_layout", seatLayout);
        listing.put("row_count", rowCount);
        listing.put("seats_available", seatsAvailable);
        return listing;
    }

    private Map<String, Object> flightAttributes(Object raw) {
        if (raw instanceof Map<?, ?> rawMap) {
            Map<String, Object> attributes = new LinkedHashMap<>();
            rawMap.forEach((key, value) -> attributes.put(text(key), value));
            return attributes;
        }
        if (raw == null || text(raw).isBlank()) return new LinkedHashMap<>();
        try {
            return JSON.readValue(
                    text(raw), new TypeReference<Map<String, Object>>() {});
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalStateException("Could not read flight listing attributes", exception);
        }
    }

    private static String normalizedSeatLayout(Map<String, Object> attributes) {
        String raw = value(
                attributes.get("seat_layout"),
                value(attributes.get("seat_configuration"),
                        value(attributes.get("aircraft_layout"), "3-3")));
        String normalized = raw.trim().toLowerCase(Locale.ROOT)
                .replace('×', '-')
                .replace('x', '-')
                .replace('+', '-')
                .replace(" ", "");
        if (!Set.of("2-2", "3-3").contains(normalized)) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Unsupported flight seat layout");
        }
        return normalized;
    }

    private List<String> validatedFlightSeats(
            Object rawSeats,
            Map<String, Object> listing) {
        if (!(rawSeats instanceof List<?> values) || values.isEmpty() || values.size() > 9) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "Select between one and nine seats");
        }
        int seatsPerSide = "2-2".equals(listing.get("seat_layout")) ? 2 : 3;
        int rowCount = integer(listing.get("row_count"), 30);
        Set<String> unique = new LinkedHashSet<>();
        for (Object value : values) {
            String seat = text(value).trim().toUpperCase(Locale.ROOT);
            java.util.regex.Matcher matcher =
                    java.util.regex.Pattern.compile("^([1-9][0-9]?)([A-F])$")
                            .matcher(seat);
            if (!matcher.matches()) {
                throw new ResponseStatusException(
                        HttpStatus.UNPROCESSABLE_ENTITY, "Invalid seat number");
            }
            int row = Integer.parseInt(matcher.group(1));
            int column = matcher.group(2).charAt(0) - 'A';
            if (row > rowCount || column >= seatsPerSide * 2) {
                throw new ResponseStatusException(
                        HttpStatus.UNPROCESSABLE_ENTITY,
                        "Seat does not exist in this aircraft layout");
            }
            if (!unique.add(seat)) {
                throw new ResponseStatusException(
                        HttpStatus.UNPROCESSABLE_ENTITY, "Duplicate seat number");
            }
        }
        List<String> seats = new ArrayList<>(unique);
        seats.sort(String::compareTo);
        return seats;
    }

    private static List<String> validatedFlightExtras(Object rawExtras) {
        if (rawExtras == null) return List.of();
        if (!(rawExtras instanceof List<?> values) || values.size() > 2) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "Invalid flight extras");
        }
        Set<String> validExtras = Set.of("extra_baggage", "flexible_ticket");
        Set<String> selected = new LinkedHashSet<>();
        for (Object value : values) {
            String extra = text(value).trim().toLowerCase(Locale.ROOT);
            if (!validExtras.contains(extra) || !selected.add(extra)) {
                throw new ResponseStatusException(
                        HttpStatus.UNPROCESSABLE_ENTITY, "Unsupported or duplicate flight extra");
            }
        }
        return List.copyOf(selected);
    }

    private static BigDecimal flightExtraPrice(String extra) {
        return FlightSeatConfiguration.EXTRAS.getOrDefault(extra, BigDecimal.ZERO);
    }

    private List<String> occupiedFlightSeats(long flightId) {
        return jdbc.queryForList("""
                SELECT seat_number
                FROM flight_seat_holds
                WHERE flight_listing_id = ?
                  AND (status = 'confirmed'
                       OR (status = 'reserved' AND expires_at > NOW()))
                ORDER BY seat_number
                """, String.class, flightId);
    }

    private BigDecimal flightFare(Map<String, Object> listing, String seatClass) {
        Map<String, Object> attributes = flightAttributes(listing.get("attributes"));
        Object rawFare = seatClass.equals("economy")
                ? listing.get("price")
                : attributes.get(seatClass + "_price");
        BigDecimal fare = decimal(rawFare);
        if (fare.signum() <= 0) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "The selected cabin fare is unavailable");
        }
        return fare;
    }

    private boolean isPremiumSeat(String seat, Map<String, Object> listing) {
        int row = Integer.parseInt(seat.substring(0, seat.length() - 1));
        return FlightSeatConfiguration.premiumRows(listing).contains(row);
    }

    private static String requiredAttribute(
            Map<String, Object> attributes,
            String key) {
        String value = text(attributes.get(key)).trim();
        if (value.isEmpty()) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Flight listing is missing " + key);
        }
        return value;
    }

    private static Object[] buildSeatConfirmationArgs(
            String reference,
            long tripId,
            long flightId,
            long userId,
            List<String> seats) {
        List<Object> args = new ArrayList<>();
        args.add(reference);
        args.add(tripId);
        args.add(flightId);
        args.add(userId);
        args.addAll(seats);
        return args.toArray();
    }

    @GetMapping("/trips/availability")
    public Map<String, Object> flightAvailability(
            @RequestParam("departure_date") String departureValue,
            @RequestParam("arrival_date") String arrivalValue,
            @RequestParam(value = "return_date", required = false) String returnValue,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        OffsetDateTime departure = flightDateTime(departureValue);
        OffsetDateTime arrival = flightDateTime(arrivalValue);
        OffsetDateTime returnDate = nullableFlightDateTime(returnValue);
        if (!arrival.isAfter(departure)) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "arrival_date must be after departure_date");
        }
        if (returnDate != null && returnDate.isBefore(departure)) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "return_date must not be before departure_date");
        }
        return Map.of("available",
                !hasFlightScheduleConflict(userId, departure, arrival, returnDate));
    }

    private boolean hasFlightScheduleConflict(
            long userId,
            OffsetDateTime departure,
            OffsetDateTime arrival,
            OffsetDateTime returnDate) {
        LocalDate requestedStart = departure.toLocalDate();
        LocalDate requestedEnd = tripLastOccupiedDate(departure, arrival, returnDate);
        List<Map<String, Object>> trips = jdbc.queryForList("""
                SELECT departure_date, return_date, status,
                       details ->> 'arrival_date' AS arrival_date
                FROM trips
                WHERE user_id = ? AND LOWER(status) NOT IN ('cancelled', 'completed')
                """, userId);

        for (Map<String, Object> trip : trips) {
            OffsetDateTime existingDeparture = storedFlightDateTime(trip.get("departure_date"));
            if (existingDeparture == null) continue;
            OffsetDateTime existingArrival = storedFlightDateTime(trip.get("arrival_date"));
            OffsetDateTime existingReturn = storedFlightDateTime(trip.get("return_date"));
            LocalDate existingStart = existingDeparture.toLocalDate();
            LocalDate existingEnd = tripLastOccupiedDate(
                    existingDeparture, existingArrival, existingReturn);
            if (!existingStart.isAfter(requestedEnd)
                    && !requestedStart.isAfter(existingEnd)) {
                return true;
            }
        }
        return false;
    }

    private static LocalDate tripLastOccupiedDate(
            OffsetDateTime departure, OffsetDateTime arrival, OffsetDateTime returnDate) {
        LocalDate end = departure.toLocalDate();
        if (arrival != null && arrival.toLocalDate().isAfter(end)) {
            end = arrival.toLocalDate();
        }
        if (returnDate != null && returnDate.toLocalDate().isAfter(end)) {
            end = returnDate.toLocalDate();
        }
        return end;
    }

    private static OffsetDateTime nullableFlightDateTime(Object value) {
        return value == null || text(value).isBlank() ? null : flightDateTime(text(value));
    }

    private static OffsetDateTime storedFlightDateTime(Object value) {
        if (value instanceof OffsetDateTime dateTime) {
            return dateTime.withOffsetSameInstant(ZoneOffset.UTC);
        }
        if (value instanceof Timestamp timestamp) {
            return timestamp.toInstant().atOffset(ZoneOffset.UTC);
        }
        if (value instanceof LocalDateTime dateTime) {
            return dateTime.atOffset(ZoneOffset.UTC);
        }
        if (value instanceof java.sql.Date date) {
            return date.toLocalDate().atStartOfDay().atOffset(ZoneOffset.UTC);
        }
        if (value == null || text(value).isBlank()) return null;
        try {
            return flightDateTime(text(value));
        } catch (ResponseStatusException exception) {
            return null;
        }
    }

    private Map<String, Object> tripRow(long id) {
        return normalizeTripHistoryRow(jdbc.queryForMap("""
                SELECT trips.*,
                       details ->> 'arrival_date' AS arrival_date,
                       details ->> 'passenger_count' AS passenger_count,
                       ARRAY(SELECT jsonb_array_elements_text(COALESCE(
                           details -> 'selected_seats', details -> 'seat_numbers',
                           '[]'::jsonb))) AS selected_seats,
                       ARRAY(SELECT jsonb_array_elements_text(COALESCE(
                           details -> 'extras', '[]'::jsonb))) AS extras,
                       details ->> 'source' AS source,
                       details ->> 'duffel_offer_id' AS duffel_offer_id,
                       details ->> 'price_currency' AS price_currency,
                       details ->> 'is_simulated' AS is_simulated,
                       details ->> 'refund_status' AS refund_status,
                       details ->> 'refund_method' AS refund_method
                FROM trips WHERE id = ?
                """, id));
    }

    private static Map<String, Object> normalizeTripHistoryRow(
            Map<String, Object> source) {
        Map<String, Object> row = new LinkedHashMap<>(source);
        row.put("selected_seats", postgresTextArray(row.get("selected_seats")));
        row.put("extras", postgresTextArray(row.get("extras")));
        return row;
    }

    private static List<String> postgresTextArray(Object value) {
        try {
            if (value instanceof java.sql.Array postgresArray) {
                value = postgresArray.getArray();
            }
        } catch (java.sql.SQLException exception) {
            throw new IllegalStateException("Could not read trip history array", exception);
        }
        if (value instanceof Object[] values) {
            return java.util.Arrays.stream(values)
                    .filter(java.util.Objects::nonNull)
                    .map(Object::toString)
                    .toList();
        }
        if (value instanceof List<?> values) {
            return values.stream()
                    .filter(java.util.Objects::nonNull)
                    .map(Object::toString)
                    .toList();
        }
        return List.of();
    }

    @DeleteMapping("/trips/{id}")
    @Transactional
    public ResponseEntity<?> deleteTrip(@PathVariable long id, HttpServletRequest request) {
        long userId = requireUserId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, status, partner_listing_id,
                       details ->> 'passenger_count' AS passenger_count,
                       details ->> 'refund_status' AS refund_status,
                       details ->> 'refund_method' AS refund_method
                FROM trips WHERE id = ? AND user_id = ? FOR UPDATE
                """, id, userId);
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND);

        Map<String, Object> trip = rows.getFirst();
        String status = value(trip.get("status"), "upcoming");
        boolean alreadyCancelled = "cancelled".equalsIgnoreCase(status);
        if (!alreadyCancelled) {
            int updated = jdbc.update("""
                    UPDATE trips
                    SET status = 'cancelled',
                        details = COALESCE(details, '{}'::jsonb) || jsonb_build_object(
                            'refund_status', 'pending_airline_review',
                            'refund_method', 'original_payment_method',
                            'refund_requested_at', NOW()),
                        updated_at = NOW()
                    WHERE id = ? AND user_id = ?
                    """, id, userId);
            if (updated == 0) throw new ResponseStatusException(HttpStatus.NOT_FOUND);
            restoreFlightSeats(
                    trip.get("partner_listing_id"),
                    integer(trip.get("passenger_count"), 1));
            jdbc.update(
                    "DELETE FROM flight_seat_holds WHERE trip_id = ? AND status = 'confirmed'",
                    id);
        }

        return ResponseEntity.ok(Map.of(
                "status", "cancelled",
            "refund_status", alreadyCancelled
                ? value(trip.get("refund_status"), "pending_airline_review")
                : "pending_airline_review",
            "refund_method", alreadyCancelled
                ? value(trip.get("refund_method"), "original_payment_method")
                : "original_payment_method"));
    }

    @GetMapping("/bookings")
    public Map<String, Object> bookings(HttpServletRequest request) {
        long userId = requireUserId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT bookings.*,
                       COALESCE(bookings.price, bookings.total_amount) AS effective_price,
                       details ->> 'end_date' AS end_date,
                       details ->> 'image_url' AS image_url,
                       COALESCE(details ->> 'rooms',
                                details ->> 'hotel_rooms_reserved',
                                '1') AS rooms
                FROM bookings
                WHERE user_id = ?
                ORDER BY created_at DESC, id DESC
                """, userId);
        List<Map<String, Object>> payload = rows.stream().map(this::bookingPayload).toList();
        return Map.of("bookings", payload);
    }

    @GetMapping("/bookings/availability")
    public Map<String, Object> bookingAvailability(
            @RequestParam String type,
            @RequestParam String title,
            @RequestParam("start_date") String startValue,
            @RequestParam("end_date") String endValue,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        String normalizedType = supportedBookingType(type);
        OffsetDateTime start = flightDateTime(startValue);
        OffsetDateTime end = flightDateTime(endValue);
        if (!end.isAfter(start)) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "end_date must be after start_date");
        }
        return Map.of("available", !hasBookingScheduleConflict(
                userId, normalizedType, title, start, end));
    }

    @PostMapping("/bookings")
    @Transactional(rollbackFor = Exception.class)
    public ResponseEntity<?> createBooking(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        long userId = requireUserId(request);
        Long paymentAttemptId = lockSuccessfulPaymentAttempt(body, userId);
        String type = supportedBookingType(required(body, "type"));
        try {
            String title = required(body, "title");
            String subtitle = required(body, "subtitle");
            OffsetDateTime start = flightDateTime(required(body, "date"));
            OffsetDateTime end = nullableFlightDateTime(body.get("end_date"));
            if (end == null) end = start.plusDays(1);
            if (!end.isAfter(start)) {
                throw new ResponseStatusException(
                        HttpStatus.UNPROCESSABLE_ENTITY, "end_date must be after start_date");
            }
            BigDecimal price = decimal(body.get("price"));
            PartnerListingAttribution attribution =
                    partnerListingAttribution(body.get("partner_listing_id"), type);
            requireExistingRecord("users", "id", userId, "User");
            if (attribution.partnerId() != null) {
                requireExistingRecord("partners", "id", attribution.partnerId(), "Partner");
            }
            if (attribution.listingId() != null) {
                requireExistingRecord("partner_listings", "id", attribution.listingId(), "Partner listing");
            }
            price = partnerBookingPrice(attribution, type, start, end, price);
            int hotelRoomCount = type.equals("hotel")
                    ? integer(body.get("rooms"), 1) : 0;
            if (type.equals("hotel") && hotelRoomCount < 1) {
                throw new ResponseStatusException(
                        HttpStatus.UNPROCESSABLE_ENTITY, "rooms must be at least one");
            }
            jdbc.queryForList("SELECT id FROM users WHERE id = ? FOR UPDATE", userId);
            if (hasBookingScheduleConflict(userId, type, title, start, end)) {
                return ResponseEntity.status(HttpStatus.CONFLICT)
                        .body(Map.of("message", "BOOKING_SCHEDULE_CONFLICT"));
            }
            boolean hotelRoomReserved = type.equals("hotel")
                    && attribution.listingId() != null;
            if (hotelRoomReserved) {
                reserveHotelRooms(attribution.listingId(), hotelRoomCount);
            }
            boolean carReserved = type.equals("car") && attribution.listingId() != null;
            if (carReserved) {
                reserveCar(attribution.listingId());
            }
            long id = insert("""
                    INSERT INTO bookings (user_id, partner_id, partner_listing_id, type, status, total_amount, title, subtitle, "date", price, ref_code, details, created_at, updated_at)
                    VALUES (?, ?, ?, ?, 'upcoming', ?, ?, ?, ?, ?, ?, CAST(? AS JSONB), NOW(), NOW())
                    """, userId, attribution.partnerId(), attribution.listingId(),
                    type, price, title, subtitle,
                    start, price, body.get("ref_code"),
                    bookingDetailsJson(end, body.get("image_url"), hotelRoomCount,
                            hotelRoomReserved, carReserved));
            if (paymentAttemptId != null) {
                linkPaymentAttemptToBooking(paymentAttemptId, userId, id);
            }
            String bookingReference = text(body.get("ref_code")).trim();
            if (bookingReference.length() > 120) {
                bookingReference = bookingReference.substring(0, 120);
            }
            String safeTitle = title.trim();
            if (safeTitle.length() > 120) {
                safeTitle = safeTitle.substring(0, 120);
            }
            String englishType = bookingTypeLabel(type, false);
            String arabicType = bookingTypeLabel(type, true);
            String englishReference = bookingReference.isBlank()
                    ? "" : " Reference: " + bookingReference + ".";
            String arabicReference = bookingReference.isBlank()
                    ? "" : " رقم الحجز: " + bookingReference + ".";
            insertUserNotification(
                    userId,
                    "booking:" + id,
                    "booking",
                    "Booking confirmed",
                    "تم تأكيد الحجز",
                    "Your " + englishType + " booking for " + safeTitle
                            + " is confirmed." + englishReference,
                    "تم تأكيد حجز " + arabicType + " " + safeTitle + "."
                            + arabicReference,
                    "booking",
                    id,
                    bookingReference.isBlank() ? null : bookingReference);
            return ResponseEntity.status(HttpStatus.CREATED)
                    .body(Map.of("booking", bookingPayload(jdbc.queryForMap("""
                            SELECT bookings.*,
                                   COALESCE(bookings.price, bookings.total_amount) AS effective_price,
                                   details ->> 'end_date' AS end_date,
                                   details ->> 'image_url' AS image_url,
                                   COALESCE(details ->> 'rooms',
                                            details ->> 'hotel_rooms_reserved',
                                            '1') AS rooms
                            FROM bookings WHERE id = ?
                            """, id))));
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (Exception exception) {
            LOG.error("Booking creation failed for user {} and type {}", userId, type, exception);
            throw new ResponseStatusException(
                    HttpStatus.INTERNAL_SERVER_ERROR, "Unable to create booking", exception);
        }
    }

    @DeleteMapping("/bookings/{id}")
    @Transactional
    public ResponseEntity<?> cancelBooking(
            @PathVariable long id, HttpServletRequest request) {
        long userId = requireUserId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT status, type, partner_listing_id,
                       COALESCE((details ->> 'hotel_rooms_reserved')::integer, 0) AS hotel_rooms_reserved,
                       COALESCE((details ->> 'car_vehicle_reserved')::integer, 0) AS car_vehicle_reserved
                FROM bookings
                WHERE id = ? AND user_id = ?
                FOR UPDATE
                """, id, userId);
        if (rows.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Booking not found");
        }

        String status = text(rows.getFirst().get("status")).toLowerCase();
        if ("completed".equals(status)) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Completed bookings cannot be cancelled");
        }
        if (!"cancelled".equals(status)) {
            jdbc.update("""
                    UPDATE bookings SET status = 'cancelled', updated_at = NOW()
                    WHERE id = ? AND user_id = ?
                    """, id, userId);
            Map<String, Object> booking = rows.getFirst();
            if ("hotel".equalsIgnoreCase(text(booking.get("type")))
                    && booking.get("partner_listing_id") != null) {
                restoreHotelRooms(
                        booking.get("partner_listing_id"),
                        integer(booking.get("hotel_rooms_reserved"), 0));
            }
            if ("car".equalsIgnoreCase(text(booking.get("type")))
                    && booking.get("partner_listing_id") != null
                    && integer(booking.get("car_vehicle_reserved"), 0) > 0) {
                restoreCar(booking.get("partner_listing_id"));
            }
        }
        return ResponseEntity.ok(Map.of("status", "cancelled"));
    }

    /** JSON in bookings.details: dates, hotel room count, and an optional HTTP(S) cover image. */
    static String bookingDetailsJson(
            OffsetDateTime end,
            Object imageUrl,
            int hotelRoomCount,
            boolean hotelRoomReserved) {
        return bookingDetailsJson(end, imageUrl, hotelRoomCount, hotelRoomReserved, false);
    }

    static String bookingDetailsJson(
            OffsetDateTime end,
            Object imageUrl,
            int hotelRoomCount,
            boolean hotelRoomReserved,
            boolean carReserved) {
        Map<String, Object> details = new LinkedHashMap<>();
        details.put("end_date", end.toString());
        if (hotelRoomCount > 0) details.put("rooms", hotelRoomCount);
        if (hotelRoomReserved) details.put("hotel_rooms_reserved", hotelRoomCount);
        if (carReserved) details.put("car_vehicle_reserved", 1);
        if (imageUrl instanceof String url) {
            String trimmed = url.trim();
            boolean safe = trimmed.length() <= 2048
                    && (trimmed.startsWith("https://") || trimmed.startsWith("http://"));
            if (safe) details.put("image_url", trimmed);
        }
        try {
            return JSON.writeValueAsString(details);
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalStateException("Could not serialize booking details", exception);
        }
    }

    private void requireExistingRecord(String table, String idColumn, long recordId, String label) {
        Integer count = jdbc.queryForObject(
                "SELECT COUNT(*) FROM " + table + " WHERE " + idColumn + " = ?",
                Integer.class,
                recordId);
        if (count == null || count == 0) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    label + " not found");
        }
    }

    private String supportedBookingType(String type) {
        String normalized = type.toLowerCase();
        if (!List.of("hotel", "car", "attraction", "package").contains(normalized)) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY,
                    "Booking type must be hotel, car, attraction, or package");
        }
        return normalized;
    }

    private static String bookingTypeLabel(String type, boolean arabic) {
        if (arabic) {
            return switch (type) {
                case "hotel" -> "الفندق";
                case "car" -> "السيارة";
                case "attraction" -> "المعلم السياحي";
                case "package" -> "الباقة السياحية";
                default -> "الحجز";
            };
        }
        return switch (type) {
            case "hotel" -> "hotel";
            case "car" -> "car";
            case "attraction" -> "attraction";
            case "package" -> "travel package";
            default -> "booking";
        };
    }

    private void insertUserNotification(
            long userId,
            String eventKey,
            String kind,
            String titleEn,
            String titleAr,
            String bodyEn,
            String bodyAr,
            String targetType,
            long targetId,
            String bookingReference) {
        if (!userNotificationsTableAvailable()) {
            LOG.warn("Notification migration is not installed; booking was saved without inbox entry");
            return;
        }
        jdbc.update("""
                INSERT INTO public.user_notifications
                    (user_id, event_key, kind, title_en, title_ar,
                     body_en, body_ar, target_type, target_id,
                     booking_ref, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
                ON CONFLICT (user_id, event_key) DO NOTHING
                """,
                userId, eventKey, kind, titleEn, titleAr, bodyEn, bodyAr,
                targetType, targetId,
                bookingReference == null || bookingReference.isBlank()
                        ? null : bookingReference);
    }

    private boolean userNotificationsTableAvailable() {
        try {
            return Boolean.TRUE.equals(jdbc.queryForObject(
                    "SELECT to_regclass('public.user_notifications') IS NOT NULL",
                    Boolean.class));
        } catch (org.springframework.dao.DataAccessException exception) {
            LOG.warn("Could not check notification migration status", exception);
            return false;
        }
    }

    private boolean hasBookingScheduleConflict(
            long userId, String type, String title, OffsetDateTime start, OffsetDateTime end) {
        List<Map<String, Object>> existingBookings = jdbc.queryForList("""
                SELECT title, "date",
                       details ->> 'end_date' AS end_date
                FROM bookings
                WHERE user_id = ? AND LOWER(type) = ?
                  AND LOWER(status) NOT IN ('cancelled', 'completed')
                """, userId, type);

        for (Map<String, Object> existing : existingBookings) {
            if ("attraction".equals(type)
                    && !text(existing.get("title")).equalsIgnoreCase(title)) {
                continue;
            }
            OffsetDateTime existingStart = storedFlightDateTime(existing.get("date"));
            if (existingStart == null) continue;
            OffsetDateTime existingEnd = storedFlightDateTime(existing.get("end_date"));
            if (existingEnd == null) existingEnd = existingStart.plusDays(1);
            if (existingStart.isBefore(end) && start.isBefore(existingEnd)) return true;
        }
        return false;
    }

    @GetMapping("/transfers")
    public Map<String, Object> transfers(HttpServletRequest request) {
        long userId = requireUserId(request);
        return Map.of("transfers", jdbc.queryForList("""
                SELECT transfers.*,
                       COALESCE(transfer_schedules.duration_minutes, 60) AS duration_minutes
                FROM transfers
                LEFT JOIN transfer_schedules ON transfer_schedules.transfer_id = transfers.id
                WHERE transfers.user_id = ?
                ORDER BY transfers.created_at DESC
                """, userId));
    }

    @GetMapping("/transfers/availability")
    public Map<String, Object> transferAvailability(
            @RequestParam("pickup_time") String pickupValue,
            @RequestParam("duration_minutes") int durationMinutes,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        validateTransferDuration(durationMinutes);
        OffsetDateTime pickupTime = dateTime(pickupValue);
        return Map.of("available",
                !hasTransferScheduleConflict(userId, pickupTime, durationMinutes));
    }

    @PostMapping("/transfers")
    @Transactional(rollbackFor = Exception.class)
    public ResponseEntity<?> createTransfer(
            @RequestBody Map<String, Object> body, HttpServletRequest request) {
        long userId = requireUserId(request);
        try {
            Long paymentAttemptId = lockSuccessfulPaymentAttempt(body, userId);
            OffsetDateTime pickupTime = dateTime(required(body, "pickup_time"));
            int durationMinutes = integer(body.get("duration_minutes"), 0);
            validateTransferDuration(durationMinutes);
            PartnerListingAttribution attribution =
                    partnerListingAttribution(body.get("partner_listing_id"), "transfer");
            requireExistingRecord("users", "id", userId, "User");
            if (attribution.partnerId() != null) {
                requireExistingRecord("partners", "id", attribution.partnerId(), "Partner");
            }
            if (attribution.listingId() != null) {
                requireExistingRecord("partner_listings", "id", attribution.listingId(), "Partner listing");
            }
            BigDecimal price = partnerBookingPrice(
                    attribution,
                    "transfer",
                    pickupTime,
                    pickupTime.plusMinutes(durationMinutes),
                    decimal(body.get("price")));
            jdbc.queryForList("SELECT id FROM users WHERE id = ? FOR UPDATE", userId);
            if (hasTransferScheduleConflict(userId, pickupTime, durationMinutes)) {
                return ResponseEntity.status(HttpStatus.CONFLICT)
                        .body(Map.of("message", "TAXI_SCHEDULE_CONFLICT"));
            }
            long id = insert("""
                    INSERT INTO transfers (user_id, partner_id, partner_listing_id, provider_name, vehicle_type, pickup_location, dropoff_location,
                    pickup_time, price, passengers, status, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())
                    """, userId, attribution.partnerId(), attribution.listingId(),
                    required(body, "provider_name"), required(body, "vehicle_type"),
                    required(body, "pickup_location"), required(body, "dropoff_location"),
                    pickupTime, price,
                    integer(body.get("passengers"), 1), value(body, "status", "confirmed"));
            jdbc.update(
                    "INSERT INTO transfer_schedules (transfer_id, duration_minutes) VALUES (?, ?)",
                    id, durationMinutes);
            if (paymentAttemptId != null) {
                linkPaymentAttemptToTransfer(paymentAttemptId, userId, id);
            }
            Map<String, Object> transfer = jdbc.queryForMap("SELECT * FROM transfers WHERE id = ?", id);
            transfer.put("id", Long.toString(id));
            transfer.put("duration_minutes", durationMinutes);
            return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("transfer", transfer));
        } catch (ResponseStatusException exception) {
            throw exception;
        } catch (Exception exception) {
            LOG.error("Transfer creation failed for user {}", userId, exception);
            throw new ResponseStatusException(
                    HttpStatus.INTERNAL_SERVER_ERROR, "Unable to create transfer", exception);
        }
    }

    private boolean hasTransferScheduleConflict(
            long userId, OffsetDateTime pickupTime, int durationMinutes) {
        OffsetDateTime requestedEnd = pickupTime.plusMinutes(durationMinutes);
        List<Map<String, Object>> transfers = jdbc.queryForList("""
                SELECT transfers.pickup_time, transfers.status,
                       COALESCE(transfer_schedules.duration_minutes, 60) AS duration_minutes
                FROM transfers
                LEFT JOIN transfer_schedules ON transfer_schedules.transfer_id = transfers.id
                WHERE transfers.user_id = ?
                  AND LOWER(transfers.status) NOT IN ('cancelled', 'completed')
                """, userId);

        for (Map<String, Object> transfer : transfers) {
                OffsetDateTime existingStart =
                    storedFlightDateTime(transfer.get("pickup_time"));
            if (existingStart == null) continue;
            int existingDuration = integer(transfer.get("duration_minutes"), 60);
            if (existingDuration < 1) existingDuration = 60;
            OffsetDateTime existingEnd = existingStart.plusMinutes(existingDuration);
            if (existingStart.isBefore(requestedEnd)
                    && pickupTime.isBefore(existingEnd)) {
                return true;
            }
        }
        return false;
    }

    private static void validateTransferDuration(int durationMinutes) {
        if (durationMinutes < 1 || durationMinutes > 1440) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY,
                    "duration_minutes must be between 1 and 1440");
        }
    }

    @PostMapping("/payments/checkout")
    public Map<String, Object> checkout(
            @RequestBody Map<String, Object> body, HttpServletRequest request) {
        requireUserId(request);
        BigDecimal amount = decimal(required(body, "amount"));
        if (amount.signum() < 0) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "amount must not be negative");
        }
        String currency = value(body, "currency", "USD").toUpperCase(Locale.ROOT);
        if (!currency.matches("[A-Z]{3}")) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "currency must be a 3-letter code");
        }
        return Map.of(
                "session_id", "mock_" + UUID.randomUUID(),
                "checkout_url", "mock://checkout");
    }

    @GetMapping("/payments/verify/{sessionId}")
    public Map<String, Object> paymentAttempt(
            @PathVariable String sessionId, HttpServletRequest request) {
        long userId = requireUserId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, status FROM payment_attempts
                WHERE session_id = ? AND user_id = ?
                """, sessionId, userId);
        if (rows.isEmpty()) {
            return Map.of(
                    "attempted", false,
                    "paid", false,
                    "session_id", sessionId);
        }
        Map<String, Object> row = rows.getFirst();
        String status = value(row.get("status"), "failed");
        return Map.of(
                "attempted", true,
                "attempt_id", number(row.get("id")),
                "status", status,
                "paid", "success".equals(status),
                "session_id", sessionId);
    }

    @PostMapping("/payments/verify/{sessionId}")
    @Transactional
    public ResponseEntity<?> recordPaymentAttempt(
            @PathVariable String sessionId,
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        if (sessionId == null || !sessionId.startsWith("mock_")
                || sessionId.length() > 128) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "Invalid simulated payment session");
        }
        if (!(body.get("paid") instanceof Boolean paid)) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "paid must be a boolean");
        }
        BigDecimal amount = decimal(required(body, "amount"));
        if (amount.signum() < 0) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "amount must not be negative");
        }
        String currency = value(body, "currency", "USD").toUpperCase(Locale.ROOT);
        if (!currency.matches("[A-Z]{3}")) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "currency must be a 3-letter code");
        }
        String status = paid ? "success" : "failed";
        jdbc.update("""
                INSERT INTO payment_attempts
                    (session_id, user_id, amount, currency, status, is_simulation)
                VALUES (?, ?, ?, ?, ?, TRUE)
                ON CONFLICT (session_id) DO NOTHING
                """, sessionId, userId, amount, currency, status);

        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, user_id, amount, currency, status
                FROM payment_attempts WHERE session_id = ?
                """, sessionId);
        if (rows.isEmpty() || number(rows.getFirst().get("user_id")) != userId) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Payment session is already associated with another account");
        }
        Map<String, Object> row = rows.getFirst();
        boolean sameRequest = status.equals(row.get("status"))
                && amount.compareTo(new BigDecimal(text(row.get("amount")))) == 0
                && currency.equals(text(row.get("currency")).trim());
        if (!sameRequest) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Payment session was already recorded differently");
        }
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                "attempt_id", number(row.get("id")),
                "status", status,
                "paid", paid,
                "is_simulation", true));
    }

    @GetMapping("/maps/search")
    public Map<String, Object> mapsSearch(@RequestParam String query,
                                          @RequestParam double lat,
                                          @RequestParam double lng,
                                          @RequestParam(defaultValue = "attraction") String category,
                                          @RequestParam(defaultValue = "10") int limit,
                                          HttpServletRequest request) {
        requireUserId(request);
        if (serpApiKey.isBlank()) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "SERPAPI_KEY is not configured");
        String url = UriComponentsBuilder.fromUriString("https://serpapi.com/search.json")
                .queryParam("engine", "google_maps").queryParam("q", query)
                .queryParam("ll", "@" + lat + "," + lng + ",14z")
                .queryParam("nearby", "true").queryParam("num", Math.min(Math.max(limit, 1), 20))
                .queryParam("api_key", serpApiKey).build().encode().toUriString();
        Map<?, ?> response = http.get().uri(url).retrieve().body(Map.class);
        List<?> source = response != null && response.get("local_results") instanceof List<?> list ? list : List.of();
        List<Map<String, Object>> results = new ArrayList<>();
        for (Object item : source) {
            if (!(item instanceof Map<?, ?> place)) continue;
            Map<?, ?> coordinates = place.get("gps_coordinates") instanceof Map<?, ?> c ? c : Map.of();
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("title", value(place.get("title"), ""));
            result.put("address", value(place.get("address"), ""));
            result.put("category", category);
            result.put("place_id", place.get("place_id"));
            result.put("rating", place.get("rating"));
            result.put("reviews", place.get("reviews"));
            result.put("phone", place.get("phone"));
            result.put("website", place.get("website"));
            result.put("latitude", coordinates.get("latitude"));
            result.put("longitude", coordinates.get("longitude"));
            result.put("type", place.get("type"));
            result.put("thumbnail", place.get("thumbnail"));
            results.add(result);
        }
        return Map.of("results", results);
    }

    private Map<String, Object> authPayload(long userId, HttpServletRequest request) {
        setLocalRlsSetting("app.user_id", Long.toString(userId));
        Map<String, Object> identity = jdbc.queryForMap(
                "SELECT role, partner_id FROM users WHERE id = ?", userId);
        String role = text(identity.get("role")).trim().toLowerCase(Locale.ROOT);
        if (!Set.of("admin", "partner", "customer").contains(role)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Unsupported account role");
        }
        setLocalRlsSetting("app.auth_role", role);
        Object rawPartnerId = identity.get("partner_id");
        String partnerId = rawPartnerId instanceof Number number && number.longValue() > 0
                ? Long.toString(number.longValue())
                : "";
        setLocalRlsSetting("app.partner_id", partnerId);

        String token = UUID.randomUUID().toString().replace("-", "") + UUID.randomUUID().toString().replace("-", "");
        jdbc.update("INSERT INTO api_tokens (user_id, token_hash, expires_at) VALUES (?, ?, ?)",
                userId, TokenAuthFilter.sha256(token), Timestamp.from(Instant.now().plusSeconds(60L * 60 * 24 * 30)));
        return Map.of("user", userPayload(userId, request), "token", token);
    }

    private void setLocalRlsSetting(String name, String value) {
        jdbc.queryForObject("SELECT set_config(?, ?, TRUE)", String.class, name, value);
    }

    private Map<String, Object> userPayload(long userId, HttpServletRequest request) {
        Map<String, Object> user = jdbc.queryForMap("""
                SELECT u.id, u.name, u.email, u.phone, u.role,
                       u.partner_id, partners.name AS partner_name,
                       partners.service_type AS partner_service_type, p.photo_url
                FROM users u
                LEFT JOIN partners ON partners.id = u.partner_id
                LEFT JOIN user_profiles p ON p.user_id = u.id
                WHERE u.id = ?
                """, userId);
        user.put("id", number(user.get("id")));
        String photoUrl = text(user.get("photo_url"));
        if (!photoUrl.isBlank()) {
            user.put("photo_url", ServletUriComponentsBuilder.fromRequestUri(request)
                    .replacePath(photoUrl)
                    .replaceQuery(null)
                    .build()
                    .toUriString());
        }
        return user;
    }

    private void saveProfilePhotoUrl(long userId, String photoUrl) {
        jdbc.update("""
                INSERT INTO user_profiles (user_id, photo_url, created_at, updated_at)
                VALUES (?, ?, NOW(), NOW())
                ON CONFLICT (user_id) DO UPDATE SET photo_url = EXCLUDED.photo_url, updated_at = NOW()
                """, userId, photoUrl);
    }

    private Map<String, Object> bookingPayload(Map<String, Object> row) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("id", Long.toString(number(row.get("id"))));
        result.put("type", row.get("type"));
        result.put("title", value(row.get("title"), ""));
        result.put("subtitle", value(row.get("subtitle"), ""));
        result.put("date", row.get("date") == null ? null : row.get("date").toString());
        result.put("end_date", row.get("end_date") == null ? null : row.get("end_date").toString());
        Object price = row.get("effective_price");
        if (price == null) price = row.get("price");
        if (price == null) price = row.get("total_amount");
        result.put("price", price);
        result.put("ref_code", row.get("ref_code"));
        result.put("image_url", row.get("image_url"));
        result.put("partner_listing_id", row.get("partner_listing_id"));
        result.put("rooms", row.get("rooms"));
        result.put("status", value(row.get("status"), "upcoming"));
        return result;
    }

    private PartnerListingAttribution partnerListingAttribution(
            Object rawListingId, String requestedType) {
        if (rawListingId == null || text(rawListingId).isBlank()) {
            return new PartnerListingAttribution(null, null, null);
        }

        long listingId;
        try {
            listingId = Long.parseLong(text(rawListingId));
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "Invalid partner listing");
        }
        List<Map<String, Object>> listings = jdbc.queryForList("""
                SELECT l.id, l.partner_id, l.type, l.active, l.price
                FROM partner_listings l
                JOIN partners p ON p.id = l.partner_id AND p.status = 'active'
                WHERE l.id = ?
                """, listingId);
        if (listings.isEmpty()) {
            throw new ResponseStatusException(
                    HttpStatus.NOT_FOUND, "Partner listing not found");
        }
        Map<String, Object> listing = listings.getFirst();
        if (!bool(listing.get("active"), false)) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Partner listing is not available");
        }
        String listingType = text(listing.get("type"));
        boolean typeMatches = switch (requestedType) {
            case "flight" -> "flight".equals(listingType);
            case "hotel", "car", "attraction", "package" ->
                    requestedType.equals(listingType);
            case "transfer" -> "transfer".equals(listingType);
            default -> false;
        };
        if (!typeMatches) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY,
                    "Partner listing does not match the reservation type");
        }
        return new PartnerListingAttribution(
                number(listing.get("partner_id")),
                number(listing.get("id")),
                decimal(listing.get("price")));
    }

    private BigDecimal partnerBookingPrice(
            PartnerListingAttribution attribution,
            String type,
            OffsetDateTime start,
            OffsetDateTime end,
            BigDecimal clientPrice) {
        if (attribution.listingId() == null) return clientPrice;
        long days = Math.max(1, java.time.temporal.ChronoUnit.DAYS.between(
                start.toLocalDate(), end.toLocalDate()));
        BigDecimal price = switch (type) {
            case "flight" -> attribution.price()
                    .multiply(new BigDecimal("1.12"))
                    .add(new BigDecimal("12"));
            case "hotel" -> attribution.price()
                    .multiply(BigDecimal.valueOf(days))
                    .multiply(new BigDecimal("1.12"));
            case "car" -> {
                Map<String, Object> fees = jdbc.queryForMap("""
                        SELECT COALESCE(attributes ->> 'insurance_fee', '4') AS insurance_fee,
                               COALESCE(attributes ->> 'service_fee', '10') AS service_fee
                        FROM partner_listings WHERE id = ?
                        """, attribution.listingId());
                yield attribution.price().multiply(BigDecimal.valueOf(days))
                        .add(decimal(fees.get("insurance_fee")))
                        .add(decimal(fees.get("service_fee")));
            }
            default -> attribution.price();
        };
        return price.setScale(2, RoundingMode.HALF_UP);
    }

    private record PartnerListingAttribution(
            Long partnerId, Long listingId, BigDecimal price) {}

    private void reserveHotelRooms(Long listingId, int roomCount) {
        if (!adjustListingInventory(listingId, "hotel_rooms", roomCount, false)) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "HOTEL_SOLD_OUT");
        }
    }

    private void restoreHotelRooms(Object rawListingId, int roomCount) {
        if (rawListingId == null || roomCount < 1) return;
        if (!adjustListingInventory(number(rawListingId), "hotel_rooms", roomCount, true)) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Could not restore hotel room inventory");
        }
    }

    private void reserveCar(Long listingId) {
        if (!adjustListingInventory(listingId, "car_vehicles", 1, false)) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "CAR_SOLD_OUT");
        }
    }

    private void restoreCar(Object rawListingId) {
        if (rawListingId != null) {
            adjustListingInventory(number(rawListingId), "car_vehicles", 1, true);
        }
    }

    private void reserveFlightSeats(Long listingId, int passengerCount) {
        if (listingId == null) return;
        if (!adjustListingInventory(listingId, "flight_seats", passengerCount, false)) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Insufficient available flight seats");
        }
    }

    private void restoreFlightSeats(Object rawListingId, int passengerCount) {
        if (rawListingId == null || text(rawListingId).isBlank()) return;
        long listingId = number(rawListingId);
        if (!adjustListingInventory(listingId, "flight_seats", passengerCount, true)) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Could not restore flight inventory");
        }
    }

    private boolean adjustListingInventory(
            Long listingId, String inventoryKind, int amount, boolean restore) {
        if (listingId == null || amount < 1) return false;
        Boolean updated = jdbc.queryForObject(
                "SELECT public.zentrip_adjust_listing_inventory(?, ?, ?, ?)",
                Boolean.class,
                listingId,
                inventoryKind,
                amount,
                restore);
        return Boolean.TRUE.equals(updated);
    }

    private long requireUserId(HttpServletRequest request) {
        Object userId = request.getAttribute("authUserId");
        if (!(userId instanceof Number number)) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Unauthenticated");
        return number.longValue();
    }

    private Long lockSuccessfulPaymentAttempt(Map<String, Object> body, long userId) {
        Object rawId = body.get("payment_attempt_id");
        if (rawId == null || text(rawId).isBlank()) return null;
        long attemptId;
        try {
            attemptId = Long.parseLong(text(rawId));
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "Invalid payment_attempt_id");
        }
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT status, booking_id, trip_id, transfer_id
                FROM payment_attempts
                WHERE id = ? AND user_id = ?
                FOR UPDATE
                """, attemptId, userId);
        if (rows.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND,
                    "Payment attempt not found for this account");
        }
        Map<String, Object> attempt = rows.getFirst();
        if (!"success".equals(text(attempt.get("status")))) {
            throw new ResponseStatusException(
                    HttpStatus.PAYMENT_REQUIRED, "PAYMENT_ATTEMPT_FAILED");
        }
        if (attempt.get("booking_id") != null || attempt.get("trip_id") != null
                || attempt.get("transfer_id") != null) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Payment attempt is already linked");
        }
        return attemptId;
    }

    private void linkPaymentAttemptToBooking(long attemptId, long userId, long bookingId) {
        int updated = jdbc.update("""
                UPDATE payment_attempts
                SET booking_id = ?
                WHERE id = ? AND user_id = ? AND status = 'success'
                  AND booking_id IS NULL AND trip_id IS NULL AND transfer_id IS NULL
                """, bookingId, attemptId, userId);
        requirePaymentAttemptLink(updated);
    }

    private void linkPaymentAttemptToTrip(long attemptId, long userId, long tripId) {
        int updated = jdbc.update("""
                UPDATE payment_attempts
                SET trip_id = ?
                WHERE id = ? AND user_id = ? AND status = 'success'
                  AND booking_id IS NULL AND trip_id IS NULL AND transfer_id IS NULL
                """, tripId, attemptId, userId);
        requirePaymentAttemptLink(updated);
    }

    private void linkPaymentAttemptToTransfer(long attemptId, long userId, long transferId) {
        int updated = jdbc.update("""
                UPDATE payment_attempts
                SET transfer_id = ?
                WHERE id = ? AND user_id = ? AND status = 'success'
                  AND booking_id IS NULL AND trip_id IS NULL AND transfer_id IS NULL
                """, transferId, attemptId, userId);
        requirePaymentAttemptLink(updated);
    }

    private static void requirePaymentAttemptLink(int updated) {
        if (updated != 1) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Payment attempt could not be linked");
        }
    }

    private static List<String> stringList(Object value) {
        if (!(value instanceof List<?> values)) return List.of();
        return values.stream()
                .filter(java.util.Objects::nonNull)
                .map(Object::toString)
                .filter(item -> !item.isBlank())
                .toList();
    }

    private long insert(String sql, Object... args) {
        KeyHolder keyHolder = new GeneratedKeyHolder();
        jdbc.update((PreparedStatementCreator) connection -> {
            PreparedStatement statement = connection.prepareStatement(sql, new String[]{"id"});
            for (int i = 0; i < args.length; i++) statement.setObject(i + 1, args[i]);
            return statement;
        }, keyHolder);
        Number key = keyHolder.getKey();
        if (key == null) throw new IllegalStateException("Insert did not return an ID");
        return key.longValue();
    }

    private static String required(Map<String, Object> body, String key) {
        String value = text(body.get(key));
        if (value.isBlank()) throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, key + " is required");
        return value;
    }

    private static Map<String, Object> validationError(String field, String message) {
        return Map.of(
                "message", "The given data was invalid.",
                "errors", Map.of(field, List.of(message)));
    }

    private static String text(Object value) {
        return value == null ? "" : value.toString();
    }

    private static String value(Map<String, Object> body, String key, String fallback) {
        return body.get(key) == null ? fallback : text(body.get(key));
    }

    private static String value(Object value, String fallback) {
        return value == null ? fallback : value.toString();
    }

    private static BigDecimal decimal(Object value) {
        if (value == null || text(value).isBlank()) return BigDecimal.ZERO;
        try {
            return new BigDecimal(text(value));
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "Invalid numeric value");
        }
    }

    private static int integer(Object value, int fallback) {
        if (value == null) return fallback;
        try {
            return Integer.parseInt(text(value));
        } catch (NumberFormatException exception) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "Invalid integer value");
        }
    }

    private static boolean bool(Object value, boolean fallback) {
        if (value == null) return fallback;
        if (value instanceof Boolean flag) return flag;
        String text = value.toString().toLowerCase();
        return text.equals("true") || text.equals("1") || text.equals("yes");
    }

    private static long number(Object value) {
        return value instanceof Number number ? number.longValue() : Long.parseLong(text(value));
    }

    private static OffsetDateTime dateTime(String value) {
        try {
            return OffsetDateTime.parse(value).withOffsetSameInstant(ZoneOffset.UTC);
        } catch (DateTimeParseException ignored) {
            try {
                return LocalDateTime.parse(value).atOffset(ZoneOffset.UTC);
            } catch (DateTimeParseException exception) {
                return LocalDate.parse(value).atStartOfDay().atOffset(ZoneOffset.UTC);
            }
        }
    }

    private static OffsetDateTime flightDateTime(String value) {
        try {
            return OffsetDateTime.parse(value)
                    .withOffsetSameInstant(ZoneOffset.UTC);
        } catch (DateTimeParseException ignored) {
            try {
                return LocalDateTime.parse(value).atOffset(ZoneOffset.UTC);
            } catch (DateTimeParseException ignoredLocalDateTime) {
                try {
                    return LocalDate.parse(value).atStartOfDay().atOffset(ZoneOffset.UTC);
                } catch (DateTimeParseException invalidDate) {
                    throw new ResponseStatusException(
                            HttpStatus.UNPROCESSABLE_ENTITY, "Invalid flight schedule time");
                }
            }
        }
    }

    private static OffsetDateTime nullableDateTime(Object value) {
        return value == null || text(value).isBlank() ? null : dateTime(text(value));
    }
}
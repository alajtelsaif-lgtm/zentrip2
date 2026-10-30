package com.zentrip.api;

import java.math.BigDecimal;
import java.math.RoundingMode;
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

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCreator;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
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
import org.springframework.web.client.RestClient;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;
import org.springframework.web.util.UriComponentsBuilder;

import jakarta.servlet.http.HttpServletRequest;

@RestController
@RequestMapping("/api")
public class ApiController {
    private final JdbcTemplate jdbc;
    private final ProfilePhotoStorage profilePhotoStorage;
    private final PasswordResetService passwordResetService;
    private final PasswordEncoder passwords = new BCryptPasswordEncoder();
    private final RestClient http = RestClient.create();
    private final String serpApiKey;
    private static final ObjectMapper JSON = new ObjectMapper();

    public ApiController(JdbcTemplate jdbc,
                         @Value("${serpapi.key:}") String serpApiKey,
                         ProfilePhotoStorage profilePhotoStorage,
                         PasswordResetService passwordResetService) {
        this.jdbc = jdbc;
        this.serpApiKey = serpApiKey;
        this.profilePhotoStorage = profilePhotoStorage;
        this.passwordResetService = passwordResetService;
    }

    @PostMapping("/auth/register")
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
        String email = text(body.get("email"));
        String password = text(body.get("password"));
        List<Map<String, Object>> rows = jdbc.queryForList("SELECT id, password FROM users WHERE email = ?", email);
        if (rows.isEmpty() || !passwords.matches(password, text(rows.getFirst().get("password")))) {
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
                ON DUPLICATE KEY UPDATE
                    rating = VALUES(rating), comment = VALUES(comment),
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
                       COALESCE(m.badge, '') AS badge
                FROM offers o
                LEFT JOIN offer_catalog_metadata m ON m.offer_id = o.id
                WHERE o.is_active = TRUE
                ORDER BY o.is_featured DESC, o.sort_order ASC, o.title ASC
                """).stream().map(row -> {
                    Map<String, Object> offer = new LinkedHashMap<>(row);
                    offer.put("highlights", parseHighlights(row.get("highlights")));
                    String badge = row.get("badge") == null ? "" : row.get("badge").toString();
                    boolean featured = Boolean.TRUE.equals(row.get("is_featured"))
                            || "1".equals(String.valueOf(row.get("is_featured")))
                            || "true".equalsIgnoreCase(String.valueOf(row.get("is_featured")));
                    offer.put("badge", badge.isEmpty() && featured ? "Featured Offer" : badge);
                    BigDecimal total = new BigDecimal(String.valueOf(
                            row.getOrDefault("flight_price_per_person", 0)))
                            .add(new BigDecimal(String.valueOf(
                                    row.getOrDefault("hotel_price_per_night", 0)))
                                    .multiply(new BigDecimal(String.valueOf(
                                            row.getOrDefault("duration_nights", 0)))));
                    offer.put("total_price_per_person", total);
                    return offer;
                }).toList();
        return Map.of("offers", payload);
    }

    @GetMapping("/attractions/search")
    public Map<String, Object> searchMonuments(
            @RequestParam(defaultValue = "") String city,
            @RequestParam(required = false) String category) {
        String cityFilter = city.trim().toLowerCase(Locale.ROOT);
        String categoryFilter = category == null ? "" : category.trim();
        List<Map<String, Object>> monuments = jdbc.queryForList("""
                SELECT id, title, location, category_tag, category, rating,
                       review_count, description, working_hours,
                       best_time_to_visit, entry_fee, image_url, tags
                FROM tourist_monuments
                WHERE is_active = TRUE
                  AND (? = '' OR LOWER(location) LIKE ?)
                  AND (? = '' OR category = ?)
                ORDER BY sort_order ASC, title ASC
                LIMIT 100
                """,
                cityFilter,
                "%" + cityFilter + "%",
                categoryFilter,
                categoryFilter);
        List<Map<String, Object>> payload = monuments.stream().map(row -> {
            Map<String, Object> attraction = new LinkedHashMap<>(row);
            String[] location = String.valueOf(row.get("location")).split(",", 2);
            attraction.put("name", row.get("title"));
            attraction.put("city", location[0].trim());
            attraction.put("country", location.length > 1 ? location[1].trim() : "");
            attraction.put("latitude", 0);
            attraction.put("longitude", 0);
            attraction.put("opening_hours", row.get("working_hours"));
            attraction.put("tags", parseHighlights(row.get("tags")));
            return attraction;
        }).toList();
        return Map.of("attractions", payload);
    }

    private static List<String> parseHighlights(Object raw) {
        if (raw instanceof List<?> list) {
            return list.stream().map(Object::toString).toList();
        }
        if (raw == null) return List.of();
        try {
            return JSON.readValue(raw.toString(), new TypeReference<List<String>>() {});
        } catch (com.fasterxml.jackson.core.JsonProcessingException exception) {
            return List.of();
        }
    }

    @GetMapping("/trips")
    public Map<String, Object> trips(HttpServletRequest request) {
        long userId = requireUserId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
            SELECT trips.*,
                  JSON_UNQUOTE(JSON_EXTRACT(details, '$.arrival_date')) AS arrival_date,
                  JSON_UNQUOTE(JSON_EXTRACT(details, '$.refund_status')) AS refund_status,
                  JSON_UNQUOTE(JSON_EXTRACT(details, '$.refund_method')) AS refund_method
            FROM trips WHERE user_id = ? ORDER BY created_at DESC
            """, userId);
        return Map.of("trips", rows);
    }

    @PostMapping("/trips")
    @Transactional
    public ResponseEntity<?> createTrip(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        long userId = requireUserId(request);
        String originCode = required(body, "origin_code");
        String originCity = required(body, "origin_city");
        String destinationCode = required(body, "destination_code");
        String destinationCity = required(body, "destination_city");
        LocalDateTime departure = flightDateTime(required(body, "departure_date"));
        LocalDateTime arrival = flightDateTime(required(body, "arrival_date"));
        LocalDateTime returnDate = nullableFlightDateTime(body.get("return_date"));
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
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, JSON_OBJECT('arrival_date', ?, 'passenger_count', ?), NOW(), NOW())
                """, userId, attribution.partnerId(), attribution.listingId(),
                originCity + " to " + destinationCity, destinationCity, originCode, originCity,
                destinationCode, destinationCity, Timestamp.valueOf(departure),
                returnDate == null ? null : Timestamp.valueOf(returnDate),
                flightNumber, body.get("airline"), body.get("airline_logo_url"), bool(body.get("is_direct"), true),
                value(body, "seat_class", "Economy"), price, body.get("booking_ref"),
                "upcoming", arrival.toString(), passengerCount);
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("trip", tripRow(id)));
    }

    @GetMapping("/flights/{flightId}/seats")
    public Map<String, Object> flightSeats(
            @PathVariable long flightId,
            HttpServletRequest request) {
        requireUserId(request);
        Map<String, Object> listing = flightListing(flightId, false);
        return Map.of(
                "occupied_seats", occupiedFlightSeats(flightId),
                "seat_layout", listing.get("seat_layout"),
                "row_count", listing.get("row_count"));
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
                    VALUES (?, ?, ?, 'reserved', DATE_ADD(NOW(), INTERVAL 15 MINUTE), NOW(), NOW())
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
        LocalDateTime departure = flightDateTime(
                requiredAttribute(attributes, "departure_time"));
        LocalDateTime arrival = flightDateTime(
                requiredAttribute(attributes, "arrival_time"));
        LocalDateTime returnDate = nullableFlightDateTime(body.get("return_date"));
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
                .multiply(new BigDecimal("15"));
        BigDecimal extraFees = extras.stream()
                .map(ApiController::flightExtraPrice)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        BigDecimal totalPrice = baseFare.multiply(BigDecimal.valueOf(seats.size()))
                .add(seatFees)
                .add(extraFees)
                .multiply(new BigDecimal("1.12"))
                .add(new BigDecimal("12"))
                .setScale(2, RoundingMode.HALF_UP);

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
                Timestamp.valueOf(departure),
                returnDate == null ? null : Timestamp.valueOf(returnDate),
                flightNumber, airline,
                airlineLogoUrl.isBlank() ? null : airlineLogoUrl,
                isDirect, seatClassLabel, totalPrice, reference, detailsJson);
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

        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of(
                "booking", Map.of(
                        "reference", reference,
                        "seats", seats,
                        "extras", extras,
                        "total_price", totalPrice),
                "trip", tripRow(tripId)));
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
        String sql = """
                SELECT l.id, l.partner_id, l.title, l.city, l.price, l.attributes,
                       p.name AS partner_name
                FROM partner_listings l
                JOIN partners p ON p.id = l.partner_id AND p.status = 'active'
                WHERE l.id = ? AND l.type = 'flight' AND l.active = TRUE
                """ + (lock ? " FOR UPDATE" : "");
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
        return switch (extra) {
            case "extra_baggage" -> new BigDecimal("18");
            case "flexible_ticket" -> new BigDecimal("12");
            default -> BigDecimal.ZERO;
        };
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
        if (row == 1) return true;
        if ("2-2".equals(listing.get("seat_layout"))) {
            return row == 7 || row == 8;
        }
        return row == 11 || row == 12;
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
        LocalDateTime departure = flightDateTime(departureValue);
        LocalDateTime arrival = flightDateTime(arrivalValue);
        LocalDateTime returnDate = nullableFlightDateTime(returnValue);
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
            LocalDateTime departure,
            LocalDateTime arrival,
            LocalDateTime returnDate) {
        LocalDate requestedStart = departure.toLocalDate();
        LocalDate requestedEnd = tripLastOccupiedDate(departure, arrival, returnDate);
        List<Map<String, Object>> trips = jdbc.queryForList("""
                SELECT departure_date, return_date, status,
                       JSON_UNQUOTE(JSON_EXTRACT(details, '$.arrival_date')) AS arrival_date
                FROM trips
                WHERE user_id = ? AND LOWER(status) NOT IN ('cancelled', 'completed')
                """, userId);

        for (Map<String, Object> trip : trips) {
            LocalDateTime existingDeparture = storedFlightDateTime(trip.get("departure_date"));
            if (existingDeparture == null) continue;
            LocalDateTime existingArrival = storedFlightDateTime(trip.get("arrival_date"));
            LocalDateTime existingReturn = storedFlightDateTime(trip.get("return_date"));
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
            LocalDateTime departure, LocalDateTime arrival, LocalDateTime returnDate) {
        LocalDate end = departure.toLocalDate();
        if (arrival != null && arrival.toLocalDate().isAfter(end)) {
            end = arrival.toLocalDate();
        }
        if (returnDate != null && returnDate.toLocalDate().isAfter(end)) {
            end = returnDate.toLocalDate();
        }
        return end;
    }

    private static LocalDateTime nullableFlightDateTime(Object value) {
        return value == null || text(value).isBlank() ? null : flightDateTime(text(value));
    }

    private static LocalDateTime storedFlightDateTime(Object value) {
        if (value instanceof Timestamp timestamp) return timestamp.toLocalDateTime();
        if (value instanceof LocalDateTime dateTime) return dateTime;
        if (value instanceof java.sql.Date date) return date.toLocalDate().atStartOfDay();
        if (value == null || text(value).isBlank()) return null;
        try {
            return flightDateTime(text(value));
        } catch (ResponseStatusException exception) {
            return null;
        }
    }

    private Map<String, Object> tripRow(long id) {
        return jdbc.queryForMap("""
                SELECT trips.*,
                       JSON_UNQUOTE(JSON_EXTRACT(details, '$.arrival_date')) AS arrival_date,
                       JSON_UNQUOTE(JSON_EXTRACT(details, '$.passenger_count')) AS passenger_count,
                       JSON_EXTRACT(details, '$.seat_numbers') AS seat_numbers,
                       JSON_UNQUOTE(JSON_EXTRACT(details, '$.refund_status')) AS refund_status,
                       JSON_UNQUOTE(JSON_EXTRACT(details, '$.refund_method')) AS refund_method
                FROM trips WHERE id = ?
                """, id);
    }

    @DeleteMapping("/trips/{id}")
    @Transactional
    public ResponseEntity<?> deleteTrip(@PathVariable long id, HttpServletRequest request) {
        long userId = requireUserId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT id, status, partner_listing_id,
                       JSON_UNQUOTE(JSON_EXTRACT(details, '$.passenger_count')) AS passenger_count,
                       JSON_UNQUOTE(JSON_EXTRACT(details, '$.refund_status')) AS refund_status,
                       JSON_UNQUOTE(JSON_EXTRACT(details, '$.refund_method')) AS refund_method
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
                        details = JSON_SET(COALESCE(details, JSON_OBJECT()),
                            '$.refund_status', 'pending_airline_review',
                            '$.refund_method', 'original_payment_method',
                            '$.refund_requested_at', UTC_TIMESTAMP()),
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
                       JSON_UNQUOTE(JSON_EXTRACT(details, '$.end_date')) AS end_date,
                       JSON_UNQUOTE(JSON_EXTRACT(details, '$.image_url')) AS image_url
                FROM bookings WHERE user_id = ? ORDER BY created_at DESC
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
        LocalDateTime start = flightDateTime(startValue);
        LocalDateTime end = flightDateTime(endValue);
        if (!end.isAfter(start)) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "end_date must be after start_date");
        }
        return Map.of("available", !hasBookingScheduleConflict(
                userId, normalizedType, title, start, end));
    }

    @PostMapping("/bookings")
    @Transactional
    public ResponseEntity<?> createBooking(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        long userId = requireUserId(request);
        String type = supportedBookingType(required(body, "type"));
        String title = required(body, "title");
        String subtitle = required(body, "subtitle");
        LocalDateTime start = flightDateTime(required(body, "date"));
        LocalDateTime end = nullableFlightDateTime(body.get("end_date"));
        if (end == null) end = start.plusDays(1);
        if (!end.isAfter(start)) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "end_date must be after start_date");
        }
        BigDecimal price = decimal(body.get("price"));
        PartnerListingAttribution attribution =
                partnerListingAttribution(body.get("partner_listing_id"), type);
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
                INSERT INTO bookings (user_id, partner_id, partner_listing_id, type, status, total_amount, title, subtitle, `date`, price, ref_code, details, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'upcoming', ?, ?, ?, ?, ?, ?, CAST(? AS JSON), NOW(), NOW())
                """, userId, attribution.partnerId(), attribution.listingId(),
                type, price, title, subtitle,
                Timestamp.valueOf(start), price, body.get("ref_code"),
                bookingDetailsJson(end, body.get("image_url"), hotelRoomCount,
                        hotelRoomReserved, carReserved));
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(Map.of("booking", bookingPayload(jdbc.queryForMap("""
                        SELECT bookings.*,
                               JSON_UNQUOTE(JSON_EXTRACT(details, '$.end_date')) AS end_date,
                               JSON_UNQUOTE(JSON_EXTRACT(details, '$.image_url')) AS image_url
                        FROM bookings WHERE id = ?
                        """, id))));
    }

    @DeleteMapping("/bookings/{id}")
    @Transactional
    public ResponseEntity<?> cancelBooking(
            @PathVariable long id, HttpServletRequest request) {
        long userId = requireUserId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT status, type, partner_listing_id,
                       CAST(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
                           details, '$.hotel_rooms_reserved'
                       )), '0') AS UNSIGNED) AS hotel_rooms_reserved,
                       CAST(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
                           details, '$.car_vehicle_reserved'
                       )), '0') AS UNSIGNED) AS car_vehicle_reserved
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

    /** JSON stored in bookings.details: end date plus an optional http(s) cover image. */
    static String bookingDetailsJson(
            LocalDateTime end,
            Object imageUrl,
            int hotelRoomCount,
            boolean hotelRoomReserved) {
        return bookingDetailsJson(end, imageUrl, hotelRoomCount, hotelRoomReserved, false);
    }

    static String bookingDetailsJson(
            LocalDateTime end,
            Object imageUrl,
            int hotelRoomCount,
            boolean hotelRoomReserved,
            boolean carReserved) {
        Map<String, Object> details = new LinkedHashMap<>();
        details.put("end_date", end.toString());
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

    private String supportedBookingType(String type) {
        String normalized = type.toLowerCase();
        if (!List.of("hotel", "car", "attraction", "package").contains(normalized)) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY,
                    "Booking type must be hotel, car, attraction, or package");
        }
        return normalized;
    }

    private boolean hasBookingScheduleConflict(
            long userId, String type, String title, LocalDateTime start, LocalDateTime end) {
        List<Map<String, Object>> existingBookings = jdbc.queryForList("""
                SELECT title, `date`,
                       JSON_UNQUOTE(JSON_EXTRACT(details, '$.end_date')) AS end_date
                FROM bookings
                WHERE user_id = ? AND LOWER(type) = ?
                  AND LOWER(status) NOT IN ('cancelled', 'completed')
                """, userId, type);

        for (Map<String, Object> existing : existingBookings) {
            if ("attraction".equals(type)
                    && !text(existing.get("title")).equalsIgnoreCase(title)) {
                continue;
            }
            LocalDateTime existingStart = storedFlightDateTime(existing.get("date"));
            if (existingStart == null) continue;
            LocalDateTime existingEnd = storedFlightDateTime(existing.get("end_date"));
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
        LocalDateTime pickupTime = dateTime(pickupValue).toLocalDateTime();
        return Map.of("available",
                !hasTransferScheduleConflict(userId, pickupTime, durationMinutes));
    }

    @PostMapping("/transfers")
    @Transactional
    public ResponseEntity<?> createTransfer(
            @RequestBody Map<String, Object> body, HttpServletRequest request) {
        long userId = requireUserId(request);
        LocalDateTime pickupTime = dateTime(required(body, "pickup_time")).toLocalDateTime();
        int durationMinutes = integer(body.get("duration_minutes"), 0);
        validateTransferDuration(durationMinutes);
        PartnerListingAttribution attribution =
                partnerListingAttribution(body.get("partner_listing_id"), "transfer");
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
                Timestamp.valueOf(pickupTime), price,
                integer(body.get("passengers"), 1), value(body, "status", "confirmed"));
        jdbc.update(
                "INSERT INTO transfer_schedules (transfer_id, duration_minutes) VALUES (?, ?)",
                id, durationMinutes);
        Map<String, Object> transfer = jdbc.queryForMap("SELECT * FROM transfers WHERE id = ?", id);
        transfer.put("id", Long.toString(id));
        transfer.put("duration_minutes", durationMinutes);
        return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("transfer", transfer));
    }

    private boolean hasTransferScheduleConflict(
            long userId, LocalDateTime pickupTime, int durationMinutes) {
        LocalDateTime requestedEnd = pickupTime.plusMinutes(durationMinutes);
        List<Map<String, Object>> transfers = jdbc.queryForList("""
                SELECT transfers.pickup_time, transfers.status,
                       COALESCE(transfer_schedules.duration_minutes, 60) AS duration_minutes
                FROM transfers
                LEFT JOIN transfer_schedules ON transfer_schedules.transfer_id = transfers.id
                WHERE transfers.user_id = ?
                  AND LOWER(transfers.status) NOT IN ('cancelled', 'completed')
                """, userId);

        for (Map<String, Object> transfer : transfers) {
            LocalDateTime existingStart =
                    storedFlightDateTime(transfer.get("pickup_time"));
            if (existingStart == null) continue;
            int existingDuration = integer(transfer.get("duration_minutes"), 60);
            if (existingDuration < 1) existingDuration = 60;
            LocalDateTime existingEnd = existingStart.plusMinutes(existingDuration);
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
    public Map<String, Object> checkout(@RequestBody Map<String, Object> body) {
        required(body, "amount");
        String reference = value(body, "reference_id", UUID.randomUUID().toString());
        return Map.of("session_id", "mock_" + reference, "checkout_url", "mock://checkout");
    }

    @GetMapping("/payments/verify/{sessionId}")
    public Map<String, Object> verifyPayment(@PathVariable String sessionId) {
        return Map.of("paid", true, "session_id", sessionId);
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
        String token = UUID.randomUUID().toString().replace("-", "") + UUID.randomUUID().toString().replace("-", "");
        jdbc.update("INSERT INTO api_tokens (user_id, token_hash, expires_at) VALUES (?, ?, ?)",
                userId, TokenAuthFilter.sha256(token), Timestamp.from(Instant.now().plusSeconds(60L * 60 * 24 * 30)));
        return Map.of("user", userPayload(userId, request), "token", token);
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
                ON DUPLICATE KEY UPDATE photo_url = ?, updated_at = NOW()
                """, userId, photoUrl, photoUrl);
    }

    private Map<String, Object> bookingPayload(Map<String, Object> row) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("id", Long.toString(number(row.get("id"))));
        result.put("type", row.get("type"));
        result.put("title", value(row.get("title"), ""));
        result.put("subtitle", value(row.get("subtitle"), ""));
        result.put("date", row.get("date") == null ? null : row.get("date").toString());
        result.put("end_date", row.get("end_date") == null ? null : row.get("end_date").toString());
        result.put("price", row.get("price"));
        result.put("ref_code", row.get("ref_code"));
        result.put("image_url", row.get("image_url"));
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
            LocalDateTime start,
            LocalDateTime end,
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
                        SELECT COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
                                   attributes, '$.insurance_fee')), '4') AS insurance_fee,
                               COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
                                   attributes, '$.service_fee')), '10') AS service_fee
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
        int updated = jdbc.update("""
                UPDATE partner_listings
                SET attributes = JSON_SET(
                        COALESCE(attributes, JSON_OBJECT()),
                        '$.available_rooms', available_rooms - ?),
                    available_rooms = available_rooms - ?,
                    updated_at = NOW()
                WHERE id = ? AND type = 'hotel' AND active = TRUE
                  AND available_rooms >= ?
                """, roomCount, roomCount, listingId, roomCount);
        if (updated != 1) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "HOTEL_SOLD_OUT");
        }
    }

    private void restoreHotelRooms(Object rawListingId, int roomCount) {
        if (rawListingId == null || roomCount < 1) return;
        int updated = jdbc.update("""
                UPDATE partner_listings
                SET attributes = JSON_SET(
                        COALESCE(attributes, JSON_OBJECT()),
                        '$.available_rooms', available_rooms + ?),
                    available_rooms = available_rooms + ?,
                    updated_at = NOW()
                WHERE id = ? AND type = 'hotel'
                """, roomCount, roomCount, number(rawListingId), roomCount);
        if (updated != 1) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Could not restore hotel room inventory");
        }
    }

    private void reserveCar(Long listingId) {
        int updated = jdbc.update("""
                UPDATE partner_listings
                SET attributes = JSON_SET(
                        COALESCE(attributes, JSON_OBJECT()),
                        '$.available_vehicles',
                        CAST(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
                            attributes, '$.available_vehicles'
                        )), '1') AS UNSIGNED) - 1),
                    updated_at = NOW()
                WHERE id = ? AND type = 'car' AND active = TRUE
                  AND CAST(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
                      attributes, '$.available_vehicles'
                  )), '1') AS UNSIGNED) > 0
                """, listingId);
        if (updated != 1) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "CAR_SOLD_OUT");
        }
    }

    private void restoreCar(Object rawListingId) {
        jdbc.update("""
                UPDATE partner_listings
                SET attributes = JSON_SET(
                        COALESCE(attributes, JSON_OBJECT()),
                        '$.available_vehicles',
                        CAST(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(
                            attributes, '$.available_vehicles'
                        )), '0') AS UNSIGNED) + 1),
                    updated_at = NOW()
                WHERE id = ? AND type = 'car'
                """, number(rawListingId));
    }

    private void reserveFlightSeats(Long listingId, int passengerCount) {
        if (listingId == null) return;
        int updated = jdbc.update("""
                UPDATE partner_listings
                SET attributes = JSON_SET(
                        COALESCE(attributes, JSON_OBJECT()),
                        '$.seats_available',
                        CAST(COALESCE(
                                JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.seats_available')),
                                '0') AS UNSIGNED) - ?),
                    updated_at = NOW()
                WHERE id = ? AND type = 'flight' AND active = TRUE
                  AND CAST(COALESCE(
                        JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.seats_available')),
                        '0') AS UNSIGNED) >= ?
                """, passengerCount, listingId, passengerCount);
        if (updated != 1) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Insufficient available flight seats");
        }
    }

    private void restoreFlightSeats(Object rawListingId, int passengerCount) {
        if (rawListingId == null || text(rawListingId).isBlank()) return;
        long listingId = number(rawListingId);
        int updated = jdbc.update("""
                UPDATE partner_listings
                SET attributes = JSON_SET(
                        COALESCE(attributes, JSON_OBJECT()),
                        '$.seats_available',
                        CAST(COALESCE(
                                JSON_UNQUOTE(JSON_EXTRACT(attributes, '$.seats_available')),
                                '0') AS UNSIGNED) + ?),
                    updated_at = NOW()
                WHERE id = ? AND type = 'flight'
                """, passengerCount, listingId);
        if (updated != 1) {
            throw new ResponseStatusException(
                    HttpStatus.CONFLICT, "Could not restore flight inventory");
        }
    }

    private long requireUserId(HttpServletRequest request) {
        Object userId = request.getAttribute("authUserId");
        if (!(userId instanceof Number number)) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Unauthenticated");
        return number.longValue();
    }

    private long insert(String sql, Object... args) {
        KeyHolder keyHolder = new GeneratedKeyHolder();
        jdbc.update((PreparedStatementCreator) connection -> {
            PreparedStatement statement = connection.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS);
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

    private static Timestamp dateTime(String value) {
        try {
            return Timestamp.valueOf(OffsetDateTime.parse(value).toLocalDateTime());
        } catch (DateTimeParseException ignored) {
            try {
                return Timestamp.valueOf(LocalDateTime.parse(value));
            } catch (DateTimeParseException exception) {
                return Timestamp.valueOf(LocalDate.parse(value).atStartOfDay());
            }
        }
    }

    private static LocalDateTime flightDateTime(String value) {
        try {
            return OffsetDateTime.parse(value)
                    .withOffsetSameInstant(ZoneOffset.UTC).toLocalDateTime();
        } catch (DateTimeParseException ignored) {
            try {
                return LocalDateTime.parse(value);
            } catch (DateTimeParseException ignoredLocalDateTime) {
                try {
                    return LocalDate.parse(value).atStartOfDay();
                } catch (DateTimeParseException invalidDate) {
                    throw new ResponseStatusException(
                            HttpStatus.UNPROCESSABLE_ENTITY, "Invalid flight schedule time");
                }
            }
        }
    }

    private static Timestamp nullableDateTime(Object value) {
        return value == null || text(value).isBlank() ? null : dateTime(text(value));
    }
}
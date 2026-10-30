package com.zentrip.api;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import jakarta.servlet.http.HttpServletRequest;

@RestController
@RequestMapping("/api/preferences/travel")
public class TravelPreferencesController {
    private static final Set<String> BUDGET_LEVELS = Set.of("budget", "balanced", "luxury");
    private static final Set<String> TRAVEL_PACES = Set.of("relaxed", "balanced", "packed");
    private static final Set<String> INTERESTS = Set.of(
            "culture", "food", "nature", "beaches", "history", "shopping", "adventure");

    private final JdbcTemplate jdbc;

    public TravelPreferencesController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping
    public Map<String, Object> get(HttpServletRequest request) {
        long userId = requireUserId(request);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                SELECT budget_level, travel_pace, trip_duration_days, travelers,
                       interests, preferred_destination
                FROM travel_preferences WHERE user_id = ?
                """, userId);
        if (rows.isEmpty()) return defaults();
        return payload(rows.getFirst());
    }

    @PutMapping
    public Map<String, Object> save(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        String budget = text(body.get("budget_level"));
        String pace = text(body.get("travel_pace"));
        int duration = integer(body.get("trip_duration_days"), 7);
        int travelers = integer(body.get("travelers"), 1);
        String destination = text(body.get("preferred_destination")).trim();
        List<String> interests = interests(body.get("interests"));

        if (!BUDGET_LEVELS.contains(budget)) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "Invalid budget_level");
        }
        if (!TRAVEL_PACES.contains(pace)) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "Invalid travel_pace");
        }
        if (duration < 1 || duration > 30) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "trip_duration_days must be between 1 and 30");
        }
        if (travelers < 1 || travelers > 12) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "travelers must be between 1 and 12");
        }
        if (destination.length() > 255) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "preferred_destination must be 255 characters or fewer");
        }

        jdbc.update("""
                INSERT INTO travel_preferences
                    (user_id, budget_level, travel_pace, trip_duration_days, travelers, interests, preferred_destination)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (user_id) DO UPDATE SET
                    budget_level = EXCLUDED.budget_level,
                    travel_pace = EXCLUDED.travel_pace,
                    trip_duration_days = EXCLUDED.trip_duration_days,
                    travelers = EXCLUDED.travelers,
                    interests = EXCLUDED.interests,
                    preferred_destination = EXCLUDED.preferred_destination,
                    updated_at = CURRENT_TIMESTAMP
                """, userId, budget, pace, duration, travelers,
                String.join(",", interests), destination.isEmpty() ? null : destination);

        return Map.of("preferences", get(request));
    }

    private static Map<String, Object> defaults() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("budget_level", "balanced");
        result.put("travel_pace", "balanced");
        result.put("trip_duration_days", 7);
        result.put("travelers", 1);
        result.put("interests", List.of());
        result.put("preferred_destination", "");
        return result;
    }

    private static Map<String, Object> payload(Map<String, Object> row) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("budget_level", text(row.get("budget_level")));
        result.put("travel_pace", text(row.get("travel_pace")));
        result.put("trip_duration_days", integer(row.get("trip_duration_days"), 7));
        result.put("travelers", integer(row.get("travelers"), 1));
        result.put("interests", interests(row.get("interests")));
        result.put("preferred_destination", text(row.get("preferred_destination")));
        return result;
    }

    private static List<String> interests(Object value) {
        if (value instanceof List<?> values) {
            return values.stream().map(String::valueOf).filter(INTERESTS::contains).distinct().toList();
        }
        String raw = text(value);
        if (raw.isBlank()) return List.of();
        return Arrays.stream(raw.split(","))
            .map(part -> part == null ? "" : part.trim())
                .filter(INTERESTS::contains)
                .distinct()
                .collect(Collectors.toList());
    }

    private static long requireUserId(HttpServletRequest request) {
        Object userId = request.getAttribute("authUserId");
        if (!(userId instanceof Number number)) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Unauthenticated");
        }
        return number.longValue();
    }

    private static int integer(Object value, int fallback) {
        if (value instanceof Number number) return number.intValue();
        if (value == null) return fallback;
        try {
            return Integer.parseInt(value.toString());
        } catch (NumberFormatException exception) {
            return fallback;
        }
    }

    private static String text(Object value) {
        return value == null ? "" : value.toString();
    }
}
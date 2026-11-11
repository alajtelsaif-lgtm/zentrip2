package com.zentrip.api;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.ConcurrentHashMap;
import java.io.IOException;
import java.io.OutputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;

import com.fasterxml.jackson.databind.ObjectMapper;

import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.dao.DataAccessException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

import jakarta.servlet.http.HttpServletRequest;

@RestController
@RequestMapping("/api/ai")
public class AiChatController {
    private static final Logger LOG = LoggerFactory.getLogger(AiChatController.class);
    private static final int MAX_MESSAGE_LENGTH = 4000;
    private static final int HISTORY_LIMIT = 10;
    private static final int STORED_MESSAGE_LIMIT = 40;
    private static final long CANCELLATION_TTL_MILLIS = 180_000;
    private static final long STREAM_HEARTBEAT_INTERVAL_SECONDS = 10;
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final ScheduledExecutorService STREAM_HEARTBEATS =
            Executors.newScheduledThreadPool(2, runnable -> {
                Thread thread = new Thread(runnable, "zen-chat-heartbeat");
                thread.setDaemon(true);
                return thread;
            });

    private final JdbcTemplate jdbc;
    private final GoogleGeminiChatService gemini;
    private final TransactionTemplate transaction;
    private final Map<String, Long> cancelledRequests = new ConcurrentHashMap<>();

    @Autowired
    public AiChatController(
            JdbcTemplate jdbc,
            GoogleGeminiChatService gemini,
            ObjectProvider<PlatformTransactionManager> transactionManagers) {
        this.jdbc = jdbc;
        this.gemini = gemini;
        PlatformTransactionManager transactionManager = transactionManagers.getIfAvailable();
        this.transaction = transactionManager == null
                ? null : new TransactionTemplate(transactionManager);
    }

    AiChatController(
            JdbcTemplate jdbc,
            GoogleGeminiChatService gemini,
            PlatformTransactionManager transactionManager) {
        this.jdbc = jdbc;
        this.gemini = gemini;
        this.transaction = new TransactionTemplate(transactionManager);
    }

    @PostMapping(value = "/chat", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public ResponseEntity<StreamingResponseBody> chat(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        String message = text(body.get("message")).trim();
        String sessionId = text(body.get("session_id")).trim();
        String requestId = text(body.get("request_id")).trim();
        String language = "ar".equalsIgnoreCase(text(body.get("language"))) ? "ar" : "en";

        if (message.isBlank() || message.length() > MAX_MESSAGE_LENGTH) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY,
                    "The message is required and must be 4000 characters or fewer.");
        }
        if (!sessionId.matches("[A-Za-z0-9_-]{1,100}")) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "A valid session_id is required.");
        }
        if (!requestId.matches("[A-Za-z0-9_-]{1,100}")) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "A valid request_id is required.");
        }

        String cancellationKey = cancellationKey(userId, sessionId, requestId);
        if (consumeCancellation(cancellationKey)) {
            return ResponseEntity.noContent().<StreamingResponseBody>build();
        }

        List<Map<String, Object>> rows;
        try {
            rows = new ArrayList<>(jdbc.queryForList("""
                    SELECT role, content FROM ai_chat_messages
                    WHERE user_id = ? AND session_id = ?
                    ORDER BY id DESC LIMIT ?
                """, userId, sessionId, HISTORY_LIMIT));
        } catch (DataAccessException exception) {
            LOG.warn("Zen chat history is unavailable for user {}. Continuing without history.",
                    userId, exception);
            rows = new ArrayList<>();
        }
        Collections.reverse(rows);

        List<GoogleGeminiChatService.ChatTurn> turns = new ArrayList<>();
        for (Map<String, Object> row : rows) {
            turns.add(new GoogleGeminiChatService.ChatTurn(
                    text(row.get("role")), text(row.get("content"))));
        }
        turns.add(new GoogleGeminiChatService.ChatTurn("user", message));

        String context;
        try {
            context = travelPreferenceContext(userId);
        } catch (DataAccessException exception) {
            LOG.warn("Zen travel preferences are unavailable for user {}.", userId, exception);
            context = "";
        }
        String locationContext = currentLocationContext(body);
        if (!locationContext.isBlank()) {
            context = context.isBlank()
                    ? locationContext
                    : context + "; " + locationContext;
        }
        String preferenceContext = context;
        StreamingResponseBody responseBody = new ChatStreamResponse(
                userId,
                sessionId,
                message,
                cancellationKey,
                turns,
                language,
                preferenceContext);
        return ResponseEntity.ok()
                .contentType(MediaType.TEXT_EVENT_STREAM)
                .header("Cache-Control", "no-cache, no-transform")
                .body(responseBody);
    }

    private final class ChatStreamResponse implements StreamingResponseBody {
        private final long userId;
        private final String sessionId;
        private final String message;
        private final String cancellationKey;
        private final List<GoogleGeminiChatService.ChatTurn> turns;
        private final String language;
        private final String context;

        private ChatStreamResponse(
                long userId,
                String sessionId,
                String message,
                String cancellationKey,
                List<GoogleGeminiChatService.ChatTurn> turns,
                String language,
                String context) {
            this.userId = userId;
            this.sessionId = sessionId;
            this.message = message;
            this.cancellationKey = cancellationKey;
            this.turns = turns;
            this.language = language;
            this.context = context;
        }

        @Override
        public void writeTo(OutputStream output) throws IOException {
            AiChatController.this.streamReply(
                    output,
                    userId,
                    sessionId,
                    message,
                    cancellationKey,
                    turns,
                    language,
                    context);
        }
    }

    private void streamReply(
            OutputStream output,
            long userId,
            String sessionId,
            String message,
            String cancellationKey,
            List<GoogleGeminiChatService.ChatTurn> turns,
            String language,
            String context) throws IOException {
        StringBuilder reply = new StringBuilder();
        AtomicBoolean outputFailed = new AtomicBoolean();
        writeComment(output, "connected");
        ScheduledFuture<?> heartbeat = STREAM_HEARTBEATS.scheduleAtFixedRate(
                () -> writeHeartbeat(output, outputFailed),
                STREAM_HEARTBEAT_INTERVAL_SECONDS,
                STREAM_HEARTBEAT_INTERVAL_SECONDS,
                TimeUnit.SECONDS);
        try {
            gemini.streamReply(turns, language, context, delta -> {
                if (outputFailed.get()) {
                    throw new UncheckedIOException(new IOException("Zen chat client disconnected"));
                }
                reply.append(delta);
                try {
                    writeEvent(output, "token", Map.of("text", delta));
                } catch (IOException exception) {
                    outputFailed.set(true);
                    throw new UncheckedIOException(exception);
                }
            });
            if (consumeCancellation(cancellationKey)) return;
            try {
                persistConversation(userId, sessionId, message, reply.toString());
            } catch (DataAccessException exception) {
                LOG.warn("Zen chat response could not be persisted for user {}.", userId,
                        exception);
            }
            writeEvent(output, "done", Map.of());
        } catch (ResponseStatusException exception) {
            if (!outputFailed.get()) {
                writeEvent(output, "error", Map.of(
                        "message", exception.getReason() == null
                                ? "Zen could not complete the request. Please retry."
                                : exception.getReason()));
            }
        } catch (UncheckedIOException exception) {
            throw exception.getCause();
        } catch (RuntimeException exception) {
            LOG.error("Zen chat stream failed unexpectedly for user {}", userId, exception);
            if (!outputFailed.get()) {
                writeEvent(output, "error", Map.of(
                        "message", "Zen could not complete the request. Please retry."));
            }
        } finally {
            heartbeat.cancel(false);
        }
    }

    private static void writeEvent(OutputStream output, String event, Map<String, String> data)
            throws IOException {
        String payload = JSON.writeValueAsString(data);
        synchronized (output) {
            output.write(("event: " + event + "\ndata: " + payload + "\n\n")
                    .getBytes(StandardCharsets.UTF_8));
            output.flush();
        }
    }

    private static void writeComment(OutputStream output, String comment) throws IOException {
        synchronized (output) {
            output.write((": " + comment + "\n\n").getBytes(StandardCharsets.UTF_8));
            output.flush();
        }
    }

    private static void writeHeartbeat(OutputStream output, AtomicBoolean outputFailed) {
        if (outputFailed.get()) return;
        try {
            writeComment(output, "keep-alive");
        } catch (IOException exception) {
            outputFailed.set(true);
        }
    }

    private void setLocal(String name, String value) {
        jdbc.queryForObject("SELECT set_config(?, ?, true)", String.class, name, value);
    }

    private void persistConversation(
            long userId, String sessionId, String message, String reply) {
        Runnable persist = () -> {
            jdbc.update("""
                    INSERT INTO ai_chat_messages (user_id, session_id, role, content)
                    VALUES (?, ?, 'user', ?), (?, ?, 'model', ?)
                    """, userId, sessionId, message, userId, sessionId, reply);
            trimHistory(userId, sessionId);
        };
        if (transaction == null) {
            persist.run();
            return;
        }
        transaction.executeWithoutResult(status -> {
            jdbc.execute("SET LOCAL ROLE zentrip_api_runtime");
            setLocal("app.auth_role", "customer");
            setLocal("app.user_id", Long.toString(userId));
            setLocal("app.partner_id", "");
            persist.run();
        });
    }

    @PostMapping("/chat/cancel")
    public ResponseEntity<Void> cancel(
            @RequestBody Map<String, Object> body,
            HttpServletRequest request) {
        long userId = requireUserId(request);
        String sessionId = text(body.get("session_id")).trim();
        String requestId = text(body.get("request_id")).trim();
        if (!sessionId.matches("[A-Za-z0-9_-]{1,100}")
                || !requestId.matches("[A-Za-z0-9_-]{1,100}")) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "Invalid cancellation request");
        }

        long now = System.currentTimeMillis();
        cancelledRequests.entrySet().removeIf(entry -> entry.getValue() < now);
        cancelledRequests.put(cancellationKey(userId, sessionId, requestId),
                now + CANCELLATION_TTL_MILLIS);
        return ResponseEntity.noContent().build();
    }

    private boolean consumeCancellation(String key) {
        Long expiresAt = cancelledRequests.remove(key);
        return expiresAt != null && expiresAt >= System.currentTimeMillis();
    }

    private static String cancellationKey(long userId, String sessionId, String requestId) {
        return userId + ":" + sessionId + ":" + requestId;
    }

    private String travelPreferenceContext(long userId) {
        List<Map<String, Object>> preferences = jdbc.queryForList("""
                SELECT budget_level, travel_pace, trip_duration_days, travelers,
                       interests, preferred_destination
                FROM travel_preferences WHERE user_id = ?
                """, userId);
        if (preferences.isEmpty()) return "";

        Map<String, Object> profile = preferences.getFirst();
        return "budget level=" + text(profile.get("budget_level"))
                + "; travel pace=" + text(profile.get("travel_pace"))
                + "; preferred trip length=" + text(profile.get("trip_duration_days")) + " days"
                + "; travelers=" + text(profile.get("travelers"))
                + "; interests=" + text(profile.get("interests"))
                + "; preferred destination=" + text(profile.get("preferred_destination"));
    }

    private static String currentLocationContext(Map<String, Object> body) {
        if (!Boolean.TRUE.equals(body.get("location_requested"))) return "";

        Object rawLocation = body.get("current_location");
        if (rawLocation instanceof Map<?, ?> location
                && location.get("latitude") instanceof Number latitude
                && location.get("longitude") instanceof Number longitude) {
            double lat = latitude.doubleValue();
            double lon = longitude.doubleValue();
            if (Double.isFinite(lat) && lat >= -90 && lat <= 90
                    && Double.isFinite(lon) && lon >= -180 && lon <= 180) {
                String place = locationDescription(location);
                return "current device coordinates: latitude=" + lat + ", longitude=" + lon
                    + (place.isBlank() ? "" : "; reverse-geocoded place: " + place)
                    + ". Treat the reverse-geocoded place as authoritative; do not infer a different country. "
                    + "Do not claim a precise address or live nearby businesses from coordinates alone";
            }
        }
        return "the user asked for location-based help, but current device location is unavailable; "
                + "do not guess their location and ask for their city or area";
    }

    private static String locationDescription(Map<?, ?> location) {
        List<String> parts = new ArrayList<>();
        addLocationPart(parts, "district", location.get("sub_locality"));
        addLocationPart(parts, "city", location.get("locality"));
        addLocationPart(parts, "region", location.get("administrative_area"));
        addLocationPart(parts, "country", location.get("country"));
        addLocationPart(parts, "country code", location.get("country_code"));
        return String.join(", ", parts);
    }

    private static void addLocationPart(List<String> parts, String label, Object value) {
        if (value instanceof String text && !text.isBlank()) {
            parts.add(label + "=" + text.trim());
        }
    }

    private void trimHistory(long userId, String sessionId) {
        jdbc.update("""
                DELETE FROM ai_chat_messages
                WHERE user_id = ? AND session_id = ? AND id NOT IN (
                    SELECT id FROM (
                        SELECT id FROM ai_chat_messages
                        WHERE user_id = ? AND session_id = ?
                        ORDER BY id DESC LIMIT ?
                    ) AS recent_messages
                )
                """, userId, sessionId, userId, sessionId, STORED_MESSAGE_LIMIT);
    }

    private static long requireUserId(HttpServletRequest request) {
        Object userId = request.getAttribute("authUserId");
        if (!(userId instanceof Number number)) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Unauthenticated");
        }
        return number.longValue();
    }

    private static String text(Object value) {
        return value == null ? "" : value.toString();
    }
}
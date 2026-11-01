package com.zentrip.api;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Daily indicative rates, isolated from pricing, booking and settlement.
 * All currencies share a USD pivot; each quote retains its own publication date.
 */
@Service
public class ExchangeRateService {
    static final String URL = "https://api.frankfurter.dev/v2/rates?base=USD";
    private final RestClient client;
    private final Clock clock;
    private List<Map<String, Object>> cached;
    private Instant fetchedAt;
    private Instant retryAt = Instant.MIN;
    private boolean refreshFailed;

    @Autowired
    public ExchangeRateService(RestClient.Builder builder) {
        var factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(Duration.ofSeconds(3));
        factory.setReadTimeout(Duration.ofSeconds(5));
        this.client = builder.clone().requestFactory(factory).build();
        this.clock = Clock.systemUTC();
    }

    ExchangeRateService(RestClient client, Clock clock) {
        this.client = client;
        this.clock = clock;
    }

    public synchronized Map<String, Object> latest() {
        Instant now = clock.instant();
        if (!now.isBefore(retryAt)) {
            try {
                JsonNode body = client.get().uri(URL).retrieve().body(JsonNode.class);
                var validated = validate(body, LocalDate.now(clock));
                if (validated.isEmpty()) throw new IllegalStateException("No valid reference rates");
                cached = List.copyOf(validated);
                fetchedAt = now;
                refreshFailed = false;
                retryAt = now.plus(Duration.ofHours(6));
            } catch (RuntimeException exception) {
                // Cache failures too: repeated result searches must not flood the provider.
                refreshFailed = true;
                retryAt = now.plus(Duration.ofMinutes(5));
            }
        }
        if (cached == null) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                    "Reference rates unavailable. Original provider prices remain available.");
        }
        return Map.of(
                "base", "USD",
                "source", "Frankfurter",
                "fetched_at", fetchedAt.toString(),
                "refresh_failed", refreshFailed,
                "rates", cached);
    }

    static List<Map<String, Object>> validate(JsonNode body, LocalDate today) {
        var rows = new ArrayList<Map<String, Object>>();
        var seen = new java.util.HashSet<String>();
        if (body == null || !body.isArray()) return rows;
        for (JsonNode row : body) {
            try {
                String quote = row.path("quote").asText();
                if (!row.path("base").asText().equals("USD") ||
                        !quote.matches("[A-Z]{3}") || quote.equals("USD")) continue;
                BigDecimal rate = new BigDecimal(row.path("rate").asText());
                LocalDate date = LocalDate.parse(row.path("date").asText());
                if (rate.signum() <= 0 || !Double.isFinite(rate.doubleValue()) ||
                        date.isAfter(today) || date.isBefore(today.minusDays(7)) ||
                        !seen.add(quote)) continue;
                rows.add(Map.of("quote", quote, "rate", rate, "date", date.toString()));
            } catch (RuntimeException ignored) {
                // A malformed quote must not invalidate the other currencies.
            }
        }
        return rows;
    }
}

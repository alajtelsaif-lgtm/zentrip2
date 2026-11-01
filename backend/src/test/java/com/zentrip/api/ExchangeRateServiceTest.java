package com.zentrip.api;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.*;

class ExchangeRateServiceTest {
    static final String VALID = """
        [{"base":"USD","quote":"EUR","rate":0.92,"date":"2026-10-30"},
         {"base":"USD","quote":"LYD","rate":5.4,"date":"2026-11-01"}]
        """;

    static class MutableClock extends Clock {
        Instant now = Instant.parse("2026-11-01T12:00:00Z");
        @Override public ZoneId getZone() { return ZoneOffset.UTC; }
        @Override public Clock withZone(ZoneId zone) { return this; }
        @Override public Instant instant() { return now; }
    }

    @Test
    void retainsQuoteDatesAndCachesSuccessThenReportsFailedRefresh() {
        var builder = RestClient.builder();
        var server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(ExchangeRateService.URL)).andRespond(withSuccess(VALID, MediaType.APPLICATION_JSON));
        server.expect(requestTo(ExchangeRateService.URL)).andRespond(withStatus(HttpStatus.BAD_GATEWAY));
        var clock = new MutableClock();
        var service = new ExchangeRateService(builder.build(), clock);
        var first = service.latest();
        assertEquals("USD", first.get("base"));
        assertEquals(2, ((List<?>) first.get("rates")).size());
        assertEquals(false, service.latest().get("refresh_failed"));
        clock.now = clock.now.plus(Duration.ofHours(7));
        var stale = service.latest();
        assertEquals(true, stale.get("refresh_failed"));
        assertEquals(first.get("fetched_at"), stale.get("fetched_at"));
        assertEquals(first.get("rates"), stale.get("rates"));
        assertEquals(stale, service.latest()); // Failure cooldown avoids an extra HTTP request.
        server.verify();
    }

    @Test
    void coldFailureIsExplicitAndThrottledThenCanRecover() {
        var builder = RestClient.builder();
        var server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(ExchangeRateService.URL)).andRespond(withSuccess("[]", MediaType.APPLICATION_JSON));
        server.expect(requestTo(ExchangeRateService.URL)).andRespond(withSuccess(VALID, MediaType.APPLICATION_JSON));
        var clock = new MutableClock();
        var service = new ExchangeRateService(builder.build(), clock);
        assertEquals(HttpStatus.SERVICE_UNAVAILABLE,
                assertThrows(ResponseStatusException.class, service::latest).getStatusCode());
        assertThrows(ResponseStatusException.class, service::latest);
        clock.now = clock.now.plus(Duration.ofMinutes(6));
        assertEquals(false, service.latest().get("refresh_failed"));
        server.verify();
    }

    @Test
    void rejectsInvalidFutureExpiredAndDuplicateQuotes() throws Exception {
        var body = new ObjectMapper().readTree("""
            [{"base":"USD","quote":"EUR","rate":0.9,"date":"2026-10-30"},
             {"base":"USD","quote":"EUR","rate":0.8,"date":"2026-10-30"},
             {"base":"EUR","quote":"GBP","rate":1,"date":"2026-10-30"},
             {"base":"USD","quote":"GBP","rate":0,"date":"2026-10-30"},
             {"base":"USD","quote":"CHF","rate":-1,"date":"2026-10-30"},
             {"base":"USD","quote":"JPY","rate":"NaN","date":"2026-10-30"},
             {"base":"USD","quote":"CAD","rate":1,"date":"2026-11-02"},
             {"base":"USD","quote":"AUD","rate":1,"date":"2026-10-01"},
             {"base":"USD","quote":"bad","rate":1,"date":"2026-10-30"},
             {"base":"USD","quote":"USD","rate":2,"date":"2026-10-30"}]
            """);
        var rows = ExchangeRateService.validate(body, LocalDate.of(2026, 11, 1));
        assertEquals(1, rows.size());
        assertEquals("EUR", rows.getFirst().get("quote"));
        assertEquals("2026-10-30", rows.getFirst().get("date"));
    }
}

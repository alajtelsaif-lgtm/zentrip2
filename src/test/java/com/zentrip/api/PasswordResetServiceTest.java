package com.zentrip.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.web.server.ResponseStatusException;

class PasswordResetServiceTest {
    private static final String EMAIL = "user@example.com";
    private static final String SECRET = "a-test-only-secret-with-at-least-32-characters";

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final JavaMailSender mailSender = mock(JavaMailSender.class);
    private final PasswordResetService service =
            new PasswordResetService(jdbc, mailSender, true, "smtp.example.com", "no-reply@example.com", SECRET);

    @Test
    void resetRequestSendsCodeAndPasswordCanBeChangedOnlyOnce() {
        when(jdbc.queryForObject(contains("password_reset_codes"), eq(Integer.class), eq(EMAIL)))
                .thenReturn(0);
        when(jdbc.queryForObject(contains("FROM users WHERE email"), eq(Integer.class), eq(EMAIL)))
                .thenReturn(1);

        service.requestCode(EMAIL);

        ArgumentCaptor<SimpleMailMessage> messageCaptor = ArgumentCaptor.forClass(SimpleMailMessage.class);
        verify(mailSender).send(messageCaptor.capture());
        assertEquals(EMAIL, messageCaptor.getValue().getTo()[0]);
        Matcher codeMatcher = Pattern.compile("\\b(\\d{6})\\b")
                .matcher(messageCaptor.getValue().getText());
        assertTrue(codeMatcher.find());
        String code = codeMatcher.group(1);

        ArgumentCaptor<String> hashCaptor = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(
                contains("INSERT INTO password_reset_codes"),
                eq(EMAIL),
                hashCaptor.capture(),
                any(Timestamp.class),
                any(Timestamp.class));

        Map<String, Object> resetRow = new HashMap<>();
        resetRow.put("code_hash", hashCaptor.getValue());
        resetRow.put("expires_at", Timestamp.from(Instant.now().plusSeconds(300)));
        resetRow.put("attempts", 0);
        when(jdbc.queryForList(contains("SELECT code_hash"), eq(EMAIL)))
                .thenReturn(List.of(resetRow));
        when(jdbc.update(contains("UPDATE users SET password"), anyString(), eq(EMAIL)))
                .thenReturn(1);

        assertTrue(service.resetPassword(EMAIL, code, "new-password"));
        verify(jdbc).update(contains("DELETE FROM api_tokens"), eq(EMAIL));
        verify(jdbc).update("DELETE FROM password_reset_codes WHERE email = ?", EMAIL);
    }

    @Test
    void unknownEmailDoesNotSendEmail() {
        when(jdbc.queryForObject(contains("password_reset_codes"), eq(Integer.class), eq(EMAIL)))
                .thenReturn(0);
        when(jdbc.queryForObject(contains("FROM users WHERE email"), eq(Integer.class), eq(EMAIL)))
                .thenReturn(0);

        service.requestCode(EMAIL);

        verify(mailSender, never()).send(any(SimpleMailMessage.class));
    }

    @Test
    void recoveryFailsExplicitlyWhenMailIsNotConfigured() {
        PasswordResetService disabled =
                new PasswordResetService(jdbc, mailSender, false, "smtp.example.com",
                        "no-reply@example.com", SECRET);

        ResponseStatusException exception =
                assertThrows(ResponseStatusException.class, () -> disabled.requestCode(EMAIL));

        assertEquals(HttpStatus.SERVICE_UNAVAILABLE, exception.getStatusCode());
    }

    @Test
    void malformedCodeIsRejectedWithoutDatabaseLookup() {
        assertFalse(service.verifyCode(EMAIL, "12x"));
        verify(jdbc, never()).queryForList(anyString(), any(Object[].class));
    }
}

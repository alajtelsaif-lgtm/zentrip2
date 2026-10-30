package com.zentrip.api;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class PasswordResetService {
    private static final int CODE_ATTEMPT_LIMIT = 5;
    private static final long CODE_LIFETIME_SECONDS = 10 * 60;
    private static final long RESEND_INTERVAL_SECONDS = 60;

    private final JdbcTemplate jdbc;
    private final JavaMailSender mailSender;
    private final PasswordEncoder passwords = new BCryptPasswordEncoder();
    private final SecureRandom random = new SecureRandom();
    private final boolean mailEnabled;
    private final String mailHost;
    private final String mailFrom;
    private final String hmacSecret;

    public PasswordResetService(
            JdbcTemplate jdbc,
            JavaMailSender mailSender,
            @Value("${app.mail.enabled:false}") boolean mailEnabled,
            @Value("${spring.mail.host:}") String mailHost,
            @Value("${app.mail.from:}") String mailFrom,
            @Value("${app.password-reset.hmac-secret:}") String hmacSecret) {
        this.jdbc = jdbc;
        this.mailSender = mailSender;
        this.mailEnabled = mailEnabled;
        this.mailHost = mailHost;
        this.mailFrom = mailFrom;
        this.hmacSecret = hmacSecret;
    }

    @Transactional
    public void requestCode(String email) {
        requireDeliveryConfiguration();
        String normalizedEmail = normalizeEmail(email);
        if (isRecentlyRequested(normalizedEmail)) return;

        Integer userCount = jdbc.queryForObject(
                "SELECT COUNT(*) FROM users WHERE email = ?", Integer.class, normalizedEmail);
        if (userCount == null || userCount == 0) return;

        String code = String.format(Locale.ROOT, "%06d", random.nextInt(1_000_000));
        Instant now = Instant.now();
        jdbc.update("""
                INSERT INTO password_reset_codes (email, code_hash, created_at, expires_at, attempts)
                VALUES (?, ?, ?, ?, 0)
                ON CONFLICT (email) DO UPDATE SET
                    code_hash = EXCLUDED.code_hash,
                    created_at = EXCLUDED.created_at,
                    expires_at = EXCLUDED.expires_at,
                    attempts = 0
                """,
                normalizedEmail,
                hashCode(normalizedEmail, code),
                Timestamp.from(now),
                Timestamp.from(now.plusSeconds(CODE_LIFETIME_SECONDS)));

        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(mailFrom);
            message.setTo(normalizedEmail);
            message.setSubject("Your Zentrip password reset code");
            message.setText("Your password reset code is " + code
                    + ". It expires in 10 minutes. If you did not request this, ignore this email.");
            mailSender.send(message);
        } catch (RuntimeException exception) {
            throw new ResponseStatusException(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Unable to send the password reset email. Please try again later.");
        }
    }

    @Transactional
    public boolean verifyCode(String email, String code) {
        String normalizedEmail = normalizeEmail(email);
        if (!isValidCode(code)) return false;

        List<Map<String, Object>> rows = jdbc.queryForList(
                "SELECT code_hash, expires_at, attempts FROM password_reset_codes WHERE email = ? FOR UPDATE",
                normalizedEmail);
        if (rows.isEmpty()) return false;

        Map<String, Object> row = rows.getFirst();
        Timestamp expiresAt = (Timestamp) row.get("expires_at");
        int attempts = ((Number) row.get("attempts")).intValue();
        if (expiresAt.toInstant().isBefore(Instant.now()) || attempts >= CODE_ATTEMPT_LIMIT) {
            deleteCode(normalizedEmail);
            return false;
        }

        String expectedHash = (String) row.get("code_hash");
        if (!java.security.MessageDigest.isEqual(
                expectedHash.getBytes(StandardCharsets.US_ASCII),
                hashCode(normalizedEmail, code).getBytes(StandardCharsets.US_ASCII))) {
            jdbc.update("UPDATE password_reset_codes SET attempts = attempts + 1 WHERE email = ?",
                    normalizedEmail);
            if (attempts + 1 >= CODE_ATTEMPT_LIMIT) deleteCode(normalizedEmail);
            return false;
        }
        return true;
    }

    @Transactional
    public boolean resetPassword(String email, String code, String newPassword) {
        String normalizedEmail = normalizeEmail(email);
        if (newPassword.length() < 8 || !verifyCode(normalizedEmail, code)) return false;

        int updated = jdbc.update("UPDATE users SET password = ?, updated_at = NOW() WHERE email = ?",
                passwords.encode(newPassword), normalizedEmail);
        if (updated != 1) {
            deleteCode(normalizedEmail);
            return false;
        }
        jdbc.update("DELETE FROM api_tokens WHERE user_id = (SELECT id FROM users WHERE email = ?)",
                normalizedEmail);
        deleteCode(normalizedEmail);
        return true;
    }

    private boolean isRecentlyRequested(String email) {
        Integer count = jdbc.queryForObject("""
                SELECT COUNT(*) FROM password_reset_codes
                WHERE email = ? AND created_at > ?
                """,
                Integer.class,
                email,
                Timestamp.from(Instant.now().minusSeconds(RESEND_INTERVAL_SECONDS)));
        return count != null && count > 0;
    }

    private void deleteCode(String email) {
        jdbc.update("DELETE FROM password_reset_codes WHERE email = ?", email);
    }

    private void requireDeliveryConfiguration() {
        if (!mailEnabled || mailSender == null || mailHost.isBlank()
                || mailFrom.isBlank() || hmacSecret.length() < 32) {
            throw new ResponseStatusException(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Password recovery email is not configured on the server.");
        }
    }

    private static String normalizeEmail(String email) {
        return email == null ? "" : email.trim().toLowerCase(Locale.ROOT);
    }

    private static boolean isValidCode(String code) {
        return code != null && code.matches("\\d{6}");
    }

    private String hashCode(String email, String code) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(hmacSecret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return HexFormat.of().formatHex(
                    mac.doFinal((email + ":" + code).getBytes(StandardCharsets.UTF_8)));
        } catch (GeneralSecurityException exception) {
            throw new IllegalStateException("Unable to hash password reset code", exception);
        }
    }
}

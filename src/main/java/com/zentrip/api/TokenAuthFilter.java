package com.zentrip.api;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.HexFormat;
import java.util.List;

@Component
public class TokenAuthFilter extends OncePerRequestFilter {
    private final JdbcTemplate jdbc;

    public TokenAuthFilter(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        String authorization = request.getHeader("Authorization");
        if (authorization != null && authorization.startsWith("Bearer ")) {
            String token = authorization.substring(7).trim();
            if (!token.isEmpty()) {
                String hash = sha256(token);
                List<Long> userIds = jdbc.query(
                        "SELECT user_id FROM api_tokens WHERE token_hash = ? AND expires_at > ?",
                        (rs, rowNum) -> rs.getLong(1), hash, Timestamp.from(Instant.now()));
                if (!userIds.isEmpty()) {
                    request.setAttribute("authUserId", userIds.getFirst());
                    request.setAttribute("authTokenHash", hash);
                }
            }
        }
        filterChain.doFilter(request, response);
    }

    static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is not available", exception);
        }
    }
}
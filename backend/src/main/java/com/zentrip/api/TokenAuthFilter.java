package com.zentrip.api;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
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
import java.util.Locale;
import java.util.Map;
import java.util.Set;

@Component
public class TokenAuthFilter extends OncePerRequestFilter {
    private static final Set<String> SUPPORTED_ROLES = Set.of("admin", "partner", "customer");
    private final JdbcTemplate jdbc;

    public TokenAuthFilter(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        String authorization = request.getHeader("Authorization");
        if (authorization != null
                && authorization.regionMatches(true, 0, "Bearer ", 0, 7)) {
            String token = authorization.substring(7).trim();
            if (!token.isEmpty()) {
                String hash = sha256(token);
                List<Map<String, Object>> identities = jdbc.queryForList("""
                        SELECT u.id AS user_id, u.role
                        FROM api_tokens t
                        JOIN users u ON u.id = t.user_id
                        WHERE t.token_hash = ? AND t.expires_at > ?
                        """, hash, Timestamp.from(Instant.now()));
                if (identities.size() == 1) {
                    Map<String, Object> identity = identities.getFirst();
                    String role = identity.get("role") == null
                            ? ""
                            : identity.get("role").toString().trim().toLowerCase(Locale.ROOT);
                    Object rawUserId = identity.get("user_id");
                    if (rawUserId instanceof Number userId && SUPPORTED_ROLES.contains(role)) {
                        request.setAttribute("authUserId", userId.longValue());
                        request.setAttribute("authRole", role);
                        request.setAttribute("authTokenHash", hash);
                        SecurityContextHolder.getContext().setAuthentication(
                                UsernamePasswordAuthenticationToken.authenticated(
                                        userId.longValue(),
                                        null,
                                        List.of(new SimpleGrantedAuthority(
                                                "ROLE_" + role.toUpperCase(Locale.ROOT)))));
                    }
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
package com.zentrip.api;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Set;

/**
 * Binds the database row-security context to the verified API token for one
 * request. SET LOCAL is required because Supabase transaction poolers can
 * assign a different PostgreSQL session to each transaction.
 */
@Component
public class RlsContextFilter extends OncePerRequestFilter {
    private static final String RUNTIME_ROLE = "zentrip_api_runtime";
    private static final Set<String> PUBLIC_AUTH_PATHS = Set.of(
            "/api/auth/register",
            "/api/auth/login",
            "/api/auth/forgot-password",
            "/api/auth/verify-code",
            "/api/auth/reset-password");
    private static final Set<String> SUPPORTED_ROLES = Set.of("admin", "partner", "customer");

    private final JdbcTemplate jdbc;
    private final TransactionTemplate transaction;

    public RlsContextFilter(
            JdbcTemplate jdbc,
            ObjectProvider<PlatformTransactionManager> transactionManagers) {
        this.jdbc = jdbc;
        PlatformTransactionManager transactionManager = transactionManagers.getIfAvailable();
        if (transactionManager == null && jdbc.getDataSource() != null) {
            throw new IllegalStateException(
                    "Database-backed API requests require an RLS transaction manager");
        }
        this.transaction = transactionManager == null
                ? null : new TransactionTemplate(transactionManager);
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI().substring(request.getContextPath().length());
        return !path.startsWith("/api/") || PUBLIC_AUTH_PATHS.contains(path);
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {
        Object rawRole = request.getAttribute("authRole");
        String role = rawRole instanceof String candidate
                && SUPPORTED_ROLES.contains(candidate) ? candidate : "anonymous";
        String userId = numericAttribute(request, "authUserId");
        String partnerId = numericAttribute(request, "authPartnerId");

        if (transaction == null) {
            filterChain.doFilter(request, response);
            return;
        }

        try {
            transaction.executeWithoutResult(status -> {
                jdbc.execute("SET LOCAL ROLE " + RUNTIME_ROLE);
                setLocal("app.auth_role", role);
                setLocal("app.user_id", userId);
                setLocal("app.partner_id", partnerId);
                try {
                    filterChain.doFilter(request, response);
                } catch (IOException | ServletException exception) {
                    throw new FilterChainFailure(exception);
                }
            });
        } catch (FilterChainFailure failure) {
            if (failure.getCause() instanceof IOException ioException) {
                throw ioException;
            }
            if (failure.getCause() instanceof ServletException servletException) {
                throw servletException;
            }
            throw failure;
        }
    }

    private void setLocal(String name, String value) {
        jdbc.queryForObject(
                "SELECT set_config(?, ?, true)",
                String.class,
                name,
                value);
    }

    private static String numericAttribute(HttpServletRequest request, String name) {
        Object value = request.getAttribute(name);
        if (value instanceof Number number && number.longValue() > 0) {
            return Long.toString(number.longValue());
        }
        return "";
    }

    private static final class FilterChainFailure extends RuntimeException {
        private FilterChainFailure(Exception cause) {
            super(cause);
        }
    }
}

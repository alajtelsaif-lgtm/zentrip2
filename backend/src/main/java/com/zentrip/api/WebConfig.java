package com.zentrip.api;

import java.nio.file.Path;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.Arrays;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebConfig {
    @Bean
    CorsConfigurationSource corsConfigurationSource(
            @Value("${app.cors.allowed-origins:}") String allowedOrigins) {
        List<String> exactOrigins = parseExactOrigins(allowedOrigins);
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        if (!exactOrigins.isEmpty()) {
            CorsConfiguration api = new CorsConfiguration();
            api.setAllowedOrigins(exactOrigins);
            api.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
            api.setAllowedHeaders(List.of("Authorization", "Content-Type"));
            api.setAllowCredentials(false);
            api.setMaxAge(3600L);
            source.registerCorsConfiguration("/api/**", api);

            CorsConfiguration uploads = new CorsConfiguration();
            uploads.setAllowedOrigins(exactOrigins);
            uploads.setAllowedMethods(List.of("GET", "OPTIONS"));
            uploads.setAllowedHeaders(List.of("Authorization", "Content-Type"));
            uploads.setAllowCredentials(false);
            uploads.setMaxAge(3600L);
            source.registerCorsConfiguration("/uploads/**", uploads);
        }
        return source;
    }

    static List<String> parseExactOrigins(String configuredOrigins) {
        if (configuredOrigins == null || configuredOrigins.isBlank()) {
            return List.of();
        }
        return Arrays.stream(configuredOrigins.split(","))
                .map(String::trim)
                .filter(origin -> !origin.isEmpty())
                .map(WebConfig::validateOrigin)
                .distinct()
                .toList();
    }

    private static String validateOrigin(String origin) {
        if (origin.contains("*")) {
            throw new IllegalArgumentException(
                    "CORS origins must be exact; wildcards are not allowed");
        }
        try {
            URI uri = new URI(origin);
            boolean validScheme = "http".equalsIgnoreCase(uri.getScheme())
                    || "https".equalsIgnoreCase(uri.getScheme());
            boolean hasPath = uri.getRawPath() != null
                    && !uri.getRawPath().isEmpty();
            if (!validScheme || uri.getHost() == null || uri.getRawUserInfo() != null
                    || hasPath || uri.getRawQuery() != null
                    || uri.getRawFragment() != null) {
                throw new IllegalArgumentException(
                        "CORS entries must be exact HTTP(S) origins without paths");
            }
            return origin;
        } catch (URISyntaxException exception) {
            throw new IllegalArgumentException("Invalid CORS origin: " + origin, exception);
        }
    }

    @Bean
    WebMvcConfigurer resourceConfigurer(
            @Value("${app.upload-dir:uploads}") String uploadDirectory) {
        Path uploadPath = Path.of(uploadDirectory).toAbsolutePath().normalize();
        String location = uploadPath.toUri().toString();
        String uploadLocation = location.endsWith("/") ? location : location + "/";

        return new WebMvcConfigurer() {
            @Override
            public void addResourceHandlers(
                    org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry registry) {
                registry.addResourceHandler("/uploads/**").addResourceLocations(uploadLocation);
            }
        };
    }
}
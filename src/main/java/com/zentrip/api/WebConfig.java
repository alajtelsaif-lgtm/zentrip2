package com.zentrip.api;

import java.nio.file.Path;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebConfig {
    @Bean
    WebMvcConfigurer corsConfigurer(
            @Value("${app.cors.allowed-origins:*}") String allowedOrigins,
            @Value("${app.upload-dir:uploads}") String uploadDirectory) {
        Path uploadPath = Path.of(uploadDirectory).toAbsolutePath().normalize();
        String location = uploadPath.toUri().toString();
        String uploadLocation = location.endsWith("/") ? location : location + "/";

        return new WebMvcConfigurer() {
            @Override
            public void addCorsMappings(CorsRegistry registry) {
                registry.addMapping("/api/**")
                        .allowedOriginPatterns(allowedOrigins.split(","))
                        .allowedMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
                        .allowedHeaders("*");
                registry.addMapping("/uploads/**")
                        .allowedOriginPatterns(allowedOrigins.split(","))
                        .allowedMethods("GET", "OPTIONS")
                        .allowedHeaders("*");
            }

            @Override
            public void addResourceHandlers(
                    org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry registry) {
                registry.addResourceHandler("/uploads/**").addResourceLocations(uploadLocation);
            }
        };
    }
}
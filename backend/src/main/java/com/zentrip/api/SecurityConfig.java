package com.zentrip.api;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.security.web.SecurityFilterChain;
import jakarta.servlet.http.HttpServletResponse;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    SecurityFilterChain securityFilterChain(
            HttpSecurity http, TokenAuthFilter tokenAuthFilter) throws Exception {
        http
            .csrf(AbstractHttpConfigurer::disable)
            .httpBasic(AbstractHttpConfigurer::disable)
            .formLogin(AbstractHttpConfigurer::disable)
            .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .exceptionHandling(errors -> errors.authenticationEntryPoint(
                    (request, response, exception) ->
                            response.sendError(HttpServletResponse.SC_UNAUTHORIZED)))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers(
                    "/api/auth/register",
                    "/api/auth/login",
                    "/api/auth/forgot-password",
                    "/api/auth/verify-code",
                    "/api/auth/reset-password",
                    "/uploads/**",
                    "/error"
                ).permitAll()
                .requestMatchers("/api/admin", "/api/admin/**").hasRole("ADMIN")
                .requestMatchers("/api/partner", "/api/partner/**").hasRole("PARTNER")
                .requestMatchers("/api/auth/me", "/api/auth/logout", "/api/profile",
                    "/api/profile/**").authenticated()
                .requestMatchers(
                    "/api/reviews", "/api/reviews/**",
                    "/api/trips", "/api/trips/**",
                    "/api/bookings", "/api/bookings/**",
                    "/api/transfers", "/api/transfers/**",
                    "/api/payments", "/api/payments/**",
                    "/api/flights/*/seats", "/api/flights/*/seats/**",
                    "/api/attractions/*/visits",
                    "/api/maps/**"
                ).hasRole("CUSTOMER")
                .anyRequest().permitAll()
            )
            .addFilterBefore(tokenAuthFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    @Bean
    FilterRegistrationBean<TokenAuthFilter> tokenAuthFilterRegistration(
            TokenAuthFilter tokenAuthFilter) {
        FilterRegistrationBean<TokenAuthFilter> registration =
                new FilterRegistrationBean<>(tokenAuthFilter);
        registration.setEnabled(false);
        return registration;
    }
}

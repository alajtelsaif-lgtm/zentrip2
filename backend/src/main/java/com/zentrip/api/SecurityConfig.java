package com.zentrip.api;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.http.HttpMethod;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.security.web.SecurityFilterChain;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnBean;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.PlatformTransactionManager;

import javax.sql.DataSource;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    @ConditionalOnBean(DataSource.class)
    @ConditionalOnMissingBean(PlatformTransactionManager.class)
    PlatformTransactionManager jdbcTransactionManager(DataSource dataSource) {
        return new DataSourceTransactionManager(dataSource);
    }

    @Bean
    SecurityFilterChain securityFilterChain(
            HttpSecurity http,
            TokenAuthFilter tokenAuthFilter,
            RlsContextFilter rlsContextFilter) throws Exception {
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
                .requestMatchers("/api/auth/me", "/api/auth/logout").authenticated()
                .requestMatchers(
                    "/api/trips", "/api/trips/**",
                    "/api/bookings", "/api/bookings/**",
                    "/api/transfers", "/api/transfers/**",
                    "/api/payments", "/api/payments/**",
                    "/api/flights/*/seats", "/api/flights/*/seats/**",
                    "/api/attractions/*/visits",
                    "/api/maps/**",
                    "/api/ai", "/api/ai/**",
                    "/api/preferences/travel", "/api/preferences/travel/**",
                    "/api/profile", "/api/profile/**",
                    "/api/hotels/search-results/*/rates"
                ).hasRole("CUSTOMER")
                .requestMatchers(HttpMethod.GET, "/api/reviews").permitAll()
                .requestMatchers(
                    "/api/airports/search",
                    "/api/flights/search",
                    "/api/flights/search/flexible",
                    "/api/hotels/locations",
                    "/api/hotels/search",
                    "/api/hotels/nearby",
                    "/api/hotels/search-results/*/rates",
                    "/api/cars/locations",
                    "/api/cars/nearby",
                    "/api/inventory/**",
                    "/api/offers",
                    "/api/attractions/search",
                    "/api/exchange-rates"
                ).permitAll()
                .requestMatchers(HttpMethod.POST, "/api/reviews", "/api/reviews/**")
                    .hasRole("CUSTOMER")
                .requestMatchers("/api/**").denyAll()
                .anyRequest().permitAll()
            )
            .addFilterBefore(tokenAuthFilter, UsernamePasswordAuthenticationFilter.class)
            .addFilterAfter(rlsContextFilter, TokenAuthFilter.class);

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

    @Bean
    FilterRegistrationBean<RlsContextFilter> rlsContextFilterRegistration(
            RlsContextFilter rlsContextFilter) {
        FilterRegistrationBean<RlsContextFilter> registration =
                new FilterRegistrationBean<>(rlsContextFilter);
        registration.setEnabled(false);
        return registration;
    }
}

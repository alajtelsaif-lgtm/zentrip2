package com.zentrip.api;

import static org.mockito.Mockito.when;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.sql.Timestamp;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest(properties = "app.cors.allowed-origins=https://app.zentrip.example")
@AutoConfigureMockMvc
class SecurityConfigIntegrationTest {
    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private JdbcTemplate jdbcTemplate;

    @MockBean
    private ProfilePhotoStorage profilePhotoStorage;

    @MockBean
    private PasswordResetService passwordResetService;

    @MockBean
    private OpenTripMapAttractionService openTripMapAttractionService;

    @Test
    void placeSuggestionsArePublicAndDoNotRequireALogin() throws Exception {
        when(openTripMapAttractionService.suggestPlaces("Trip", "en", null, null))
                .thenReturn(List.of(Map.of("label", "Tripoli", "result_type", "city")));

        mockMvc.perform(get("/api/attractions/suggestions")
                        .param("query", "Trip")
                        .param("lang", "en"))
                .andExpect(status().isOk());
    }

    @Test
    void nearbyAttractionsArePublicAndReachTheProviderService() throws Exception {
        when(openTripMapAttractionService.searchNearby(
                32.8, 13.2, 5000.0, "historical", "en"))
                .thenReturn(List.of());

        mockMvc.perform(get("/api/attractions/nearby")
                        .param("lat", "32.8")
                        .param("lng", "13.2")
                        .param("radius", "5000")
                        .param("category", "historical")
                        .param("lang", "en"))
                .andExpect(status().isOk());
    }

    @Test
    void attractionMapIsPublicLikeTheAttractionSearch() throws Exception {
        mockMvc.perform(get("/api/attractions/map").param("zoom", "5"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void publicLoginEndpointDoesNotRequireHttpBasicAuthentication() throws Exception {
        when(jdbcTemplate.queryForList("SELECT id, password FROM users WHERE email = ?", "user@example.com"))
                .thenReturn(List.of());

        mockMvc.perform(post("/api/auth/login")
                        .contentType("application/json")
                        .content("{\"email\":\"user@example.com\",\"password\":\"wrong\"}"))
                .andExpect(status().isUnprocessableEntity());
    }

    @Test
    void protectedRoleEndpointsRejectRequestsWithoutTokens() throws Exception {
        mockMvc.perform(get("/api/admin/dashboard"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/partner/dashboard"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/bookings"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void customerDataEndpointsRejectRequestsWithoutTokens() throws Exception {
        mockMvc.perform(get("/api/preferences/travel"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(post("/api/ai/chat")
                        .contentType("application/json")
                        .content("{}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void unknownApiRoutesAreNotPublicByDefault() throws Exception {
        mockMvc.perform(get("/api/not-a-real-route"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void pushTokenRouteRequiresAuthentication() throws Exception {
        mockMvc.perform(post("/api/users/fcm-token")
                        .contentType("application/json")
                        .content("{\"token\":\"device-token\",\"platform\":\"web\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void corsAllowsOnlyTheConfiguredExactOrigin() throws Exception {
        mockMvc.perform(options("/api/offers")
                        .header("Origin", "https://app.zentrip.example")
                        .header("Access-Control-Request-Method", "GET"))
                .andExpect(status().isOk())
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers
                        .header().string("Access-Control-Allow-Origin",
                                "https://app.zentrip.example"));

        mockMvc.perform(options("/api/offers")
                        .header("Origin", "https://untrusted.example")
                        .header("Access-Control-Request-Method", "GET"))
                .andExpect(status().isForbidden());
    }

    @Test
    void customerTokenCannotReadAdminOrPartnerDashboards() throws Exception {
        String token = "customer-role-test-token";
        when(jdbcTemplate.queryForList(
                contains("FROM api_tokens t"),
                eq(TokenAuthFilter.sha256(token)),
                any(Timestamp.class)))
                .thenReturn(List.of(Map.of("user_id", 27L, "role", "customer")));

        mockMvc.perform(get("/api/admin/dashboard")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isForbidden());
        mockMvc.perform(get("/api/partner/dashboard")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isForbidden());
    }

    @Test
    void partnerTokenCannotUseCustomerBookingEndpoints() throws Exception {
        String token = "partner-role-test-token";
        when(jdbcTemplate.queryForList(
                contains("FROM api_tokens t"),
                eq(TokenAuthFilter.sha256(token)),
                any(Timestamp.class)))
                .thenReturn(List.of(Map.of(
                        "user_id", 29L,
                        "role", "partner",
                        "partner_id", 4L)));

        mockMvc.perform(get("/api/bookings")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isForbidden());
    }

    @Test
    void customerTokenCanReachCustomerBookingEndpoints() throws Exception {
        String token = "customer-booking-test-token";
        when(jdbcTemplate.queryForList(
                contains("FROM api_tokens t"),
                eq(TokenAuthFilter.sha256(token)),
                any(Timestamp.class)))
                .thenReturn(List.of(Map.of("user_id", 28L, "role", "customer")));

        mockMvc.perform(get("/api/bookings")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
    }
}

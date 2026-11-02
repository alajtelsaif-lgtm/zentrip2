package com.zentrip.api;

import static org.mockito.Mockito.when;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
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

@SpringBootTest
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

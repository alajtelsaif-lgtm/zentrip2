package com.zentrip.api;

import static org.mockito.Mockito.when;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;

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
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

@SpringBootTest(properties = {
        "app.cors.allowed-origins=https://app.zentrip.example",
        "ZENTRIP_SECURITY_ALLOW_REPLIT_PREVIEW_EMBEDDING=false"
})
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

    @MockBean
    private LandmarkCatalogService landmarkCatalogService;

    @MockBean
    private GoogleGeminiChatService geminiChatService;

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
    void unifiedPlaceListingIsPublicAndReturnsOnlyTheCatalogResponse() throws Exception {
        when(landmarkCatalogService.listCanonicalPlaces("", "", "", "", "en", 40, 0))
                .thenReturn(Map.of(
                        "places", List.of(Map.of("canonical_name", "Leptis Magna")),
                        "total_count", 1,
                        "limit", 40,
                        "offset", 0,
                        "has_more", false));

        mockMvc.perform(get("/api/places"))
                .andExpect(status().isOk())
                .andExpect(content().string(
                        org.hamcrest.Matchers.containsString("Leptis Magna")));
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
        mockMvc.perform(post("/api/places/ingest")
                        .contentType("application/json")
                        .content("{\"source\":\"opentripmap\",\"places\":[]}"))
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
                .andExpect(status().isUnauthorized())
                .andExpect(header().string("X-Frame-Options", "DENY"));
    }

    @Test
    void pushTokenRouteRequiresAuthentication() throws Exception {
        mockMvc.perform(post("/api/users/fcm-token")
                        .contentType("application/json")
                        .content("{\"token\":\"device-token\",\"platform\":\"web\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void notificationInboxRequiresCustomerAuthentication() throws Exception {
        mockMvc.perform(get("/api/notifications"))
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
        mockMvc.perform(post("/api/places/ingest")
                        .header("Authorization", "Bearer " + token)
                        .contentType("application/json")
                        .content("""
                                {"source":"opentripmap","places":[
                                  {"xid":"N12345","name":"Example Place",
                                   "latitude":32.64,"longitude":14.29}
                                ]}
                                """))
                .andExpect(status().isForbidden());
    }

    @Test
    void adminTokenCanIngestConfiguredProviderRecords() throws Exception {
        String token = "admin-place-ingest-test-token";
        when(jdbcTemplate.queryForList(
                contains("FROM api_tokens t"),
                eq(TokenAuthFilter.sha256(token)),
                any(Timestamp.class)))
                .thenReturn(List.of(Map.of("user_id", 30L, "role", "admin")));
        when(landmarkCatalogService.ingestBatch(eq("opentripmap"), anyList()))
                .thenReturn(List.of(Map.of(
                        "id", "N12345",
                        "canonical_place_id", "c0a8019e-0000-4000-8000-000000000001")));

        mockMvc.perform(post("/api/places/ingest")
                        .header("Authorization", "Bearer " + token)
                        .contentType("application/json")
                        .content("""
                                {"source":"opentripmap","places":[
                                  {"xid":"N12345","name":"Example Place",
                                   "latitude":32.64,"longitude":14.29}
                                ]}
                                """))
                .andExpect(status().isOk())
                .andExpect(content().string(
                        org.hamcrest.Matchers.containsString("\"count\":1")));
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

    @Test
    void authenticatedZenChatCanCompleteAsyncErrorStreamDispatch() throws Exception {
        String token = "customer-zen-async-test-token";
        when(jdbcTemplate.queryForList(
                contains("FROM api_tokens t"),
                eq(TokenAuthFilter.sha256(token)),
                any(Timestamp.class)))
                .thenReturn(List.of(Map.of("user_id", 31L, "role", "customer")));
        when(jdbcTemplate.queryForList(any(String.class), eq(31L), eq("zen-async"), eq(10)))
                .thenReturn(List.of());
        when(jdbcTemplate.queryForList(any(String.class), eq(31L)))
                .thenReturn(List.of());
        org.mockito.Mockito.doThrow(new ResponseStatusException(
                HttpStatus.SERVICE_UNAVAILABLE, "The configured Gemini model is unavailable."))
                .when(geminiChatService)
                .streamReply(any(), eq("en"), any(String.class), any());

        MvcResult started = mockMvc.perform(post("/api/ai/chat")
                        .header("Authorization", "Bearer " + token)
                        .contentType("application/json")
                        .content("""
                                {"message":"Plan a trip","session_id":"zen-async",
                                 "request_id":"request-async","language":"en"}
                                """))
                .andExpect(request().asyncStarted())
                .andReturn();

        mockMvc.perform(asyncDispatch(started))
                .andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("event: error")))
                .andExpect(content().string(org.hamcrest.Matchers.containsString(
                        "The configured Gemini model is unavailable.")));
    }
}

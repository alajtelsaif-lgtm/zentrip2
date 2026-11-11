package com.zentrip.api;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertThrows;
import org.junit.jupiter.api.Test;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.asyncDispatch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.request;
import org.springframework.http.ResponseEntity;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;
import org.springframework.web.server.ResponseStatusException;

class AiChatControllerTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final GoogleGeminiChatService gemini = mock(GoogleGeminiChatService.class);
    private final PlatformTransactionManager transactionManager =
            new PlatformTransactionManager() {
                @Override
                public TransactionStatus getTransaction(TransactionDefinition definition) {
                    return new SimpleTransactionStatus();
                }

                @Override
                public void commit(TransactionStatus status) {}

                @Override
                public void rollback(TransactionStatus status) {}
            };
    private final AiChatController controller =
            new AiChatController(jdbc, gemini, transactionManager);

    @Test
        void rejectsUnauthenticatedRequestsBeforeCallingGemini() {
        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class, () -> controller.chat(
                Map.of("message", "Plan a trip", "session_id", "chat-1"),
                new MockHttpServletRequest()));

        assertEquals(401, exception.getStatusCode().value());
        verifyNoInteractions(jdbc, gemini);
    }

    @Test
    void returnsReplyAndPersistsAuthenticatedConversation() throws Exception {
        when(jdbc.queryForList(anyString(), eq(42L), eq("chat-1"), eq(10)))
                .thenReturn(List.of(
                        Map.of("role", "model", "content", "I can help with that."),
                        Map.of("role", "user", "content", "I like beaches")));
        when(jdbc.queryForList(anyString(), eq(42L))).thenReturn(List.of(Map.of(
                "budget_level", "budget",
                "travel_pace", "relaxed",
                "trip_duration_days", 5,
                "travelers", 2,
                "interests", "food,beaches",
                "preferred_destination", "Bali")));
        doAnswer(invocation -> {
            java.util.function.Consumer<String> onDelta = invocation.getArgument(3);
            onDelta.accept("إليك ");
            onDelta.accept("خطة سفر");
            return null;
        }).when(gemini).streamReply(anyList(), eq("ar"), anyString(), any());
        when(jdbc.update(anyString(), eq(42L), eq("chat-1"), eq("Plan a trip"),
                eq(42L), eq("chat-1"), eq("إليك خطة سفر"))).thenReturn(2);
        when(jdbc.update(anyString(), eq(42L), eq("chat-1"), eq(42L), eq("chat-1"), eq(40)))
                .thenReturn(0);
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute("authUserId", 42L);

        ResponseEntity<?> response = controller.chat(Map.of(
                "message", "Plan a trip",
                "session_id", "chat-1",
                "request_id", "request-1",
                "language", "ar",
                "location_requested", true,
                "current_location", Map.of(
                        "latitude", 37.7749,
                        "longitude", -122.4194,
                        "locality", "San Francisco",
                        "country", "United States",
                        "country_code", "US")), request);

        assertEquals(200, response.getStatusCode().value());
        assertEquals("text/event-stream", response.getHeaders().getContentType().toString());
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        ((StreamingResponseBody) response.getBody()).writeTo(output);
        String stream = output.toString(StandardCharsets.UTF_8);
        assertTrue(stream.contains("event: token"));
        assertTrue(stream.contains("\"text\":\"إليك \""));
        assertTrue(stream.contains("\"text\":\"خطة سفر\""));
        assertTrue(stream.contains("event: done"));
        verify(gemini).streamReply(eq(List.of(
                new GoogleGeminiChatService.ChatTurn("user", "I like beaches"),
                new GoogleGeminiChatService.ChatTurn("model", "I can help with that."),
                new GoogleGeminiChatService.ChatTurn("user", "Plan a trip"))), eq("ar"),
                org.mockito.ArgumentMatchers.argThat(context ->
                        context.contains("budget level=budget")
                                && context.contains("interests=food,beaches")
                                && context.contains("preferred destination=Bali")
                                && context.contains("latitude=37.7749")
                                && context.contains("longitude=-122.4194")
                                && context.contains("city=San Francisco")
                                && context.contains("country=United States")
                                && context.contains("country code=US")
                                && context.contains("Treat the reverse-geocoded place as authoritative")),
                any());
        verify(jdbc).update(anyString(), eq(42L), eq("chat-1"), eq("Plan a trip"),
                eq(42L), eq("chat-1"), eq("إليك خطة سفر"));
    }

    @Test
    void sendsStreamingResponseThroughMvcWithoutConverterError() throws Exception {
        when(jdbc.queryForList(anyString(), eq(42L), eq("mvc-chat"), eq(10)))
                .thenReturn(List.of());
        when(jdbc.queryForList(anyString(), eq(42L))).thenReturn(List.of());
        doAnswer(invocation -> {
            java.util.function.Consumer<String> onDelta = invocation.getArgument(3);
            onDelta.accept("Zen reply");
            return null;
        }).when(gemini).streamReply(anyList(), eq("en"), anyString(), any());

        MockMvc mockMvc = MockMvcBuilders.standaloneSetup(controller).build();
        MvcResult started = mockMvc.perform(post("/api/ai/chat")
                        .requestAttr("authUserId", 42L)
                        .contentType(MediaType.APPLICATION_JSON)
                        .accept(MediaType.TEXT_EVENT_STREAM)
                        .content("""
                                {
                                  "message": "Hello",
                                  "session_id": "mvc-chat",
                                  "request_id": "mvc-request",
                                  "language": "en"
                                }
                                """))
                .andExpect(request().asyncStarted())
                .andReturn();

        MvcResult completed = mockMvc.perform(asyncDispatch(started)).andReturn();

        assertEquals(200, completed.getResponse().getStatus());
        assertEquals(MediaType.TEXT_EVENT_STREAM_VALUE, completed.getResponse().getContentType());
        assertTrue(completed.getResponse().getContentAsString().contains("event: token"));
        assertTrue(completed.getResponse().getContentAsString().contains("\"text\":\"Zen reply\""));
        assertTrue(completed.getResponse().getContentAsString().contains("event: done"));
    }

    @Test
    void emitsSseHeartbeatBeforeReplyTokens() throws Exception {
        doAnswer(invocation -> {
            java.util.function.Consumer<String> onDelta = invocation.getArgument(3);
            onDelta.accept("Hello from Zen.");
            return null;
        }).when(gemini).streamReply(anyList(), eq("en"), anyString(), any());
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute("authUserId", 42L);
        ResponseEntity<?> response = controller.chat(Map.of(
                "message", "Hello",
                "session_id", "chat-heartbeat",
                "request_id", "request-heartbeat",
                "language", "en"), request);

        ByteArrayOutputStream output = new ByteArrayOutputStream();
        ((StreamingResponseBody) response.getBody()).writeTo(output);
        String stream = output.toString(StandardCharsets.UTF_8);

        assertTrue(stream.contains(": connected\n\n"));
        assertTrue(stream.indexOf(": connected") < stream.indexOf("event: token"));
        assertTrue(stream.contains("event: done"));
    }

    @Test
    void convertsUnexpectedProviderErrorsIntoStreamErrorsInsteadOfHttp500()
            throws Exception {
        org.mockito.Mockito.doThrow(new IllegalStateException("provider parser failure"))
                .when(gemini).streamReply(anyList(), eq("en"), anyString(), any());
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute("authUserId", 42L);
        ResponseEntity<?> response = controller.chat(Map.of(
                "message", "Hello",
                "session_id", "chat-provider-error",
                "request_id", "request-provider-error",
                "language", "en"), request);

        ByteArrayOutputStream output = new ByteArrayOutputStream();
        ((StreamingResponseBody) response.getBody()).writeTo(output);
        String stream = output.toString(StandardCharsets.UTF_8);

        assertEquals(200, response.getStatusCode().value());
        assertTrue(stream.contains("event: error"));
        assertTrue(stream.contains("Zen could not complete the request. Please retry."));
        assertTrue(!stream.contains("event: done"));
    }

        @Test
        void cancellationReceivedBeforeGenerationSuppressesTheRequest() {
                MockHttpServletRequest request = new MockHttpServletRequest();
                request.setAttribute("authUserId", 42L);
                controller.cancel(Map.of("session_id", "chat-1", "request_id", "request-2"), request);

                ResponseEntity<?> response = controller.chat(Map.of(
                                "message", "Plan a trip",
                                "session_id", "chat-1",
                                "request_id", "request-2",
                                "language", "en"), request);

                assertEquals(204, response.getStatusCode().value());
                verifyNoInteractions(jdbc, gemini);
        }

    @Test
    void missingChatHistoryOrPreferenceTablesDoNotTurnZenIntoAnInternalServerError()
            throws Exception {
        when(jdbc.queryForList(anyString(), eq(42L), eq("chat-resilient"), eq(10)))
                .thenThrow(new DataAccessResourceFailureException("history table unavailable"));
        when(jdbc.queryForList(anyString(), eq(42L)))
                .thenThrow(new DataAccessResourceFailureException("preferences unavailable"));
        doAnswer(invocation -> {
            java.util.function.Consumer<String> onDelta = invocation.getArgument(3);
            onDelta.accept("The trip plan is ready.");
            return null;
        }).when(gemini).streamReply(anyList(), eq("en"), anyString(), any());

        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute("authUserId", 42L);
        ResponseEntity<?> response = controller.chat(Map.of(
                "message", "Plan a trip",
                "session_id", "chat-resilient",
                "request_id", "request-resilient",
                "language", "en"), request);

        assertEquals(200, response.getStatusCode().value());
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        ((StreamingResponseBody) response.getBody()).writeTo(output);
        String stream = output.toString(StandardCharsets.UTF_8);
        assertTrue(stream.contains("The trip plan is ready."));
        assertTrue(stream.contains("event: done"));
    }
}
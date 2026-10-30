package com.zentrip.api;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.Statement;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCreator;
import org.springframework.jdbc.support.KeyHolder;
import org.springframework.mock.web.MockHttpServletRequest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class PartnerBookingPriceTest {
    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final ApiController controller = new ApiController(
            jdbc,
            "",
            mock(ProfilePhotoStorage.class),
            mock(PasswordResetService.class));

    @Test
    void hotelBookingUsesCurrentPartnerRateAndStayLength() throws Exception {
        when(jdbc.queryForList(contains("FROM partner_listings l"), eq(44L)))
                .thenReturn(List.of(Map.of(
                        "id", 44L,
                        "partner_id", 3L,
                        "type", "hotel",
                        "active", true,
                        "price", new BigDecimal("100.00"))));
        when(jdbc.queryForList(contains("FOR UPDATE"), eq(7L)))
                .thenReturn(List.of(Map.of("id", 7L)));
        when(jdbc.queryForList(
                contains("FROM bookings"),
                eq(7L),
                eq("hotel")))
                .thenReturn(List.of());
        when(jdbc.update(any(PreparedStatementCreator.class), any(KeyHolder.class)))
                .thenAnswer(invocation -> {
                    KeyHolder holder = invocation.getArgument(1);
                    holder.getKeyList().add(Map.of("GENERATED_KEY", 99L));
                    return 1;
                });
        when(jdbc.queryForMap(contains("SELECT bookings.*"), eq(99L)))
                .thenReturn(new java.util.LinkedHashMap<>(Map.of(
                        "id", 99L,
                        "type", "hotel",
                        "title", "Sea View",
                        "subtitle", "Tripoli",
                        "date", "2026-11-10T00:00",
                        "end_date", "2026-11-13T00:00",
                        "price", new BigDecimal("336.00"),
                        "status", "upcoming")));

        controller.createBooking(
                Map.of(
                        "type", "hotel",
                        "title", "Sea View",
                        "subtitle", "Tripoli",
                        "date", "2026-11-10T00:00:00Z",
                        "end_date", "2026-11-13T00:00:00Z",
                        "price", 1,
                        "partner_listing_id", 44),
                authenticatedRequest());

        org.mockito.ArgumentCaptor<PreparedStatementCreator> creator =
                org.mockito.ArgumentCaptor.forClass(PreparedStatementCreator.class);
        verify(jdbc).update(creator.capture(), any(KeyHolder.class));
        Connection connection = mock(Connection.class);
        PreparedStatement statement = mock(PreparedStatement.class);
        when(connection.prepareStatement(any(String.class), eq(Statement.RETURN_GENERATED_KEYS)))
                .thenReturn(statement);
        creator.getValue().createPreparedStatement(connection);
        verify(statement).setObject(5, new BigDecimal("336.00"));
        verify(statement).setObject(9, new BigDecimal("336.00"));
    }

    private static MockHttpServletRequest authenticatedRequest() {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.setAttribute("authUserId", 7L);
        return request;
    }
}

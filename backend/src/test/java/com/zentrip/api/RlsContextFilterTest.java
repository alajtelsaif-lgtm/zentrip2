package com.zentrip.api;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.junit.jupiter.api.Assertions.assertThrows;

import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.support.DefaultListableBeanFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;

import javax.sql.DataSource;

class RlsContextFilterTest {

    @Test
    void usesVerifiedRequestIdentityInsteadOfClientHeaders() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        PlatformTransactionManager manager = mock(PlatformTransactionManager.class);
        when(manager.getTransaction(any(TransactionDefinition.class)))
                .thenReturn(new SimpleTransactionStatus());
        doNothing().when(manager).commit(any(TransactionStatus.class));
        ObjectProvider<PlatformTransactionManager> managers = provider(manager);
        RlsContextFilter filter = new RlsContextFilter(jdbc, managers);

        MockHttpServletRequest request =
                new MockHttpServletRequest("GET", "/api/partner/listings");
        request.setAttribute("authRole", "partner");
        request.setAttribute("authUserId", 87L);
        request.setAttribute("authPartnerId", 12L);
        request.addHeader("X-Role", "admin");
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = (req, res) -> response.setStatus(200);

        filter.doFilter(request, response, chain);

        verify(jdbc).execute("SET LOCAL ROLE zentrip_api_runtime");
        verify(jdbc).queryForObject(
                "SELECT set_config(?, ?, true)",
                String.class,
                "app.auth_role",
                "partner");
        verify(jdbc).queryForObject(
                "SELECT set_config(?, ?, true)",
                String.class,
                "app.user_id",
                "87");
        verify(jdbc).queryForObject(
                "SELECT set_config(?, ?, true)",
                String.class,
                "app.partner_id",
                "12");
    }

    @Test
    void skipsAuthenticationEndpointsOutsideTheRlsRequestContext() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        PlatformTransactionManager manager = mock(PlatformTransactionManager.class);
        RlsContextFilter filter = new RlsContextFilter(jdbc, provider(manager));
        MockHttpServletRequest request =
                new MockHttpServletRequest("POST", "/api/auth/login");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, (req, res) -> response.setStatus(200));

        verifyNoInteractions(jdbc);
        verifyNoInteractions(manager);
    }

    @Test
    void failsClosedWhenDatabaseHasNoTransactionManager() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.getDataSource()).thenReturn(mock(DataSource.class));
        ObjectProvider<PlatformTransactionManager> managers = mock(ObjectProvider.class);
        when(managers.getIfAvailable()).thenReturn(null);

        assertThrows(
                IllegalStateException.class,
                () -> new RlsContextFilter(jdbc, managers));
    }

    private static ObjectProvider<PlatformTransactionManager> provider(
            PlatformTransactionManager manager) {
        ObjectProvider<PlatformTransactionManager> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(manager);
        return provider;
    }
}

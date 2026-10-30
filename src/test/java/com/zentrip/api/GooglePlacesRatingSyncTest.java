package com.zentrip.api;

import java.io.InputStream;
import java.util.Map;
import java.util.Properties;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.MutablePropertySources;
import org.springframework.core.env.PropertySourcesPropertyResolver;
import org.springframework.core.env.PropertiesPropertySource;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.contains;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import static org.springframework.http.HttpMethod.GET;

class GooglePlacesRatingSyncTest {
    @Test
    void startupRetriesHotelsWithUnverifiedZeroRatingValues() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        GooglePlacesRatingSync sync = mock(GooglePlacesRatingSync.class);

        new GooglePlacesRatingStartupSync(jdbc, sync, "test-places-key")
                .refreshSeededHotelsMissingGoogleRatings();

        verify(jdbc).query(
                contains("google_rating = 0"),
                any(RowMapper.class));
    }

    @Test
    void mapsDocumentedEnvironmentVariableToPlacesServiceProperty() throws Exception {
        Properties applicationProperties = new Properties();
        try (InputStream stream = getClass().getResourceAsStream("/application.properties")) {
            assertNotNull(stream);
            applicationProperties.load(stream);
        }

        MutablePropertySources sources = new MutablePropertySources();
        sources.addFirst(new MapPropertySource(
                "environment", Map.of("GOOGLE_PLACES_API_KEY", "mapped-test-key")));
        sources.addLast(new PropertiesPropertySource(
                "application", applicationProperties));

        assertEquals(
                "mapped-test-key",
                new PropertySourcesPropertyResolver(sources)
                        .getProperty("google.places.api-key"));
    }

    @Test
    void fetchesAndPersistsOfficialPlaceRatingAndReviewCount() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GooglePlacesRatingSync sync =
                new GooglePlacesRatingSync(jdbc, builder, "test-places-key");
        String placeId = "ChIJN1t_tDeuEmsRUsoyG83frY4";
        server.expect(requestTo(
                        "https://places.googleapis.com/v1/places/" + placeId))
                .andExpect(method(GET))
                .andExpect(header("X-Goog-Api-Key", "test-places-key"))
                .andExpect(header("X-Goog-FieldMask", "id,rating,userRatingCount"))
                .andRespond(withSuccess(
                        """
                        {"id":"%s","rating":4.9,"userRatingCount":8240}
                        """.formatted(placeId),
                        MediaType.APPLICATION_JSON));
        when(jdbc.update(anyString(), any(Object[].class)))
                .thenReturn(1);

        sync.refreshAsync(42, "Grand Horizon Hotel", "City Center, Misrata", "", placeId);

        server.verify();
        ArgumentCaptor<Object[]> arguments = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).update(anyString(), arguments.capture());
        assertArrayEquals(
                new Object[] {placeId, 4.9, 8240, placeId, 4.9, 8240, 42L},
                arguments.getValue());
    }

    @Test
    void resolvesMapsLocationByHotelNameBeforeFetchingPlaceRatings() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        GooglePlacesRatingSync sync =
                new GooglePlacesRatingSync(jdbc, builder, "test-places-key");
        String placeId = "ChIJN1t_tDeuEmsRUsoyG83frY4";
        server.expect(requestTo("https://places.googleapis.com/v1/places:searchText"))
                .andExpect(method(org.springframework.http.HttpMethod.POST))
                .andExpect(header("X-Goog-Api-Key", "test-places-key"))
                .andExpect(header("X-Goog-FieldMask", "places.id"))
                .andExpect(content().json(
                        "{\"textQuery\":\"Grand Horizon Hotel City Center, Misrata\"}"))
                .andRespond(withSuccess(
                        """
                        {"places":[{"id":"%s"}]}
                        """.formatted(placeId),
                        MediaType.APPLICATION_JSON));
        server.expect(requestTo(
                        "https://places.googleapis.com/v1/places/" + placeId))
                .andExpect(method(GET))
                .andRespond(withSuccess(
                        """
                        {"id":"%s","rating":4.9,"userRatingCount":8240}
                        """.formatted(placeId),
                        MediaType.APPLICATION_JSON));
        when(jdbc.update(anyString(), any(Object[].class)))
                .thenReturn(1);

        sync.refreshAsync(
                43,
                "Grand Horizon Hotel",
                "City Center, Misrata",
                "https://maps.google.com/?q=32.3754%2C15.0925",
                "");

        server.verify();
        ArgumentCaptor<Object[]> arguments = ArgumentCaptor.forClass(Object[].class);
        verify(jdbc).update(anyString(), arguments.capture());
        assertArrayEquals(
                new Object[] {placeId, 4.9, 8240, placeId, 4.9, 8240, 43L},
                arguments.getValue());
    }
}

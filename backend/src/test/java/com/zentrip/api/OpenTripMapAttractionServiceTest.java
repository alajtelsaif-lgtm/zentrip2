package com.zentrip.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.queryParam;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

class OpenTripMapAttractionServiceTest {
    private static final String BASE_URL = "https://api.opentripmap.org/0.1";
    private static final OpenTripMapAttractionService.GeoPoint ROME =
            new OpenTripMapAttractionService.GeoPoint(
                    41.9, 12.5, "Rome", "Italy", null, null, null, null);

    @Test
    void requestsOpenTripMapAndNormalizesPlaceDetails() {
        RestClient.Builder builder = RestClient.builder().baseUrl(BASE_URL);
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "/en/places/geoname")))
                .andExpect(queryParam("apikey", "test-key"))
                .andExpect(queryParam("name", "Rome"))
                .andRespond(withSuccess(
                        """
                        {"name":"Rome","country":"IT","lat":41.9,"lon":12.5}
                        """, APPLICATION_JSON));
        server.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "/en/places/radius")))
                .andExpect(queryParam("kinds",
                        org.hamcrest.Matchers.containsString("museums")))
                .andRespond(withSuccess(
                        """
                        [{
                          "xid":"N12345",
                          "name":"Colosseum",
                          "kinds":"historic,monuments",
                          "rate":"3",
                          "point":{"lat":41.8902,"lon":12.4922}
                        }]
                        """, APPLICATION_JSON));
        server.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "/en/places/xid/N12345")))
                .andRespond(withSuccess(
                        """
                        {
                          "xid":"N12345",
                          "name":"Colosseum",
                          "kinds":"historic,monuments",
                          "rate":"3",
                          "point":{"lat":41.8902,"lon":12.4922},
                          "image":"https://images.example/colosseum.jpg",
                          "wikipedia":"en:Colosseum",
                          "wikipedia_extracts":{"text":"An ancient amphitheatre."},
                          "address":{"city":"Rome","country":"Italy"},
                          "sources":{"attributes":["osm","wikidata"]}
                        }
                        """, APPLICATION_JSON));

        OpenTripMapAttractionService service = service("test-key", builder);
        OpenTripMapAttractionService.SearchOutcome result =
                service.searchAttractionsWithStatus("Rome", "IT", "en");

        assertTrue(result.cityFound());
        assertEquals(1, result.totalCount());
        Map<String, Object> place = result.places().getFirst();
        assertEquals("N12345", place.get("id"));
        assertEquals("Colosseum", place.get("name"));
        assertEquals("historical", place.get("category"));
        assertEquals("https://images.example/colosseum.jpg", place.get("image_url"));
        assertTrue(String.valueOf(place.get("source_attribution"))
                .contains("OpenStreetMap contributors"));
        assertEquals("opentripmap", place.get("source_provider"));
        server.verify();
    }

    @Test
    void suppressesDuplicateAndRecordsItsReason() {
        RestClient.Builder builder = RestClient.builder().baseUrl(BASE_URL);
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder)
                .ignoreExpectOrder(true)
                .build();
        server.expect(requestTo(org.hamcrest.Matchers.containsString("/geoname")))
                .andRespond(withSuccess(
                        """
                        {"name":"Rome","country":"IT","lat":41.9,"lon":12.5}
                        """, APPLICATION_JSON));
        server.expect(requestTo(org.hamcrest.Matchers.containsString("/radius")))
                .andRespond(withSuccess(
                        """
                        [
                          {"xid":"N111","name":"Ichijō Modoribashi",
                           "kinds":"bridges,architecture","rate":"3",
                           "point":{"lat":41.8986,"lon":12.4769}},
                          {"xid":"N222","name":"Ichijo-modoribashi bridge",
                           "kinds":"bridges,architecture","rate":"2",
                           "point":{"lat":41.89865,"lon":12.47695}}
                        ]
                        """, APPLICATION_JSON));
        server.expect(requestTo(org.hamcrest.Matchers.containsString("/xid/N111")))
                .andRespond(withSuccess(
                        """
                        {"xid":"N111","name":"Ichijō Modoribashi",
                         "kinds":"bridges,architecture","rate":"3",
                         "point":{"lat":41.8986,"lon":12.4769}}
                        """, APPLICATION_JSON));
        server.expect(requestTo(org.hamcrest.Matchers.containsString("/xid/N222")))
                .andRespond(withSuccess(
                        """
                        {"xid":"N222","name":"Ichijo-modoribashi bridge",
                         "kinds":"bridges,architecture","rate":"2",
                         "point":{"lat":41.89865,"lon":12.47695}}
                        """, APPLICATION_JSON));

        OpenTripMapAttractionService.SearchOutcome result =
                service("test-key", builder)
                        .searchAttractionsWithStatus("Rome", "IT", "en");

        assertEquals(1, result.places().size());
        assertEquals(1, result.droppedByReason().get("duplicate"));
        assertEquals("duplicate", result.droppedItems().getFirst().reason());
        server.verify();
    }

    @Test
    void mapsArabicRequestsToTheDocumentedEnglishEndpoint() {
        RestClient.Builder builder = RestClient.builder().baseUrl(BASE_URL);
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "/en/places/geoname")))
                .andRespond(withSuccess(
                        """
                        {"name":"Tripoli","country":"LY","lat":32.89,"lon":13.19}
                        """, APPLICATION_JSON));
        server.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "/en/places/radius")))
                .andRespond(withSuccess("[]", APPLICATION_JSON));

        var result = service("test-key", builder)
                .searchAttractionsWithStatus("Tripoli", "LY", "ar");

        assertTrue(result.cityFound());
        assertTrue(result.places().isEmpty());
        server.verify();
    }

    @Test
    void searchesWorldwideCityWithoutAnOptionalCountry() {
        RestClient.Builder builder = RestClient.builder().baseUrl(BASE_URL);
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "/en/places/geoname")))
                .andExpect(queryParam("name", "Rome"))
                .andRespond(withSuccess(
                        """
                        {"name":"Rome","country":"IT","lat":41.9,"lon":12.5}
                        """, APPLICATION_JSON));
        server.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "/en/places/radius")))
                .andRespond(withSuccess("[]", APPLICATION_JSON));

        var result = service("test-key", builder)
                .searchAttractionsWithStatus("Rome", null, "en");

        assertTrue(result.cityFound());
        assertTrue(result.places().isEmpty());
        server.verify();
    }

    @Test
    void countryNameIsConvertedToIsoFilterAndWrongCountryGeonameIsRejected() {
        RestClient.Builder builder = RestClient.builder().baseUrl(BASE_URL);
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "/en/places/geoname")))
                .andExpect(requestTo(org.hamcrest.Matchers.containsString(
                        "name=Leptis%20Magna")))
                .andExpect(queryParam("country", "LY"))
                .andRespond(withSuccess(
                        """
                        {"name":"Leptis Magna","country":"US","lat":40.7,"lon":-111.9}
                        """, APPLICATION_JSON));

        var result = service("test-key", builder)
                .searchAttractionsWithStatus("Leptis Magna", "Libya", "en");

        assertFalse(result.cityFound());
        assertTrue(result.places().isEmpty());
        server.verify();
    }

    @Test
    void usesTheLinkedWikipediaImageOnlyWhenOpenTripMapHasNoImage() {
        RestClient.Builder builder = RestClient.builder().baseUrl(BASE_URL);
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        RestClient.Builder wikipediaBuilder = RestClient.builder();
        MockRestServiceServer wikipediaServer =
                MockRestServiceServer.bindTo(wikipediaBuilder).build();
        server.expect(requestTo(org.hamcrest.Matchers.containsString("/geoname")))
                .andRespond(withSuccess(
                        """
                        {"name":"Rome","country":"IT","lat":41.9,"lon":12.5}
                        """, APPLICATION_JSON));
        server.expect(requestTo(org.hamcrest.Matchers.containsString("/radius")))
                .andRespond(withSuccess(
                        """
                        [{"xid":"N333","name":"Test Landmark","kinds":"historic",
                          "rate":"3","point":{"lat":41.9,"lon":12.5}}]
                        """, APPLICATION_JSON));
        server.expect(requestTo(org.hamcrest.Matchers.containsString("/xid/N333")))
                .andRespond(withSuccess(
                        """
                        {"xid":"N333","name":"Test Landmark","kinds":"historic",
                         "rate":"3","wikipedia":"en:Test_Landmark",
                         "point":{"lat":41.9,"lon":12.5}}
                        """, APPLICATION_JSON));
        wikipediaServer.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "https://en.wikipedia.org/api/rest_v1/page/summary/Test_Landmark")))
                .andRespond(withSuccess(
                        """
                        {"thumbnail":{"source":
                          "https://upload.wikimedia.org/test-landmark.jpg"}}
                        """, APPLICATION_JSON));

        OpenTripMapAttractionService service = new OpenTripMapAttractionService(
                "test-key", false, false, builder.build(), wikipediaBuilder.build());
        var result = service.searchAttractionsWithStatus("Rome", "IT", "en");

        assertEquals(
                "https://upload.wikimedia.org/test-landmark.jpg",
                result.places().getFirst().get("image_url"));
        assertEquals(
                "https://en.wikipedia.org/wiki/Test_Landmark",
                result.places().getFirst().get("wikipedia_url"));
        assertTrue(String.valueOf(result.places().getFirst().get("image_attribution"))
                .contains("Wikipedia"));
        server.verify();
        wikipediaServer.verify();
    }

    @Test
    void prefersDirectPreviewImagesAndNormalizesCommonsFilePages() {
        assertEquals(
                "https://upload.wikimedia.org/preview.jpg",
                OpenTripMapAttractionService.displayImageUrl(
                        "https://upload.wikimedia.org/preview.jpg",
                        null,
                        "https://commons.wikimedia.org/wiki/File:original.jpg"));
        assertEquals(
                "https://commons.wikimedia.org/wiki/Special:FilePath/Example%20Image.jpg",
                OpenTripMapAttractionService.displayImageUrl(
                        null,
                        null,
                        "https://commons.wikimedia.org/wiki/File:Example%20Image.jpg"));
        String blocked400pxThumbnail =
                "https://upload.wikimedia.org/wikipedia/commons/thumb/7/7a/"
                        + "Palazzo_Reale_di_Tripoli.jpg/400px-Palazzo_Reale_di_Tripoli.jpg";
        assertEquals(
                blocked400pxThumbnail.replace("/400px-", "/500px-"),
                OpenTripMapAttractionService.displayImageUrl(
                        blocked400pxThumbnail, null, null));
        assertEquals(
                "https://upload.wikimedia.org/fallback.jpg",
                OpenTripMapAttractionService.displayImageUrl(
                        null,
                        "https://upload.wikimedia.org/fallback.jpg",
                        null));
    }

    @Test
    void refusesToReturnMockLandmarksWhenTheServerKeyIsMissing() {
        OpenTripMapAttractionService service = new OpenTripMapAttractionService(
                "", false, true, RestClient.builder().baseUrl(BASE_URL).build());

        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> service.searchAttractionsWithStatus("Rome", "IT", "en"));

        assertEquals(HttpStatus.SERVICE_UNAVAILABLE, exception.getStatusCode());
    }

    @Test
    void strictlyFiltersBusinessesTypesCodesAndOutOfAreaPlaces() {
        assertRejected("Museum Store", "museums", "business");
        assertRejected("City Restaurant", "restaurants", "business");
        assertRejected("Hotel Roma", "hotels", "business");
        assertRejected("Office", "offices", "business");
        assertRejected("DAS18", "museums", "no_identity");
        assertRejected("Ordinary building", "buildings", "type");
        assertRejected("Battle of Tripoli", "battlefields,historic", "event");
        var farAway = candidate("Far Museum", "museums", 42.3, 12.5, "3");
        assertEquals("location", OpenTripMapAttractionService.isRealLandmark(
                farAway, ROME, null, null, null, null).reason());
    }

    @Test
    void keepsRealMuseumsBeachesAndArchaeologicalPlaces() {
        assertAccepted("Capitoline Museums", "museums", "museum");
        assertAccepted("Ostia Beach", "beaches", "beach");
        assertAccepted("Ostia Antica", "archaeology,historic", "historical");
    }

    private static void assertRejected(String name, String kinds, String reason) {
        var result = OpenTripMapAttractionService.isRealLandmark(
                candidate(name, kinds, 41.9, 12.5, "3"),
                ROME, null, null, null, null);
        assertFalse(result.accepted(), name);
        assertEquals(reason, result.reason(), name);
    }

    private static void assertAccepted(String name, String kinds, String category) {
        var result = OpenTripMapAttractionService.isRealLandmark(
                candidate(name, kinds, 41.9, 12.5, "3"),
                ROME, null, null, null, null);
        assertTrue(result.accepted(), name);
        assertEquals(category, result.category(), name);
    }

    private static OpenTripMapAttractionService.Candidate candidate(
            String name, String kinds, double latitude, double longitude, String rate) {
        return new OpenTripMapAttractionService.Candidate(
                "N12345", name, kinds, latitude, longitude, rate,
                null, null, "https://images.example/place.jpg", null,
                null, null, Map.of());
    }

    private static String pantheonDetails() {
        return """
                {
                  "xid":"N111",
                  "name":"Pantheon",
                  "kinds":"historic",
                  "rate":"3",
                  "point":{"lat":41.8986,"lon":12.4769},
                  "image":"https://images.example/pantheon.jpg"
                }
                """;
    }

    private static OpenTripMapAttractionService service(
            String key, RestClient.Builder builder) {
        return new OpenTripMapAttractionService(
                key, false, false, builder.build());
    }
}

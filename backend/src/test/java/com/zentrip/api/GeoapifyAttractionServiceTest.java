package com.zentrip.api;

import java.util.List;
import java.util.Map;

import static org.hamcrest.Matchers.containsString;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.queryParam;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class GeoapifyAttractionServiceTest {
    @Test
    void strictLandmarkFilterRejectsBusinessAndUnverifiedCandidates() {
        assertRejected("Museum Store",
                List.of("entertainment.museum"),
                Map.of(), "Q100", true, "business");
        assertRejected("Wright Antiques", List.of("tourism.attraction"),
                Map.of(), "Q104", true, "business");
        assertRejected("Hussam Alarbi", List.of("tourism.attraction"),
                Map.of("tourism", "attraction"), null, false, "no_identity");
        assertRejected("DAS18", List.of("tourism.attraction"),
                Map.of(), null, false, "no_identity");
        assertRejected("Restaurant", List.of("catering.restaurant"),
                Map.of("amenity", "restaurant"), "Q101", true, "business");
        assertRejected("Office", List.of("office.government"),
                Map.of("office", "government"), "Q102", true, "business");
        assertRejected("Hotel", List.of("accommodation.hotel"),
                Map.of("tourism", "hotel"), "Q103", true, "business");
        assertRejected("Hotel Roma", List.of("accommodation.hotel"),
                Map.of("tourism", "hotel"), "Q105", true, "business");
    }

    @Test
    void strictLandmarkFilterKeepsVerifiedMuseumBeachAndArchaeologicalSite() {
        assertAccepted("National Museum", List.of("entertainment.museum"),
                "Q200", true);
        assertAccepted("Coral Beach", List.of("beach"), "Q201", true);
        assertAccepted("Ancient Ruins",
                List.of("tourism.sights.archaeological_site"), "Q202", true);
        var historicOfficeUse = GeoapifyAttractionService.isRealLandmark(
                "Palazzo Farnese", List.of("office.government"),
                Map.of("office", "government"), "Q848386", true,
                null, null, false, true);
        assertTrue(historicOfficeUse.accepted());
        var rawHistoricOffice = GeoapifyAttractionService.isRealLandmark(
                "Palazzo Farnese", List.of("office.government"),
                Map.of("office", "government", "historic", "palace"), "Q848386", false,
                "en:Palazzo Farnese", null, false, true);
        assertTrue(rawHistoricOffice.accepted());
    }

    @Test
    void keepsGeoapifyLandmarksAndReturnsWarningWhenWikidataIsUnavailable() {
        RestClient.Builder geoBuilder = RestClient.builder().baseUrl("https://geo.test");
        RestClient.Builder wikidataBuilder = RestClient.builder();
        MockRestServiceServer geoServer = MockRestServiceServer.bindTo(geoBuilder).build();
        MockRestServiceServer wikidataServer =
                MockRestServiceServer.bindTo(wikidataBuilder).build();
        geoServer.expect(requestTo(containsString("/v1/geocode/search")))
                .andRespond(withSuccess("""
                        {"results":[{"lat":41.9,"lon":12.5,"city":"Rome",
                          "country":"Italy","country_code":"it"}]}
                        """, MediaType.APPLICATION_JSON));
        geoServer.expect(requestTo(containsString("/v2/places")))
                .andRespond(withSuccess("""
                        {"features":[{"properties":{
                          "name":"Roman Forum","name:en":"Roman Forum",
                          "city":"Rome","country":"Italy",
                          "lat":41.89,"lon":12.48,
                          "categories":["tourism.attraction"],
                          "place_id":"rome-forum",
                          "datasource":{"raw":{"wikidata":"Q123",
                            "historic":"archaeological_site",
                            "tourism":"attraction","name":"Roman Forum"}}
                        }},{"properties":{
                          "name":"Palazzo Farnese","name:en":"Palazzo Farnese",
                          "city":"Rome","country":"Italy",
                          "lat":41.89,"lon":12.48,
                          "categories":["office.government"],
                          "place_id":"palazzo-farnese",
                          "datasource":{"raw":{"wikidata":"Q124",
                            "office":"government","name":"Palazzo Farnese"}}
                        }},{"properties":{
                          "name":"No Image Landmark","name:en":"No Image Landmark",
                          "city":"Rome","country":"Italy",
                          "lat":41.89,"lon":12.48,
                          "categories":["tourism.attraction"],
                          "place_id":"rome-no-image",
                          "datasource":{"raw":{"wikidata":"Q125",
                            "wikipedia":"en:No Image Landmark",
                            "tourism":"attraction","name":"No Image Landmark"}}
                        }}]}
                        """, MediaType.APPLICATION_JSON));
        wikidataServer.expect(requestTo(containsString("query.wikidata.org/sparql")))
                .andRespond(withServerError());
        wikidataServer.expect(requestTo(containsString("www.wikidata.org/w/api.php")))
                .andRespond(withSuccess("""
                        {"entities":{"Q123":{
                          "labels":{"en":{"value":"Roman Forum"}},
                          "descriptions":{"en":{"value":"Archaeological site in Rome"}},
                          "sitelinks":{"enwiki":{"title":"Roman Forum"}},
                          "claims":{"P18":[{"mainsnak":{"datavalue":{
                            "value":"Roman Forum.jpg"}}}]}
                        },
                        "Q124":{
                          "labels":{"en":{"value":"Palazzo Farnese"}},
                          "sitelinks":{"enwiki":{"title":"Palazzo Farnese"}},
                          "claims":{"P18":[{"mainsnak":{"datavalue":{
                            "value":"Palazzo Farnese.jpg"}}}],
                            "P31":[{"mainsnak":{"datavalue":{"value":{
                              "id":"Q16560"}}}}]}
                        },
                        "Q125":{
                          "labels":{"en":{"value":"No Image Landmark"}},
                          "sitelinks":{"enwiki":{"title":"No Image Landmark"}}
                        }}}
                        """, MediaType.APPLICATION_JSON));

        GeoapifyAttractionService service =
                new GeoapifyAttractionService("test-key", geoBuilder, wikidataBuilder);

        var outcome = service.searchAttractionsWithStatus("Rome", "Italy", "en");

        assertEquals(2, outcome.places().size(),
                outcome.droppedByReason() + " / " + outcome.droppedItems());
        assertEquals("Roman Forum", outcome.places().getFirst().get("name"));
        assertTrue(String.valueOf(outcome.places().getFirst().get("image_url"))
                .contains("Roman%20Forum.jpg"));
        assertEquals("geoapify+wikidata",
                outcome.places().getFirst().get("source_provider"));
        assertEquals("historical", outcome.places().getFirst().get("category"));
        Map<String, Object> palazzo = outcome.places().stream()
                .filter(place -> "Palazzo Farnese".equals(place.get("name")))
                .findFirst().orElseThrow();
        assertEquals("architecture", palazzo.get("category"));
        assertTrue(palazzo.get("image_url") != null);
        assertEquals(1, outcome.droppedByReason().get("image_missing"));
        assertTrue(outcome.warnings().stream().anyMatch(
                warning -> warning.toLowerCase().contains("wikidata")));
        geoServer.verify();
        wikidataServer.verify();
    }

    private static void assertRejected(
            String name,
            List<String> categories,
            Map<String, String> raw,
            String wikidataId,
            boolean verifiedType,
            String expectedReason) {
        var result = GeoapifyAttractionService.isRealLandmark(
                name, categories, raw, wikidataId, verifiedType,
                null, null, false, true);
        assertFalse(result.accepted(), name);
        assertEquals(expectedReason, result.reason(), name);
    }

    private static void assertAccepted(
            String name, List<String> categories, String wikidataId, boolean verifiedType) {
        var result = GeoapifyAttractionService.isRealLandmark(
                name, categories, Map.of(), wikidataId, verifiedType,
                null, null, false, true);
        assertTrue(result.accepted(), name + ": " + result.reason());
    }

    @Test
    void returnsOnlyDeduplicatedWikidataVerifiedPlacesInTheRequestedLanguage() {
        RestClient.Builder geoBuilder = RestClient.builder().baseUrl("https://geo.test");
        RestClient.Builder wikidataBuilder = RestClient.builder();
        MockRestServiceServer geoServer = MockRestServiceServer.bindTo(geoBuilder).build();
        MockRestServiceServer wikidataServer =
                MockRestServiceServer.bindTo(wikidataBuilder).build();

        geoServer.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "https://geo.test/v1/geocode/search")))
                .andExpect(queryParam("filter", "countrycode:ly"))
                .andExpect(queryParam("lang", "ar"))
                .andRespond(withSuccess("""
                        {"results":[{
                          "lat":32.8,"lon":13.2,"city":"طرابلس",
                          "country":"ليبيا","country_code":"ly",
                          "bbox":{"lat1":32.7,"lon1":13.0,"lat2":32.9,"lon2":13.3}
                        }]}
                        """, MediaType.APPLICATION_JSON));
        geoServer.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "https://geo.test/v2/places")))
                .andExpect(queryParam("filter", "rect:13.0,32.7,13.3,32.9"))
                .andExpect(queryParam("categories",
                        "tourism.sights,tourism.attraction,entertainment.museum,"
                                + "leisure.park,leisure.park.garden,beach,heritage,"
                                + "building.historic"))
                .andRespond(withSuccess("""
                        {"features":[
                          {"properties":{
                            "place_id":"place-1","wikidata":"Q1",
                            "name":"Historic Site","city":"طرابلس","country":"ليبيا",
                            "country_code":"ly","lat":32.8,"lon":13.2,
                            "categories":["tourism.sights.historic"]
                          }},
                          {"properties":{
                            "place_id":"place-1-copy","wikidata":"Q1",
                            "name":"Historic Site","city":"طرابلس","country":"ليبيا",
                            "country_code":"ly","lat":32.8,"lon":13.2,
                            "categories":["tourism.sights.historic"]
                          }},
                          {"properties":{
                            "place_id":"DAS18","name":"DAS18","city":"Tripoli",
                            "country":"Libya","country_code":"ly","lat":32.81,"lon":13.21,
                            "categories":["tourism.attraction"]
                          }},
                          {"properties":{
                            "place_id":"unverified","wikidata":"Q2",
                            "name":"Unverified","city":"طرابلس","country":"ليبيا",
                            "country_code":"ly","lat":32.81,"lon":13.21,
                            "categories":["tourism.sights"]
                          }},
                          {"properties":{
                            "place_id":"market","wikidata":"Q1",
                            "name":"Market","city":"طرابلس","country":"ليبيا",
                            "country_code":"ly","lat":32.82,"lon":13.22,
                            "categories":["commercial.marketplace","tourism.sights"]
                          }}
                        ]}
                        """, MediaType.APPLICATION_JSON));
        wikidataServer.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "https://query.wikidata.org/sparql?query=")))
                .andRespond(withSuccess("""
                        {"results":{"bindings":[{
                          "item":{"value":"http://www.wikidata.org/entity/Q1"},
                          "landmarkType":{"value":"http://www.wikidata.org/entity/Q4989906"},
                          "coordinates":{"value":"Point(13.2 32.8)"},
                          "labelEn":{"value":"Historic Site"},
                          "labelAr":{"value":"موقع تاريخي"},
                          "descriptionEn":{"value":"An English description."},
                          "descriptionAr":{"value":"وصف عربي."},
                          "enwiki":{"value":"https://en.wikipedia.org/wiki/Historic_Site"},
                          "arwiki":{"value":"https://ar.wikipedia.org/wiki/موقع_تاريخي"},
                          "image":{"value":"https://upload.wikimedia.org/wikipedia/commons/a/ab/Site.jpg"}
                        }]}}
                        """, MediaType.APPLICATION_JSON));

        GeoapifyAttractionService service =
                new GeoapifyAttractionService("test-key", geoBuilder, wikidataBuilder);
        var outcome = service.searchAttractionsWithStatus("Tripoli", "Libya", "ar");
        var places = outcome.places();

        assertEquals(Boolean.TRUE, outcome.cityFound());
        assertEquals(6, outcome.candidateCount());
        assertEquals(1, places.size());
        var place = places.getFirst();
        assertEquals("موقع تاريخي", place.get("name"));
        assertEquals("Historic Site", place.get("name_en"));
        assertEquals("موقع تاريخي", place.get("name_ar"));
        assertEquals("طرابلس", place.get("city"));
        assertEquals("ليبيا", place.get("country"));
        assertEquals("وصف عربي.", place.get("description"));
        assertEquals("https://commons.wikimedia.org/wiki/Special:FilePath/Site.jpg?width=1200",
                place.get("image_url"));
        assertEquals("https://ar.wikipedia.org/wiki/موقع_تاريخي", place.get("wikipedia_url"));
        assertEquals("Q1", place.get("wikidata_id"));
        assertEquals("historical", place.get("category_tag"));
        assertEquals(5, outcome.droppedByReason().values().stream()
                .mapToInt(Integer::intValue).sum());
        assertEquals(1, outcome.droppedByReason().get("no_identity"));
        assertEquals(1, outcome.droppedByReason().get("type"));
        assertEquals(1, outcome.droppedByReason().get("business"));
        assertEquals(2, outcome.droppedByReason().get("duplicate"));

        var cached = service.searchAttractionsWithStatus("Tripoli", "Libya", "ar");
        assertEquals(places, cached.places());
        assertEquals(outcome.droppedByReason(), cached.droppedByReason());
        geoServer.verify();
        wikidataServer.verify();
    }

    @Test
    void marksAnUnresolvedCityWithoutCallingPlacesOrWikidata() {
        RestClient.Builder geoBuilder = RestClient.builder().baseUrl("https://geo.test");
        RestClient.Builder wikidataBuilder = RestClient.builder();
        MockRestServiceServer geoServer = MockRestServiceServer.bindTo(geoBuilder).build();
        MockRestServiceServer wikidataServer =
                MockRestServiceServer.bindTo(wikidataBuilder).build();
        geoServer.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "https://geo.test/v1/geocode/search")))
                .andRespond(withSuccess(
                        "{\"results\":[]}", MediaType.APPLICATION_JSON));

        GeoapifyAttractionService service =
                new GeoapifyAttractionService("test-key", geoBuilder, wikidataBuilder);
        var outcome = service.searchAttractionsWithStatus(
                "No Such City", "Libya", "en");

        assertFalse(outcome.cityFound() == null);
        assertEquals(Boolean.FALSE, outcome.cityFound());
        assertTrue(outcome.places().isEmpty());
        assertNull(outcome.places().stream().findFirst().orElse(null));
        geoServer.verify();
        wikidataServer.verify();
    }

    @Test
    void suggestionsKeepCitiesAndLandmarksButHideCafes() {
        RestClient.Builder geoBuilder = RestClient.builder().baseUrl("https://geo.test");
        RestClient.Builder wikidataBuilder = RestClient.builder();
        MockRestServiceServer geoServer = MockRestServiceServer.bindTo(geoBuilder).build();
        MockRestServiceServer.bindTo(wikidataBuilder).build();
        geoServer.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "https://geo.test/v1/geocode/autocomplete")))
                .andExpect(queryParam("lang", "en"))
                .andRespond(withSuccess("""
                        {"results":[
                          {"result_type":"city","name":"Tripoli","city":"Tripoli",
                           "country":"Libya","country_code":"ly","lat":32.8,"lon":13.2},
                          {"result_type":"amenity","name":"Historic Site","city":"Tripoli",
                           "country":"Libya","country_code":"ly","lat":32.8,"lon":13.2,
                           "wikidata":"Q1","categories":["tourism.sights.historic"]},
                          {"result_type":"amenity","name":"Cafe","city":"Tripoli",
                           "country":"Libya","country_code":"ly","lat":32.8,"lon":13.2,
                           "categories":["catering.cafe"]}
                        ]}
                        """, MediaType.APPLICATION_JSON));

        GeoapifyAttractionService service =
                new GeoapifyAttractionService("test-key", geoBuilder, wikidataBuilder);
        var suggestions = service.suggestPlaces("Trip", "en");

        assertEquals(2, suggestions.size());
        assertEquals("Tripoli, Libya", suggestions.getFirst().get("label"));
        assertEquals("Historic Site", suggestions.get(1).get("label"));
        assertTrue(suggestions.stream().noneMatch(
                suggestion -> "Cafe".equals(suggestion.get("label"))));
        assertEquals(suggestions, service.suggestPlaces("Trip", "en"));
        geoServer.verify();
    }

    @Test
    void arabicSuggestionsDoNotMixLatinAndArabicLabels() {
        RestClient.Builder geoBuilder = RestClient.builder().baseUrl("https://geo.test");
        RestClient.Builder wikidataBuilder = RestClient.builder();
        MockRestServiceServer geoServer = MockRestServiceServer.bindTo(geoBuilder).build();
        MockRestServiceServer.bindTo(wikidataBuilder).build();
        geoServer.expect(requestTo(org.hamcrest.Matchers.containsString(
                        "https://geo.test/v1/geocode/autocomplete")))
                .andRespond(withSuccess("""
                        {"results":[
                          {"result_type":"city","name":"Tripoli, IA",
                           "city":"Tripoli, IA","country":"الولايات المتحدة",
                           "country_code":"us","lat":42.0,"lon":-94.0,
                           "formatted":"Tripoli, IA, الولايات المتحدة"},
                          {"result_type":"city","name":"Tripoli","city":"طرابلس",
                           "country":"ليبيا","country_code":"ly","lat":32.8,"lon":13.2}
                        ]}
                        """, MediaType.APPLICATION_JSON));

        GeoapifyAttractionService service =
                new GeoapifyAttractionService("test-key", geoBuilder, wikidataBuilder);
        var suggestions = service.suggestPlaces("Tripoli", "ar");

        assertEquals(1, suggestions.size());
        assertEquals("طرابلس، ليبيا", suggestions.getFirst().get("label"));
        assertFalse(suggestions.getFirst().get("label").toString()
                .matches(".*[A-Za-z].*"));
        geoServer.verify();
    }
}

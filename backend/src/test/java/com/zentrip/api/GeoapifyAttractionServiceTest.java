package com.zentrip.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.queryParam;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class GeoapifyAttractionServiceTest {
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
        assertEquals(5, outcome.candidateCount());
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
        assertEquals(4, outcome.droppedByReason().values().stream()
                .mapToInt(Integer::intValue).sum());
        assertEquals(1, outcome.droppedByReason().get("missing_wikidata_id"));
        assertEquals(1, outcome.droppedByReason()
                .get("wikidata_type_or_coordinates_unverified"));
        assertEquals(1, outcome.droppedByReason()
                .get("category_not_in_landmark_allowlist"));
        assertEquals(1, outcome.droppedByReason()
                .get("duplicate_name_and_coordinates"));

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

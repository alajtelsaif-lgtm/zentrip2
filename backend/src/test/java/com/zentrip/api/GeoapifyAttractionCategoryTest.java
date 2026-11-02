package com.zentrip.api;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import org.junit.jupiter.api.Test;

class GeoapifyAttractionCategoryTest {
    @Test
    void acceptsOnlyLandmarkCategoryFamilies() {
        for (String category : List.of(
                "tourism.sights",
                "tourism.sights.archaeological_site",
                "tourism.sights.building",
                "tourism.attraction",
                "entertainment.museum",
                "leisure.park",
                "heritage.unesco",
                "building.historic")) {
            assertTrue(
                    GeoapifyAttractionService.isAllowedLandmarkCategory(List.of(category)),
                    category);
        }
    }

    @Test
    void rejectsGenericPlacesAndShoppingCategories() {
        for (String category : List.of(
                "commercial.shopping_mall",
                "commercial.supermarket",
                "commercial.marketplace",
                "shop.clothes",
                "catering.restaurant",
                "catering.cafe",
                "office",
                "accommodation.hotel",
                "tourism.museum",
                "building.architecture")) {
            assertFalse(
                    GeoapifyAttractionService.isAllowedLandmarkCategory(List.of(category)),
                    category);
        }
    }

    @Test
    void classifiesBadRequestsWithoutLoggingProviderResponseBodies() {
        assertEquals(
                "HTTP 400 (category filter rejected)",
                GeoapifyAttractionService.classifyProviderFailure(
                        400, "{\"message\":\"unsupported category filter\"}"));
        assertEquals(
                "HTTP 400 (provider rejected request)",
                GeoapifyAttractionService.classifyProviderFailure(
                        400, "{\"message\":\"sensitive provider detail\"}"));
        assertEquals(
                "HTTP 429",
                GeoapifyAttractionService.classifyProviderFailure(429, "ignored"));
    }
}

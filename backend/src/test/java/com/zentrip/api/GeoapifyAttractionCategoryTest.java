package com.zentrip.api;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import org.junit.jupiter.api.Test;

class GeoapifyAttractionCategoryTest {
    @Test
    void acceptsOnlyLandmarkCategoryFamilies() {
        for (String category : List.of(
                "tourism.sights",
                "tourism.attraction",
                "tourism.museum",
                "entertainment.museum",
                "leisure.park",
                "heritage.unesco",
                "building.historic",
                "building.architecture")) {
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
                "catering.restaurant",
                "office",
                "accommodation.hotel")) {
            assertFalse(
                    GeoapifyAttractionService.isAllowedLandmarkCategory(List.of(category)),
                    category);
        }
    }
}

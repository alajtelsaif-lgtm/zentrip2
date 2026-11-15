package com.zentrip.api;

import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class UnifiedInventoryServiceTest {
    private final ExchangeRateService exchangeRates = mock(ExchangeRateService.class);
    private final UnifiedInventoryService service =
            new UnifiedInventoryService(exchangeRates);

    @Test
    void mergesPartnerAndLiteApiResultsIntoTheSameLegacyCompatibleShape() {
        Map<String, Object> partnerHotel = Map.of(
                "id", "partner-7",
                "source", "partner",
                "name", "Partner Hotel",
                "city", "Tripoli",
                "price_per_night", new BigDecimal("84.50"),
                "price_currency", "USD",
                "booking_ref", "must-not-leak",
                "amenities", List.of("Wi-Fi"),
                "image_url", "https://example.com/partner.jpg");
        Map<String, Object> liteApiHotel = Map.of(
                "id", "liteapi-8",
                "source", "liteapi",
                "name", "LiteAPI Hotel",
                "city", "Tripoli",
                "price_per_night", new BigDecimal("100.00"),
                "price_currency", "GBP",
                "offers", List.of(
                        Map.of("id", "rate-1", "price_per_night", 100, "price_currency", "GBP"),
                        Map.of("id", "rate-2", "price_per_night", 120, "price_currency", "GBP")),
                "gallery_images", List.of("https://example.com/liteapi.jpg"));

        UnifiedInventoryService.SearchOutcome result = service.merge(
                "hotel",
                () -> List.of(partnerHotel),
                List.of(new UnifiedInventoryService.ProviderSearch(
                        "liteapi",
                        "LiteAPI unavailable",
                        () -> UnifiedInventoryService.SourceOutcome.of(
                                List.of(liteApiHotel)))),
                "Partner inventory unavailable");

        assertEquals(2, result.items().size());
        assertEquals(Map.of("partner", 1L, "liteapi", 1L), result.sources());
        Map<String, Object> partner = result.items().getFirst();
        Map<String, Object> liteApi = result.items().getLast();
        for (Map<String, Object> item : result.items()) {
            for (String key : List.of(
                    "id", "source", "type", "title", "location", "price", "currency",
                    "dates", "images", "rating", "amenities", "offers", "booking_ref")) {
                assertTrue(item.containsKey(key), "missing unified field: " + key);
            }
            assertEquals("hotel", item.get("type"));
            assertEquals(null, item.get("booking_ref"));
        }
        assertEquals("Partner Hotel", partner.get("title"));
        assertEquals(2, ((List<?>) liteApi.get("offers")).size());
        assertEquals("GBP", liteApi.get("currency"));
        assertEquals(
                List.of("https://example.com/liteapi.jpg"), liteApi.get("images"));
        assertTrue(((Map<?, ?>) ((List<?>) liteApi.get("offers")).getFirst())
                .containsKey("conditions"));
    }

    @Test
    void providerFailureKeepsPartnerResultsAndReturnsAWarning() {
        UnifiedInventoryService.SearchOutcome result = service.merge(
                "hotel",
                () -> List.of(Map.of(
                        "id", "partner-1",
                        "source", "partner",
                        "name", "Partner Hotel",
                        "price_per_night", 80)),
                () -> {
                    throw new IllegalStateException("provider down");
                },
                "Partner inventory unavailable",
                "LiteAPI unavailable");

        assertEquals(1, result.items().size());
        assertEquals("partner", result.items().getFirst().get("source"));
        assertTrue(result.warnings().contains("LiteAPI unavailable"));
    }

    @Test
    void emptyLiteApiRatesDoNotRemovePartnerFallbackHotels() {
        UnifiedInventoryService.SearchOutcome result = service.merge(
                "hotel",
                () -> List.of(Map.of(
                        "id", "partner-tripoli-1",
                        "source", "partner",
                        "name", "Partner Hotel",
                        "price_per_night", 80)),
                List.of(new UnifiedInventoryService.ProviderSearch(
                        "liteapi",
                        "LiteAPI returned no rates",
                        () -> new UnifiedInventoryService.SourceOutcome(
                                List.of(),
                                List.of("No LiteAPI rates for the selected dates."),
                                "empty",
                                Map.of(
                                        "metadata_count", 0,
                                        "rates_count", 0,
                                        "rates_http_status", 200)))),
                "Partner unavailable");

        assertEquals(1, result.items().size());
        assertEquals("partner-tripoli-1", result.items().getFirst().get("id"));
        assertEquals(Map.of("partner", 1L, "liteapi", 0L), result.sources());
        assertEquals("empty", result.providerStatuses().get("liteapi"));
        assertEquals(0, result.providerDiagnostics()
                .get("liteapi").get("rates_count"));
        assertTrue(result.warnings().contains(
                "No LiteAPI rates for the selected dates."));
    }

    @Test
    void oneProviderFailureDoesNotRemoveResultsFromOtherProviders() {
        UnifiedInventoryService.SearchOutcome result = service.merge(
                "hotel",
                () -> List.of(Map.of(
                        "id", "partner-1",
                        "source", "partner",
                        "name", "Partner Hotel")),
                List.of(
                        new UnifiedInventoryService.ProviderSearch(
                                "liteapi",
                                "LiteAPI unavailable",
                                () -> UnifiedInventoryService.SourceOutcome.of(List.of(Map.of(
                                        "id", "liteapi-1",
                                        "source", "liteapi",
                                        "name", "LiteAPI Hotel")))),
                        new UnifiedInventoryService.ProviderSearch(
                                "liteapi",
                                "LiteAPI secondary lookup unavailable",
                                () -> {
                                    throw new IllegalStateException("content provider denied");
                                })),
                "Partner unavailable");

        assertEquals(2, result.items().size());
        assertEquals(Map.of(
                "partner", 1L, "liteapi", 1L), result.sources());
        assertTrue(result.warnings().contains("LiteAPI secondary lookup unavailable"));
    }

    @Test
    void partnerFailureKeepsDuffelFlightResultsAndReturnsAWarning() {
        UnifiedInventoryService.SearchOutcome result = service.merge(
                "flight",
                () -> {
                    throw new IllegalStateException("database down");
                },
                () -> UnifiedInventoryService.SourceOutcome.of(List.of(Map.of(
                        "id", "duffel-srr-1",
                        "source", "duffel",
                        "name", "Duffel flight"))),
                "Partner unavailable",
                "Duffel unavailable");

        assertEquals(1, result.items().size());
        assertEquals("duffel", result.items().getFirst().get("source"));
        assertTrue(result.warnings().contains("Partner unavailable"));
    }

    @Test
    void serverFiltersConvertCurrencyAndMatchAmenitiesRoomTypeAndPreferences() {
        when(exchangeRates.latest()).thenReturn(Map.of(
                "rates", List.of(Map.of(
                        "quote", "GBP",
                        "rate", new BigDecimal("0.80")))));
        Map<String, Object> matches = Map.of(
                "id", "liteapi-1",
                "source", "liteapi",
                "name", "Family hotel",
                "description", "Family-friendly accommodation",
                "price", new BigDecimal("80.00"),
                "currency", "GBP",
                "rating", 4.6,
                "amenities", List.of("Wi-Fi", "Breakfast"),
                "offers", List.of(Map.of(
                        "name", "Breakfast included",
                        "room_name", "Deluxe double room")));
        Map<String, Object> tooExpensive = Map.of(
                "id", "partner-2",
                "source", "partner",
                "name", "Other hotel",
                "price", new BigDecimal("120.00"),
                "currency", "USD",
                "rating", 4.9,
                "amenities", List.of("Wi-Fi"),
                "offers", List.of(Map.of("room_name", "Single room")));

        UnifiedInventoryService.FilterOutcome result = service.filterHotels(
                List.of(matches, tooExpensive),
                new UnifiedInventoryService.HotelFilters(
                        "USD",
                        new BigDecimal("95"),
                        new BigDecimal("105"),
                        new BigDecimal("4"),
                        "wifi",
                        "double",
                        "family,breakfast"));

        assertEquals(1, result.hotels().size());
        assertEquals("liteapi-1", result.hotels().getFirst().get("id"));
        assertTrue(result.warnings().isEmpty());
    }

    @Test
    void unsupportedDisplayCurrenciesAreRejected() {
        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> service.filterHotels(
                        List.of(),
                        new UnifiedInventoryService.HotelFilters(
                                "CAD", null, null, null, null, null, null)));

        assertEquals(400, error.getStatusCode().value());
        assertFalse(error.getReason().isBlank());
    }

    @Test
    void hotelPriceFiltersUseTheFixedLydReferenceRate() {
        when(exchangeRates.latest()).thenReturn(Map.of("rates", List.of()));
        Map<String, Object> hotel = Map.of(
                "id", "hotel-usd-100",
                "name", "USD hotel",
                "price", new BigDecimal("100.00"),
                "price_currency", "USD");

        UnifiedInventoryService.FilterOutcome result = service.filterHotels(
                List.of(hotel),
                new UnifiedInventoryService.HotelFilters(
                        "LYD",
                        new BigDecimal("640"),
                        new BigDecimal("640"),
                        null,
                        null,
                        null,
                        null));

        assertEquals(1, result.hotels().size());
        assertEquals("hotel-usd-100", result.hotels().getFirst().get("id"));
    }

    @Test
    void nullProviderRowsAndNullFilterInputAreHandledSafely() {
        UnifiedInventoryService.SourceOutcome source =
                new UnifiedInventoryService.SourceOutcome(
                        Arrays.asList(null, Map.of("id", "hotel-1")),
                        Arrays.asList(null, " "));
        UnifiedInventoryService.FilterOutcome filtered = service.filterHotels(
                null,
                new UnifiedInventoryService.HotelFilters(
                        "USD", null, null, null, null, null, null));

        assertEquals(1, source.items().size());
        assertTrue(source.warnings().isEmpty());
        assertTrue(filtered.hotels().isEmpty());
        assertTrue(filtered.warnings().isEmpty());
    }
}

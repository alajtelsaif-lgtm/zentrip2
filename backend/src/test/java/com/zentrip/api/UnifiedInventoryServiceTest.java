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
    void mergesPartnerAndDuffelResultsIntoTheSameLegacyCompatibleShape() {
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
        Map<String, Object> duffelHotel = Map.of(
                "id", "duffel-srr-8",
                "source", "duffel",
                "name", "Duffel Hotel",
                "city", "Tripoli",
                "price_per_night", new BigDecimal("100.00"),
                "price_currency", "GBP",
                "offers", List.of(
                        Map.of("id", "rate-1", "price_per_night", 100, "price_currency", "GBP"),
                        Map.of("id", "rate-2", "price_per_night", 120, "price_currency", "GBP")),
                "gallery_images", List.of("https://example.com/duffel.jpg"));

        UnifiedInventoryService.SearchOutcome result = service.merge(
                "hotel",
                () -> List.of(partnerHotel),
                () -> UnifiedInventoryService.SourceOutcome.of(List.of(duffelHotel)),
                "Partner inventory unavailable",
                "Duffel unavailable");

        assertEquals(2, result.items().size());
        assertEquals(Map.of("partner", 1L, "duffel", 1L), result.sources());
        Map<String, Object> partner = result.items().getFirst();
        Map<String, Object> duffel = result.items().getLast();
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
        assertEquals(2, ((List<?>) duffel.get("offers")).size());
        assertEquals("GBP", duffel.get("currency"));
        assertEquals(List.of("https://example.com/duffel.jpg"), duffel.get("images"));
        assertTrue(((Map<?, ?>) ((List<?>) duffel.get("offers")).getFirst())
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
                "Duffel unavailable");

        assertEquals(1, result.items().size());
        assertEquals("partner", result.items().getFirst().get("source"));
        assertTrue(result.warnings().contains("Duffel unavailable"));
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
                                "duffel",
                                "Duffel unavailable",
                                () -> UnifiedInventoryService.SourceOutcome.of(List.of(Map.of(
                                        "id", "duffel-srr-1",
                                        "source", "duffel",
                                        "name", "Duffel Hotel")))),
                        new UnifiedInventoryService.ProviderSearch(
                                "rapidapi",
                                "RapidAPI unavailable",
                                () -> {
                                    throw new IllegalStateException("provider denied");
                                })),
                "Partner unavailable");

        assertEquals(2, result.items().size());
        assertEquals(Map.of(
                "partner", 1L, "duffel", 1L, "rapidapi", 0L), result.sources());
        assertTrue(result.warnings().contains("RapidAPI unavailable"));
    }

    @Test
    void partnerFailureKeepsDuffelResultsAndReturnsAWarning() {
        UnifiedInventoryService.SearchOutcome result = service.merge(
                "hotel",
                () -> {
                    throw new IllegalStateException("database down");
                },
                () -> UnifiedInventoryService.SourceOutcome.of(List.of(Map.of(
                        "id", "duffel-srr-1",
                        "source", "duffel",
                        "name", "Duffel Hotel"))),
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
                "id", "duffel-srr-1",
                "source", "duffel",
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
        assertEquals("duffel-srr-1", result.hotels().getFirst().get("id"));
        assertTrue(result.warnings().isEmpty());
    }

    @Test
    void onlySupportedDisplayCurrenciesAreAccepted() {
        ResponseStatusException error = assertThrows(
                ResponseStatusException.class,
                () -> service.filterHotels(
                        List.of(),
                        new UnifiedInventoryService.HotelFilters(
                                "LYD", null, null, null, null, null, null)));

        assertEquals(400, error.getStatusCode().value());
        assertFalse(error.getReason().isBlank());
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

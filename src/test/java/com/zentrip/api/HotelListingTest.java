package com.zentrip.api;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class HotelListingTest {
    @Test
    void pricingForNightsCalculatesSubtotalTaxesAndTotal() {
        HotelListing hotel = new HotelListing(
                "hotel-1",
                "Grand Horizon Hotel",
                "City Center, Misrata",
                null,
                null,
                new BigDecimal("4.9"),
                8240,
                List.of("Gym", "Wi-Fi", "Restaurant", "Spa", "Pool"),
                "A welcoming stay in Misrata.",
                new BigDecimal("420.00"),
                new BigDecimal("12.00"),
                15);

        HotelListing.PriceBreakdown breakdown = hotel.pricingFor(3);

        assertEquals(new BigDecimal("1260.00"), breakdown.subtotal());
        assertEquals(new BigDecimal("151.20"), breakdown.taxAndFees());
        assertEquals(new BigDecimal("1411.20"), breakdown.totalPrice());
        assertEquals(15, hotel.availableRooms());
    }

    @Test
    void pricingRejectsZeroOrNegativeNightCounts() {
        HotelListing hotel = new HotelListing(
                "hotel-1", "Hotel", "City", null, null, null, null,
                List.of(), "", BigDecimal.TEN, BigDecimal.valueOf(12), 0);

        assertThrows(IllegalArgumentException.class, () -> hotel.pricingFor(0));
    }
}

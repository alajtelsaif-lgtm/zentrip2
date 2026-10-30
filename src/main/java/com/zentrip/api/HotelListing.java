package com.zentrip.api;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;

public record HotelListing(
        String id,
        String name,
        String locationName,
        String googleMapsUrl,
        String placeId,
        BigDecimal googleRating,
        Integer googleReviewCount,
        List<String> amenities,
        String description,
        BigDecimal pricePerNight,
        BigDecimal taxAndFeesPercentage,
        int availableRooms) {

    public HotelListing {
        amenities = amenities == null ? List.of() : List.copyOf(amenities);
        pricePerNight = pricePerNight == null ? BigDecimal.ZERO : pricePerNight;
        taxAndFeesPercentage = taxAndFeesPercentage == null
                ? BigDecimal.valueOf(12) : taxAndFeesPercentage;
    }

    public PriceBreakdown pricingFor(int numberOfNights) {
        if (numberOfNights < 1) {
            throw new IllegalArgumentException("numberOfNights must be positive");
        }
        BigDecimal subtotal = pricePerNight
                .multiply(BigDecimal.valueOf(numberOfNights))
                .setScale(2, RoundingMode.HALF_UP);
        BigDecimal taxAndFees = subtotal
                .multiply(taxAndFeesPercentage)
                .divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
        return new PriceBreakdown(
                subtotal,
                taxAndFees,
                subtotal.add(taxAndFees).setScale(2, RoundingMode.HALF_UP));
    }

    public record PriceBreakdown(
            BigDecimal subtotal,
            BigDecimal taxAndFees,
            BigDecimal totalPrice) {}
}

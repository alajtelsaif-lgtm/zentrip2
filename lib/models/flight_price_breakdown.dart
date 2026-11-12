import 'flight_model.dart';

/// Search/summary estimate for a flight. Partner inventory uses Zentrip's
/// existing 12% tax and $12 service-fee rules; Duffel supplies a total quote
/// whose tax split is not available in the normalized offer.
class FlightPriceBreakdown {
  final double subtotal;
  final double? taxesAndFees;
  final double? serviceFee;
  final double total;
  final bool providerTotalIncludesFees;

  const FlightPriceBreakdown({
    required this.subtotal,
    required this.taxesAndFees,
    required this.serviceFee,
    required this.total,
    required this.providerTotalIncludesFees,
  });

  factory FlightPriceBreakdown.forSearch({
    required FlightModel flight,
    required int passengers,
    required String seatClass,
  }) {
    final quoted = flight.comparisonTotal(
      passengers: passengers,
      seatClass: seatClass,
    );
    if (quoted == null) {
      return const FlightPriceBreakdown(
        subtotal: 0,
        taxesAndFees: null,
        serviceFee: null,
        total: 0,
        providerTotalIncludesFees: false,
      );
    }
    if (flight.priceIsTotal) {
      return FlightPriceBreakdown(
        subtotal: quoted,
        taxesAndFees: null,
        serviceFee: null,
        total: quoted,
        providerTotalIncludesFees: true,
      );
    }
    final tax = quoted * 0.12;
    const serviceFee = 12.0;
    return FlightPriceBreakdown(
      subtotal: quoted,
      taxesAndFees: tax,
      serviceFee: serviceFee,
      total: quoted + tax + serviceFee,
      providerTotalIncludesFees: false,
    );
  }
}

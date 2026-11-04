import 'flight_model.dart';
import 'trip_model.dart';

class FlightBookingDraft {
  final FlightModel flight;
  final int passengerCount;
  final String seatClass;
  final List<String> seats;
  final DateTime? returnDate;
  final double totalPrice;
  final List<String> extras;
  final int? paymentAttemptId;

  const FlightBookingDraft({
    required this.flight,
    required this.passengerCount,
    required this.seatClass,
    required this.seats,
    required this.returnDate,
    required this.totalPrice,
    this.extras = const [],
    this.paymentAttemptId,
  });
}

class FlightBookingConfirmation {
  final TripModel trip;
  final String reference;
  final List<String> seats;
  final double totalPrice;
  final List<String> extras;

  const FlightBookingConfirmation({
    required this.trip,
    required this.reference,
    required this.seats,
    required this.totalPrice,
    this.extras = const [],
  });

  factory FlightBookingConfirmation.fromJson(Map<String, dynamic> json) {
    final booking = Map<String, dynamic>.from(json['booking'] as Map);
    final trip = TripModel.fromJson(
      Map<String, dynamic>.from(json['trip'] as Map),
    );
    final seats = booking['seats'];
    final extras = booking['extras'];
    return FlightBookingConfirmation(
      trip: trip,
      reference: (booking['reference'] ?? trip.bookingRef ?? '').toString(),
      seats: seats is List ? seats.map((seat) => seat.toString()).toList() : [],
      totalPrice: _doubleFromDynamic(booking['total_price'] ?? trip.price),
      extras: extras is List
          ? extras.map((extra) => extra.toString()).toList()
          : [],
    );
  }

  static double _doubleFromDynamic(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

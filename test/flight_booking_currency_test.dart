import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/models/trip_model.dart';

void main() {
  test('selected booking currency survives trip JSON round trips', () {
    final trip = TripModel.fromJson({
      'id': 17,
      'origin_code': 'MJI',
      'origin_city': 'Misrata',
      'destination_code': 'TUN',
      'destination_city': 'Tunis',
      'departure_date': '2026-12-01T10:00:00Z',
      'arrival_date': '2026-12-01T12:00:00Z',
      'flight_number': 'ZT123',
      'price': 100,
      'price_currency': 'USD',
      'booking_display_amount': '92.00',
      'booking_currency': 'EUR',
    });

    expect(trip.price, 100);
    expect(trip.priceCurrencyCode, 'USD');
    expect(trip.bookingDisplayAmount, 92);
    expect(trip.bookingCurrencyCode, 'EUR');

    final saved = trip.toJson();
    expect(saved['price'], 100);
    expect(saved['price_currency'], 'USD');
    expect(saved['booking_display_amount'], 92);
    expect(saved['booking_currency'], 'EUR');
  });
}

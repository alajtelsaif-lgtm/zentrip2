import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/models/flight_model.dart';

void main() {
  test('Duffel offers retain provider currency and unknown seat availability', () {
    final flight = FlightModel.fromJson({
      'id': 'duffel-off_example',
      'source': 'duffel',
      'duffel_offer_id': 'off_example',
      'airline': 'Example Air',
      'airline_code': 'EX',
      'flight_number': 'EX123',
      'origin_code': 'MJI',
      'origin_city': 'Misrata',
      'destination_code': 'TUN',
      'destination_city': 'Tunis',
      'departure_time': '2026-11-08T09:00:00',
      'arrival_time': '2026-11-08T11:15:00',
      'duration_minutes': 135,
      'is_direct': true,
      'stops': 0,
      'economy_price': 150.50,
      'price_currency': 'EUR',
      'price_is_total': true,
      'seats_available': -1,
      'partner_listing_id': null,
      'is_active': true,
      'aircraft_name': '',
      'seat_layout': '',
      'seat_rows': 0,
    });

    expect(flight.isDuffelOffer, isTrue);
    expect(flight.priceCurrencyCode, 'EUR');
    expect(flight.priceIsTotal, isTrue);
    expect(flight.seatsAvailable, -1);
    expect(flight.matchesSearch(
      originCode: 'MJI',
      destinationCode: 'TUN',
      originCity: 'Misrata',
      destinationCity: 'Tunis',
      departureDate: DateTime(2026, 11, 8),
      passengers: 2,
    ), isTrue);
  });
}

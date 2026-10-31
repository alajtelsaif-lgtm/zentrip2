import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/models/flight_seat_map.dart';

Map<String, dynamic> response({int seatsPerRow = 4}) => {
  'row_count': 4,
  'seat_letters': seatsPerRow == 4 ? ['A', 'B', 'C', 'D'] : ['A', 'B', 'C', 'D', 'E', 'F'],
  'occupied_seats': ['1A'],
  'extra_legroom_rows': [2],
  'fares': <Map<String, dynamic>>[
    {'id': 'economy', 'label': 'Economy', 'price': '138.25',
      'available_seats': 10, 'shared_inventory': true},
    {'id': 'business', 'label': 'Business', 'price': 331,
      'available_seats': 10, 'shared_inventory': true},
  ],
  'cabins': [
    {'id': '1', 'name': 'Forward cabin', 'rows': [1, 2],
      'total_seats': seatsPerRow * 2, 'available_seats': seatsPerRow * 2 - 1},
    {'id': '2', 'name': 'Rear cabin', 'rows': [3, 4],
      'total_seats': seatsPerRow * 2, 'available_seats': seatsPerRow * 2},
  ],
  'pricing': {
    'extra_legroom_fee': 15, 'tax_rate': .12, 'booking_fee': 12,
    'extras': {'extra_baggage': 18, 'flexible_ticket': 12},
  },
};

void main() {
  test('parses API fares, pricing, actual cabin rows and both aircraft layouts', () {
    for (final seats in [4, 6]) {
      final map = FlightSeatMap.fromJson(response(seatsPerRow: seats));
      expect(map.seatLetters.length, seats);
      expect(map.fares.first.price, 138.25);
      expect(map.fares.last.id, 'business');
      expect(map.fares.first.sharedInventory, isTrue);
      expect(map.cabins.last.rows, [3, 4]);
      expect(map.cabins.first.totalSeats, seats * 2);
      expect(map.occupiedSeats, {'1A'});
      expect(map.extraLegroomRows, {2});
      expect(map.taxRate, .12);
      expect(map.extraLegroomFee, 15);
      expect(map.extras['extra_baggage'], 18);
    }
  });

  test('missing inventory data is an error, never a fabricated default', () {
    for (final key in ['row_count', 'seat_letters', 'fares', 'cabins', 'pricing', 'occupied_seats']) {
      final data = response()..remove(key);
      expect(() => FlightSeatMap.fromJson(data), throwsFormatException);
    }
  });

  test('rejects negative, nonfinite and missing prices', () {
    for (final value in [-1, double.infinity, null, 'not a price', 0]) {
      final data = response();
      ((data['fares'] as List).first as Map)['price'] = value;
      expect(() => FlightSeatMap.fromJson(data), throwsFormatException);
    }
  });

  test('rejects overlapping, incomplete and impossible cabins', () {
    for (final rows in [[2, 3], [3], [3, 5]]) {
      final data = response();
      ((data['cabins'] as List).last as Map)['rows'] = rows;
      expect(() => FlightSeatMap.fromJson(data), throwsFormatException);
    }
    final data = response();
    ((data['cabins'] as List).first as Map)['available_seats'] = 100;
    expect(() => FlightSeatMap.fromJson(data), throwsFormatException);
  });

  test('rejects invalid letters, fractional rows and out-of-range premium rows', () {
    for (final entry in [
      const MapEntry('seat_letters', ['A', 'B', 'X', 'Y']),
      const MapEntry('row_count', 4.5),
      const MapEntry('extra_legroom_rows', [9]),
    ]) {
      final data = response()..[entry.key] = entry.value;
      expect(() => FlightSeatMap.fromJson(data), throwsFormatException);
    }
  });
}

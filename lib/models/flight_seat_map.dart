/// Live inventory and presentation configuration returned by the flight API.
class FlightSeatMap {
  final int rowCount;
  final List<String> seatLetters;
  final Set<int> extraLegroomRows;
  final Set<String> occupiedSeats;
  final List<FlightSeatFare> fares;
  final List<FlightSeatCabin> cabins;
  final double extraLegroomFee;
  final double taxRate;
  final double bookingFee;
  final Map<String, double> extras;

  const FlightSeatMap({
    required this.rowCount,
    required this.seatLetters,
    required this.extraLegroomRows,
    required this.occupiedSeats,
    required this.fares,
    required this.cabins,
    required this.extraLegroomFee,
    required this.taxRate,
    required this.bookingFee,
    required this.extras,
  });

  factory FlightSeatMap.fromJson(Map<String, dynamic> json) {
    final rows = _integer(json['row_count']);
    final letters = _list(json['seat_letters']).map((v) => v.toString()).toList();
    final fares = _list(json['fares'])
        .map((v) => FlightSeatFare.fromJson(_map(v))).toList();
    final cabins = _list(json['cabins'])
        .map((v) => FlightSeatCabin.fromJson(_map(v))).toList();
    final pricing = _map(json['pricing']);
    final extras = _map(pricing['extras']);
    final premiumRows = _list(json['extra_legroom_rows']).map(_integer).toSet();
    final assignedRows = cabins.expand((c) => c.rows).toList();
    final totalSeats = rows * letters.length;
    if (rows < 1 || rows > 30 ||
        ![4, 6].contains(letters.length) ||
        letters.toSet().length != letters.length ||
        letters.asMap().entries.any((v) => v.value != 'ABCDEF'[v.key]) ||
        fares.isEmpty || cabins.isEmpty ||
        fares.map((v) => v.id).toSet().length != fares.length ||
        cabins.map((v) => v.id).toSet().length != cabins.length ||
        assignedRows.length != rows || assignedRows.toSet().length != rows ||
        premiumRows.any((row) => row < 1 || row > rows) ||
        fares.any((v) => v.availableSeats > totalSeats) ||
        cabins.any((c) => c.rows.isEmpty ||
            c.rows.any((row) => row < 1 || row > rows) ||
            c.totalSeats != c.rows.length * letters.length ||
            c.availableSeats > c.totalSeats)) {
      throw const FormatException('Invalid flight seat configuration');
    }
    return FlightSeatMap(
      rowCount: rows,
      seatLetters: letters,
      extraLegroomRows: premiumRows,
      occupiedSeats: _list(json['occupied_seats']).map((v) => v.toString()).toSet(),
      fares: fares,
      cabins: cabins,
      extraLegroomFee: _number(pricing['extra_legroom_fee']),
      taxRate: _number(pricing['tax_rate']),
      bookingFee: _number(pricing['booking_fee']),
      extras: extras.map((key, value) => MapEntry(key, _number(value))),
    );
  }
}

class FlightSeatFare {
  final String id;
  final String label;
  final double price;
  final int availableSeats;
  final bool sharedInventory;

  const FlightSeatFare({
    required this.id,
    required this.label,
    required this.price,
    required this.availableSeats,
    required this.sharedInventory,
  });

  factory FlightSeatFare.fromJson(Map<String, dynamic> json) => FlightSeatFare(
    id: _text(json['id']),
    label: _text(json['label']),
    price: _positivePrice(json['price']),
    availableSeats: _integer(json['available_seats']),
    sharedInventory: json['shared_inventory'] == true,
  );
}

class FlightSeatCabin {
  final String id;
  final String name;
  final List<int> rows;
  final int totalSeats;
  final int availableSeats;

  const FlightSeatCabin({
    required this.id,
    required this.name,
    required this.rows,
    required this.totalSeats,
    required this.availableSeats,
  });

  factory FlightSeatCabin.fromJson(Map<String, dynamic> json) => FlightSeatCabin(
    id: _text(json['id']),
    name: _text(json['name']),
    rows: _list(json['rows']).map(_integer).toList(),
    totalSeats: _integer(json['total_seats']),
    availableSeats: _integer(json['available_seats']),
  );
}

Map<String, dynamic> _map(dynamic value) {
  if (value is! Map) throw const FormatException('Invalid flight seat response');
  return Map<String, dynamic>.from(value);
}

List<dynamic> _list(dynamic value) {
  if (value is! List) throw const FormatException('Invalid flight seat response');
  return value;
}

double _number(dynamic value) {
  final result = value is num ? value.toDouble() : double.tryParse('$value');
  if (result == null || !result.isFinite || result < 0) {
    throw const FormatException('Invalid flight seat pricing');
  }
  return result;
}

int _integer(dynamic value) {
  final result = value is num ? value.toInt() : int.tryParse('$value');
  if (result == null || result < 0 || (value is num && value != result)) {
    throw const FormatException('Invalid flight seat count');
  }
  return result;
}

String _text(dynamic value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Missing flight seat details');
  }
  return value;
}

double _positivePrice(dynamic value) {
  final result = _number(value);
  if (result <= 0) throw const FormatException('Invalid flight fare');
  return result;
}

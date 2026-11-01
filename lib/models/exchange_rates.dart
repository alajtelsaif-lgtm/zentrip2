/// Reference rates only. Never write converted amounts back to provider models.
class ExchangeRate {
  final double unitsPerUsd;
  final DateTime date;

  const ExchangeRate(this.unitsPerUsd, this.date);
}

class ExchangeRates {
  final Map<String, ExchangeRate> rates;
  final DateTime fetchedAt;
  final bool refreshFailed;

  ExchangeRates({
    required Map<String, ExchangeRate> rates,
    required this.fetchedAt,
    this.refreshFailed = false,
  }) : rates = Map.unmodifiable(rates);

  factory ExchangeRates.fromJson(Map<String, dynamic> json) {
    if (json['base'] != 'USD') {
      throw const FormatException('Expected USD reference rates');
    }
    final rates = <String, ExchangeRate>{};
    for (final row in json['rates'] as List) {
      final code = row['quote']?.toString().trim().toUpperCase() ?? '';
      final rate = double.tryParse('${row['rate']}');
      final date = DateTime.tryParse('${row['date']}');
      if (RegExp(r'^[A-Z]{3}$').hasMatch(code) &&
          rate != null &&
          rate.isFinite &&
          rate > 0 &&
          date != null) {
        // Publication dates are UTC calendar dates, not the device's midnight.
        rates[code] = ExchangeRate(
          rate,
          DateTime.utc(date.year, date.month, date.day),
        );
      }
    }
    return ExchangeRates(
      rates: rates,
      fetchedAt: DateTime.parse(json['fetched_at'] as String).toUtc(),
      refreshFailed: json['refresh_failed'] == true,
    );
  }

  ExchangeRate? _usable(String code, DateTime now) {
    if (code == 'USD') return ExchangeRate(1, now);
    final rate = rates[code];
    if (rate == null ||
        rate.date.isAfter(now) ||
        now.difference(rate.date) > const Duration(days: 7)) {
      return null;
    }
    return rate;
  }

  double? convert(double amount, String from, String to, DateTime now) {
    if (!amount.isFinite || amount < 0) return null;
    if (from == to) return amount;
    final source = _usable(from, now);
    final target = _usable(to, now);
    if (source == null || target == null) return null;
    final converted = amount / source.unitsPerUsd * target.unitsPerUsd;
    return converted.isFinite ? converted : null;
  }

  DateTime? oldestDate(Iterable<String> currencies, DateTime now) {
    final dates = currencies
        .toSet()
        .where((c) => c != 'USD')
        .map((c) => _usable(c, now)?.date)
        .whereType<DateTime>()
        .toList()
      ..sort();
    return dates.isEmpty ? null : dates.first;
  }
}

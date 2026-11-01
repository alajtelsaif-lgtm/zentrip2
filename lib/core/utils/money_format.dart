import 'package:intl/intl.dart';

/// ISO currency minor units (e.g. LYD/TND 3, USD/EUR 2, JPY 0).
/// Comparison calculations must use unrounded amounts, not this display value.
String formatProviderMoney(double amount, String currency) {
  final normalized = currency.trim().toUpperCase();
  final digits =
      NumberFormat.simpleCurrency(name: normalized).decimalDigits ?? 2;
  const symbols = {'USD': '\$', 'EUR': '€', 'GBP': '£'};
  final symbol = symbols[normalized];
  final formatted = amount.toStringAsFixed(digits);
  return symbol == null ? '$normalized $formatted' : '$symbol$formatted';
}

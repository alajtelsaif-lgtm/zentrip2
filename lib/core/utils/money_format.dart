import 'package:intl/intl.dart';

/// ISO currency minor units (e.g. LYD/TND 3, USD/EUR 2, JPY 0).
/// Comparison calculations must use unrounded amounts, not this display value.
String formatProviderMoney(double amount, String currency) {
  final digits = NumberFormat.simpleCurrency(name: currency).decimalDigits ?? 2;
  return '$currency ${amount.toStringAsFixed(digits)}';
}

import 'package:intl/intl.dart';

/// ISO currency minor units (e.g. LYD/TND 3, USD/EUR 2, JPY 0).
/// Comparison calculations must use unrounded amounts, not this display value.
int currencyDecimalDigits(String currency) {
  final normalized = currency.trim().toUpperCase();
  return switch (normalized) {
    'LYD' || 'TND' => 3,
    'JPY' || 'KRW' => 0,
    _ => NumberFormat.simpleCurrency(name: normalized).decimalDigits ?? 2,
  };
}

String currencySymbolFor(String currency, {String locale = 'en'}) {
  final normalized = currency.trim().toUpperCase();
  return switch (normalized) {
    'USD' => '\$',
    'EUR' => '€',
    'GBP' => '£',
    'LYD' => locale.toLowerCase().startsWith('ar') ? 'د.ل' : 'LYD',
    _ => normalized,
  };
}

String currencySelectionLabel(String currency, {String locale = 'en'}) {
  return currency.trim().toUpperCase();
}

String formatCurrencyAmount(
  double amount,
  String currency, {
  String locale = 'en',
  int? decimalDigits,
}) {
  if (!amount.isFinite) return '—';
  final normalized = currency.trim().toUpperCase();
  final digits = decimalDigits ?? currencyDecimalDigits(normalized);
  final formatted = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: digits,
  ).format(amount);
  final symbol = currencySymbolFor(normalized, locale: locale);
  if (const {'USD', 'EUR', 'GBP'}.contains(normalized)) {
    return '$symbol$formatted';
  }
  if (normalized == 'LYD' && locale.toLowerCase().startsWith('ar')) {
    return '$formatted $symbol';
  }
  return '$symbol $formatted';
}

String formatProviderMoney(
  double amount,
  String currency, {
  String locale = 'en',
}) {
  return formatCurrencyAmount(amount, currency, locale: locale);
}

/// Formats a booked amount with its persisted ISO currency code. LYD uses its
/// localized code/symbol so the Libyan Dinar remains clear in RTL layouts.
String formatBookingCurrencyAmount(
  double amount,
  String currency, {
  String locale = 'en',
  int? decimalDigits,
}) {
  final normalized = currency.trim().toUpperCase();
  if (normalized == 'LYD') {
    return formatCurrencyAmount(
      amount,
      normalized,
      locale: locale,
      decimalDigits: decimalDigits,
    );
  }
  final digits = decimalDigits ?? currencyDecimalDigits(normalized);
  final formatted = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: digits,
  ).format(amount);
  return '$normalized $formatted';
}

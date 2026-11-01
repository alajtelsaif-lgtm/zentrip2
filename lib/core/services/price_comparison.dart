import 'package:flutter/foundation.dart';
import '../../models/exchange_rates.dart';

/// Shared by result controllers; no booking or settlement code depends on this.
class PriceComparison extends ChangeNotifier {
  static const List<String> supportedCurrencies = ['USD', 'EUR', 'GBP'];

  final Future<ExchangeRates> Function() loadRates;
  final DateTime Function() clock;
  ExchangeRates? rates;
  String currency = 'USD';
  bool isLoading = false;
  bool failed = false;
  bool _disposed = false;

  PriceComparison({required this.loadRates, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  Future<void> refresh() async {
    if (isLoading || _disposed) return;
    isLoading = true;
    notifyListeners();
    try {
      final updated = await loadRates();
      if (_disposed) return;
      rates = updated;
      failed = updated.refreshFailed;
    } catch (_) {
      if (_disposed) return;
      failed = true;
    } finally {
      if (!_disposed) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  void setCurrency(String value) {
    final normalized = value.trim().toUpperCase();
    if (!supportedCurrencies.contains(normalized)) {
      throw ArgumentError.value(value, 'currency', 'Unsupported currency');
    }
    if (currency == normalized) return;
    currency = normalized;
    notifyListeners();
  }

  List<String> get currencies => supportedCurrencies;

  double? convert(double amount, String from) {
    if (!amount.isFinite || amount < 0) return null;
    if (from == currency) return amount;
    return rates?.convert(amount, from, currency, clock().toUtc());
  }

  /// Unknown prices always go last, even in descending order.
  int compare(double? a, double? b, {bool descending = false}) {
    if (a == null) return b == null ? 0 : 1;
    if (b == null) return -1;
    return descending ? b.compareTo(a) : a.compareTo(b);
  }

  DateTime? oldestDate(Iterable<String> sources) =>
      rates?.oldestDate([...sources, currency], clock().toUtc());

  bool isStale(Iterable<String> sources) {
    final date = oldestDate(sources);
    return date != null &&
        clock().toUtc().difference(date) > const Duration(days: 4);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

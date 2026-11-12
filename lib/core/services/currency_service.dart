import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// تحويل وعرض الأسعار بعملات متعددة. كل الأسعار في التطبيق (Flight/Hotel/
/// Car/Package/BookingModel) متخزنة بالدولار (USD) كوحدة أساسية داخلية،
/// وده بيتحوّل للعرض بس حسب العملة المختارة.
class Currency {
  final String code; // ISO 4217
  final String symbol;
  final String nameAr;
  const Currency(this.code, this.symbol, this.nameAr);
}

class CurrencyService extends ChangeNotifier {
  static final CurrencyService instance = CurrencyService._();
  CurrencyService._();

  static const List<Currency> supported = [
    Currency('USD', '\$', 'دولار أمريكي'),
    Currency('EUR', '€', 'يورو'),
    Currency('GBP', '£', 'جنيه إسترليني'),
  ];

  /// Fallback quotes are used only when the cached Frankfurter service cannot
  /// provide a current rate. They are indicative, not settlement rates.
  static const _fallbackRates = {
    'USD': 1.0,
    'EUR': 0.92,
    'GBP': 0.79,
  };
  static const _prefsKey = 'selected_currency';

  Currency _selected = supported.first;
  Currency get selected => _selected;

  Map<String, double> _rates = Map.of(_fallbackRates);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(_prefsKey);
    if (savedCode != null) {
      _selected = supported.firstWhere((c) => c.code == savedCode,
          orElse: () => supported.first);
    }
    await _loadRates();
  }

  Future<void> _loadRates() async {
    try {
      final latest = await ApiService.instance.exchangeRates();
      final liveRates = <String, double>{'USD': 1};
      for (final entry in latest.rates.entries) {
        liveRates[entry.key] = entry.value.unitsPerUsd;
      }
      _rates = liveRates;
    } catch (_) {
      _rates = Map.of(_fallbackRates);
    }
    notifyListeners();
  }

  Future<void> selectCode(String code) async {
    final normalized = code.trim().toUpperCase();
    final currency = supported.firstWhere(
      (item) => item.code == normalized,
      orElse: () => throw ArgumentError.value(code, 'currency'),
    );
    await setCurrency(currency);
  }

  Future<void> setCurrency(Currency c) async {
    if (!supported.any((currency) => currency.code == c.code)) {
      throw ArgumentError.value(c.code, 'currency', 'Unsupported currency');
    }
    _selected = c;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, c.code);
  }

  double convert(double usdAmount) =>
      usdAmount * (_rates[_selected.code] ?? 1.0);

  /// بيرجّع السعر جاهز للعرض بالعملة المختارة (مثال: "235 د.ل").
  String format(double usdAmount) {
    final converted = convert(usdAmount);
    final formatted = converted >= 100
        ? converted.toStringAsFixed(0)
        : converted.toStringAsFixed(2);
    return '$formatted ${_selected.symbol}';
  }
}

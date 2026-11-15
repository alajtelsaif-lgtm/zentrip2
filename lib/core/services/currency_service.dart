import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/currency_rates.dart';
import 'api_service.dart';
import 'user_settings_sync.dart';
import '../utils/money_format.dart';

/// تحويل وعرض الأسعار بعملات متعددة. كل الأسعار في التطبيق (Flight/Hotel/
/// Car/Package/BookingModel) متخزنة بالدولار (USD) كوحدة أساسية داخلية،
/// وده بيتحوّل للعرض بس حسب العملة المختارة.
class Currency {
  final String code; // ISO 4217
  final String symbol;
  final String nameAr;
  final String nameEn;
  const Currency(this.code, this.symbol, this.nameAr, this.nameEn);
}

class CurrencyService extends ChangeNotifier {
  static final CurrencyService instance = CurrencyService._();
  CurrencyService._();

  static const List<Currency> supported = [
    Currency('USD', '\$', 'دولار أمريكي', 'US Dollar'),
    Currency('EUR', '€', 'يورو', 'Euro'),
    Currency('GBP', '£', 'جنيه إسترليني', 'British Pound'),
    Currency('LYD', 'د.ل', 'دينار ليبي', 'Libyan Dinar'),
  ];

  /// Fallback quotes are used only when the cached Frankfurter service cannot
  /// provide a current rate. They are indicative, not settlement rates.
  static const _fallbackRates = {
    'USD': 1.0,
    'EUR': 0.92,
    'GBP': 0.79,
    'LYD': usdToLydRate,
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
      final liveRates = Map<String, double>.of(_fallbackRates);
      for (final entry in latest.rates.entries) {
        if (entry.key != 'LYD') {
          liveRates[entry.key] = entry.value.unitsPerUsd;
        }
      }
      liveRates['LYD'] = usdToLydRate;
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
    await UserSettingsSync.instance.push({'currency': c.code});
  }

  double? convertFrom(double amount, String sourceCurrencyCode) {
    if (!amount.isFinite || amount < 0) return null;
    final source = sourceCurrencyCode.trim().toUpperCase();
    final target = _selected.code;
    if (source == target) return amount;
    final sourceRate = _rates[source] ?? _fallbackRates[source];
    final targetRate = _rates[target] ?? _fallbackRates[target];
    if (sourceRate == null || targetRate == null) return null;
    return amount / sourceRate * targetRate;
  }

  /// Converts between reference currencies without changing stored or charged
  /// amounts. Rates are expressed as units per USD, so USD remains the pivot.
  double? convertTo(
    double amount,
    String sourceCurrencyCode,
    String targetCurrencyCode,
  ) {
    if (!amount.isFinite || amount < 0) return null;
    final source = sourceCurrencyCode.trim().toUpperCase();
    final target = targetCurrencyCode.trim().toUpperCase();
    final sourceRate = _rates[source];
    final targetRate = _rates[target];
    if (sourceRate == null || targetRate == null || sourceRate <= 0) {
      return null;
    }
    return amount / sourceRate * targetRate;
  }

  double convert(double usdAmount) =>
      convertFrom(usdAmount, 'USD') ?? usdAmount;

  /// بيرجّع السعر جاهز للعرض بالعملة المختارة (مثال: "235 د.ل").
  String format(double usdAmount, {String locale = 'en'}) =>
      formatCurrencyAmount(convert(usdAmount), _selected.code, locale: locale);
}

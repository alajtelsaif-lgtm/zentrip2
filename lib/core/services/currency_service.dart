import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// دفتر أسعار الصرف — 1 USD = كام من العملة دي. لوضع المحاكاة بس؛ الأسعار
  /// الحقيقية بتتغيّر يوميًا فمحتاجة مصدر حي (exchangerate-api.com مثلاً).
  static const bool useMockMode = true;
  static const _mockRates = {
    'USD': 1.0,
    'EUR': 0.92,
    'GBP': 0.79,
  };
  static const _prefsKey = 'selected_currency';

  Currency _selected = supported.first;
  Currency get selected => _selected;

  Map<String, double> _rates = Map.of(_mockRates);

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
    if (useMockMode) {
      _rates = Map.of(_mockRates);
      notifyListeners();
      return;
    }
    // TODO: عند التفعيل — نداء حقيقي لـ exchangerate-api.com أو مصدر مماثل،
    // وتحديث _rates بالأسعار الحية، مع الاحتفاظ بـ _mockRates كـ fallback
    // لو النداء فشل (مفيش إنترنت مثلاً).
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

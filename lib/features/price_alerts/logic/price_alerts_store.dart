import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/utils/money_format.dart';
import '../../../core/services/api_service.dart';
import '../../../features/notifications/logic/notifications_store.dart';
import '../../../global_widgets/locale_controller.dart';
import '../../../models/flight_model.dart';
import '../../../models/price_alert_model.dart';

/// تتبّع أسعار رحلات محددة — ولو السعر نزل عن آخر سعر شفناه، بيولّد إشعار
/// حقيقي (عن طريق NotificationsStore) بدل ما يفضل المستخدم يفتح ويقارن بنفسه.
class PriceAlertsStore extends ChangeNotifier {
  static final PriceAlertsStore instance = PriceAlertsStore._();
  PriceAlertsStore._();

  final List<PriceAlert> _alerts = [];
  List<PriceAlert> get all => List.unmodifiable(_alerts);

  String get _key =>
      'price_alerts_${ApiService.instance.currentUser?.email ?? 'guest'}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool isTracking(
          String originCode, String destinationCode, DateTime departureDate) =>
      _alerts.any((a) =>
          a.originCode == originCode &&
          a.destinationCode == destinationCode &&
          _sameDay(a.departureDate, departureDate));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    _alerts
      ..clear()
      ..addAll(raw.map(
          (e) => PriceAlert.fromJson(jsonDecode(e) as Map<String, dynamic>)));
    notifyListeners();
  }

  void clear() {
    _alerts.clear();
    notifyListeners();
  }

  Future<void> track({
    required String originCode,
    required String destinationCode,
    required DateTime departureDate,
    required double priceUsd,
  }) async {
    if (isTracking(originCode, destinationCode, departureDate)) return;
    _alerts.insert(
        0,
        PriceAlert(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          originCode: originCode,
          destinationCode: destinationCode,
          departureDate: departureDate,
          referencePriceUsd: priceUsd,
          createdAt: DateTime.now(),
        ));
    notifyListeners();
    await _persist();
  }

  Future<void> untrack(
      String originCode, String destinationCode, DateTime departureDate) async {
    _alerts.removeWhere((a) =>
        a.originCode == originCode &&
        a.destinationCode == destinationCode &&
        _sameDay(a.departureDate, departureDate));
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    _alerts.removeWhere((a) => a.id == id);
    notifyListeners();
    await _persist();
  }

  /// بتتنادى بعد كل نتيجة بحث رحلات جديدة — بتقارن بالتنبيهات المسجّلة،
  /// ولو لقت سعر أقل من آخر سعر مسجّل، بتولّد إشعار وتحدّث السعر المرجعي.
  Future<void> checkResults(List<FlightModel> results,
      {required String promoTitle}) async {
    var changed = false;
    for (final flight in results) {
      final idx = _alerts.indexWhere((a) =>
          a.originCode == flight.originCode &&
          a.destinationCode == flight.destinationCode &&
          _sameDay(a.departureDate, flight.departureTime));
      if (idx == -1) continue;
      final alert = _alerts[idx];
      final priceUsd = CurrencyService.instance.convertTo(
        flight.economyPrice,
        flight.priceCurrencyCode,
        'USD',
      );
      if (priceUsd != null && priceUsd < alert.referencePriceUsd) {
        final locale = LocaleController.instance.locale.languageCode;
        final converted = CurrencyService.instance.convertFrom(priceUsd, 'USD');
        final formattedPrice = converted == null
            ? formatProviderMoney(
                priceUsd,
                'USD',
                locale: locale,
              )
            : CurrencyService.instance.format(converted, locale: locale);
        await NotificationsStore.instance.add(
          kind: NotifKind.promo,
          title: promoTitle,
          subtitle:
              '${flight.originCode} → ${flight.destinationCode}: $formattedPrice',
        );
        _alerts[idx] = alert.copyWith(referencePriceUsd: priceUsd);
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      await _persist();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, _alerts.map((a) => jsonEncode(a.toJson())).toList());
  }
}

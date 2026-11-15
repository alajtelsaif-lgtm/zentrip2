
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/core/services/price_comparison.dart';
import 'package:zentrip/features/hotel_booking/logic/hotel_controller.dart';
import 'package:zentrip/features/hotel_booking/presentation/screens/hotel_results_screen.dart';
import 'package:zentrip/global_widgets/price_comparison_controls.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/models/exchange_rates.dart';
import 'package:zentrip/models/hotel_model.dart';

final _now = DateTime.utc(2026, 11, 1, 12);
PriceComparison _comparison({bool fail = false}) => PriceComparison(
      clock: () => _now,
      loadRates: () async {
        if (fail) throw StateError('offline');
        return ExchangeRates(
          fetchedAt: _now,
          rates: {'EUR': ExchangeRate(0.5, _now)},
        );
      },
    );

Widget _app(Widget child, Object controller, Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        settings: RouteSettings(arguments: controller),
        builder: (_) => child,
      ),
    );

void main() {
  for (final locale in [const Locale('en'), const Locale('ar')]) {
    testWidgets(
        'hotel failed-rate and empty-budget recovery at 360px ${locale.languageCode}',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ctrl = HotelController(
        comparison: _comparison(fail: true),
        searchHotels: (_) async => [
          HotelModel.fromJson({
            'id': 'duffel-1',
            'name': 'Example Hotel',
            'source': 'duffel',
            'price_currency': 'EUR',
            'price_per_night': 50,
            'location_name': 'A very long street address in Tunis, Tunisia',
          })
        ],
      );
      await ctrl.search(HotelSearchParams(
          city: 'Tunis',
          checkIn: _now,
          checkOut: _now.add(const Duration(days: 2))));
      ctrl.setFilter(HotelFilter.budget);
      await tester.pumpWidget(_app(const HotelResultsScreen(), ctrl, locale));
      await tester.pumpAndSettle();
      // The fallback comparison rate keeps the hotel filterable during outage.
      expect(ctrl.results.length, 1);
      expect(find.byType(PriceComparisonControls), findsOneWidget);
      expect(tester.takeException(), isNull);
      final l10n = AppLocalizations.of(
          tester.element(find.byType(PriceComparisonControls)));
      expect(find.text(l10n.retryRates), findsOneWidget);
      // Same-currency prices remain comparable even while the rate service is down.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EUR').last);
      await tester.pumpAndSettle();
      expect(ctrl.results.length, 1);
      expect(find.textContaining('€50.00'), findsWidgets);
      expect(tester.takeException(), isNull);
      ctrl.dispose();
    });
  }

  testWidgets('invalid budget does not silently remove an active filter',
      (tester) async {
    final c = _comparison();
    double? budget = 100;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: PriceComparisonControls(
        comparison: c,
        sourceCurrencies: const ['EUR'],
        unpricedCount: 0,
        showBudget: true,
        budget: budget,
        onBudgetChanged: (value) => budget = value,
      )),
    ));
    await tester.enterText(find.byType(TextFormField), '-20');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(budget, 100);
    expect(find.text('Enter a valid amount ≥0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    c.dispose();
  });

  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets(
        'hotel empty search shows localized retry ${locale.languageCode}',
        (tester) async {
      final ctrl = HotelController(
        comparison: _comparison(),
        searchHotels: (_) async => <HotelModel>[],
      );
      await ctrl.search(HotelSearchParams(
        city: 'Paris',
        checkIn: _now,
        checkOut: _now.add(const Duration(days: 2)),
      ));
      await tester.pumpWidget(_app(const HotelResultsScreen(), ctrl, locale));
      await tester.pumpAndSettle();

      final l10n =
          AppLocalizations.of(tester.element(find.byType(HotelResultsScreen)));
      expect(find.text(l10n.hotelNoResults), findsOneWidget);
      expect(find.text(l10n.tryAgain), findsOneWidget);
      expect(tester.takeException(), isNull);
      ctrl.dispose();
    });

    testWidgets(
        'hotel provider error clears results and shows localized retry '
        '${locale.languageCode}', (tester) async {
      var attempts = 0;
      final ctrl = HotelController(
        comparison: _comparison(),
        searchHotels: (_) async {
          attempts++;
          if (attempts == 1) {
            return [
              HotelModel.fromJson({
                'id': 'stale-paris',
                'name': 'Stale Paris Hotel',
                'source': 'liteapi',
                'price_per_night': 90,
              }),
            ];
          }
          throw StateError('provider unavailable');
        },
      );
      await ctrl.search(HotelSearchParams(
        city: 'Paris',
        checkIn: _now,
        checkOut: _now.add(const Duration(days: 2)),
      ));
      expect(ctrl.results, hasLength(1));
      await ctrl.search(HotelSearchParams(
        city: 'Dubai',
        checkIn: _now,
        checkOut: _now.add(const Duration(days: 2)),
      ));
      await tester.pumpWidget(_app(const HotelResultsScreen(), ctrl, locale));
      await tester.pumpAndSettle();

      final l10n =
          AppLocalizations.of(tester.element(find.byType(HotelResultsScreen)));
      expect(ctrl.results, isEmpty);
      expect(ctrl.hasSearchError, isTrue);
      expect(find.text(l10n.hotelSearchUnavailable), findsOneWidget);
      expect(find.text('Stale Paris Hotel'), findsNothing);
      expect(find.text(l10n.tryAgain), findsOneWidget);
      expect(tester.takeException(), isNull);
      ctrl.dispose();
    });
  }
}

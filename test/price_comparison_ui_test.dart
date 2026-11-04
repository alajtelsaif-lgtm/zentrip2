import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/core/services/price_comparison.dart';
import 'package:zentrip/features/flight_booking/logic/flight_controller.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/flight_results_screen.dart';
import 'package:zentrip/features/hotel_booking/logic/hotel_controller.dart';
import 'package:zentrip/features/hotel_booking/presentation/screens/hotel_results_screen.dart';
import 'package:zentrip/global_widgets/price_comparison_controls.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/models/exchange_rates.dart';
import 'package:zentrip/models/flight_model.dart';
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
  testWidgets('flexible search keeps its loading notice and currency controls',
      (tester) async {
    final pending = Completer<List<FlightModel>>();
    FlightSearchParams? received;
    final ctrl = FlightController(
      comparison: _comparison(),
      searchFlights: (params) {
        received = params;
        return pending.future;
      },
    );
    final params = FlightSearchParams(
      originCode: 'MJI',
      originCity: 'Misrata',
      destinationCode: 'TUN',
      destinationCity: 'Tunis',
      departureDate: _now,
      flexibleDepartureMonths: [DateTime(2026, 11), DateTime(2026, 12)],
      flexibleTripDurationDays: 10,
      flexibleWeekendsOnly: true,
    );
    final search = ctrl.search(params);
    await tester.pumpWidget(
        _app(const FlightResultsScreen(), ctrl, const Locale('en')));
    await tester.pump();
    final l10n = AppLocalizations.of(
        tester.element(find.byType(PriceComparisonControls)));
    expect(find.text(l10n.flightFlexibleSearchLoading), findsOneWidget);
    expect(find.byType(PriceComparisonControls), findsOneWidget);
    expect(received?.flexibleDepartureMonths, params.flexibleDepartureMonths);
    expect(received?.flexibleTripDurationDays, 10);
    expect(received?.flexibleWeekendsOnly, isTrue);
    expect(tester.takeException(), isNull);
    pending.complete([]);
    await search;
    await tester.pumpAndSettle();
    expect(find.text(l10n.flightFlexibleSearchLoading), findsNothing);
    expect(find.byType(PriceComparisonControls), findsOneWidget);
    ctrl.dispose();
  });

  for (final locale in [const Locale('en'), const Locale('ar')]) {
    testWidgets(
        'flight currency and budget controls remain usable at 360px ${locale.languageCode}',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ctrl = FlightController(
        comparison: _comparison(),
        searchFlights: (_) async => [
          FlightModel.fromJson({
            'id': 'duffel-1',
            'source': 'duffel',
            'airline': 'Example Air',
            'economy_price': 75.25,
            'price_currency': 'EUR',
            'price_is_total': true,
            'seats_available': -1,
            'departure_time': '2026-11-05T09:00:00',
            'arrival_time': '2026-11-05T11:00:00',
          })
        ],
      );
      await ctrl.search(FlightSearchParams(
        originCode: 'MJI',
        originCity: 'Misrata',
        destinationCode: 'TUN',
        destinationCity: 'Tunis',
        departureDate: _now,
        passengers: 2,
      ));
      await tester.pumpWidget(_app(const FlightResultsScreen(), ctrl, locale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final l10n = AppLocalizations.of(
          tester.element(find.byType(PriceComparisonControls)));
      final budget = find.byType(TextFormField);
      await tester.enterText(budget, '100');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(ctrl.results, isEmpty);
      expect(find.byType(PriceComparisonControls), findsOneWidget);
      await tester.tap(find.byTooltip(l10n.clearBudget));
      await tester.pumpAndSettle();
      expect(ctrl.results.length, 1);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EUR').last);
      await tester.pumpAndSettle();
      expect(ctrl.comparison.currency, 'EUR');
      expect(ctrl.comparisonPrice(ctrl.results.single), 75.25);
      expect(tester.takeException(), isNull);
      // The card is below the route header on narrow screens.
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(find.text('€75.25'), findsOneWidget);
      final selectFlight = find.ancestor(
        of: find.text(l10n.flightSelectThis),
        matching: find.byType(ElevatedButton),
      );
      expect(tester.widget<ElevatedButton>(selectFlight).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      ctrl.dispose();
    });

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
      expect(ctrl.results, isEmpty);
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/features/flight_booking/logic/flight_controller.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/search_flight_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/models/flight_model.dart';
import 'package:zentrip/routes/app_routes.dart';

void main() {
  testWidgets('renders the route header, seven dates, and ticket data',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    final controller = _loadedController();
    addTearDown(() {
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_app(
      SearchFlightScreen(controller: controller),
      routes: {
        AppRoutes.flightBooking: (_) =>
            const Scaffold(body: Text('Choose fare route')),
      },
    ));
    await tester.pumpAndSettle();

    expect(find.text('Select Flight'), findsOneWidget);
    expect(find.text('MJI'), findsWidgets);
    expect(find.text('CAI'), findsWidgets);
    expect(find.text('Flight Date'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('1 airline'), findsOneWidget);
    expect(find.text('Economy'), findsNWidgets(2));
    expect(find.text('Zentrip Air'), findsOneWidget);
    expect(find.text('ZA 204'), findsOneWidget);
    expect(find.text('FLIGHT NUMBER'), findsOneWidget);
    expect(find.text('CLASS'), findsOneWidget);
    expect(find.text('SEATS'), findsOneWidget);
    expect(find.text('\$146.40'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('flight-date-2026-11-18')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Zentrip Air'));
    await tester.pumpAndSettle();
    expect(controller.selectedFlight?.id, 'flight-1');
    expect(find.text('Choose fare route'), findsOneWidget);
  });

  testWidgets('shows skeleton tickets while a search is pending',
      (tester) async {
    final pendingSearch = Completer<List<FlightModel>>();
    final controller = FlightController(
      searchFlights: (_) => pendingSearch.future,
    )..searchParams = _params();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(SearchFlightScreen(controller: controller)),
    );
    await tester.pump();

    expect(
        find.byKey(const ValueKey('flight-loading-skeletons')), findsOneWidget);
    expect(tester.takeException(), isNull);

    pendingSearch.complete(const []);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('shows a retry message when the flight provider fails',
      (tester) async {
    final controller = FlightController(
      searchFlights: (_) async => throw StateError('provider unavailable'),
    )..searchParams = _params();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _app(SearchFlightScreen(controller: controller)),
    );
    await tester.pump();
    await tester.pump();

    expect(
        find.text(
            'Live flight search is temporarily unavailable. Please try again.'),
        findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out flight results in Arabic RTL on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    final controller = _loadedController();
    addTearDown(() {
      controller.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_app(
      SearchFlightScreen(controller: controller),
      locale: const Locale('ar'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('اختر الرحلة'), findsOneWidget);
    expect(find.textContaining('شركة طيران'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

MaterialApp _app(
  Widget home, {
  Locale locale = const Locale('en'),
  Map<String, WidgetBuilder> routes = const {},
}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routes: routes,
      home: home,
    );

FlightSearchParams _params() => FlightSearchParams(
      originCode: 'MJI',
      originCity: 'Tripoli',
      destinationCode: 'CAI',
      destinationCity: 'Cairo',
      departureDate: DateTime(2026, 11, 12),
      passengers: 1,
      seatClass: 'economy',
    );

FlightController _loadedController() => FlightController()
  ..searchParams = _params()
  ..results = [_flight()];

FlightModel _flight() => FlightModel(
      id: 'flight-1',
      airline: 'Zentrip Air',
      airlineCode: 'ZA',
      flightNumber: 'ZA 204',
      originCode: 'MJI',
      originCity: 'Tripoli',
      destinationCode: 'CAI',
      destinationCity: 'Cairo',
      departureTime: DateTime(2026, 11, 12, 8, 15),
      arrivalTime: DateTime(2026, 11, 12, 10, 30),
      durationMinutes: 135,
      isDirect: true,
      stops: 0,
      economyPrice: 120,
      seatsAvailable: 8,
      seatLayout: '2-2',
      seatRows: 16,
    );

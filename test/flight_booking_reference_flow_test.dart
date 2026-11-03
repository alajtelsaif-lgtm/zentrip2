import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/core/services/api_result.dart';
import 'package:zentrip/features/flight_booking/logic/flight_controller.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/flight_booking_flow_screen.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/flight_primary_button.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/models/flight_model.dart';
import 'package:zentrip/models/flight_seat_map.dart';

FlightModel _flight() => FlightModel(
      id: '891',
      partnerListingId: 891,
      airline: 'Northwind Air',
      airlineCode: 'NW',
      flightNumber: 'NW 204',
      originCode: 'MJI',
      originCity: 'Tripoli',
      destinationCode: 'CAI',
      destinationCity: 'Cairo',
      departureTime: DateTime(2027, 5, 4, 8, 50),
      arrivalTime: DateTime(2027, 5, 4, 10, 40),
      durationMinutes: 110,
      isDirect: true,
      stops: 0,
      economyPrice: 110,
      seatsAvailable: 12,
      priceCurrencyCode: 'USD',
    );

FlightSeatMap _seatMap() => const FlightSeatMap(
      rowCount: 2,
      seatLetters: ['A', 'B', 'C', 'D'],
      extraLegroomRows: {},
      occupiedSeats: {'1D'},
      fares: [
        FlightSeatFare(
          id: 'economy',
          label: 'Economy Flex',
          price: 110,
          availableSeats: 7,
          sharedInventory: false,
        ),
      ],
      cabins: [
        FlightSeatCabin(
          id: 'main',
          name: 'Main cabin',
          rows: [1, 2],
          totalSeats: 8,
          availableSeats: 7,
        ),
      ],
      extraLegroomFee: 0,
      taxRate: 0.08,
      bookingFee: 3,
      extras: {},
    );

FlightController _controller() {
  final controller = FlightController(searchFlights: (_) async => []);
  controller.searchParams = FlightSearchParams(
    originCode: 'MJI',
    originCity: 'Tripoli',
    destinationCode: 'CAI',
    destinationCity: 'Cairo',
    departureDate: DateTime(2027, 5, 4),
    passengers: 1,
  );
  controller.selectedFlight = _flight();
  return controller;
}

Widget _app({required FlightController controller, Locale? locale}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FlightBookingFlowScreen(
        controller: controller,
        seatMapLoader: (_) async => ApiResult.success(_seatMap()),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('connects fare, passenger, seat and review screens',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Choose your fare'), findsOneWidget);
    expect(find.text('Economy Flex'), findsWidgets);
    await tester.tap(find.widgetWithText(FlightPrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Who’s flying?'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).first, 'Example Traveler');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FlightPrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Choose Seats'), findsOneWidget);
    final seat = find.byKey(const ValueKey('seat-1A'));
    await tester.ensureVisible(seat);
    await tester.tap(seat);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FlightPrimaryButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Review & Pay'), findsOneWidget);
    expect(find.text('MJI'), findsOneWidget);
    expect(find.text('CAI'), findsOneWidget);
    expect(find.text('Example Traveler'), findsOneWidget);
    expect(find.text('Secure simulated payment'), findsOneWidget);
    final payButton =
        tester.widget<FlightPrimaryButton>(find.byType(FlightPrimaryButton));
    expect(payButton.onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FlightPrimaryButton>(find.byType(FlightPrimaryButton))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Duffel offer remains one quoted fare and keeps its currency',
      (tester) async {
    final controller = _controller()
      ..selectedFlight = FlightModel(
        id: 'duffel-off_test',
        source: 'duffel',
        duffelOfferId: 'off_test',
        airline: 'Northwind Air',
        airlineCode: 'NW',
        flightNumber: 'NW 204',
        originCode: 'MJI',
        originCity: 'Tripoli',
        destinationCode: 'CAI',
        destinationCity: 'Cairo',
        departureTime: DateTime(2027, 5, 4, 8, 50),
        arrivalTime: DateTime(2027, 5, 4, 10, 40),
        durationMinutes: 110,
        isDirect: true,
        stops: 0,
        economyPrice: 240,
        seatsAvailable: -1,
        priceCurrencyCode: 'EUR',
        priceIsTotal: true,
      );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_app(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('EUR 240.00'), findsWidgets);
    expect(find.textContaining('Available seats'), findsNothing);
    expect(find.text('Business'), findsNothing);
    expect(find.text('Lite'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

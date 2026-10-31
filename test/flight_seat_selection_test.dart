import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/core/services/api_result.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/flight_seat_selection.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/flight_primary_button.dart';
import 'package:zentrip/models/flight_model.dart';
import 'package:zentrip/models/flight_seat_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders dynamic flight header and API fare inventory',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(loader: (_) async => ApiResult.success(_map())));
    await tester.pumpAndSettle();

    expect(find.text('CAI–DPS'), findsOneWidget);
    expect(find.text('Airbus A320'), findsOneWidget);
    expect(find.textContaining('ZT 482'), findsOneWidget);
    expect(find.text('Economy'), findsOneWidget);
    expect(find.text('Business'), findsOneWidget);
    expect(find.text('25 seats'), findsOneWidget);
    expect(find.text('30 seats'), findsOneWidget);
    expect(find.text('Shared inventory'), findsOneWidget);
    expect(find.text('Cabin 1'), findsOneWidget);
    expect(find.text('5/12 available'), findsOneWidget);
    expect(find.text('DECK'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Extra legroom'), findsOneWidget);
    expect(find.text('Your seat'), findsOneWidget);
    expect(find.text('Taken'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switches cabin and fare, selects available and premium seats',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(loader: (_) async => ApiResult.success(_map())));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(find.text('Forward cabin'), findsOneWidget);
    expect(find.text('4/6 available'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Business'));
    await tester.pumpAndSettle();
    expect(find.text('30 seats'), findsOneWidget);

    // The cabin contains actual rows 14 and 15; 14 is API-designated premium.
    final premiumSeat = find.byKey(const ValueKey('seat-14A'));
    expect(tester.getSemantics(premiumSeat).label,
        startsWith('Seat 14A, extra legroom, available'));
    await tester.tap(premiumSeat);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(premiumSeat).label,
      startsWith('Seat 14A, your seat'),
    );
    await tester.scrollUntilVisible(
      find.text('Extra-legroom seats'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Extra-legroom seats'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('taken seats are disabled and refresh error offers retry',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var calls = 0;
    await tester.pumpWidget(_app(loader: (_) async {
      calls++;
      if (calls == 2) {
        return ApiResult.failure('Seat map temporarily unavailable');
      }
      return ApiResult.success(_map());
    }));
    await tester.pumpAndSettle();

    final takenSeat = find.bySemanticsLabel('Seat 12B, taken');
    expect(takenSeat, findsOneWidget);
    await tester.tap(takenSeat);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Seat 12B, taken'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('seat-12A')));
    await tester.pumpAndSettle();
    expect(tester.widget<FlightPrimaryButton>(find.byType(FlightPrimaryButton)).onPressed,
        isNotNull);

    await tester.tap(find.byTooltip('Refresh availability'));
    await tester.pumpAndSettle();
    expect(find.text('Seat map temporarily unavailable'), findsOneWidget);
    expect(tester.widget<FlightPrimaryButton>(find.byType(FlightPrimaryButton)).onPressed,
        isNull);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(find.text('Seat map temporarily unavailable'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('limits passenger selection and reconciles seats on periodic refresh',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_app(loader: (_) async {
      calls++;
      return ApiResult.success(_map(
          occupied: calls > 1 ? {'12A', '12B', '14C', '15D'} : null));
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('seat-12A')));
    await tester.pumpAndSettle();
    expect(find.text('Proceed to Payment · \$162.56'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('seat-13A')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Select up to 1 seats'), findsOneWidget);
    expect(find.text('Proceed to Payment · \$162.56'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.textContaining('no longer available'), findsOneWidget);
    expect(tester.widget<FlightPrimaryButton>(find.byType(FlightPrimaryButton)).onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _app({required FlightSeatMapLoader loader}) => MaterialApp(
      home: FlightSeatSelectionScreen(
        flight: FlightModel(
          id: '81',
          airline: 'Zentrip Air',
          airlineCode: 'ZT',
          flightNumber: 'ZT 482',
          originCode: 'CAI',
          originCity: 'Cairo',
          destinationCode: 'DPS',
          destinationCity: 'Bali',
          departureTime: DateTime(2026, 9, 5, 6, 14),
          arrivalTime: DateTime(2026, 9, 5, 13, 42),
          durationMinutes: 448,
          isDirect: true,
          stops: 0,
          economyPrice: 90,
          seatsAvailable: 24,
          aircraftName: 'Airbus A320',
        ),
        passengerCount: 1,
        seatClass: 'economy',
        returnDate: null,
        seatsPerSide: 3,
        rowCount: 30,
        seatMapLoader: loader,
      ),
    );

FlightSeatMap _map({Set<String>? occupied}) => FlightSeatMap(
      rowCount: 18,
      seatLetters: ['A', 'B', 'C', 'D', 'E', 'F'],
      extraLegroomRows: {14},
      occupiedSeats: occupied ?? {'12B', '14C', '15D'},
      fares: [
        const FlightSeatFare(
          id: 'economy',
          label: 'Economy',
          price: 138,
          availableSeats: 25,
          sharedInventory: false,
        ),
        const FlightSeatFare(
          id: 'business',
          label: 'Business',
          price: 331,
          availableSeats: 30,
          sharedInventory: true,
        ),
      ],
      cabins: [
        const FlightSeatCabin(
          id: 'aft',
          name: 'Cabin 1',
          rows: [12, 13],
          totalSeats: 12,
          availableSeats: 5,
        ),
        const FlightSeatCabin(
          id: 'forward',
          name: 'Forward cabin',
          rows: [14, 15],
          totalSeats: 6,
          availableSeats: 4,
        ),
      ],
      extraLegroomFee: 22,
      taxRate: .12,
      bookingFee: 8,
      extras: {'extra_baggage': 18, 'flexible_ticket': 12},
    );

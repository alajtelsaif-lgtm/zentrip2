import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentrip/features/flight_booking/logic/flight_controller.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/search_flight_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('flight date selector shows seven dates and calendar action',
      (tester) async {
    DateTime? selected;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: FlightDateSelector(
          departureDate: DateTime(2026, 9, 4),
          onSelected: (value) => selected = value,
        ),
      ),
    ));

    expect(find.text('Flight Date'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('flight-date-2026-9-10')),
      findsOneWidget,
    );
    await tester.tap(find.text('5'));
    expect(selected, DateTime(2026, 9, 5));
  });

  testWidgets('round-trip date choices stop at the return date',
      (tester) async {
    DateTime? selected;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: FlightDateSelector(
          departureDate: DateTime(2026, 9, 4),
          lastDate: DateTime(2026, 9, 5),
          onSelected: (date) => selected = date,
        ),
      ),
    ));

    expect(find.text('5'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    await tester.tap(find.text('6'));
    expect(selected, isNull);
  });

  testWidgets('empty flight search retains route and date selection on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _EmptyFlightController(FlightSearchParams(
      originCode: 'CGK',
      originCity: 'Tangerang',
      destinationCode: 'DPS',
      destinationCity: 'Denpasar',
      departureDate: DateTime(2026, 9, 4),
    ));
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SearchFlightScreen(controller: controller),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Select Flight'), findsOneWidget);
    expect(find.text('CGK'), findsOneWidget);
    expect(find.text('DPS'), findsOneWidget);
    expect(find.text('Flight Date'), findsOneWidget);
    expect(find.textContaining('No flights found from CGK to DPS'),
        findsOneWidget);
    expect(find.byIcon(Icons.flight_outlined), findsNothing);
    expect(find.text('Search Flights'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();
    expect(controller.searchParams!.departureDate, DateTime(2026, 9, 5));
    expect(tester.takeException(), isNull);
  });
}

class _EmptyFlightController extends FlightController {
  _EmptyFlightController(FlightSearchParams initial) {
    searchParams = initial;
  }

  @override
  Future<void> search(FlightSearchParams params) async {
    searchParams = params;
    notifyListeners();
  }
}

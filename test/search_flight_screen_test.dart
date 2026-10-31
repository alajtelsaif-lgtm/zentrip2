import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/features/flight_booking/logic/flight_controller.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/search_flight_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/models/flight_model.dart';

void main() {
  testWidgets('renders flight data and fare for the active search',
      (tester) async {
    final controller = FlightController()
      ..searchParams = FlightSearchParams(
        originCode: 'MJI',
        originCity: 'Tripoli',
        destinationCode: 'CAI',
        destinationCity: 'Cairo',
        departureDate: DateTime(2026, 11, 12),
        passengers: 1,
        seatClass: 'economy',
      )
      ..results = [
        FlightModel(
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
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SearchFlightScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MJI'), findsWidgets);
    expect(find.text('CAI'), findsWidgets);
    expect(find.text('Select Flight'), findsOneWidget);
    expect(find.text('Flight Date'), findsOneWidget);
    expect(find.text('Tripoli'), findsNWidgets(2));
    expect(find.text('Cairo'), findsNWidgets(2));
    expect(find.text('Zentrip Air'), findsOneWidget);
    expect(find.text('ZA 204'), findsOneWidget);
    expect(find.text('Direct'), findsOneWidget);
    expect(find.text('\$146.40'), findsOneWidget);
    expect(find.text('Select this flight'), findsOneWidget);

    controller.dispose();
  });
}

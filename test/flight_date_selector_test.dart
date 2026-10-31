import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/search_flight_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';

void main() {
  testWidgets('flight date selector shows the chosen date range and selection',
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
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    await tester.tap(find.text('5'));
    expect(selected, DateTime(2026, 9, 5));
  });
}

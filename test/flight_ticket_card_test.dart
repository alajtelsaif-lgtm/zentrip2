import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/booking_confirmed_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/models/flight_model.dart';

void main() {
  testWidgets('confirmed flight ticket displays a scannable booking QR',
      (tester) async {
    final flight = FlightModel(
      id: 'partner-25',
      airline: 'Zentrip Airways',
      airlineCode: 'ZT',
      flightNumber: 'ZT-125',
      originCode: 'MJI',
      originCity: 'Tripoli',
      destinationCode: 'IST',
      destinationCity: 'Istanbul',
      departureTime: DateTime(2026, 11, 10, 8),
      arrivalTime: DateTime(2026, 11, 10, 10),
      durationMinutes: 120,
      isDirect: true,
      stops: 0,
      economyPrice: 180,
      seatsAvailable: 64,
      aircraftName: 'ATR 72',
      seatLayout: '2-2',
      seatRows: 16,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FlightTicketCard(
            flight: flight,
            reference: 'ZT-12345678',
            seats: const ['4A', '4B'],
            seatClass: 'economy',
            totalPrice: 213.60,
            currencyCode: 'USD',
            passengerName: 'Arya Pratama Wijaya',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('ZT-12345678'), findsOneWidget);
    expect(find.text('MJI'), findsOneWidget);
    expect(find.text('IST'), findsOneWidget);
    expect(find.text('4A, 4B'), findsOneWidget);
    expect(find.text('Arya Pratama Wijaya'), findsOneWidget);
    expect(find.text('Zentrip Airways'), findsOneWidget);
    expect(find.text('\$213.60'), findsOneWidget);
  });
}

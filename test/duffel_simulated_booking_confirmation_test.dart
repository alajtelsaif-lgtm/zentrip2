import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/booking_confirmed_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/models/flight_booking_model.dart';
import 'package:zentrip/models/flight_model.dart';
import 'package:zentrip/models/trip_model.dart';

void main() {
  testWidgets(
    'Duffel simulator confirmation renders saved trip without partner seats',
    (tester) async {
      final departure = DateTime.utc(2027, 3, 10, 8);
      final arrival = DateTime.utc(2027, 3, 10, 11);
      final flight = FlightModel(
        id: 'duffel-offer-test',
        source: 'duffel',
        duffelOfferId: 'off_test_123',
        priceCurrencyCode: 'EUR',
        priceIsTotal: true,
        airline: 'Test Air',
        airlineCode: 'TA',
        flightNumber: 'TA100',
        originCode: 'MRA',
        originCity: 'Misrata',
        destinationCode: 'MJI',
        destinationCity: 'Tripoli',
        departureTime: departure,
        arrivalTime: arrival,
        durationMinutes: 180,
        isDirect: true,
        stops: 0,
        economyPrice: 125,
        seatsAvailable: -1,
      );
      final trip = TripModel(
        id: 41,
        originCode: 'MRA',
        originCity: 'Misrata',
        destinationCode: 'MJI',
        destinationCity: 'Tripoli',
        departureDate: departure,
        arrivalDate: arrival,
        flightNumber: 'TA100',
        airline: 'Test Air',
        isDirect: true,
        price: 125,
        bookingRef: 'ZT-SIM-DUF-TEST',
        source: 'duffel',
        sourceOfferId: 'off_test_123',
        priceCurrencyCode: 'EUR',
        isSimulated: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BookingConfirmedScreen(
            draft: FlightBookingDraft(
              flight: flight,
              passengerCount: 1,
              seatClass: 'economy',
              seats: const [],
              returnDate: null,
              totalPrice: 125,
            ),
            initialConfirmation: FlightBookingConfirmation(
              trip: trip,
              reference: 'ZT-D-TEST',
              seats: const [],
              totalPrice: 125,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ZT-D-TEST'), findsOneWidget);
      expect(find.text('€125.00'), findsOneWidget);
      expect(find.text('Simulation'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    },
  );
}

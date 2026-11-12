import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/core/services/api_result.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/flight_primary_button.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/flight_seat_selection.dart';
import 'package:zentrip/global_widgets/payment_checkout_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/models/flight_model.dart';
import 'package:zentrip/models/payment_session.dart';
import 'package:zentrip/models/trip_model.dart';

FlightModel _duffelFlight() => FlightModel(
      id: 'duffel-off_example',
      source: 'duffel',
      duffelOfferId: 'off_example',
      airline: 'Example Air',
      airlineCode: 'EA',
      flightNumber: 'EA123',
      originCode: 'MRA',
      originCity: 'Misrata',
      destinationCode: 'TUN',
      destinationCity: 'Tunis',
      departureTime: DateTime.utc(2027, 3, 10, 8),
      arrivalTime: DateTime.utc(2027, 3, 10, 10),
      durationMinutes: 120,
      isDirect: true,
      stops: 0,
      economyPrice: 240,
      seatsAvailable: -1,
      priceCurrencyCode: 'EUR',
      priceIsTotal: true,
    );

Widget _localizedApp(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  testWidgets('simulated payment shows the amount in the offer currency',
      (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        const PaymentCheckoutScreen(
          session: PaymentSession(
            sessionId: 'mock-duffel',
            checkoutUrl: 'mock://checkout',
          ),
          amount: 240,
          currencyCode: 'EUR',
        ),
      ),
    );

    expect(find.text('Total: EUR 240.00'), findsOneWidget);
  });

  testWidgets(
      'Duffel simulation uses offer currency and persists only after success',
      (tester) async {
    TripModel? savedTrip;
    var paymentAmount = 0.0;
    var paymentCurrency = '';
    final flight = _duffelFlight();

    await tester.pumpWidget(
      _localizedApp(
        FlightSeatSelectionScreen(
          flight: flight,
          passengerCount: 2,
          seatClass: 'economy',
          returnDate: null,
          seatsPerSide: 3,
          rowCount: 0,
          paymentLauncher: (
            context, {
            required amount,
            required currencyCode,
            required description,
            required referenceId,
          }) async {
            paymentAmount = amount;
            paymentCurrency = currencyCode;
            return true;
          },
          tripCreator: (trip) async {
            savedTrip = trip;
            return ApiResult.success(trip);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Simulated seat map'), findsOneWidget);
    for (final seat in ['seat-1A', 'seat-1B']) {
      final finder = find.byKey(ValueKey(seat));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }
    final button = find.byType(FlightPrimaryButton);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(paymentAmount, 240);
    expect(paymentCurrency, 'EUR');
    expect(savedTrip?.source, 'duffel');
    expect(savedTrip?.sourceOfferId, 'off_example');
    expect(savedTrip?.priceCurrencyCode, 'EUR');
    expect(savedTrip?.isSimulated, isTrue);
    expect(savedTrip?.bookingRef, startsWith('ZT-SIM-DUF-'));
    expect(find.text('Simulation'), findsOneWidget);
    expect(find.text('€240.00'), findsOneWidget);
  });

  testWidgets('failed Duffel simulator payment does not save a trip',
      (tester) async {
    var saveCalls = 0;
    await tester.pumpWidget(
      _localizedApp(
        FlightSeatSelectionScreen(
          flight: _duffelFlight(),
          passengerCount: 1,
          seatClass: 'economy',
          returnDate: null,
          seatsPerSide: 3,
          rowCount: 0,
          paymentLauncher: (
            context, {
            required amount,
            required currencyCode,
            required description,
            required referenceId,
          }) async =>
              false,
          tripCreator: (trip) async {
            saveCalls++;
            return ApiResult.success(trip);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final seat = find.byKey(const ValueKey('seat-1A'));
    await tester.ensureVisible(seat);
    await tester.tap(seat);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FlightPrimaryButton));
    await tester.pumpAndSettle();

    expect(saveCalls, 0);
    expect(find.textContaining('No trip was saved'), findsOneWidget);
  });
}

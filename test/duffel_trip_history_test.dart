import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/features/trips/logic/trips_controller.dart';
import 'package:zentrip/features/trips/presentation/screens/trip_item_card.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/models/trip_model.dart';

void main() {
  test('Duffel simulation metadata round-trips through the existing trip model',
      () {
    final now = DateTime.utc(2027, 3, 10);
    final original = TripModel(
      id: 9,
      originCode: 'MRA',
      originCity: 'Misrata',
      destinationCode: 'TUN',
      destinationCity: 'Tunis',
      departureDate: now,
      arrivalDate: now.add(const Duration(hours: 2)),
      flightNumber: 'EA123',
      isDirect: true,
      price: 240,
      bookingRef: 'ZT-SIM-DUF-test',
      source: 'duffel',
      sourceOfferId: 'off_example',
      priceCurrencyCode: 'EUR',
      isSimulated: true,
      selectedSeats: const ['10A', '10B'],
      extras: const ['checked_bag'],
    );
    final restored = TripModel.fromJson(original.toJson());

    expect(restored.source, 'duffel');
    expect(restored.sourceOfferId, 'off_example');
    expect(restored.priceCurrencyCode, 'EUR');
    expect(restored.isSimulated, isTrue);
    expect(restored.selectedSeats, ['10A', '10B']);
    expect(restored.extras, ['checked_bag']);
  });

  testWidgets('My Trips marks Duffel simulator trips and keeps currency',
      (tester) async {
    final now = DateTime.utc(2027, 3, 10);
    final item = TripItem(
      kind: TripKind.flight,
      title: 'Misrata → Tunis',
      subtitle: 'MRA → TUN · EA123',
      start: now,
      end: now.add(const Duration(hours: 2)),
      status: TripTab.upcoming,
      price: 240,
      priceCurrencyCode: 'EUR',
      isSimulated: true,
      reference: 'ZT-SIM-DUF-off_example',
      flight: TripModel(
        id: 1,
        originCode: 'MRA',
        originCity: 'Misrata',
        destinationCode: 'TUN',
        destinationCity: 'Tunis',
        departureDate: now,
        arrivalDate: now.add(const Duration(hours: 2)),
        flightNumber: 'EA123',
        isDirect: true,
        price: 240,
        bookingRef: 'ZT-SIM-DUF-off_example',
        source: 'duffel',
        sourceOfferId: 'off_example',
        priceCurrencyCode: 'EUR',
        isSimulated: true,
        selectedSeats: const ['10A', '10B'],
        extras: const ['checked_bag'],
      ),
    );
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TripItemCard(
            item: item,
            isDark: false,
            l10n: AppLocalizations.of(context),
            onTap: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Simulation'), findsOneWidget);
    expect(find.text('EUR 240.00'), findsOneWidget);
    expect(find.text('Seats: 10A, 10B'), findsOneWidget);
    expect(find.text('Extras: checked_bag'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

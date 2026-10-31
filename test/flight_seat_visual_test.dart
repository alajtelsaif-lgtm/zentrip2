// Optional rendering of the real screen with isolated test data, never a route
// or authentication bypass in the application.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/core/services/api_result.dart';
import 'package:zentrip/features/flight_booking/presentation/screens/flight_seat_selection.dart';
import 'package:zentrip/models/flight_model.dart';
import 'package:zentrip/models/flight_seat_map.dart';

void main() {
  if (!const bool.fromEnvironment('CAPTURE_FLIGHT_SEATS')) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('SeatPreview');
    loader.addFont(File('.local/toolchains/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf')
        .readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    await loader.load();
  });

  for (final width in [402.0, 1280.0]) {
    testWidgets('capture seat screen at $width pixels', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'SeatPreview', useMaterial3: true),
          home: FlightSeatSelectionScreen(
            flight: FlightModel(
              id: '1', airline: 'Test airline', airlineCode: 'TEST',
              flightNumber: 'TEST 656', originCode: 'MRA', originCity: 'Misrata',
              destinationCode: 'MJI', destinationCity: 'Tripoli',
              departureTime: DateTime(2035, 9, 5, 6, 14),
              arrivalTime: DateTime(2035, 9, 5, 7, 14),
              durationMinutes: 60, isDirect: true, stops: 0,
              economyPrice: 138, seatsAvailable: 20, aircraftName: 'ATR 72',
            ),
            passengerCount: 1, seatClass: 'economy', returnDate: null,
            seatsPerSide: 2, rowCount: 6,
            seatMapLoader: (_) async => ApiResult.success(const FlightSeatMap(
              rowCount: 6, seatLetters: ['A', 'B', 'C', 'D'],
              extraLegroomRows: {1, 4}, occupiedSeats: {'3A', '4B', '2C', '6C'},
              fares: [
                FlightSeatFare(id: 'economy', label: 'Economy', price: 138,
                    availableSeats: 20, sharedInventory: true),
                FlightSeatFare(id: 'business', label: 'Business', price: 331,
                    availableSeats: 20, sharedInventory: true),
              ],
              cabins: [
                FlightSeatCabin(id: '1', name: 'Cabin 1', rows: [1, 2, 3, 4, 5, 6],
                    totalSeats: 24, availableSeats: 20),
              ],
              extraLegroomFee: 15, taxRate: .12, bookingFee: 12, extras: {},
            )),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('seat-2A')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('generated-artifacts/flight-seats-${width.toInt()}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

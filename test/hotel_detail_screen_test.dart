import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/core/services/api_result.dart';
import 'package:zentrip/core/services/price_comparison.dart';
import 'package:zentrip/features/hotel_booking/logic/hotel_controller.dart';
import 'package:zentrip/features/hotel_booking/presentation/screens/hotel_detail_screen.dart';
import 'package:zentrip/global_widgets/booking_load_error.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/models/exchange_rates.dart';
import 'package:zentrip/models/hotel_model.dart';
import 'package:zentrip/models/review_model.dart';

PriceComparison _comparison() => PriceComparison(
      loadRates: () async => ExchangeRates(
        fetchedAt: DateTime.now().toUtc(),
        rates: const {},
      ),
    );

HotelModel _hotel({
  bool duffel = false,
  bool rapidApi = false,
  bool xotelo = false,
  String? price,
  String currency = 'USD',
}) =>
    HotelModel.fromJson({
      'id': duffel
          ? 'duffel-srr_test-1'
          : rapidApi
              ? 'rapidapi-123'
              : xotelo
                  ? 'xotelo-g297930-d123'
                  : 'partner-hotel-1',
      'source': duffel
          ? 'duffel'
          : rapidApi
              ? 'rapidapi'
              : xotelo
                  ? 'xotelo'
                  : 'partner',
      if (duffel) 'provider_search_result_id': 'srr_test-1',
      'name': 'Central Test Hotel',
      'city': 'Tripoli',
      'country': 'Libya',
      'address': 'Central Tripoli',
      'description': 'A quiet hotel in the city centre.',
      'price_per_night': price,
      'price_currency': currency,
      'availability_known': !duffel,
      'available_rooms': duffel ? null : 4,
      'image_url': 'https://images.example.test/hotel.jpg',
      'gallery_images': <String>[],
      'amenities': <String>['Wi-Fi'],
      'stars': 4,
    });

Future<HotelController> _controllerFor(HotelModel hotel) async {
  final controller = HotelController(
    comparison: _comparison(),
    searchHotels: (_) async => [hotel],
  );
  await controller.search(HotelSearchParams(
    city: 'Tripoli',
    checkIn: DateTime(2026, 12, 1),
    checkOut: DateTime(2026, 12, 3),
  ));
  controller.selectHotel(controller.results.single);
  return controller;
}

Widget _app(
  HotelController controller, {
  Future<ApiResult<Map<String, dynamic>>> Function(String)? loadRates,
}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        settings: RouteSettings(arguments: controller),
        builder: (_) => HotelDetailScreen(
          loadReviews: (_) async =>
              ApiResult<List<ReviewModel>>.success(<ReviewModel>[]),
          loadDuffelRates: loadRates,
        ),
      ),
    );

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _expectNoFlutterException(WidgetTester tester) {
  final exception = tester.takeException();
  if (exception is FlutterError) {
    debugPrint(exception.toStringDeep());
  }
  expect(exception, isNull);
}

void main() {
  testWidgets('partner detail shows image, price, currency and active booking',
      (tester) async {
    _usePhoneViewport(tester);

    final controller = await _controllerFor(_hotel(price: '120'));
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Central Test Hotel'), findsOneWidget);
    expect(find.text('USD 120'), findsOneWidget);
    expect(find.text('USD 269'), findsOneWidget);
    expect(find.text('A quiet hotel in the city centre.'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image).first);
    expect((image.image as NetworkImage).url, contains('hotel.jpg'));
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
    _expectNoFlutterException(tester);

    controller.dispose();
  });

  testWidgets('Duffel rate loading and success render rate and currency',
      (tester) async {
    _usePhoneViewport(tester);
    final pendingRates = Completer<ApiResult<Map<String, dynamic>>>();
    final controller = await _controllerFor(
      _hotel(duffel: true, price: null, currency: 'GBP'),
    );
    await tester.pumpWidget(
      _app(controller, loadRates: (_) => pendingRates.future),
    );
    await tester.pump();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(HotelDetailScreen)));

    expect(find.text(l10n.hotelRoomRatesLoading), findsOneWidget);
    expect(find.text(l10n.priceUnavailable), findsAtLeastNWidgets(1));

    pendingRates.complete(ApiResult<Map<String, dynamic>>.success({
      'room_types': <Map<String, dynamic>>[],
      'offers': <Map<String, dynamic>>[
        {
          'name': 'Breakfast included',
          'price_per_night': 125.0,
          'price_currency': 'GBP',
          'total_amount': '250.00',
          'total_currency': 'GBP',
        },
      ],
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('GBP 125'), findsOneWidget);
    expect(find.text('GBP 250.00'), findsOneWidget);
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -900),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    _expectNoFlutterException(tester);
    controller.dispose();
  });

  testWidgets('empty and failed Duffel rates display unavailable state',
      (tester) async {
    _usePhoneViewport(tester);
    for (final result in <ApiResult<Map<String, dynamic>>>[
      ApiResult<Map<String, dynamic>>.success({
        'room_types': <Map<String, dynamic>>[],
        'offers': <Map<String, dynamic>>[],
      }),
      ApiResult<Map<String, dynamic>>.failure('rate service unavailable'),
    ]) {
      final controller = await _controllerFor(
        _hotel(duffel: true, price: null, currency: 'GBP'),
      );
      await tester.pumpWidget(
        _app(controller, loadRates: (_) async => result),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final l10n =
          AppLocalizations.of(tester.element(find.byType(HotelDetailScreen)));
      expect(find.text(l10n.hotelRoomRatesUnavailable), findsOneWidget);
      expect(find.text(l10n.priceUnavailable), findsAtLeastNWidgets(1));
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -900),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      _expectNoFlutterException(tester);
      controller.dispose();
    }
  });

  testWidgets('RapidAPI hotel details do not offer unsupported in-app booking',
      (tester) async {
    _usePhoneViewport(tester);
    final controller = await _controllerFor(
      _hotel(rapidApi: true, price: '120'),
    );
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final l10n =
        AppLocalizations.of(tester.element(find.byType(HotelDetailScreen)));
    expect(find.text('Central Test Hotel'), findsOneWidget);
    expect(find.text('USD 120'), findsOneWidget);
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -900),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.text(l10n.hotelExternalBookingUnavailable),
      findsOneWidget,
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    _expectNoFlutterException(tester);
    controller.dispose();
  });

  testWidgets('Xotelo information uses the existing simulated booking flow',
      (tester) async {
    _usePhoneViewport(tester);
    final controller = await _controllerFor(
      _hotel(xotelo: true, price: '71'),
    );
    await tester.pumpWidget(_app(controller));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final l10n =
        AppLocalizations.of(tester.element(find.byType(HotelDetailScreen)));
    expect(find.text('Central Test Hotel'), findsOneWidget);
    expect(find.text(l10n.hotelXoteloEstimateLabel), findsOneWidget);
    await tester.drag(
      find.byType(CustomScrollView),
      const Offset(0, -900),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    _expectNoFlutterException(tester);
    controller.dispose();
  });

  testWidgets('missing selection renders the existing detail error state',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HotelDetailScreen(),
    ));
    await tester.pump();
    expect(find.byType(BookingLoadError), findsOneWidget);
    _expectNoFlutterException(tester);
  });
}

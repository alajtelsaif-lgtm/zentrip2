import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/core/services/api_result.dart';
import 'package:zentrip/core/services/api_service.dart';
import 'package:zentrip/features/trips/logic/trips_controller.dart';
import 'package:zentrip/models/booking_model.dart';
import 'package:zentrip/models/trip_model.dart';

void main() {
  TripModel flightTrip() => TripModel(
        id: 41,
        originCode: 'MJI',
        originCity: 'Misrata',
        destinationCode: 'TUN',
        destinationCity: 'Tunis',
        departureDate: DateTime.now().add(const Duration(days: 12)),
        flightNumber: 'ZT410',
        isDirect: true,
      );

  BookingModel hotelBooking() => BookingModel(
        id: '82',
        type: BookingType.hotel,
        title: 'Harbor Hotel',
        subtitle: 'Tunis',
        date: DateTime.now().add(const Duration(days: 14)),
      );

  test('My Trips combines flights from trips and other bookings', () async {
    final controller = TripsController(
      loadFlightTrips: () async =>
          ApiResult<List<TripModel>>.success([flightTrip()]),
      loadBookings: () async =>
          ApiResult<List<BookingModel>>.success([hotelBooking()]),
    );
    addTearDown(controller.dispose);

    await controller.loadTrips();

    expect(controller.loadError, isNull);
    expect(controller.visibleItems, hasLength(2));
    expect(
      controller.visibleItems.map((item) => item.kind),
      containsAll([TripKind.flight, TripKind.hotel]),
    );
  });

  test('failed source does not leave stale bookings visible', () async {
    var bookingResult = ApiResult<List<BookingModel>>.success([hotelBooking()]);
    final controller = TripsController(
      loadFlightTrips: () async => ApiResult<List<TripModel>>.success(const []),
      loadBookings: () async => bookingResult,
    );
    addTearDown(controller.dispose);

    await controller.loadTrips();
    expect(controller.visibleItems, hasLength(1));

    bookingResult = ApiResult<List<BookingModel>>.failure('server unavailable');
    await controller.loadTrips();

    controller.setFilter(TripFilter.hotels);
    expect(controller.loadError, isNotNull);
    expect(controller.visibleItems, isEmpty);
  });

  test('flight trip changes trigger a My Trips refresh', () async {
    var flightLoadCount = 0;
    final controller = TripsController(
      loadFlightTrips: () async {
        flightLoadCount++;
        return ApiResult<List<TripModel>>.success(const []);
      },
      loadBookings: () async => ApiResult<List<BookingModel>>.success(const []),
    );
    addTearDown(controller.dispose);
    await controller.loadTrips();

    expect(flightLoadCount, 1);
    final refreshed = Completer<void>();
    void onChanged() {
      if (!controller.isLoading &&
          flightLoadCount > 1 &&
          !refreshed.isCompleted) {
        refreshed.complete();
      }
    }

    controller.addListener(onChanged);
    ApiService.flightTripsRevision.value++;
    await refreshed.future.timeout(const Duration(seconds: 2));
    controller.removeListener(onChanged);

    expect(flightLoadCount, 2);
  });
}

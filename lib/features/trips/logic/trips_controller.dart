import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../../core/constants/media_urls.dart';
import '../../../core/services/api_service.dart';
import '../../../models/booking_model.dart';
import '../../../models/trip_model.dart';

enum TripTab { upcoming, active, completed, cancelled }

enum TripFilter { all, flights, hotels, cars, tours }

enum TripKind { flight, hotel, car, tour }

/// Unified My Trips entry: a flight trip or a hotel/car/tour booking.
class TripItem {
  final TripKind kind;
  final String title;
  final String subtitle;
  final DateTime start;
  final DateTime end;
  final TripTab status;
  final String? imageUrl;
  final double? price;
  final String priceCurrencyCode;
  final bool isSimulated;
  final String? reference;
  final TripModel? flight;
  final BookingModel? booking;

  /// Reviews are available only after the trip's dates have completed.
  bool get canReview => status == TripTab.completed;

  const TripItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.start,
    required this.end,
    required this.status,
    this.imageUrl,
    this.price,
    this.priceCurrencyCode = 'USD',
    this.isSimulated = false,
    this.reference,
    this.flight,
    this.booking,
  });
}

class TripsController extends ChangeNotifier {
  TripsController() {
    ApiService.bookingsRevision.addListener(_onBookingsChanged);
  }

  List<TripModel> _flights = [];
  List<BookingModel> _bookings = [];
  int _loadGeneration = 0;
  bool isLoading = false;
  TripTab selectedTab = TripTab.upcoming;
  TripFilter selectedFilter = TripFilter.all;

  // Cancelled/completed stay as stored; otherwise status is derived from the dates.
  static TripTab resolveStatus(
      String stored, DateTime start, DateTime end, DateTime now) {
    if (stored == 'cancelled') return TripTab.cancelled;
    if (stored == 'completed') return TripTab.completed;
    if (now.isBefore(start)) return TripTab.upcoming;
    if (now.isAfter(end)) return TripTab.completed;
    return TripTab.active;
  }

  static TripKind kindForBooking(BookingType type) => switch (type) {
        BookingType.hotel => TripKind.hotel,
        BookingType.car => TripKind.car,
        BookingType.attraction || BookingType.package => TripKind.tour,
      };

  static String? coverForCity(String code) => switch (code.toUpperCase()) {
        'MJI' => MediaUrls.cityTripoli,
        'MRA' => MediaUrls.cityMisrata,
        'BEN' => MediaUrls.cityBenghazi,
        'CAI' => MediaUrls.cityCairo,
        'TUN' => MediaUrls.cityTunis,
        'IST' => MediaUrls.cityIstanbul,
        'JED' => MediaUrls.cityJeddah,
        'DXB' => MediaUrls.cityDubai,
        _ => null,
      };

  List<TripItem> get _items {
    final now = DateTime.now();
    final items = <TripItem>[];
    for (final t in _flights) {
      final start = t.departureDate;
      var end = t.arrivalDate ?? start.add(const Duration(hours: 6));
      final back = t.returnDate;
      if (back != null) end = back.add(const Duration(days: 1));
      items.add(TripItem(
        kind: TripKind.flight,
        title: '${t.originCity} → ${t.destinationCity}',
        subtitle:
            '${t.originCode} → ${t.destinationCode} · ${t.airline ?? t.flightNumber}',
        start: start,
        end: end,
        status: resolveStatus(t.status, start, end, now),
        imageUrl: coverForCity(t.destinationCode),
        price: t.price,
        priceCurrencyCode: t.priceCurrencyCode,
        isSimulated: t.isSimulated,
        reference: t.bookingRef ?? t.flightNumber,
        flight: t,
      ));
    }
    for (final b in _bookings) {
      final end = b.endDate ?? b.date.add(const Duration(days: 1));
      items.add(TripItem(
        kind: kindForBooking(b.type),
        title: b.title,
        subtitle: b.subtitle,
        start: b.date,
        end: end,
        status: resolveStatus(b.status, b.date, end, now),
        imageUrl: b.imageUrl,
        price: b.price,
        reference: b.refCode,
        booking: b,
      ));
    }
    return items;
  }

  static bool _matches(TripFilter f, TripItem i) => switch (f) {
        TripFilter.all => true,
        TripFilter.flights => i.kind == TripKind.flight,
        TripFilter.hotels => i.kind == TripKind.hotel,
        TripFilter.cars => i.kind == TripKind.car,
        TripFilter.tours => i.kind == TripKind.tour,
      };

  /// Count per status tab, respecting the selected category filter.
  int countFor(TripTab tab) => _items
      .where((i) => _matches(selectedFilter, i) && i.status == tab)
      .length;

  /// Count per category within the selected status tab.
  int countForFilter(TripFilter f) =>
      _items.where((i) => i.status == selectedTab && _matches(f, i)).length;

  List<TripItem> get visibleItems {
    final list = _items
        .where((i) => _matches(selectedFilter, i) && i.status == selectedTab)
        .toList();
    final ascending =
        selectedTab == TripTab.upcoming || selectedTab == TripTab.active;
    list.sort((a, b) =>
        ascending ? a.start.compareTo(b.start) : b.start.compareTo(a.start));
    return list;
  }

  bool get isEmpty => visibleItems.isEmpty;

  void _onBookingsChanged() {
    unawaited(loadTrips());
  }

  Future<void> loadTrips() async {
    final generation = ++_loadGeneration;
    isLoading = true;
    notifyListeners();

    try {
      // My Trips reflects bookings made by this account, not catalog data.
      final flightsResult = await ApiService.instance.getMyFlightTrips();
      final bookingsResult = await ApiService.instance.getMyBookings();

      if (generation != _loadGeneration) return;
      if (flightsResult.isSuccess && flightsResult.data != null) {
        _flights = flightsResult.data!;
      }
      if (bookingsResult.isSuccess && bookingsResult.data != null) {
        _bookings = bookingsResult.data!;
      }
    } finally {
      if (generation == _loadGeneration) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    ApiService.bookingsRevision.removeListener(_onBookingsChanged);
    super.dispose();
  }

  void setTab(TripTab tab) {
    selectedTab = tab;
    notifyListeners();
  }

  void setFilter(TripFilter filter) {
    selectedFilter = filter;
    notifyListeners();
  }

  TripModel? get upcomingTrip =>
      _flights.where((t) => t.status == 'upcoming').isNotEmpty
          ? _flights.firstWhere((t) => t.status == 'upcoming')
          : null;
}

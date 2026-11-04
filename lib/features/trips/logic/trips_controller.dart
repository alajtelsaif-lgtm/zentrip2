import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../../core/constants/media_urls.dart';
import '../../../core/services/api_result.dart';
import '../../../core/services/api_service.dart';
import '../../../models/booking_model.dart';
import '../../../models/trip_model.dart';
import '../../../models/transfer_model.dart';

enum TripTab { upcoming, active, completed, cancelled }

enum TripFilter { all, flights, hotels, cars, tours, transfers }

enum TripKind { flight, hotel, car, tour, transfer }

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
  final TransferModel? transfer;

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
    this.transfer,
  });
}

class TripsController extends ChangeNotifier {
  TripsController({
    Future<ApiResult<List<TripModel>>> Function()? loadFlightTrips,
    Future<ApiResult<List<BookingModel>>> Function()? loadBookings,
    Future<ApiResult<List<TransferModel>>> Function()? loadTransfers,
  })  : _loadFlightTrips =
            loadFlightTrips ?? ApiService.instance.getMyFlightTrips,
        _loadBookings = loadBookings ?? ApiService.instance.getMyBookings,
        _loadTransfers = loadTransfers ?? ApiService.instance.getMyTransfers {
    ApiService.flightTripsRevision.addListener(_onBookingDataChanged);
    ApiService.bookingsRevision.addListener(_onBookingDataChanged);
    ApiService.transfersRevision.addListener(_onBookingDataChanged);
  }

  final Future<ApiResult<List<TripModel>>> Function() _loadFlightTrips;
  final Future<ApiResult<List<BookingModel>>> Function() _loadBookings;
  final Future<ApiResult<List<TransferModel>>> Function() _loadTransfers;
  List<TripModel> _flights = [];
  List<BookingModel> _bookings = [];
  List<TransferModel> _transfers = [];
  int _loadGeneration = 0;
  bool isLoading = false;
  String? loadError;
  TripTab selectedTab = TripTab.upcoming;
  TripFilter selectedFilter = TripFilter.all;

  // Cancelled/completed stay as stored; otherwise status is derived from the dates.
  static TripTab resolveStatus(
      String stored, DateTime start, DateTime end, DateTime now) {
    final normalized = stored.trim().toLowerCase();
    if (normalized == 'cancelled') return TripTab.cancelled;
    if (normalized == 'completed') return TripTab.completed;
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
    for (final transfer in _transfers) {
      final start = transfer.pickupTime;
      final end = start.add(Duration(
          minutes: transfer.durationMinutes > 0
              ? transfer.durationMinutes
              : 60));
      items.add(TripItem(
        kind: TripKind.transfer,
        title: '${transfer.pickupLocation} → ${transfer.dropoffLocation}',
        subtitle: '${transfer.providerName} · ${transfer.vehicleType}',
        start: start,
        end: end,
        status: resolveStatus(transfer.status, start, end, now),
        imageUrl: transfer.vehicleImageUrl,
        price: transfer.priceUSD,
        transfer: transfer,
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
        TripFilter.transfers => i.kind == TripKind.transfer,
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

  void _onBookingDataChanged() {
    unawaited(loadTrips());
  }

  Future<void> loadTrips() async {
    final generation = ++_loadGeneration;
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      // Both requests are started together: flights are stored in trips, while
      // hotel/car/tour reservations are stored in bookings.
      final flightsRequest = _safeLoad(_loadFlightTrips);
      final bookingsRequest = _safeLoad(_loadBookings);
      final transfersRequest = _safeLoad(_loadTransfers);
      final results = await Future.wait([
        flightsRequest,
        bookingsRequest,
        transfersRequest,
      ]);
      final flightsResult = results[0] as ApiResult<List<TripModel>>;
      final bookingsResult = results[1] as ApiResult<List<BookingModel>>;
      final transfersResult = results[2] as ApiResult<List<TransferModel>>;

      if (generation != _loadGeneration) return;
      _flights =
          flightsResult.isSuccess ? flightsResult.data ?? const [] : const [];
      _bookings =
          bookingsResult.isSuccess ? bookingsResult.data ?? const [] : const [];
      _transfers =
          transfersResult.isSuccess ? transfersResult.data ?? const [] : const [];
      final errors = [
        if (flightsResult.isFailure)
          flightsResult.errorMessage ?? 'Flight trips could not be loaded',
        if (bookingsResult.isFailure)
          bookingsResult.errorMessage ?? 'Bookings could not be loaded',
        if (transfersResult.isFailure)
          transfersResult.errorMessage ?? 'Transfers could not be loaded',
      ];
      loadError = errors.isEmpty ? null : errors.join('; ');
    } catch (error) {
      if (generation != _loadGeneration) return;
      _flights = [];
      _bookings = [];
      _transfers = [];
      loadError = error.toString();
    } finally {
      if (generation == _loadGeneration) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<ApiResult<T>> _safeLoad<T>(
      Future<ApiResult<T>> Function() load) async {
    try {
      return await load();
    } catch (error) {
      return ApiResult.failure(error.toString());
    }
  }

  @override
  void dispose() {
    ApiService.flightTripsRevision.removeListener(_onBookingDataChanged);
    ApiService.bookingsRevision.removeListener(_onBookingDataChanged);
    ApiService.transfersRevision.removeListener(_onBookingDataChanged);
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

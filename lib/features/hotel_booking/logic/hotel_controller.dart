import 'package:flutter/foundation.dart';
import '../../../core/services/api_service.dart';
import '../../../models/hotel_model.dart';

class HotelSearchParams {
  final String city;
  final DateTime checkIn;
  final DateTime checkOut;
  final int rooms;
  final int guests;

  const HotelSearchParams({
    required this.city,
    required this.checkIn,
    required this.checkOut,
    this.rooms = 1,
    this.guests = 2,
  });

  int get nights => checkOut.difference(checkIn).inDays;
}

enum HotelSort { priceLow, priceHigh, rating, distance }

enum HotelFilter { all, budget, midRange, luxury }

class HotelController extends ChangeNotifier {
  static const double defaultNearbyRadiusMeters = 50000;

  HotelSearchParams? searchParams;
  List<HotelModel> _all = [];
  List<HotelModel> results = [];
  bool isLoading = false;
  bool hasSearchError = false;
  HotelSort sort = HotelSort.rating;
  HotelFilter filter = HotelFilter.all;
  HotelModel? selectedHotel;
  int _searchRevision = 0;

  Future<void> search(HotelSearchParams params) async {
    final revision = ++_searchRevision;
    searchParams = params;
    isLoading = true;
    hasSearchError = false;
    notifyListeners();
    try {
      final hotels = await ApiService.instance.searchHotels(
        city: params.city,
        checkIn: params.checkIn,
        checkOut: params.checkOut,
        rooms: params.rooms,
        guests: params.guests,
      );
      if (revision != _searchRevision) return;
      _all = hotels;
      _applyFilter();
    } catch (_) {
      if (revision != _searchRevision) return;
      _all = [];
      results = [];
      hasSearchError = true;
    } finally {
      if (revision == _searchRevision) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> searchNearby(
    HotelSearchParams params, {
    required double latitude,
    required double longitude,
    double radiusMeters = defaultNearbyRadiusMeters,
  }) async {
    final revision = ++_searchRevision;
    searchParams = HotelSearchParams(
      city: params.city,
      checkIn: params.checkIn,
      checkOut: params.checkOut,
      rooms: params.rooms,
      guests: params.guests,
    );
    isLoading = true;
    hasSearchError = false;
    sort = HotelSort.distance;
    notifyListeners();
    try {
      _all = await ApiService.instance.nearbyHotels(
        lat: latitude,
        lng: longitude,
        radiusMeters: radiusMeters,
      );
      if (revision != _searchRevision) return;
      _applyFilter();
    } catch (_) {
      if (revision != _searchRevision) return;
      _all = [];
      results = [];
      hasSearchError = true;
    } finally {
      if (revision == _searchRevision) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  void setSort(HotelSort s) {
    sort = s;
    _applyFilter();
    notifyListeners();
  }

  void setFilter(HotelFilter f) {
    filter = f;
    _applyFilter();
    notifyListeners();
  }

  void selectHotel(HotelModel hotel) {
    selectedHotel = hotel;
    notifyListeners();
  }

  void _applyFilter() {
    List<HotelModel> r = List.of(_all);
    switch (filter) {
      case HotelFilter.budget:
        r = r.where((h) => h.pricePerNight < 100).toList();
        break;
      case HotelFilter.midRange:
        r = r
            .where((h) => h.pricePerNight >= 100 && h.pricePerNight < 250)
            .toList();
        break;
      case HotelFilter.luxury:
        r = r.where((h) => h.pricePerNight >= 250).toList();
        break;
      default:
        break;
    }
    switch (sort) {
      case HotelSort.priceLow:
        r.sort((a, b) {
          final currencyOrder =
              a.priceCurrencyCode.compareTo(b.priceCurrencyCode);
          return currencyOrder != 0
              ? currencyOrder
              : a.pricePerNight.compareTo(b.pricePerNight);
        });
        break;
      case HotelSort.priceHigh:
        r.sort((a, b) {
          final currencyOrder =
              a.priceCurrencyCode.compareTo(b.priceCurrencyCode);
          return currencyOrder != 0
              ? currencyOrder
              : b.pricePerNight.compareTo(a.pricePerNight);
        });
        break;
      case HotelSort.rating:
        r.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case HotelSort.distance:
        r.sort((a, b) => (a.distanceMeters ?? double.infinity)
            .compareTo(b.distanceMeters ?? double.infinity));
        break;
    }
    results = r;
  }
}

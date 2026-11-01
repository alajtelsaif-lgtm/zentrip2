import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/price_comparison.dart';
import '../../../models/hotel_model.dart';

class HotelSearchParams {
  final String city;
  final DateTime checkIn;
  final DateTime checkOut;
  final int rooms;
  final int guests;
  final double? ratingMin;
  final List<String> amenities;
  final String? roomType;
  final List<String> preferences;

  const HotelSearchParams({
    required this.city,
    required this.checkIn,
    required this.checkOut,
    this.rooms = 1,
    this.guests = 2,
    this.ratingMin,
    this.amenities = const [],
    this.roomType,
    this.preferences = const [],
  });

  int get nights => checkOut.difference(checkIn).inDays;
}

enum HotelSort { priceLow, priceHigh, rating, distance }

enum HotelFilter { all, budget, midRange, luxury }

class HotelController extends ChangeNotifier {
  final PriceComparison comparison;
  final Future<List<HotelModel>> Function(HotelSearchParams)? searchHotels;

  HotelController({PriceComparison? comparison, this.searchHotels})
      : comparison = comparison ??
            PriceComparison(loadRates: ApiService.instance.exchangeRates) {
    this.comparison.addListener(_comparisonChanged);
  }

  void _comparisonChanged() {
    _applyFilter();
    final currencyChanged = _lastServerFilterCurrency != comparison.currency;
    _lastServerFilterCurrency = comparison.currency;
    if (currencyChanged && filter != HotelFilter.all) {
      _scheduleFilteredSearch();
    }
    notifyListeners();
  }

  double? comparisonPrice(HotelModel hotel) {
    final price = hotel.comparisonNightlyPrice;
    return price == null
        ? null
        : comparison.convert(price, hotel.priceCurrencyCode);
  }

  int get unpricedCount => _all.where((h) => comparisonPrice(h) == null).length;
  Iterable<String> get sourceCurrencies => _all.map((h) => h.priceCurrencyCode);

  @override
  void dispose() {
    _filterSearchDebounce?.cancel();
    comparison.removeListener(_comparisonChanged);
    comparison.dispose();
    super.dispose();
  }

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
  String _lastServerFilterCurrency = 'USD';
  Timer? _filterSearchDebounce;
  bool _isNearbySearch = false;
  List<String> searchWarnings = const [];

  Future<void> search(HotelSearchParams params) async {
    final revision = ++_searchRevision;
    _isNearbySearch = false;
    searchParams = params;
    isLoading = true;
    hasSearchError = false;
    searchWarnings = const [];
    notifyListeners();
    comparison.refresh();
    try {
      final hotels = searchHotels != null
          ? await searchHotels!(params)
          : await ApiService.instance.searchHotels(
              city: params.city,
              checkIn: params.checkIn,
              checkOut: params.checkOut,
              rooms: params.rooms,
              guests: params.guests,
              currency: comparison.currency,
              priceMin: _serverPriceBounds.$1,
              priceMax: _serverPriceBounds.$2,
              ratingMin: params.ratingMin,
              amenities: params.amenities,
              roomType: params.roomType,
              preferences: params.preferences,
              onWarnings: (warnings) {
                if (revision != _searchRevision) return;
                searchWarnings = List.unmodifiable(warnings);
                notifyListeners();
              },
            );
      if (revision != _searchRevision) return;
      _all = hotels;
      _applyFilter();
    } catch (_) {
      if (revision != _searchRevision) return;
      if (_all.isEmpty) results = [];
      hasSearchError = true;
      searchWarnings = const ['Some hotel results could not be refreshed.'];
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
    _isNearbySearch = true;
    searchParams = HotelSearchParams(
      city: params.city,
      checkIn: params.checkIn,
      checkOut: params.checkOut,
      rooms: params.rooms,
      guests: params.guests,
      ratingMin: params.ratingMin,
      amenities: params.amenities,
      roomType: params.roomType,
      preferences: params.preferences,
    );
    isLoading = true;
    hasSearchError = false;
    sort = HotelSort.distance;
    notifyListeners();
    comparison.refresh();
    try {
      final hotels = await ApiService.instance.nearbyHotels(
        lat: latitude,
        lng: longitude,
        radiusMeters: radiusMeters,
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

  void setSort(HotelSort s) {
    sort = s;
    _applyFilter();
    notifyListeners();
  }

  void setFilter(HotelFilter f) {
    filter = f;
    _applyFilter();
    notifyListeners();
    _scheduleFilteredSearch();
  }

  (double?, double?) get _serverPriceBounds => switch (filter) {
        HotelFilter.budget => (null, 99.999999),
        HotelFilter.midRange => (100, 249.999999),
        HotelFilter.luxury => (250, null),
        HotelFilter.all => (null, null),
      };

  void _scheduleFilteredSearch() {
    if (searchHotels != null || _isNearbySearch || searchParams == null) return;
    _filterSearchDebounce?.cancel();
    _filterSearchDebounce = Timer(const Duration(milliseconds: 250), () {
      final params = searchParams;
      if (params != null) unawaited(search(params));
    });
  }

  void selectHotel(HotelModel hotel) {
    selectedHotel = hotel;
    notifyListeners();
  }

  void _applyFilter() {
    List<HotelModel> r = List.of(_all);
    switch (filter) {
      case HotelFilter.budget:
        r = r.where((h) {
          final price = comparisonPrice(h);
          return price != null && price < 100;
        }).toList();
        break;
      case HotelFilter.midRange:
        r = r.where((h) {
          final price = comparisonPrice(h);
          return price != null && price >= 100 && price < 250;
        }).toList();
        break;
      case HotelFilter.luxury:
        r = r.where((h) {
          final price = comparisonPrice(h);
          return price != null && price >= 250;
        }).toList();
        break;
      default:
        break;
    }
    switch (sort) {
      case HotelSort.priceLow:
        r.sort((a, b) {
          final order =
              comparison.compare(comparisonPrice(a), comparisonPrice(b));
          return order != 0 ? order : a.id.compareTo(b.id);
        });
        break;
      case HotelSort.priceHigh:
        r.sort((a, b) {
          final order = comparison.compare(
              comparisonPrice(a), comparisonPrice(b),
              descending: true);
          return order != 0 ? order : a.id.compareTo(b.id);
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

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/price_comparison.dart';
import '../../../models/hotel_destination_suggestion.dart';
import '../../../models/hotel_model.dart';

class HotelSearchParams {
  final String city;
  final DateTime checkIn;
  final DateTime checkOut;
  final int rooms;
  final int guests;
  final String? destinationCode;
  final String? countryCode;
  final String? placeId;
  final double? latitude;
  final double? longitude;
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
    this.destinationCode,
    this.countryCode,
    this.placeId,
    this.latitude,
    this.longitude,
    this.ratingMin,
    this.amenities = const [],
    this.roomType,
    this.preferences = const [],
  });

  int get nights => DateTime.utc(
        checkOut.year,
        checkOut.month,
        checkOut.day,
      )
          .difference(DateTime.utc(checkIn.year, checkIn.month, checkIn.day))
          .inDays;
}

enum HotelSort { priceLow, priceHigh, rating, distance }

enum HotelFilter { all, budget, midRange, luxury }

class HotelController extends ChangeNotifier {
  final PriceComparison comparison;
  final Future<List<HotelModel>> Function(HotelSearchParams)? searchHotels;
  final Future<List<HotelDestinationSuggestion>> Function(String query)?
      loadDestinations;

  HotelController({
    PriceComparison? comparison,
    this.searchHotels,
    this.loadDestinations,
  }) : comparison = comparison ??
            PriceComparison(loadRates: ApiService.instance.exchangeRates) {
    _lastServerFilterCurrency = this.comparison.currency;
    this.comparison.addListener(_comparisonChanged);
  }

  void _comparisonChanged() {
    final currencyChanged = _lastServerFilterCurrency != comparison.currency;
    if (currencyChanged && filter != HotelFilter.all) {
      _serverFiltered = false;
    }
    _applyFilter();
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
    _destinationDebounce?.cancel();
    _destinationCancelToken?.cancel('Hotel search screen disposed');
    _destinationSuggestionRevision++;
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
  String searchStatus = 'idle';
  String searchReason = '';
  HotelSort sort = HotelSort.rating;
  HotelFilter filter = HotelFilter.all;
  HotelModel? selectedHotel;
  int _searchRevision = 0;
  String _lastServerFilterCurrency = 'USD';
  Timer? _filterSearchDebounce;
  bool _isNearbySearch = false;
  bool _serverFiltered = false;
  List<String> searchWarnings = const [];
  List<HotelDestinationSuggestion> destinationSuggestions = const [];
  bool isLoadingDestinationSuggestions = false;
  bool hasDestinationSuggestionError = false;
  String _destinationQuery = '';
  String _destinationLanguage = 'en';
  Timer? _destinationDebounce;
  CancelToken? _destinationCancelToken;
  int _destinationSuggestionRevision = 0;

  Future<void> search(HotelSearchParams params) async {
    final revision = ++_searchRevision;
    _isNearbySearch = false;
    searchParams = params;
    isLoading = true;
    hasSearchError = false;
    searchStatus = 'loading';
    searchReason = '';
    _all = [];
    results = [];
    _serverFiltered = false;
    searchWarnings = const [];
    notifyListeners();
    comparison.refresh();
    try {
      final hotels = searchHotels != null
          ? await searchHotels!(params)
          : await ApiService.instance.searchHotels(
              city: params.city,
              destinationCode: params.destinationCode,
              countryCode: params.countryCode,
              placeId: params.placeId,
              latitude: params.latitude,
              longitude: params.longitude,
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
              onStatus: (status, reason) {
                if (revision != _searchRevision) return;
                searchStatus = status;
                searchReason = reason;
                hasSearchError = status == 'error' || status == 'unavailable';
                notifyListeners();
              },
            );
      if (revision != _searchRevision) return;
      _all = hotels;
      if (searchStatus == 'loading') {
        searchStatus = hotels.isEmpty ? 'empty' : 'success';
      }
      _serverFiltered = searchHotels == null;
      _applyFilter();
    } catch (_) {
      if (revision != _searchRevision) return;
      _all = [];
      results = [];
      hasSearchError = true;
      searchStatus = 'unavailable';
      searchReason = '';
      searchWarnings = const [];
    } finally {
      if (revision == _searchRevision) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  void updateDestinationQuery(
    String query, {
    String languageCode = 'en',
    Duration debounce = const Duration(milliseconds: 350),
  }) {
    _destinationDebounce?.cancel();
    _destinationCancelToken?.cancel('Destination query changed');
    _destinationCancelToken = null;
    _destinationQuery = query.trim();
    _destinationLanguage =
        languageCode.toLowerCase().startsWith('ar') ? 'ar' : 'en';
    final revision = ++_destinationSuggestionRevision;
    if (_destinationQuery.length < 2) {
      destinationSuggestions = const [];
      isLoadingDestinationSuggestions = false;
      hasDestinationSuggestionError = false;
      notifyListeners();
      return;
    }

    destinationSuggestions = const [];
    isLoadingDestinationSuggestions = true;
    hasDestinationSuggestionError = false;
    notifyListeners();
    _destinationDebounce = Timer(debounce, () {
      _destinationDebounce = null;
      final token = CancelToken();
      _destinationCancelToken = token;
      _fetchDestinationSuggestions(_destinationQuery, revision, token);
    });
  }

  Future<void> loadDestinationSuggestionsNow(
    String query, {
    String languageCode = 'en',
  }) async {
    if (destinationSuggestions.isNotEmpty &&
        _destinationQuery == query.trim() &&
        !isLoadingDestinationSuggestions) {
      return;
    }
    _destinationDebounce?.cancel();
    _destinationDebounce = null;
    _destinationCancelToken?.cancel('Destination query submitted');
    final token = CancelToken();
    _destinationCancelToken = token;
    _destinationQuery = query.trim();
    _destinationLanguage =
        languageCode.toLowerCase().startsWith('ar') ? 'ar' : 'en';
    final revision = ++_destinationSuggestionRevision;
    if (_destinationQuery.length < 2) {
      destinationSuggestions = const [];
      isLoadingDestinationSuggestions = false;
      hasDestinationSuggestionError = false;
      notifyListeners();
      return;
    }
    destinationSuggestions = const [];
    isLoadingDestinationSuggestions = true;
    hasDestinationSuggestionError = false;
    notifyListeners();
    await _fetchDestinationSuggestions(_destinationQuery, revision, token);
  }

  Future<void> _fetchDestinationSuggestions(
    String query,
    int revision,
    CancelToken cancelToken,
  ) async {
    try {
      final suggestions = loadDestinations != null
          ? await loadDestinations!(query)
          : await ApiService.instance.suggestHotelDestinations(
              query,
              languageCode: _destinationLanguage,
              cancelToken: cancelToken,
            );
      if (revision != _destinationSuggestionRevision) return;
      destinationSuggestions = suggestions;
      hasDestinationSuggestionError = false;
    } catch (_) {
      if (revision != _destinationSuggestionRevision) return;
      destinationSuggestions = const [];
      hasDestinationSuggestionError = true;
    } finally {
      if (revision == _destinationSuggestionRevision) {
        isLoadingDestinationSuggestions = false;
        notifyListeners();
      }
    }
  }

  void clearDestinationSuggestions() {
    _destinationDebounce?.cancel();
    _destinationDebounce = null;
    _destinationCancelToken?.cancel('Destination selection changed');
    _destinationCancelToken = null;
    _destinationSuggestionRevision++;
    _destinationQuery = '';
    destinationSuggestions = const [];
    isLoadingDestinationSuggestions = false;
    hasDestinationSuggestionError = false;
    notifyListeners();
  }

  Future<void> searchNearby(
    HotelSearchParams params, {
    required double latitude,
    required double longitude,
    double radiusMeters = defaultNearbyRadiusMeters,
  }) async {
    final revision = ++_searchRevision;
    _isNearbySearch = true;
    _serverFiltered = false;
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
    searchWarnings = const [];
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
    if (filter == f) return;
    filter = f;
    _serverFiltered = false;
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
    if (!_serverFiltered) {
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

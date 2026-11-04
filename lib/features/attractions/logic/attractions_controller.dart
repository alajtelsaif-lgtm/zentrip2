import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/current_location_service.dart';
import '../../../models/attraction_model.dart';
import '../../../models/attraction_place_suggestion.dart';
import '../../../models/attraction_search_page.dart';
import '../../../models/attraction_recent_destination.dart';

typedef AttractionSearchFunction = Future<List<AttractionModel>> Function({
  required String city,
  String? country,
  String? language,
});

typedef AttractionSearchPageFunction = Future<AttractionSearchPage> Function({
  required String city,
  String? category,
  String? country,
  String? language,
  double? latitude,
  double? longitude,
  double? south,
  double? west,
  double? north,
  double? east,
  String? placeId,
  int limit,
  int offset,
});

typedef AttractionSuggestionsFunction = Future<List<AttractionPlaceSuggestion>>
    Function(String query, {String? language});

typedef CurrentPlaceLoader = Future<CurrentPlace> Function();
typedef AttractionPreferencesLoader = Future<SharedPreferences> Function();
typedef RecentAttractionDestinationLoader = Future<AttractionRecentDestination?>
    Function();

class AttractionsController extends ChangeNotifier {
  AttractionsController({
    AttractionSearchFunction? searchAttractions,
    AttractionSearchPageFunction? searchPage,
    AttractionSuggestionsFunction? searchSuggestions,
    CurrentPlaceLoader? loadCurrentPlace,
    AttractionPreferencesLoader? loadPreferences,
    RecentAttractionDestinationLoader? loadRecentDestination,
  })  : _supportsPaging = searchAttractions == null || searchPage != null,
        _searchPage = searchPage ??
            (searchAttractions == null
                ? ApiService.instance.searchAttractionPage
                : ({
                    required String city,
                    String? category,
                    String? country,
                    String? language,
                    double? latitude,
                    double? longitude,
                    double? south,
                    double? west,
                    double? north,
                    double? east,
                    String? placeId,
                    int limit = 40,
                    int offset = 0,
                  }) async {
                    final found = await searchAttractions(
                      city: city,
                      country: country,
                      language: language,
                    );
                    return AttractionSearchPage(
                      attractions: found,
                      totalCount: found.length,
                      hasMore: false,
                    );
                  }),
        _searchSuggestions = searchSuggestions,
        _loadCurrentPlace = loadCurrentPlace ??
            (() => const CurrentLocationService().getCurrentPlace()),
        _loadPreferences = loadPreferences ?? SharedPreferences.getInstance,
        _loadRecentDestination = loadRecentDestination ??
            (searchAttractions != null || searchPage != null
                ? () async => null
                : ApiService.instance.recentAttractionDestination);

  static const _lastCityKey = 'attraction_last_city';
  static const _lastCountryKey = 'attraction_last_country';
  static const _lastDisplayKey = 'attraction_last_display';
  static const _lastSearchAtKey = 'attraction_last_search_at';
  static const _suggestionDebounce = Duration(milliseconds: 400);
  static const _pageSize = 40;

  final AttractionSearchPageFunction _searchPage;
  final bool _supportsPaging;
  final AttractionSuggestionsFunction? _searchSuggestions;
  final CurrentPlaceLoader _loadCurrentPlace;
  final AttractionPreferencesLoader _loadPreferences;
  final RecentAttractionDestinationLoader _loadRecentDestination;

  List<AttractionModel> _all = [];
  List<AttractionModel> results = [];
  bool isLoading = false;
  bool hasError = false;
  bool cityNotFound = false;
  bool hasSearched = false;
  bool isLoadingMore = false;
  bool hasMore = false;
  List<String> warnings = [];
  String searchQuery = '';
  String selectedCategory = 'all';
  int _requestGeneration = 0;
  int _suggestionGeneration = 0;
  int _offset = 0;
  String _lastCity = '';
  String _lastCountry = '';
  String _lastDisplay = '';
  String _lastLanguage = 'en';
  double? _lastLatitude;
  double? _lastLongitude;
  double? _lastSouth;
  double? _lastWest;
  double? _lastNorth;
  double? _lastEast;
  String? _lastPlaceId;

  static const categories = [
    'all',
    'historical',
    'natural',
    'architecture',
    'landmark',
    'museum',
    'park',
    'beach',
  ];

  /// Place categories shown in the popular-places home section.
  static const monumentCategories = {
    'historical',
    'natural',
    'cultural',
    'architecture',
    'landmark',
    'museum',
    'park',
    'beach',
  };

  static bool isMonument(AttractionModel attraction) =>
      monumentCategories.contains(attraction.category.toLowerCase());

  /// Reuses the most recent search or saved trip/booking before geolocation.
  Future<String?> loadDefault({String language = 'en'}) async {
    final generation = ++_requestGeneration;
    isLoading = true;
    hasError = false;
    cityNotFound = false;
    hasSearched = false;
    notifyListeners();

    String lastCity = '';
    String lastCountry = '';
    String lastDisplay = '';
    DateTime? lastSearchAt;
    try {
      final preferences = await _loadPreferences();
      lastCity = preferences.getString(_lastCityKey) ?? '';
      lastCountry = preferences.getString(_lastCountryKey) ?? '';
      lastDisplay = preferences.getString(_lastDisplayKey) ?? '';
      lastSearchAt = DateTime.tryParse(
        preferences.getString(_lastSearchAtKey) ?? '',
      );
    } catch (_) {
      // Preferences are optional; without them the screen remains empty.
    }

    if (generation != _requestGeneration) return null;
    AttractionRecentDestination? recent;
    try {
      recent =
          await _loadRecentDestination().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Recent trip/booking lookup is optional; local history still works.
    }
    if (generation != _requestGeneration) return null;

    final hasLocalDestination =
        lastCity.trim().isNotEmpty || lastCountry.trim().isNotEmpty;
    final hasRecentDestination = recent != null && recent.city.isNotEmpty;
    final recentAt = recent?.createdAt;
    final preferRecent = hasRecentDestination &&
        (!hasLocalDestination ||
            recentAt == null ||
            lastSearchAt == null ||
            recentAt.isAfter(lastSearchAt));
    if (preferRecent) {
      await load(
        city: recent.city,
        country: recent.country,
        language: language,
        displayQuery: recent.city,
      );
      return recent.city;
    }

    if (hasLocalDestination) {
      final display =
          lastDisplay.trim().isNotEmpty ? lastDisplay.trim() : lastCity.trim();
      await load(
        city: lastCity,
        country: lastCountry,
        language: language,
        displayQuery: display,
      );
      return display.isEmpty ? null : display;
    }

    try {
      final currentPlace =
          await _loadCurrentPlace().timeout(const Duration(seconds: 8));
      final city = currentPlace.city?.trim() ?? '';
      if (city.isNotEmpty && generation == _requestGeneration) {
        await load(
          city: city,
          country: currentPlace.country,
          language: language,
          displayQuery: city,
        );
        return city;
      }
    } catch (_) {
      // Location access is optional; the screen keeps its existing empty state.
    }

    if (generation != _requestGeneration) return null;
    isLoading = false;
    hasError = false;
    cityNotFound = false;
    hasSearched = false;
    _all = [];
    results = [];
    notifyListeners();
    return null;
  }

  Future<void> load({
    String? city,
    String? country,
    String language = 'en',
    String? displayQuery,
    double? latitude,
    double? longitude,
    double? south,
    double? west,
    double? north,
    double? east,
    String? placeId,
  }) async {
    final requestGeneration = ++_requestGeneration;
    isLoading = true;
    isLoadingMore = false;
    hasError = false;
    cityNotFound = false;
    hasSearched = true;
    searchQuery = displayQuery ?? city?.trim() ?? '';
    warnings = [];
    _offset = 0;
    hasMore = false;
    _lastCity = city ?? '';
    _lastCountry = country ?? '';
    _lastDisplay = displayQuery ?? city ?? '';
    _lastLanguage = language;
    _lastLatitude = latitude;
    _lastLongitude = longitude;
    _lastSouth = south;
    _lastWest = west;
    _lastNorth = north;
    _lastEast = east;
    _lastPlaceId = placeId;
    notifyListeners();
    try {
      final page = await _searchPage(
        city: city ?? '',
        category: selectedCategory == 'all' ? null : selectedCategory,
        country: country,
        language: language,
        latitude: latitude,
        longitude: longitude,
        south: south,
        west: west,
        north: north,
        east: east,
        placeId: placeId,
        limit: _pageSize,
        offset: 0,
      );
      if (requestGeneration != _requestGeneration) return;
      _all = page.attractions.where(isMonument).toList();
      _offset = page.attractions.length;
      hasMore = _supportsPaging && page.hasMore;
      warnings = page.warnings;
      _persistLastSearch(
        city: city ?? '',
        country: country ?? '',
        display: displayQuery ?? city ?? '',
      );
    } on AttractionCityNotFoundException {
      if (requestGeneration != _requestGeneration) return;
      _all = [];
      cityNotFound = true;
      hasMore = false;
    } catch (_) {
      if (requestGeneration != _requestGeneration) return;
      _all = [];
      hasError = true;
      hasMore = false;
    }
    if (requestGeneration != _requestGeneration) return;
    _applyCategory();
    isLoading = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (!_supportsPaging || !hasMore || isLoading || isLoadingMore) return;
    final generation = _requestGeneration;
    isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _searchPage(
        city: _lastCity,
        category: selectedCategory == 'all' ? null : selectedCategory,
        country: _lastCountry,
        language: _lastLanguage,
        latitude: _lastLatitude,
        longitude: _lastLongitude,
        south: _lastSouth,
        west: _lastWest,
        north: _lastNorth,
        east: _lastEast,
        placeId: _lastPlaceId,
        limit: _pageSize,
        offset: _offset,
      );
      if (generation != _requestGeneration) return;
      final existingIds = _all.map((item) => item.id).toSet();
      _all.addAll(page.attractions.where(
        (item) => isMonument(item) && existingIds.add(item.id),
      ));
      _offset += page.attractions.length;
      hasMore = page.hasMore;
      warnings = {...warnings, ...page.warnings}.toList();
      _applyCategory();
    } catch (_) {
      // Keep the visible results and allow a later scroll to retry the page.
    }
    if (generation != _requestGeneration) return;
    isLoadingMore = false;
    notifyListeners();
  }

  Future<List<AttractionPlaceSuggestion>> suggestionsFor(
    String query, {
    String language = 'en',
    bool debounce = true,
  }) async {
    final normalizedQuery = query.trim();
    final generation = ++_suggestionGeneration;
    if (normalizedQuery.length < 2) return const [];
    if (debounce) await Future<void>.delayed(_suggestionDebounce);
    if (generation != _suggestionGeneration) return const [];
    try {
      final suggestions = _searchSuggestions == null
          ? await ApiService.instance.searchAttractionSuggestions(
              normalizedQuery,
              language: language,
              latitude: _lastLatitude,
              longitude: _lastLongitude,
            )
          : await _searchSuggestions(
              normalizedQuery,
              language: language,
            );
      return generation == _suggestionGeneration ? suggestions : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> loadSuggestion(
    AttractionPlaceSuggestion suggestion, {
    String language = 'en',
  }) async {
    final country = suggestion.countryCode.isNotEmpty
        ? suggestion.countryCode
        : suggestion.country;
    await load(
      city: suggestion.isCountry
          ? ''
          : suggestion.city.isNotEmpty
              ? suggestion.city
              : suggestion.label,
      country: country,
      language: language,
      displayQuery: suggestion.label,
      latitude: suggestion.latitude,
      longitude: suggestion.longitude,
      south: suggestion.south,
      west: suggestion.west,
      north: suggestion.north,
      east: suggestion.east,
      placeId: suggestion.placeId,
    );
  }

  Future<void> searchPlace(
    String query, {
    String language = 'en',
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      await loadDefault(language: language);
      return;
    }
    final suggestions = await suggestionsFor(
      normalizedQuery,
      language: language,
      debounce: false,
    );
    if (suggestions.isNotEmpty) {
      await loadSuggestion(suggestions.first, language: language);
      return;
    }
    await load(
      city: normalizedQuery,
      language: language,
      displayQuery: normalizedQuery,
    );
  }

  void clearSearch() {
    _requestGeneration++;
    _suggestionGeneration++;
    ApiService.instance.cancelAttractionRequests();
    _all = [];
    results = [];
    warnings = [];
    searchQuery = '';
    _lastCity = '';
    _lastCountry = '';
    _lastDisplay = '';
    _lastLatitude = null;
    _lastLongitude = null;
    _lastSouth = null;
    _lastWest = null;
    _lastNorth = null;
    _lastEast = null;
    _lastPlaceId = null;
    _offset = 0;
    isLoading = false;
    isLoadingMore = false;
    hasMore = false;
    hasError = false;
    cityNotFound = false;
    hasSearched = false;
    notifyListeners();
  }

  void setCategory(String category) {
    if (!categories.contains(category)) return;
    if (selectedCategory == category) return;
    selectedCategory = category;
    _applyCategory();
    if (_supportsPaging && hasSearched) {
      unawaited(load(
        city: _lastCity,
        country: _lastCountry,
        language: _lastLanguage,
        displayQuery: _lastDisplay,
        latitude: _lastLatitude,
        longitude: _lastLongitude,
        south: _lastSouth,
        west: _lastWest,
        north: _lastNorth,
        east: _lastEast,
        placeId: _lastPlaceId,
      ));
      return;
    }
    notifyListeners();
  }

  void _applyCategory() {
    results = selectedCategory == 'all'
        ? List.of(_all)
        : _all
            .where((attraction) =>
                attraction.category.toLowerCase() == selectedCategory)
            .toList();
  }

  void _persistLastSearch({
    required String city,
    required String country,
    required String display,
  }) {
    if (city.trim().isEmpty && country.trim().isEmpty) return;
    unawaited(() async {
      try {
        final preferences = await _loadPreferences();
        await preferences.setString(_lastCityKey, city.trim());
        await preferences.setString(_lastCountryKey, country.trim());
        await preferences.setString(_lastDisplayKey, display.trim());
        await preferences.setString(
          _lastSearchAtKey,
          DateTime.now().toUtc().toIso8601String(),
        );
      } catch (_) {
        // The screen remains functional if local persistence is unavailable.
      }
    }());
  }

  /// Featured places come from the catalog and are ranked by recorded visits.
  static Future<List<AttractionModel>> loadFeaturedMonuments({
    int limit = 8,
    required String city,
    required String country,
    String language = 'en',
    double? latitude,
    double? longitude,
  }) async {
    final all = await ApiService.instance.searchAttractions(
      city: city,
      country: country,
      language: language,
      latitude: latitude,
      longitude: longitude,
    );
    return rankFeaturedMonuments(all, limit: limit);
  }

  @visibleForTesting
  static List<AttractionModel> rankFeaturedMonuments(
    Iterable<AttractionModel> attractions, {
    int limit = 8,
  }) {
    final monuments = attractions.where(isMonument).toList()
      ..sort((a, b) {
        final visits = b.visitCount.compareTo(a.visitCount);
        if (visits != 0) return visits;
        final ratings = b.rating.compareTo(a.rating);
        if (ratings != 0) return ratings;
        return (a.distanceKm ?? double.infinity)
            .compareTo(b.distanceKm ?? double.infinity);
      });
    return monuments.take(limit).toList();
  }

  @override
  void dispose() {
    _requestGeneration++;
    _suggestionGeneration++;
    super.dispose();
  }
}

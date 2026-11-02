import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/current_location_service.dart';
import '../../../models/attraction_model.dart';
import '../../../models/attraction_place_suggestion.dart';

typedef AttractionSearchFunction = Future<List<AttractionModel>> Function({
  required String city,
  String? country,
  String? language,
});

typedef AttractionSuggestionsFunction = Future<List<AttractionPlaceSuggestion>>
    Function(String query, {String? language});

typedef CurrentPlaceLoader = Future<CurrentPlace> Function();
typedef AttractionPreferencesLoader = Future<SharedPreferences> Function();

class AttractionsController extends ChangeNotifier {
  AttractionsController({
    AttractionSearchFunction? searchAttractions,
    AttractionSuggestionsFunction? searchSuggestions,
    CurrentPlaceLoader? loadCurrentPlace,
    AttractionPreferencesLoader? loadPreferences,
  })  : _searchAttractions = searchAttractions ??
            (({required city, country, language}) =>
                ApiService.instance.searchAttractions(
                  city: city,
                  country: country,
                  language: language,
                )),
        _searchSuggestions = searchSuggestions ??
            ((query, {language}) => ApiService.instance
                .searchAttractionSuggestions(query, language: language)),
        _loadCurrentPlace = loadCurrentPlace ??
            (() => const CurrentLocationService().getCurrentPlace()),
        _loadPreferences = loadPreferences ?? SharedPreferences.getInstance;

  static const _lastCityKey = 'attraction_last_city';
  static const _lastCountryKey = 'attraction_last_country';
  static const _lastDisplayKey = 'attraction_last_display';
  static const _suggestionDebounce = Duration(milliseconds: 300);

  final AttractionSearchFunction _searchAttractions;
  final AttractionSuggestionsFunction _searchSuggestions;
  final CurrentPlaceLoader _loadCurrentPlace;
  final AttractionPreferencesLoader _loadPreferences;

  List<AttractionModel> _all = [];
  List<AttractionModel> results = [];
  bool isLoading = false;
  bool hasError = false;
  bool cityNotFound = false;
  bool hasSearched = false;
  String searchQuery = '';
  String selectedCategory = 'all';
  int _requestGeneration = 0;
  int _suggestionGeneration = 0;

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

  /// Loads the current city first, then the last successful search.
  /// If neither is available, the screen keeps its existing empty state.
  Future<String?> loadDefault({String language = 'en'}) async {
    final generation = ++_requestGeneration;
    isLoading = true;
    hasError = false;
    cityNotFound = false;
    hasSearched = false;
    notifyListeners();

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
      // Location access is optional; the saved search is the fallback.
    }

    if (generation != _requestGeneration) return null;
    String lastCity = '';
    String lastCountry = '';
    String lastDisplay = '';
    try {
      final preferences = await _loadPreferences();
      lastCity = preferences.getString(_lastCityKey) ?? '';
      lastCountry = preferences.getString(_lastCountryKey) ?? '';
      lastDisplay = preferences.getString(_lastDisplayKey) ?? '';
    } catch (_) {
      // Preferences are optional; without them the screen remains empty.
    }

    if (generation != _requestGeneration) return null;
    if (lastCity.trim().isNotEmpty || lastCountry.trim().isNotEmpty) {
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
  }) async {
    final requestGeneration = ++_requestGeneration;
    isLoading = true;
    hasError = false;
    cityNotFound = false;
    hasSearched = true;
    searchQuery = displayQuery ?? city?.trim() ?? '';
    notifyListeners();
    try {
      final found = await _searchAttractions(
        city: city ?? '',
        country: country,
        language: language,
      );
      if (requestGeneration != _requestGeneration) return;
      _all = found.where(isMonument).toList();
      _persistLastSearch(
        city: city ?? '',
        country: country ?? '',
        display: displayQuery ?? city ?? '',
      );
    } on AttractionCityNotFoundException {
      if (requestGeneration != _requestGeneration) return;
      _all = [];
      cityNotFound = true;
    } catch (_) {
      if (requestGeneration != _requestGeneration) return;
      _all = [];
      hasError = true;
    }
    if (requestGeneration != _requestGeneration) return;
    _applyCategory();
    isLoading = false;
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
      final suggestions = await _searchSuggestions(
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

  void setCategory(String category) {
    if (!categories.contains(category)) return;
    selectedCategory = category;
    _applyCategory();
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
      } catch (_) {
        // The screen remains functional if local persistence is unavailable.
      }
    }());
  }

  /// Featured places come from the catalog and are ranked by recorded visits.
  static Future<List<AttractionModel>> loadFeaturedMonuments({
    int limit = 8,
    String city = 'Tripoli',
    String country = 'Libya',
    String language = 'en',
  }) async {
    final all = await ApiService.instance.searchAttractions(
      city: city,
      country: country,
      language: language,
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

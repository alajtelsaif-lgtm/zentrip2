import 'package:flutter/foundation.dart';
import '../../../core/services/api_service.dart';
import '../../../models/attraction_model.dart';
import '../../../models/flight_model.dart';

class AttractionsController extends ChangeNotifier {
  List<AttractionModel> _all = [];
  List<AttractionModel> results = [];
  bool isLoading = false;
  bool hasError = false;
  String searchQuery = '';
  String selectedCategory = 'all';
  String selectedCountry = 'Libya';

  static List<String> get countryOptions =>
      AirportOption.supported.map((airport) => airport.country).toSet().toList()
        ..sort();

  static const categories = [
    'all',
    'historical',
    'natural',
    'cultural',
    'architecture',
    'landmark',
    'museum',
    'park',
    'beach',
    'shopping',
    'restaurant',
    'cafe',
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

  static bool isMonument(AttractionModel a) =>
      monumentCategories.contains(a.category);

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

  Future<void> load({
    String? city,
    String? country,
    String language = 'en',
    String? initialCategory,
  }) async {
    isLoading = true;
    hasError = false;
    if (country != null && country.trim().isNotEmpty) {
      selectedCountry = country;
    }
    if (initialCategory != null && categories.contains(initialCategory)) {
      selectedCategory = initialCategory;
    }
    notifyListeners();
    try {
      _all = await ApiService.instance.searchAttractions(
        city: city ?? '',
        country: selectedCountry,
        language: language,
      );
    } catch (_) {
      _all = [];
      hasError = true;
    }
    _apply();
    isLoading = false;
    notifyListeners();
  }

  void setCategory(String cat) {
    selectedCategory = cat;
    _apply();
    notifyListeners();
  }

  void search(String query) {
    searchQuery = query;
    _apply();
    notifyListeners();
  }

  void _apply() {
    List<AttractionModel> r = List.of(_all);
    if (selectedCategory != 'all') {
      r = r.where((a) => a.category == selectedCategory).toList();
    }
    if (searchQuery.isNotEmpty) {
      r = r
          .where((a) =>
              a.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
              a.city.toLowerCase().contains(searchQuery.toLowerCase()))
          .toList();
    }
    results = r;
  }
}

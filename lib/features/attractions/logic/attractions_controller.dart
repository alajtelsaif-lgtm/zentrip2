import 'package:flutter/foundation.dart';
import '../../../core/services/api_service.dart';
import '../../../models/attraction_model.dart';

class AttractionsController extends ChangeNotifier {
  List<AttractionModel> _all = [];
  List<AttractionModel> results = [];
  bool isLoading = false;
  String searchQuery = '';
  String selectedCategory = 'all';

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
  };

  static bool isMonument(AttractionModel a) =>
      monumentCategories.contains(a.category);

  /// Featured places come from the catalog and are ranked by recorded visits.
  static Future<List<AttractionModel>> loadFeaturedMonuments(
      {int limit = 8}) async {
    final all = await ApiService.instance.searchAttractions(city: '');
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
        return visits != 0 ? visits : b.rating.compareTo(a.rating);
      });
    return monuments.take(limit).toList();
  }

  Future<void> load({String? city, String? initialCategory}) async {
    isLoading = true;
    if (initialCategory != null && categories.contains(initialCategory)) {
      selectedCategory = initialCategory;
    }
    notifyListeners();
    _all = await ApiService.instance.searchAttractions(city: city ?? '');
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

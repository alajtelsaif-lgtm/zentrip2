import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/api_service.dart';
import '../../../models/map_search_result.dart';

class FavoritePlace {
  final String id;
  final String title;
  final String subtitle;
  final String
      type; // 'destination' | 'hotel' | 'attraction' | 'restaurant' | 'cafe'
  final String? imageUrl;
  final double? latitude;
  final double? longitude;

  const FavoritePlace({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    this.imageUrl,
    this.latitude,
    this.longitude,
  });

  factory FavoritePlace.fromMapSearchResult(MapSearchResult place) {
    final id = place.placeId ??
        '${place.category}:${place.title}:${place.address}'.toLowerCase();
    return FavoritePlace(
      id: id,
      title: place.title,
      subtitle: place.address,
      type: place.category,
      imageUrl: place.thumbnail,
      latitude: place.latitude,
      longitude: place.longitude,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'type': type,
        'image_url': imageUrl,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory FavoritePlace.fromJson(Map<String, dynamic> j) => FavoritePlace(
        id: j['id'] as String,
        title: j['title'] as String,
        subtitle: (j['subtitle'] as String?) ?? '',
        type: j['type'] as String,
        imageUrl: j['image_url'] as String?,
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
      );
}

class FavoritesController extends ChangeNotifier {
  static final FavoritesController instance = FavoritesController._();
  FavoritesController._();

  final List<FavoritePlace> _favorites = [];

  /// مفتاح مربوط بإيميل الحساب المسجّل دخول حاليًا — عشان مفضلة حساب
  /// معيّن متختلطش مع حساب تاني على نفس الجهاز.
  String get _key =>
      'favorites_v2_${ApiService.instance.currentUser?.email ?? 'guest'}';

  List<FavoritePlace> get all => List.unmodifiable(_favorites);

  bool isFavorite(String id) => _favorites.any((f) => f.id == id);

  /// One-time flag per account: device favorites saved before server sync
  /// existed are uploaded once, then the server is the source of truth.
  String get _uploadedKey => '${_key}_uploaded_to_server';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final keyAtLoad = _key;
    final raw = prefs.getStringList(keyAtLoad) ?? [];
    _favorites
      ..clear()
      ..addAll(raw.map((e) =>
          FavoritePlace.fromJson(jsonDecode(e) as Map<String, dynamic>)));
    notifyListeners();
    await _syncFromServer(prefs, keyAtLoad);
  }

  Future<void> _syncFromServer(SharedPreferences prefs, String keyAtLoad) async {
    final api = ApiService.instance;
    if (!api.canSyncSavedData) return;
    final result = await api.getFavorites();
    if (!result.isSuccess || result.data == null || _key != keyAtLoad) return;
    final server = <FavoritePlace>[];
    for (final row in result.data!) {
      try {
        server.add(FavoritePlace.fromJson(row));
      } catch (error) {
        debugPrint('Ignoring invalid server favorite: $error');
      }
    }
    if (prefs.getBool(_uploadedKey) != true) {
      final serverIds = server.map((f) => f.id).toSet();
      for (final local in _favorites.where((f) => !serverIds.contains(f.id))) {
        final saved = await api.saveFavorite(local.toJson());
        if (saved.isSuccess) server.add(local);
      }
      await prefs.setBool(_uploadedKey, true);
    }
    if (_key != keyAtLoad) return;
    _favorites
      ..clear()
      ..addAll(server);
    notifyListeners();
    await _persist();
  }

  /// بتتنادى عند تسجيل الخروج — عشان القائمة متفضلش شايلة بيانات الحساب
  /// القديم في الذاكرة لحد ما تسجل دخول تاني.
  void clear() {
    _favorites.clear();
    notifyListeners();
  }

  Future<void> toggle(FavoritePlace place) async {
    final removing = isFavorite(place.id);
    if (removing) {
      _favorites.removeWhere((f) => f.id == place.id);
    } else {
      _favorites.insert(0, place);
    }
    notifyListeners();
    await _persist();
    final api = ApiService.instance;
    if (!api.canSyncSavedData) return;
    final result = removing
        ? await api.removeFavorite(place.id)
        : await api.saveFavorite(place.toJson());
    if (result.isFailure) {
      debugPrint('Favorite was kept on this device only: ${result.errorMessage}');
    }
  }

  Future<void> remove(String id) async {
    _favorites.removeWhere((f) => f.id == id);
    notifyListeners();
    await _persist();
    final api = ApiService.instance;
    if (!api.canSyncSavedData) return;
    final result = await api.removeFavorite(id);
    if (result.isFailure) {
      debugPrint('Favorite removal was kept on this device only: ${result.errorMessage}');
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, _favorites.map((f) => jsonEncode(f.toJson())).toList());
  }
}

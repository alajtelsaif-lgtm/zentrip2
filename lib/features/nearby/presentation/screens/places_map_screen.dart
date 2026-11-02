import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/current_location_service.dart';
import '../../../../features/favorites/logic/favorites_controller.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/attraction_map_viewport.dart';
import '../../../../models/attraction_model.dart';
import '../../../../models/map_search_result.dart';

typedef AttractionViewportLoader = Future<AttractionMapViewport> Function({
  required double south,
  required double west,
  required double north,
  required double east,
  required double zoom,
  String? category,
  int minRate,
  String? language,
});

/// Unified place map with exclusive category filters and tappable markers.
class PlacesMapScreen extends StatefulWidget {
  final MapSearchResult? selectedPlace;
  final List<MapSearchResult> places;
  final AttractionViewportLoader? loadAttractionViewport;

  const PlacesMapScreen(
      {super.key,
      this.selectedPlace,
      this.places = const [],
      this.loadAttractionViewport});

  @override
  State<PlacesMapScreen> createState() => _PlacesMapScreenState();
}

enum _MapLayer { favorites, restaurants, cafes, hotels, attractions }

class _MapPlace {
  final String id;
  final String title;
  final String subtitle;
  final LatLng point;
  final _MapLayer layer;
  final String? priceOrRating;
  final MapSearchResult? result;
  final String? favoriteId;
  final int? clusterCount;
  const _MapPlace(
      {required this.id,
      required this.title,
      required this.subtitle,
      required this.point,
      required this.layer,
      this.priceOrRating,
      this.result,
      this.favoriteId,
      this.clusterCount});
}

class _PlacesMapScreenState extends State<PlacesMapScreen> {
  final _locationService = const CurrentLocationService();
  final MapController _mapController = MapController();
  final Map<String, _CachedAttractionViewport> _viewportCache = {};
  _MapLayer? _activeLayer;
  LatLng? _myLocation;
  CurrentLocationError? _locationError;
  bool _isLoading = true;
  double _mapZoom = 12;
  List<AttractionModel> _remoteAttractions = const [];
  List<AttractionMapCluster> _remoteClusters = const [];
  Timer? _viewportDebounce;
  int _viewportGeneration = 0;
  bool _initialViewportScheduled = false;

  @override
  void initState() {
    super.initState();
    if (widget.selectedPlace != null) _mapZoom = 16;
    _load();
  }

  Future<void> _load() async {
    if (widget.selectedPlace != null || widget.places.isNotEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final position = await _locationService.getPosition();
      _myLocation = LatLng(position.latitude, position.longitude);
      _locationError = null;
    } on CurrentLocationException catch (error) {
      _locationError = error.reason;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _viewportDebounce?.cancel();
    _viewportGeneration++;
    ApiService.instance.cancelAttractionRequests();
    super.dispose();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _mapZoom = camera.zoom;
    if (!hasGesture) return;
    _viewportDebounce?.cancel();
    _viewportDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_loadViewport(camera.visibleBounds, camera.zoom));
    });
  }

  void _loadInitialViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final camera = _mapController.camera;
        unawaited(_loadViewport(camera.visibleBounds, camera.zoom));
      } catch (_) {
        // The controller is not attached until FlutterMap has completed layout.
      }
    });
  }

  Future<void> _loadViewport(LatLngBounds bounds, double zoom) async {
    if (!mounted) return;
    final generation = ++_viewportGeneration;
    final key = [
      bounds.southWest.latitude.toStringAsFixed(3),
      bounds.southWest.longitude.toStringAsFixed(3),
      bounds.northEast.latitude.toStringAsFixed(3),
      bounds.northEast.longitude.toStringAsFixed(3),
      zoom.round(),
      Localizations.localeOf(context).languageCode,
    ].join(':');
    final cached = _viewportCache[key];
    if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
      if (widget.loadAttractionViewport == null) {
        ApiService.instance.cancelAttractionMapRequest();
      }
      if (!mounted) return;
      setState(() {
        _remoteAttractions = cached.viewport.attractions;
        _remoteClusters = cached.viewport.clusters;
        _mapZoom = zoom;
      });
      return;
    }

    try {
      final loader = widget.loadAttractionViewport ??
          ApiService.instance.searchAttractionMap;
      final viewport = await loader(
        south: bounds.southWest.latitude,
        west: bounds.southWest.longitude,
        north: bounds.northEast.latitude,
        east: bounds.northEast.longitude,
        zoom: zoom,
        language: Localizations.localeOf(context).languageCode,
      );
      if (!mounted || generation != _viewportGeneration) return;
      _viewportCache[key] = _CachedAttractionViewport(
        DateTime.now().add(const Duration(minutes: 5)),
        viewport,
      );
      if (_viewportCache.length > 32) {
        _viewportCache.remove(_viewportCache.keys.first);
      }
      setState(() {
        _remoteAttractions = viewport.attractions;
        _remoteClusters = viewport.clusters;
        _mapZoom = zoom;
      });
    } catch (_) {
      // Keep the last successful viewport visible when a request fails.
    }
  }

  String _locationErrorMessage(AppLocalizations l10n) =>
      switch (_locationError!) {
        CurrentLocationError.serviceDisabled =>
          l10n.nearbyLocationServiceDisabled,
        CurrentLocationError.permissionDenied =>
          l10n.nearbyLocationPermissionDenied,
        CurrentLocationError.permissionDeniedForever =>
          l10n.nearbyLocationPermissionDeniedForever,
        CurrentLocationError.unableToDetermine =>
          l10n.nearbyLocationUnableToDetermine,
      };

  _MapLayer? _layerForCategory(String category) => switch (category) {
        'restaurant' => _MapLayer.restaurants,
        'cafe' => _MapLayer.cafes,
        'hotel' => _MapLayer.hotels,
        'landmark' || 'attraction' => _MapLayer.attractions,
        _ => null,
      };

  _MapPlace _mapPlaceFromResult(MapSearchResult result) {
    final favorite = FavoritePlace.fromMapSearchResult(result);
    final rating = result.rating == null ? null : '★ ${result.rating}';
    return _MapPlace(
      id: favorite.id,
      title: result.title,
      subtitle: result.address,
      point: LatLng(result.latitude!, result.longitude!),
      layer: _layerForCategory(result.category) ?? _MapLayer.attractions,
      priceOrRating: rating,
      result: result,
    );
  }

  List<_MapPlace> get _places {
    final list = <_MapPlace>[];
    final visibleResultIds = <String>{};
    final showsAttractions =
        _activeLayer == null || _activeLayer == _MapLayer.attractions;
    for (final result in widget.places) {
      if (result.latitude == null || result.longitude == null) continue;
      final layer = _layerForCategory(result.category);
      if (layer == null || (_activeLayer != null && _activeLayer != layer)) {
        continue;
      }
      final mapPlace = _mapPlaceFromResult(result);
      list.add(mapPlace);
      visibleResultIds.add(mapPlace.id);
    }
    if (showsAttractions) {
      final clusteredIds = <String>{};
      if (_mapZoom < 7) {
        for (final cluster in _remoteClusters) {
          for (final place in cluster.places) {
            clusteredIds.add(place.id);
          }
          list.add(_MapPlace(
            id: 'cluster-${cluster.latitude}-${cluster.longitude}',
            title: '${cluster.count} places',
            subtitle: '',
            point: LatLng(cluster.latitude, cluster.longitude),
            layer: _MapLayer.attractions,
            clusterCount: cluster.count,
          ));
        }
      }
      for (final attraction in _remoteAttractions) {
        if (clusteredIds.contains(attraction.id) ||
            attraction.latitude < -90 ||
            attraction.latitude > 90 ||
            attraction.longitude < -180 ||
            attraction.longitude > 180) {
          continue;
        }
        final result = MapSearchResult(
          title: attraction.name,
          address: [attraction.city, attraction.country]
              .where((part) => part.trim().isNotEmpty)
              .join(', '),
          category: 'attraction',
          placeId: attraction.id,
          rating: attraction.rating,
          reviews: attraction.reviewCount,
          latitude: attraction.latitude,
          longitude: attraction.longitude,
          type: attraction.category,
          thumbnail: attraction.imageUrl,
        );
        final place = _mapPlaceFromResult(result);
        if (visibleResultIds.add(place.id)) list.add(place);
      }
    }
    for (final f in FavoritesController.instance.all) {
      if (f.latitude == null || f.longitude == null) continue;
      if ((_activeLayer != null && _activeLayer != _MapLayer.favorites) ||
          visibleResultIds.contains(f.id)) {
        continue;
      }
      list.add(_MapPlace(
        id: 'fav-${f.id}',
        title: f.title,
        subtitle: f.subtitle,
        point: LatLng(f.latitude!, f.longitude!),
        layer: _MapLayer.favorites,
        favoriteId: f.id,
      ));
    }
    return list;
  }

  (IconData, Color) _layerStyle(_MapLayer l) => switch (l) {
        _MapLayer.favorites => (Icons.bookmark_rounded, AppColors.accentOrange),
        _MapLayer.restaurants => (Icons.restaurant_rounded, AppColors.primary),
        _MapLayer.cafes => (Icons.local_cafe_rounded, const Color(0xFF8D6E63)),
        _MapLayer.hotels => (Icons.hotel_rounded, AppColors.accentPurple),
        _MapLayer.attractions => (Icons.place_rounded, AppColors.accentRed),
      };

  String _layerLabel(AppLocalizations l10n, _MapLayer l) => switch (l) {
        _MapLayer.favorites => l10n.favorites,
        _MapLayer.restaurants => l10n.nearbyRestaurants,
        _MapLayer.cafes => l10n.nearbyCafes,
        _MapLayer.hotels => l10n.nearbyHotels,
        _MapLayer.attractions => l10n.nearbyAttractions,
      };

  void _showMapResult(MapSearchResult result) {
    if (result.latitude == null || result.longitude == null) return;
    _showPlaceSheet(_mapPlaceFromResult(result));
  }

  void _onMapPlaceTap(_MapPlace place) {
    if (place.clusterCount != null) {
      final double nextZoom =
          (_mapController.camera.zoom + 2).clamp(0.0, 24.0).toDouble();
      _mapController.move(place.point, nextZoom);
      unawaited(_loadViewport(_mapController.camera.visibleBounds, nextZoom));
      return;
    }
    _showPlaceSheet(place);
  }

  void _showPlaceSheet(_MapPlace place) {
    final l10n = AppLocalizations.of(context);
    final (icon, color) = _layerStyle(place.layer);
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(place.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 3),
                        Text(place.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (place.priceOrRating != null)
                    Text(place.priceOrRating!,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: color,
                            fontSize: 14)),
                ],
              ),
              if (place.result?.phone != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(place.result!.phone!,
                      style: const TextStyle(color: AppColors.textSecondary)),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: ListenableBuilder(
                  listenable: FavoritesController.instance,
                  builder: (_, __) {
                    final favoriteId = place.result == null
                        ? place.favoriteId
                        : FavoritePlace.fromMapSearchResult(place.result!).id;
                    final isSaved = favoriteId != null &&
                        FavoritesController.instance.isFavorite(favoriteId);
                    return FilledButton.tonalIcon(
                      onPressed: favoriteId == null
                          ? null
                          : () async {
                              if (place.result != null) {
                                await FavoritesController.instance.toggle(
                                  FavoritePlace.fromMapSearchResult(
                                      place.result!),
                                );
                              } else {
                                await FavoritesController.instance
                                    .remove(favoriteId);
                              }
                              if (mounted) setState(() {});
                            },
                      icon: Icon(isSaved
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_add_outlined),
                      label: Text(isSaved ? l10n.savedPlace : l10n.savePlace),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedPlace = widget.selectedPlace;
    final places = _places;
    final selectedCenter = selectedPlace != null &&
            selectedPlace.latitude != null &&
            selectedPlace.longitude != null
        ? LatLng(selectedPlace.latitude!, selectedPlace.longitude!)
        : null;
    final center = selectedCenter ??
        _myLocation ??
        (places.isNotEmpty ? places.first.point : null);
    if (center != null && !_initialViewportScheduled) {
      _initialViewportScheduled = true;
      _loadInitialViewport();
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.placesMapTitle)),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : center == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_off_rounded,
                            color: AppColors.accentRed, size: 44),
                        const SizedBox(height: 12),
                        Text(
                          _locationErrorMessage(l10n),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _isLoading = true);
                            _load();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(l10n.retry),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: selectedCenter == null ? 12 : 16,
                        onPositionChanged: _onPositionChanged,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.zentrip.app',
                        ),
                        MarkerLayer(markers: [
                          if (selectedPlace != null &&
                              selectedPlace.latitude != null &&
                              selectedPlace.longitude != null)
                            Marker(
                              point: LatLng(selectedPlace.latitude!,
                                  selectedPlace.longitude!),
                              width: 52,
                              height: 52,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _showMapResult(selectedPlace),
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.red,
                                  size: 48,
                                ),
                              ),
                            ),
                          if (_myLocation != null)
                            Marker(
                              point: _myLocation!,
                              width: 22,
                              height: 22,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 6)
                                  ],
                                ),
                              ),
                            ),
                          for (final p in places)
                            Marker(
                              point: p.point,
                              width: 40,
                              height: 40,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _onMapPlaceTap(p),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _layerStyle(p.layer).$2,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.25),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2))
                                    ],
                                  ),
                                  child: p.clusterCount == null
                                      ? Icon(_layerStyle(p.layer).$1,
                                          color: Colors.white, size: 18)
                                      : Text(
                                          p.clusterCount.toString(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                        ]),
                      ],
                    ),
                    // ── طبقات قابلة للتفعيل ─────────────────────────────────
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _MapLayer.values.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final layer =
                                i == 0 ? null : _MapLayer.values[i - 1];
                            final isActive = _activeLayer == layer;
                            final (icon, color) = layer == null
                                ? (Icons.layers_rounded, AppColors.primary)
                                : _layerStyle(layer);
                            final label = layer == null
                                ? l10n.nearbyAll
                                : _layerLabel(l10n, layer);
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () =>
                                    setState(() => _activeLayer = layer),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? color
                                        : (isDark
                                            ? AppColors.darkSurface
                                            : Colors.white),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.12),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2))
                                    ],
                                  ),
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(icon,
                                            size: 15,
                                            color: isActive
                                                ? Colors.white
                                                : color),
                                        const SizedBox(width: 6),
                                        Text(label,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: isActive
                                                  ? Colors.white
                                                  : (isDark
                                                      ? AppColors
                                                          .darkTextPrimary
                                                      : AppColors.textPrimary),
                                            )),
                                      ]),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _CachedAttractionViewport {
  final DateTime expiresAt;
  final AttractionMapViewport viewport;

  const _CachedAttractionViewport(this.expiresAt, this.viewport);
}

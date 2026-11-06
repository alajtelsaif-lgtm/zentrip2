import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/services/location_settings_service.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../features/favorites/logic/favorites_controller.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/map_search_result.dart';
import '../../logic/nearby_controller.dart';
import 'places_map_screen.dart';

IconData _nearbyCategoryIcon(String category) => switch (category.toLowerCase()) {
      'all' => Icons.explore_rounded,
      'landmark' || 'landmarks' => Icons.account_balance_rounded,
      'restaurant' || 'restaurants' => Icons.restaurant_rounded,
      'cafe' || 'cafes' => Icons.local_cafe_rounded,
      'hotel' || 'hotels' => Icons.hotel_rounded,
      'attraction' || 'attractions' => Icons.attractions_rounded,
      'museum' || 'museums' => Icons.museum_rounded,
      'park' || 'parks' => Icons.park_rounded,
      'beach' || 'beaches' => Icons.beach_access_rounded,
      'shopping' => Icons.shopping_bag_rounded,
      _ => Icons.place_rounded,
    };

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key});

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  final _ctrl = NearbyController();
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.init();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.nearbyTitle,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      ListenableBuilder(
                        listenable: _ctrl,
                        builder: (_, __) => IconButton.filledTonal(
                          onPressed: _ctrl.isLoadingLocation ||
                                  _ctrl.isLoadingPlaces ||
                                  (_ctrl.allPlaces.isEmpty &&
                                      FavoritesController.instance.all.isEmpty)
                              ? null
                              : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PlacesMapScreen(
                                        places: _ctrl.allPlaces,
                                      ),
                                    ),
                                  ),
                          icon: const Icon(Icons.map_rounded),
                          tooltip: l10n.placesMapTitle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Search
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceSecondary
                          : AppColors.surfaceSecondary,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color:
                              isDark ? AppColors.darkBorder : AppColors.border),
                    ),
                    child: ListenableBuilder(
                      listenable: _ctrl,
                      builder: (_, __) => TextField(
                        controller: _searchCtrl,
                        onChanged: _ctrl.search,
                        decoration: InputDecoration(
                          hintText: l10n.nearbySearchHint,
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: AppColors.textSecondary, size: 20),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 14),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon:
                                      const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _ctrl.search('');
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Filters
                  _FilterChips(ctrl: _ctrl, l10n: l10n),
                ],
              ),
            ),

            // ── Places list ─────────────────────────────────────────────────
            Expanded(
              child: ListenableBuilder(
                listenable: _ctrl,
                builder: (_, __) {
                  if (_ctrl.isLoadingPlaces || _ctrl.isLoadingLocation) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary));
                  }
                  final placeResults = _ctrl.filtered;
                  if (placeResults.isEmpty) {
                    if (_ctrl.placesLoadError != null) {
                      return _PlacesLoadError(
                        l10n: l10n,
                        onRetry: _ctrl.retryPlaces,
                      );
                    }
                    if (_ctrl.locationError != null) {
                      return _LocationErrorView(
                          error: _ctrl.locationError!, l10n: l10n);
                    }
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 56, color: AppColors.textHint),
                          const SizedBox(height: 12),
                          Text(l10n.noNearbyPlaces,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      if (_ctrl.placesLoadError != null)
                        _PlacesLoadError(
                          l10n: l10n,
                          onRetry: _ctrl.retryPlaces,
                          compact: true,
                        ),
                      if (_ctrl.locationError != null)
                        _LocationErrorView(
                          error: _ctrl.locationError!,
                          l10n: l10n,
                          compact: true,
                        ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: placeResults.length,
                          itemBuilder: (_, i) => _PlaceCard(
                            place: placeResults[i],
                            places: _ctrl.allPlaces,
                            index: i,
                          )
                              .animate(delay: Duration(milliseconds: 60 * i))
                              .fade()
                              .slideY(begin: 0.05, end: 0),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final NearbyController ctrl;
  final AppLocalizations l10n;
  const _FilterChips({required this.ctrl, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final filters = [
      (NearbyFilter.all, l10n.nearbyAll),
      (NearbyFilter.landmark, l10n.nearbyLandmarks),
      (NearbyFilter.restaurant, l10n.nearbyRestaurants),
      (NearbyFilter.cafe, l10n.nearbyCafes),
      (NearbyFilter.hotel, l10n.nearbyHotels),
      (NearbyFilter.attraction, l10n.nearbyAttractions),
    ];
    return ListenableBuilder(
      listenable: ctrl,
      builder: (_, __) => SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: filters.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final (filter, label) = filters[i];
            final isSelected = ctrl.selectedFilter == filter;
            final icon = _nearbyCategoryIcon(switch (filter) {
              NearbyFilter.all => 'all',
              NearbyFilter.landmark => 'landmark',
              NearbyFilter.restaurant => 'restaurant',
              NearbyFilter.cafe => 'cafe',
              NearbyFilter.hotel => 'hotel',
              NearbyFilter.attraction => 'attraction',
            });
            return GestureDetector(
              onTap: () => ctrl.setFilter(filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        size: 16,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textSecondary),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color:
                            isSelected ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final MapSearchResult place;
  final List<MapSearchResult> places;
  final int index;
  const _PlaceCard(
      {required this.place, required this.places, required this.index});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlacesMapScreen(
            places: places,
            selectedPlace: place,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
        ),
        child: Row(
          children: [
            // Icon/category
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: AppColors.destinationGradients[
                    index % AppColors.destinationGradients.length],
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_nearbyCategoryIcon(place.category),
                  color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(place.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(place.address,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Colors.amber, size: 14),
                      Text(' ${place.rating?.toStringAsFixed(1) ?? '-'} ',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('(${place.reviews ?? 0})',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(place.category,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                const SizedBox(height: 6),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textHint, size: 18),
                ListenableBuilder(
                  listenable: FavoritesController.instance,
                  builder: (_, __) {
                    final favorite = FavoritePlace.fromMapSearchResult(place);
                    final isSaved =
                        FavoritesController.instance.isFavorite(favorite.id);
                    return IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: isSaved
                          ? AppLocalizations.of(context).removeSavedPlace
                          : AppLocalizations.of(context).savePlace,
                      onPressed: () =>
                          FavoritesController.instance.toggle(favorite),
                      icon: Icon(
                        isSaved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_add_outlined,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}

class _PlacesLoadError extends StatelessWidget {
  final AppLocalizations l10n;
  final VoidCallback onRetry;
  final bool compact;

  const _PlacesLoadError({
    required this.l10n,
    required this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: AppColors.textHint, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l10n.genericError,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(l10n.retry),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text(l10n.genericError,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationErrorView extends StatelessWidget {
  final NearbyLocationError error;
  final AppLocalizations l10n;
  final bool compact;
  const _LocationErrorView(
      {required this.error, required this.l10n, this.compact = false});

  String _message() {
    switch (error) {
      case NearbyLocationError.serviceDisabled:
        return l10n.nearbyLocationServiceDisabled;
      case NearbyLocationError.permissionDenied:
        return l10n.nearbyLocationPermissionDenied;
      case NearbyLocationError.permissionDeniedForever:
        return l10n.nearbyLocationPermissionDeniedForever;
      case NearbyLocationError.unableToDetermine:
        return l10n.nearbyLocationUnableToDetermine;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            const Icon(Icons.location_off_rounded,
                color: AppColors.accentRed, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_message(),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ),
            TextButton(
              onPressed: LocationSettingsService.isSupported
                  ? LocationSettingsService.openLocationSettings
                  : null,
              child: Text(l10n.openSettings),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_rounded,
                size: 64, color: AppColors.accentRed),
            const SizedBox(height: 16),
            Text(l10n.locationPermissionTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_message(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: LocationSettingsService.isSupported
                  ? LocationSettingsService.openLocationSettings
                  : null,
              icon: const Icon(Icons.settings_outlined),
              label: Text(l10n.openSettings),
            ),
          ],
        ),
      ),
    );
  }
}

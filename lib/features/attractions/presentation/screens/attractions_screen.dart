import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../global_widgets/app_network_image.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/attraction_model.dart';
import '../../../../routes/app_routes.dart';
import '../../logic/attractions_controller.dart';
import '../attraction_category.dart';

class AttractionsScreen extends StatefulWidget {
  const AttractionsScreen({super.key});

  @override
  State<AttractionsScreen> createState() => _AttractionsScreenState();
}

class _AttractionsScreenState extends State<AttractionsScreen> {
  final _ctrl = AttractionsController();
  final _searchCtrl = TextEditingController();
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    // ممكن تفتح الشاشة من الرئيسية مع فئة معيّنة (String) كـ route argument.
    final arg = ModalRoute.of(context)?.settings.arguments;
    _ctrl.load(
      country: _ctrl.selectedCountry,
      language: Localizations.localeOf(context).languageCode,
      initialCategory: arg is String ? arg : null,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.attractionsTitle)),
      body: Column(
        children: [
          // ── Search + filter ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(children: [
              DropdownButtonFormField<String>(
                value: _ctrl.selectedCountry,
                decoration: InputDecoration(
                  labelText: l10n.attractionCountryFilter,
                  prefixIcon: const Icon(Icons.public_rounded),
                  filled: true,
                  fillColor: isDark
                      ? AppColors.darkSurfaceSecondary
                      : AppColors.surfaceSecondary,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? AppColors.darkBorder : AppColors.border,
                    ),
                  ),
                ),
                items: AttractionsController.countryOptions
                    .map((country) => DropdownMenuItem(
                          value: country,
                          child: Text(country),
                        ))
                    .toList(),
                onChanged: (country) {
                  if (country == null) return;
                  _ctrl.load(
                    country: country,
                    language: Localizations.localeOf(context).languageCode,
                    initialCategory: _ctrl.selectedCategory,
                  );
                },
              ),
              const SizedBox(height: 10),
              Container(
                height: 46,
                decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceSecondary
                        : AppColors.surfaceSecondary,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color:
                            isDark ? AppColors.darkBorder : AppColors.border)),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _ctrl.search,
                  decoration: InputDecoration(
                    hintText: l10n.attractionSearchHint,
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppColors.textSecondary, size: 20),
                    border: InputBorder.none,
                    filled: false,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ListenableBuilder(
                listenable: _ctrl,
                builder: (_, __) => SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: AttractionsController.categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final cat = AttractionsController.categories[i];
                      final isSelected = _ctrl.selectedCategory == cat;
                      return GestureDetector(
                        onTap: () => _ctrl.setCategory(cat),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.accentPurple
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: isSelected
                                      ? AppColors.accentPurple
                                      : AppColors.border)),
                          child: Text(attractionCategoryLabel(l10n, cat),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500)),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ]),
          ),
          // ── Results ───────────────────────────────────────────────────
          Expanded(
            child: ListenableBuilder(
              listenable: _ctrl,
              builder: (_, __) {
                if (_ctrl.isLoading)
                  return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentPurple));
                if (_ctrl.hasError) {
                  return Center(
                    child: Text(
                      l10n.attractionCountryLoadError,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (_ctrl.results.isEmpty)
                  return Center(
                      child: Text(l10n.noResults,
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600)));
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 260,
                      childAspectRatio: 0.78,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12),
                  itemCount: _ctrl.results.length,
                  itemBuilder: (_, i) => _AttrCard(
                    attraction: _ctrl.results[i],
                    index: i,
                    onTap: () => Navigator.pushNamed(
                        context, AppRoutes.attractionDetail,
                        arguments: _ctrl.results[i]),
                  ).animate(delay: Duration(milliseconds: 60 * i)).fade().scale(
                      begin: const Offset(0.95, 0.95), end: const Offset(1, 1)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AttrCard extends StatelessWidget {
  final AttractionModel attraction;
  final int index;
  final VoidCallback onTap;
  const _AttrCard(
      {required this.attraction, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gradient = AppColors
        .destinationGradients[index % AppColors.destinationGradients.length];
    final icon = attractionCategoryIcon(attraction.category);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: gradient.colors.first.withValues(alpha: 0.3),
                blurRadius: 14,
                offset: const Offset(0, 6))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppNetworkImage(
                  url: attraction.imageUrl,
                  fallbackIcon: icon,
                  fallbackGradient: gradient),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x33000000),
                      Color(0x00000000),
                      Color(0xE6000000)
                    ],
                    stops: [0, 0.4, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(10)),
                          child: Icon(icon, color: Colors.white, size: 18)),
                    ]),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(attraction.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Colors.white)),
                          const SizedBox(height: 2),
                          Text('${attraction.city}, ${attraction.country}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 11)),
                          const SizedBox(height: 4),
                          if (attraction.rating > 0 &&
                                  attraction.reviewCount > 0 ||
                              !attraction.isExternal)
                            Row(children: [
                              if (attraction.rating > 0 &&
                                  attraction.reviewCount > 0) ...[
                                const Icon(Icons.star_rounded,
                                    color: Colors.amber, size: 12),
                                Text(
                                  ' ${attraction.rating}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              if (!attraction.isExternal)
                                attraction.isFree
                                    ? Text(l10n.free,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13))
                                    : Text(
                                        '\$${attraction.entryFee?.toStringAsFixed(0) ?? '?'}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15)),
                            ]),
                        ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

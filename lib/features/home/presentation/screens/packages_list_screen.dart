import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../global_widgets/app_network_image.dart';
import '../../../../global_widgets/currency_amount_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/travel_package_model.dart';
import '../../../trips/presentation/screens/package_detail_screen.dart';

/// نوع القائمة: "أفكار جديدة" (كل الوجهات) أو "العروض" (المميّزة أولاً).
enum PackagesListKind { ideas, deals }

class PackagesListArgs {
  final PackagesListKind kind;

  /// البيانات الحالية من الرئيسية — لو فاضية الشاشة بتجيبها بنفسها.
  final List<TravelPackage> packages;

  const PackagesListArgs({required this.kind, this.packages = const []});
}

/// شاشة "عرض الكل" لقسمي الأفكار الجديدة والعروض في الرئيسية.
/// بتاخد القائمة اللي الرئيسية بتعرضها (نفس المصدر) وتعيد تحميلها من الـ API
/// لو كانت فاضية أو لما المستخدم يسحب للتحديث.
class PackagesListScreen extends StatefulWidget {
  final PackagesListArgs args;
  const PackagesListScreen({super.key, required this.args});

  @override
  State<PackagesListScreen> createState() => _PackagesListScreenState();
}

class _PackagesListScreenState extends State<PackagesListScreen> {
  late List<TravelPackage> _packages = List.of(widget.args.packages);
  bool _loading = false;
  String? _error;
  String _category = 'all';

  @override
  void initState() {
    super.initState();
    if (_packages.isEmpty) _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ApiService.instance.getOffers();
    if (!mounted) return;
    setState(() {
      _packages = result.data ?? [];
      _error = result.isFailure ? result.errorMessage : null;
      _loading = false;
      if (_category != 'all' &&
          !_packages.any((p) => p.category == _category)) {
        _category = 'all';
      }
    });
  }

  List<TravelPackage> get _visible {
    var list = List<TravelPackage>.of(_packages);
    if (widget.args.kind == PackagesListKind.deals) {
      final featured = list.where((p) => p.isFeatured).toList();
      if (featured.isNotEmpty) list = featured;
    }
    if (_category != 'all') {
      list = list.where((p) => p.category == _category).toList();
    }
    if (widget.args.kind == PackagesListKind.deals) {
      // Keep the same featured-first fallback used by the Home offers row.
      list.sort((a, b) {
        if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
        return a.pricePerPerson.compareTo(b.pricePerPerson);
      });
    }
    return list;
  }

  String _categoryLabel(AppLocalizations l10n, String c) => switch (c) {
        'all' => l10n.attractionCategoryAll,
        'beach' => l10n.beach,
        'cultural' => l10n.attractionCatCultural,
        'city' => l10n.packageCatCity,
        'mountain' => l10n.packageCatMountain,
        'desert' => l10n.packageCatDesert,
        _ => c,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDeals = widget.args.kind == PackagesListKind.deals;
    final categories = [
      'all',
      ...{for (final p in _packages) p.category}
    ];
    final visible = _visible;

    return Scaffold(
      appBar:
          AppBar(title: Text(isDeals ? l10n.homeOffers : l10n.homeNewIdeas)),
      body: Column(
        children: [
          if (categories.length > 2)
            SizedBox(
              height: 52,
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final c = categories[i];
                  final selected = c == _category;
                  return ChoiceChip(
                    label: Text(_categoryLabel(l10n, c)),
                    selected: selected,
                    onSelected: (_) => setState(() => _category = c),
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12,
                    ),
                    showCheckmark: false,
                  );
                },
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _reload,
              child: _buildBody(l10n, visible, isDeals),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
      AppLocalizations l10n, List<TravelPackage> visible, bool isDeals) {
    if (_loading && _packages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (visible.isEmpty) {
      final message = _error != null
          ? l10n.homeOffersLoadError
          : (isDeals ? l10n.homeNoOffers : l10n.homeNoDestinations);
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Icon(Icons.travel_explore_rounded,
                      size: 64, color: AppColors.textHint),
                  const SizedBox(height: 16),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: _reload, child: Text(l10n.retry)),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 440,
        mainAxisExtent: 250,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: visible.length,
      itemBuilder: (context, i) => _PackageTile(
        package: visible[i],
        l10n: l10n,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PackageDetailScreen(package: visible[i])),
        ),
      )
          .animate(delay: Duration(milliseconds: 50 * (i % 8)))
          .fade()
          .slideY(begin: 0.05, end: 0),
    );
  }
}

class _PackageTile extends StatelessWidget {
  final TravelPackage package;
  final AppLocalizations l10n;
  final VoidCallback onTap;
  const _PackageTile(
      {required this.package, required this.l10n, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: package.gradient,
            boxShadow: [
              BoxShadow(
                color: package.gradient.colors.first.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AppNetworkImage(
                  url: package.imageUrl,
                  fallbackIcon: package.icon,
                  fallbackGradient: package.gradient,
                ),
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
                PositionedDirectional(
                  top: 12,
                  start: 12,
                  child: _Badge(text: package.country),
                ),
                if (package.isFeatured)
                  PositionedDirectional(
                    top: 12,
                    end: 12,
                    child: _Badge(
                        text: l10n.homeFeaturedOffer,
                        color: AppColors.accentOrange),
                  ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.star_rounded,
                            color: AppColors.accentYellow, size: 15),
                        const SizedBox(width: 3),
                        Text(package.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(package.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 11)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(package.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      const SizedBox(height: 2),
                      CurrencyAmountText(
                        amount: package.pricePerPerson,
                        prefix: '${l10n.homeStartingFrom} ',
                        suffix: ' · ${package.durationLabel}',
                        decimalDigits: 0,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.9)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      );
}

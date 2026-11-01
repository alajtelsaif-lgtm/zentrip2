import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../global_widgets/app_network_image.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../global_widgets/price_comparison_controls.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/hotel_model.dart';
import '../../../../routes/app_routes.dart';
import '../../logic/hotel_controller.dart';

class HotelResultsScreen extends StatefulWidget {
  const HotelResultsScreen({super.key});

  @override
  State<HotelResultsScreen> createState() => _HotelResultsScreenState();
}

class _HotelResultsScreenState extends State<HotelResultsScreen> {
  HotelController? _ctrl;
  String? _lastWarningMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctrl ??= ModalRoute.of(context)?.settings.arguments as HotelController?;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final ctrl = _ctrl;
    if (ctrl == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _showSearchWarnings(
      ctrl.searchWarnings.isNotEmpty
          ? ctrl.searchWarnings
          : ctrl.hasSearchError
              ? [l10n.genericError]
              : const [],
    );

    return Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: ctrl,
          builder: (_, __) => Text(l10n.hotelResultsTitle(
              ctrl.searchParams?.city ?? '', ctrl.searchParams?.nights ?? 0)),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: ListenableBuilder(
            listenable: ctrl,
            builder: (_, __) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  for (final f in HotelFilter.values)
                    _FilterChip(
                        label: _filterLabel(f, l10n, ctrl.comparison.currency),
                        selected: ctrl.filter == f,
                        onTap: () => ctrl.setFilter(f)),
                  const SizedBox(width: 8),
                  Container(width: 1, height: 24, color: AppColors.border),
                  const SizedBox(width: 8),
                  for (final s in HotelSort.values)
                    _FilterChip(
                        label: _sortLabel(s, l10n),
                        selected: ctrl.sort == s,
                        onTap: () => ctrl.setSort(s),
                        isSort: true),
                ],
              ),
            ),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (_, __) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: PriceComparisonControls(
                comparison: ctrl.comparison,
                sourceCurrencies: ctrl.sourceCurrencies,
                unpricedCount: ctrl.unpricedCount,
              ),
            ),
            Expanded(
              child: ctrl.isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : ctrl.results.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                      ctrl.hasSearchError
                                          ? Icons.cloud_off_rounded
                                          : Icons.hotel_rounded,
                                      size: 56,
                                      color: AppColors.textHint),
                                  const SizedBox(height: 12),
                                  Text(
                                      ctrl.hasSearchError
                                          ? l10n.genericError
                                          : l10n.hotelNoResults,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w600)),
                                  if (ctrl.hasSearchError &&
                                      ctrl.searchParams != null) ...[
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          ctrl.search(ctrl.searchParams!),
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: Text(l10n.tryAgain),
                                    ),
                                  ],
                                ]),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: ctrl.results.length,
                          itemBuilder: (_, i) => _HotelCard(
                            hotel: ctrl.results[i],
                            nights: ctrl.searchParams?.nights ?? 1,
                            rooms: ctrl.searchParams?.rooms ?? 1,
                            comparisonPrice:
                                ctrl.comparisonPrice(ctrl.results[i]),
                            comparisonCurrency: ctrl.comparison.currency,
                            isDark: isDark,
                            l10n: l10n,
                            onTap: () {
                              ctrl.selectHotel(ctrl.results[i]);
                              Navigator.pushNamed(
                                  context, AppRoutes.hotelDetail,
                                  arguments: ctrl);
                            },
                          )
                              .animate(delay: Duration(milliseconds: 80 * i))
                              .fade()
                              .slideY(begin: 0.05, end: 0),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSearchWarnings(List<String> warnings) {
    final message = warnings.join(' ').trim();
    if (message.isEmpty) {
      _lastWarningMessage = null;
      return;
    }
    if (message == _lastWarningMessage) return;
    _lastWarningMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppSnackbar.warning(context, message);
    });
  }

  String _filterLabel(HotelFilter f, AppLocalizations l10n, String currency) =>
      switch (f) {
        HotelFilter.all => l10n.hotelFilterAll,
        HotelFilter.budget => l10n.hotelBudgetThreshold(currency),
        HotelFilter.midRange => l10n.hotelMidThreshold(currency),
        HotelFilter.luxury => l10n.hotelLuxuryThreshold(currency),
      };
  String _sortLabel(HotelSort s, AppLocalizations l10n) => switch (s) {
        HotelSort.rating => l10n.hotelSortRating,
        HotelSort.priceLow => l10n.hotelSortPriceLow,
        HotelSort.priceHigh => l10n.hotelSortPriceHigh,
        HotelSort.distance => l10n.hotelSortDistance,
      };
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isSort;
  const _FilterChip(
      {required this.label,
      required this.selected,
      required this.onTap,
      this.isSort = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (isSort ? AppColors.accentTeal : AppColors.primary)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected
                  ? (isSort ? AppColors.accentTeal : AppColors.primary)
                  : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12)),
      ),
    );
  }
}

class _HotelCard extends StatelessWidget {
  final HotelModel hotel;
  final int nights;
  final int rooms;
  final bool isDark;
  final VoidCallback onTap;
  final AppLocalizations l10n;
  final double? comparisonPrice;
  final String comparisonCurrency;
  const _HotelCard(
      {required this.hotel,
      required this.nights,
      required this.rooms,
      required this.isDark,
      required this.onTap,
      required this.comparisonPrice,
      required this.comparisonCurrency,
      required this.l10n});

  @override
  Widget build(BuildContext context) {
    final isSoldOut = hotel.availabilityKnown && hotel.availableRooms < rooms;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 4))
                ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image header
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: SizedBox(
              height: 140,
              child: Stack(fit: StackFit.expand, children: [
                AppNetworkImage(
                  url: hotel.imageUrl,
                  fallbackIcon: Icons.hotel_rounded,
                  fallbackGradient: AppColors.destinationGradients[
                      hotel.id.hashCode.abs() %
                          AppColors.destinationGradients.length],
                ),
                Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                              hotel.starRating,
                              (i) => const Icon(Icons.star_rounded,
                                  color: Colors.amber, size: 12))),
                    )),
                if (hotel.isFeatured)
                  Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(l10n.hotelFeatured,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      )),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hotel.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (hotel.hasGoogleRating)
                  Row(children: [
                    const Icon(Icons.star_rounded,
                        color: Colors.amber, size: 14),
                    Text('(${hotel.reviewCount})',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    Text(' ${hotel.rating.toStringAsFixed(1)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                  ])
                else
                  Text(
                    l10n.hotelRatingUnavailable,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ]),
              if (isSoldOut) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.hotelSoldOut,
                  style: const TextStyle(
                    color: AppColors.accentOrange,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 5),
              Row(children: [
                const Icon(Icons.place_outlined,
                    size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(hotel.address,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
              ]),
              if (hotel.distanceMeters != null) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.hotelDistanceKilometers(
                    (hotel.distanceMeters! / 1000).toStringAsFixed(1),
                  ),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                  spacing: 6,
                  children: hotel.amenities
                      .take(3)
                      .map((a) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: AppColors.primarySurface,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(a,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                          ))
                      .toList()),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${l10n.providerPrice} · ${hotel.isDuffelOffer ? l10n.offerSourceDuffel : l10n.offerSourcePartner}: ${hotel.comparisonNightlyPrice == null ? l10n.priceUnavailable : formatProviderMoney(hotel.pricePerNight, hotel.priceCurrencyCode)}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(l10n.hotelPerRoomNight,
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text(
                          comparisonPrice == null
                              ? '${l10n.comparisonEstimate}: ${l10n.priceUnavailable}'
                              : '${l10n.comparisonEstimate}: ${formatProviderMoney(comparisonPrice!, comparisonCurrency)}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.accentTeal,
                              fontWeight: FontWeight.w700),
                        ),
                        Text(l10n.hotelEstimatePerRoomNight,
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textSecondary)),
                        const SizedBox(height: 5),
                        Text(
                          '${l10n.hotelTotalLabel}: ${hotel.comparisonNightlyPrice == null ? l10n.priceUnavailable : formatProviderMoney(hotel.pricingFor(nights, rooms: rooms).totalPrice, hotel.priceCurrencyCode)} ${l10n.hotelNightsSuffix(nights)}',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                      onPressed: isSoldOut ? null : onTap,
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(92, 40)),
                      child: Text(
                          isSoldOut ? l10n.hotelSoldOut : l10n.hotelViewBtn)),
                ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../features/favorites/logic/favorites_controller.dart';
import '../../../../features/flight_booking/logic/flight_controller.dart';
import '../../../../features/flight_booking/presentation/screens/flight_booking_flow_screen.dart';
import '../../../../global_widgets/app_network_image.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../global_widgets/currency_amount_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/destination_info_model.dart';
import '../../../../models/travel_package_model.dart';

class PackageDetailScreen extends StatefulWidget {
  final TravelPackage package;
  const PackageDetailScreen({super.key, required this.package});

  @override
  State<PackageDetailScreen> createState() => _PackageDetailScreenState();
}

class _PackageDetailScreenState extends State<PackageDetailScreen> {
  bool _isBooking = false;

  Future<void> _bookOffer() async {
    final l10n = AppLocalizations.of(context);
    final package = widget.package;
    final flight = package.flight;
    if (flight == null || !flight.isActive) {
      AppSnackbar.error(context, l10n.flightProviderUnavailable);
      return;
    }
    final controller = FlightController();
    controller.selectFlight(flight);
    controller.searchParams = FlightSearchParams(
      originCode: flight.originCode,
      originCity: flight.originCity,
      destinationCode: flight.destinationCode,
      destinationCity: flight.destinationCity,
      departureDate: flight.departureTime,
      passengers: 1,
      seatClass: 'economy',
      isRoundTrip: false,
    );
    setState(() => _isBooking = true);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => FlightBookingFlowScreen(
            controller: controller,
            packageOffer: package,
          ),
        ),
      );
    } finally {
      controller.dispose();
      if (mounted) setState(() => _isBooking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final package = widget.package;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            stretch: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(package.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 8)])),
              background: AppNetworkImage(
                url: package.imageUrl,
                fallbackIcon: package.icon,
                fallbackGradient: package.gradient,
              ),
            ),
            actions: [
              ListenableBuilder(
                listenable: FavoritesController.instance,
                builder: (_, __) {
                  final isFav =
                      FavoritesController.instance.isFavorite(package.id);
                  return IconButton(
                    icon: Icon(
                        isFav
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: Colors.white),
                    onPressed: () => FavoritesController.instance.toggle(
                      FavoritePlace(
                          id: package.id,
                          title: package.title,
                          subtitle: package.location,
                          type: 'destination'),
                    ),
                  );
                },
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Meta ─────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(package.location,
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ),
                    const Spacer(),
                    RatingBarIndicator(
                        rating: package.rating,
                        itemSize: 16,
                        itemBuilder: (_, __) => const Icon(Icons.star_rounded,
                            color: Colors.amber)),
                    const SizedBox(width: 6),
                    Text('${package.rating}  (${package.reviewCount})',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ).animate().fade(duration: 300.ms),
                const SizedBox(height: 20),
                // ── خط الرحلة الجاهز: ليالي + سعر تذكرة + سعر فندق ────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color:
                            isDark ? AppColors.darkBorder : AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.nights_stay_rounded,
                              color: AppColors.accentTeal, size: 18),
                          const SizedBox(width: 8),
                          Text(package.durationLabel,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppColors.accentGreen
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(l10n.bookThisOffer,
                                style: const TextStyle(
                                    color: AppColors.accentGreen,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11)),
                          ),
                        ],
                      ),
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1)),
                      if (package.flight case final flight?)
                        Row(
                          children: [
                            const Icon(Icons.flight_takeoff_rounded,
                                color: AppColors.primary, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${l10n.packageAirline}: ${flight.airline}'
                                '${flight.flightNumber.isEmpty ? '' : ' · ${flight.flightNumber}'}'
                                ' · ${flight.originCode} → ${flight.destinationCode}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            l10n.flightProviderUnavailable,
                            style: const TextStyle(
                              color: AppColors.accentOrange,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      _PriceLine(
                          icon: Icons.flight_rounded,
                          label: l10n.packageTicketPrice,
                          value: package.flight?.economyPrice ??
                              package.flightPricePerPerson),
                      const SizedBox(height: 10),
                      _PriceLine(
                          icon: Icons.hotel_rounded,
                          label: l10n.packageHotelPricePerNight,
                          value: package.hotelPricePerNight),
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(l10n.packageTotalPrice,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                          CurrencyAmountText(
                              amount: package.totalPricePerPerson,
                              decimalDigits: 0,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                  color: AppColors.primary)),
                        ],
                      ),
                    ],
                  ),
                ).animate().fade(delay: 100.ms).slideY(begin: 0.05, end: 0),
                const SizedBox(height: 16),
                _DestinationInfoRow(
                        city: package.location, country: package.country)
                    .animate()
                    .fade(delay: 130.ms),
                const SizedBox(height: 20),
                // ── Description ───────────────────────────────────────
                Text(l10n.tripsAboutDestination,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(package.description,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(height: 1.7))
                    .animate()
                    .fade(delay: 150.ms),
                const SizedBox(height: 20),
                // ── Highlights ────────────────────────────────────────
                Text(l10n.tripsHighlights,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: package.highlights
                      .asMap()
                      .entries
                      .map((e) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: package.gradient.colors.first
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: package.gradient.colors.first
                                      .withValues(alpha: 0.2)),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.check_circle_rounded,
                                  color: package.gradient.colors.first,
                                  size: 14),
                              const SizedBox(width: 6),
                              Text(e.value,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: package.gradient.colors.first)),
                            ]),
                          )
                              .animate(
                                  delay: Duration(milliseconds: 80 * e.key))
                              .fade()
                              .scale())
                      .toList(),
                ),
                const SizedBox(height: 32),
                // ── زرار حجز واحد للعرض بالكامل ─────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isBooking ||
                            package.flight == null ||
                            !package.flight!.isActive
                        ? null
                        : _bookOffer,
                    icon: _isBooking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.card_travel_rounded, size: 18),
                    label: Text(_isBooking
                        ? l10n.flightBookingInProgress
                        : l10n.bookThisOffer),
                  ),
                ).animate().fade(delay: 300.ms),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  const _PriceLine(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary))),
        CurrencyAmountText(
            amount: value,
            decimalDigits: 0,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      ],
    );
  }
}

/// شريط سريع بمعلومات الطقس ومتطلبات التأشيرة للوجهة — بيتحمّل مستقل عن
/// باقي محتوى الشاشة عشان مايعطلش عرض تفاصيل العرض لو الطقس اتأخر مثلاً.
class _DestinationInfoRow extends StatefulWidget {
  final String city;
  final String country;
  const _DestinationInfoRow({required this.city, required this.country});

  @override
  State<_DestinationInfoRow> createState() => _DestinationInfoRowState();
}

class _DestinationInfoRowState extends State<_DestinationInfoRow> {
  WeatherInfo? _weather;
  VisaInfo? _visa;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final weatherRequest =
          ApiService.instance.getDestinationWeather(widget.city);
      final visaRequest = ApiService.instance.getVisaInfo(widget.country);
      final weatherResult = await weatherRequest;
      final visaResult = await visaRequest;
      if (!mounted) return;
      setState(() {
        _weather = weatherResult.data;
        _visa = visaResult.data;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _weather = null;
          _visa = null;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _visaLabel(AppLocalizations l10n, String requirement) =>
      switch (requirement) {
        'visa_free' => l10n.visaFree,
        'visa_on_arrival' => l10n.visaOnArrival,
        'e_visa' => l10n.eVisa,
        _ => l10n.visaRequired,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_loading) return const SizedBox.shrink();
    if (_weather == null && _visa == null) {
      return Text(
        l10n.destinationInfoUnavailable,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (_weather != null)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceSecondary
                          : AppColors.surfaceSecondary,
                      borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        const Icon(Icons.wb_sunny_rounded,
                            color: AppColors.accentOrange, size: 20),
                        const SizedBox(width: 8),
                        Text('${_weather!.tempCelsius.toStringAsFixed(0)}°C',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ]),
                      if (_weather!.isSample)
                        Text(l10n.sampleDataLabel,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            if (_weather != null && _visa != null) const SizedBox(width: 10),
            if (_visa != null)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceSecondary
                          : AppColors.surfaceSecondary,
                      borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        const Icon(Icons.badge_outlined,
                            color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_visaLabel(l10n, _visa!.requirement),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12),
                                overflow: TextOverflow.ellipsis)),
                      ]),
                      if (_visa!.isSample)
                        Text(l10n.sampleDataLabel,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 10)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (_weather == null || _visa == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.destinationInfoPartial,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

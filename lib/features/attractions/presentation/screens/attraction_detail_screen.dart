import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../features/favorites/logic/favorites_controller.dart';
import '../../../../global_widgets/app_network_image.dart';
import '../../../../global_widgets/app_shell.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../global_widgets/booking_load_error.dart';
import '../../../../global_widgets/payment_checkout_screen.dart';
import '../../../../features/notifications/logic/notifications_store.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/attraction_model.dart';
import '../../../../models/booking_model.dart';
import '../../../../routes/app_routes.dart';
import '../attraction_category.dart';

class AttractionDetailScreen extends StatefulWidget {
  const AttractionDetailScreen({super.key});

  @override
  State<AttractionDetailScreen> createState() => _AttractionDetailScreenState();
}

class _AttractionDetailScreenState extends State<AttractionDetailScreen> {
  AttractionModel? _attraction;
  bool _isBooking = false;
  bool _visitRecorded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attraction ??=
        ModalRoute.of(context)?.settings.arguments as AttractionModel?;
    final attraction = _attraction;
    if (attraction != null && !_visitRecorded) {
      _visitRecorded = true;
      if (!attraction.isExternal) {
        unawaited(_recordVisit(attraction.id));
      }
    }
  }

  Future<void> _recordVisit(String attractionId) async {
    try {
      await ApiService.instance.recordAttractionVisit(attractionId);
    } catch (error) {
      debugPrint('Could not record place visit: $error');
    }
  }

  Future<void> _bookTicket() async {
    final a = _attraction;
    if (a == null) {
      AppSnackbar.error(context, AppLocalizations.of(context).genericError);
      return;
    }
    final ref =
        'ZT-A-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final l10n = AppLocalizations.of(context);
    final today = DateTime.now();
    final visitDate = DateTime(today.year, today.month, today.day + 1);
    final visitEnd = visitDate.add(const Duration(days: 1));

    final availability = await ApiService.instance.checkBookingAvailability(
      type: BookingType.attraction,
      title: a.name,
      startDate: visitDate,
      endDate: visitEnd,
    );
    if (!mounted) return;
    if (availability.isFailure || availability.data != true) {
      AppSnackbar.error(
        context,
        availability.isFailure
            ? availability.errorMessage ?? l10n.genericError
            : l10n.bookingScheduleConflict,
      );
      return;
    }

    // لو النشاط مجاني (entryFee = null أو صفر) نتخطى الدفع تمامًا.
    int? paymentAttemptId;
    if (a.entryFee != null && a.entryFee! > 0) {
      final payment = await PaymentCheckoutScreen.start(context,
          amountUsd: a.entryFee!, description: a.name, referenceId: ref);
      if (!mounted) return;
      if (payment?.paid != true) {
        AppSnackbar.error(context, l10n.paymentFailedMessage);
        return;
      }
      paymentAttemptId = payment?.attemptId;
    }

    setState(() => _isBooking = true);
    await Future.delayed(const Duration(seconds: 1));
    final booking = BookingModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: BookingType.attraction,
      title: a.name,
      subtitle: a.city,
      date: visitDate,
      endDate: visitEnd,
      price: a.entryFee,
      refCode: ref,
      status: 'upcoming',
      imageUrl: a.imageUrl,
      partnerListingId: a.partnerListingId,
    );
    final createResult = await ApiService.instance.createBooking(
      booking,
      paymentAttemptId: paymentAttemptId,
    );
    if (createResult.isFailure) {
      if (!mounted) return;
      setState(() => _isBooking = false);
      AppSnackbar.error(
        context,
        createResult.errorMessage == 'BOOKING_SCHEDULE_CONFLICT'
            ? l10n.bookingScheduleConflict
            : createResult.errorMessage ?? l10n.genericError,
      );
      return;
    }
    setState(() => _isBooking = false);
    if (!mounted) return;
    AppSnackbar.success(context, l10n.attractionTicketBookedSuccess);
    unawaited(NotificationsStore.instance.refreshAfterBooking(
      title: l10n.notifBookingConfirmedTitle,
      subtitle: a.name,
      bookingRef: ref,
    ));
    if (!mounted) return;
    AppShellTabController.goToTab(3); // تاب "رحلاتي" — عشان يشوف حجزه فورًا
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final a = _attraction;
    if (a == null) return const BookingLoadError();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final gradientIndex =
        a.id.hashCode.abs() % AppColors.destinationGradients.length;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            stretch: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(a.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 8)])),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  AppNetworkImage(
                    url: a.imageUrl,
                    fallbackIcon: attractionCategoryIcon(a.category),
                    fallbackGradient:
                        AppColors.destinationGradients[gradientIndex],
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x33000000), Color(0x99000000)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              ListenableBuilder(
                listenable: FavoritesController.instance,
                builder: (_, __) {
                  final isFav = FavoritesController.instance.isFavorite(a.id);
                  return IconButton(
                    icon: Icon(
                        isFav
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: Colors.white),
                    onPressed: () =>
                        FavoritesController.instance.toggle(FavoritePlace(
                      id: a.id,
                      title: a.name,
                      subtitle: a.city,
                      type: a.category == 'restaurant' || a.category == 'cafe'
                          ? a.category
                          : 'attraction',
                      latitude: a.latitude,
                      longitude: a.longitude,
                    )),
                  );
                },
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Location + rating
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        const Icon(Icons.place_rounded,
                            color: AppColors.accentPurple, size: 16),
                        const SizedBox(width: 4),
                         Text(a.location,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13))
                      ]),
                      if (a.rating > 0 && a.reviewCount > 0)
                        Row(children: [
                          const Icon(Icons.star_rounded,
                              color: Colors.amber, size: 16),
                          Text(' ${a.rating} (${a.reviewCount})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13))
                        ]),
                    ]).animate().fade(duration: 300.ms),
                const SizedBox(height: 16),

                // Tags
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _Tag(
                      attractionCategoryLabel(l10n, a.category),
                      attractionCategoryIcon(a.category),
                      AppColors.accentPurple),
                  if (a.isFree)
                    _Tag(l10n.free, Icons.money_off_rounded,
                        AppColors.accentGreen),
                  if (a.distanceKm != null)
                    _Tag('${a.distanceKm!.toStringAsFixed(1)} km',
                        Icons.near_me_rounded, AppColors.primary),
                ]).animate().fade(delay: 100.ms),
                const SizedBox(height: 20),

                // Description
                if (a.description.trim().isNotEmpty) ...[
                  Text(l10n.attractionAbout,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(a.description,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(height: 1.7))
                      .animate()
                      .fade(delay: 150.ms),
                  const SizedBox(height: 20),
                ],
                if (a.sourceAttribution != null) ...[
                  Text(
                    a.sourceAttribution!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Visiting hours
                if (a.openingHours != null) ...[
                  _InfoCard(
                      isDark: isDark,
                      title: l10n.attractionVisitingHours,
                      children: [
                        _InfoRow(l10n.openingHours, a.openingHours!),
                        if (a.bestTimeToVisit != null)
                          _InfoRow(l10n.attractionBestTimeToVisit,
                              a.bestTimeToVisit!),
                        _InfoRow(
                            l10n.attractionEntryFee,
                            a.isFree
                                ? l10n.free
                                : '\$${a.entryFee?.toStringAsFixed(0) ?? '?'}'),
                      ]).animate().fade(delay: 200.ms),
                  const SizedBox(height: 28),
                ],

                // Book ticket
                if (!a.isFree)
                  ElevatedButton.icon(
                    onPressed: _isBooking ? null : _bookTicket,
                    icon: _isBooking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.confirmation_num_rounded),
                    label: Text(_isBooking
                        ? l10n.attractionBooking
                        : l10n.attractionBookTicket(
                            '\$${a.entryFee?.toStringAsFixed(0) ?? '?'}')),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentPurple),
                  ).animate().fade(delay: 250.ms)
                else
                  ElevatedButton.icon(
                    onPressed: () =>
                        AppSnackbar.info(context, l10n.attractionMapComingSoon),
                    icon: const Icon(Icons.map_rounded),
                    label: Text(l10n.attractionOpenOnMap),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentGreen),
                  ).animate().fade(delay: 250.ms),
                const SizedBox(height: 20),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _Tag(this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 12))
      ]),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isDark;
  const _InfoCard(
      {required this.title, required this.children, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border)),
        child: Column(children: children),
      ),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      );
}

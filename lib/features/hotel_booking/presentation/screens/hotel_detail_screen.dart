import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/api_result.dart';
import '../../../../global_widgets/app_network_image.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../global_widgets/booking_load_error.dart';
import '../../../../global_widgets/booking_confirmation_screen.dart';
import '../../../../global_widgets/booking_loading_overlay.dart';
import '../../../../global_widgets/payment_checkout_screen.dart';
import '../../../../global_widgets/review_form_sheet.dart';
import '../../../../features/notifications/logic/notifications_store.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/booking_model.dart';
import '../../../../models/hotel_model.dart';
import '../../../../models/review_model.dart';
import '../../logic/hotel_controller.dart';

class HotelDetailScreen extends StatefulWidget {
  const HotelDetailScreen({
    super.key,
    this.loadReviews,
  });

  final Future<ApiResult<List<ReviewModel>>> Function(String itemId)?
      loadReviews;

  @override
  State<HotelDetailScreen> createState() => _HotelDetailScreenState();
}

class _HotelDetailScreenState extends State<HotelDetailScreen> {
  HotelController? _ctrl;
  bool _isBooking = false;
  int _photoIndex = 0;
  Future<ApiResult<List<ReviewModel>>>? _hotelReviewsFuture;

  String _formatPrice(HotelModel hotel, double amount, {int decimals = 0}) {
    final locale = Localizations.localeOf(context).languageCode;
    if (hotel.priceCurrencyCode.toUpperCase() == 'LYD') {
      return formatCurrencyAmount(amount, 'LYD', locale: locale);
    }
    return '${hotel.priceCurrencyCode} ${amount.toStringAsFixed(decimals)}';
  }

  String _formatAvailablePrice(
    HotelModel hotel,
    double amount,
    AppLocalizations l10n, {
    int decimals = 0,
  }) =>
      hotel.comparisonNightlyPrice == null
          ? l10n.priceUnavailable
          : _formatPrice(hotel, amount, decimals: decimals);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller =
        ModalRoute.of(context)?.settings.arguments as HotelController?;
    if (_ctrl != controller) {
      _ctrl = controller;
      final hotel = controller?.selectedHotel;
      if (hotel != null) {
        final loadReviews = widget.loadReviews;
        _hotelReviewsFuture = loadReviews == null
            ? ApiService.instance.getReviews(itemId: hotel.id)
            : loadReviews(hotel.id);
      }
    }
  }

  void _writeHotelReview(HotelModel hotel) {
    ReviewFormSheet.show(
      context,
      itemId: hotel.id,
      itemType: 'hotel',
      onSubmitted: () {
        if (!mounted) return;
        setState(() {
          _hotelReviewsFuture =
              ApiService.instance.getReviews(itemId: hotel.id);
        });
      },
    );
  }

  Future<void> _book() async {
    final l10n = AppLocalizations.of(context);
    final ctrl = _ctrl;
    final selectedHotel = ctrl?.selectedHotel;
    final hotel = selectedHotel;
    if (hotel == null) {
      AppSnackbar.error(context, l10n.genericError);
      return;
    }
    final rooms = ctrl?.searchParams?.rooms ?? 1;
    if (hotel.availabilityKnown && hotel.availableRooms < rooms) {
      AppSnackbar.error(context, l10n.hotelSoldOut);
      return;
    }
    final checkIn = ctrl?.searchParams?.checkIn ?? DateTime.now();
    final checkOut =
        ctrl?.searchParams?.checkOut ?? checkIn.add(const Duration(days: 1));
    final availability = await ApiService.instance.checkBookingAvailability(
      type: BookingType.hotel,
      title: hotel.name,
      startDate: checkIn,
      endDate: checkOut,
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
    final nights = ctrl?.searchParams?.nights ?? 1;
    final totalPrice = hotel.pricingFor(nights, rooms: rooms).totalPrice;
    final ref =
        'ZT-H-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

    final payment = await PaymentCheckoutScreen.start(context,
        amountUsd: totalPrice, description: hotel.name, referenceId: ref);
    if (!mounted) return;
    if (payment?.paid != true) {
      AppSnackbar.error(context, l10n.paymentFailedMessage);
      return;
    }

    setState(() => _isBooking = true);
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    final booking = BookingModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: BookingType.hotel,
      title: hotel.name,
      subtitle: hotel.address,
      date: checkIn,
      endDate: checkOut,
      price: totalPrice,
      refCode: ref,
      status: 'upcoming',
      imageUrl: hotel.imageUrl,
      partnerListingId: hotel.partnerListingId,
      rooms: rooms,
    );
    final createResult = await BookingLoadingOverlay.run(
      context,
      title: l10n.hotelBookingInProgress,
      subtitle: hotel.name,
      serviceIcon: Icons.hotel_rounded,
      action: () => ApiService.instance.createBooking(
        booking,
        paymentAttemptId: payment?.attemptId,
      ),
    );
    if (createResult.isFailure) {
      if (!mounted) return;
      setState(() => _isBooking = false);
      AppSnackbar.error(
        context,
        createResult.errorMessage == 'BOOKING_SCHEDULE_CONFLICT'
            ? l10n.bookingScheduleConflict
            : createResult.errorMessage == 'HOTEL_SOLD_OUT'
                ? l10n.hotelSoldOut
                : createResult.errorMessage ?? l10n.genericError,
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isBooking = false);
    AppSnackbar.success(context, l10n.hotelBookingSuccess);
    unawaited(NotificationsStore.instance.refreshAfterBooking(
      title: l10n.notifBookingConfirmedTitle,
      subtitle: hotel.name,
      bookingRef: ref,
    ));
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingConfirmationScreen(
          serviceName: l10n.quickActionHotels,
          primaryText: hotel.name,
          secondaryText: hotel.address,
          reference: ref,
          dateLabel:
              MaterialLocalizations.of(context).formatMediumDate(checkIn),
          priceLabel: _formatPrice(hotel, totalPrice, decimals: 2),
          serviceIcon: Icons.hotel_rounded,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final ctrl = _ctrl;
    final hotel = ctrl?.selectedHotel;
    final nights = ctrl?.searchParams?.nights ?? 1;
    final rooms = ctrl?.searchParams?.rooms ?? 1;
    if (hotel == null) return const BookingLoadError();
    final isSoldOut = hotel.availabilityKnown && hotel.availableRooms < rooms;
    final pricing = hotel.pricingFor(nights, rooms: rooms);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            stretch: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(hotel.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 8)])),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    itemCount: hotel.photos.length,
                    onPageChanged: (index) =>
                        setState(() => _photoIndex = index),
                    itemBuilder: (context, index) => AppNetworkImage(
                      url: hotel.photos[index],
                      fallbackIcon: Icons.hotel_rounded,
                      fallbackGradient: AppColors.destinationGradients[
                          hotel.id.hashCode.abs() %
                              AppColors.destinationGradients.length],
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                  if (hotel.photos.length > 1)
                    PositionedDirectional(
                      end: 20,
                      bottom: 18,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '${_photoIndex + 1}/${hotel.photos.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Location + rating
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.place_rounded,
                              color: AppColors.primary, size: 16),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              hotel.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...List.generate(
                            hotel.starRating,
                            (_) => const Icon(Icons.star_rounded,
                                color: Colors.amber, size: 14),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              hotel.hasGoogleRating
                                  ? '(${hotel.reviewCount}) '
                                      '${hotel.rating.toStringAsFixed(1)}'
                                  : l10n.hotelRatingUnavailable,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: hotel.hasGoogleRating
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ).animate().fade(duration: 300.ms),
                const SizedBox(height: 16),
                // Amenities
                Text(l10n.hotelAmenities,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: hotel.amenities
                      .map((a) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                                color: AppColors.primarySurface,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text(a,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                          ))
                      .toList(),
                ).animate().fade(delay: 100.ms),
                const SizedBox(height: 20),
                // Description
                Text(l10n.hotelAbout,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                        hotel.description.isEmpty
                            ? l10n.hotelDefaultDescription
                            : hotel.description,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(height: 1.7))
                    .animate()
                    .fade(delay: 150.ms),
                const SizedBox(height: 20),
                _hotelReviewsSection(hotel, l10n),
                const SizedBox(height: 20),
                // Price summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color:
                            isDark ? AppColors.darkBorder : AppColors.border),
                  ),
                  child: Column(children: [
                    _Row(
                      hotel.isLiteApiOffer
                          ? '${l10n.hotelNightPrice} · LiteAPI'
                          : l10n.hotelNightPrice,
                      _formatAvailablePrice(hotel, hotel.pricePerNight, l10n),
                    ),
                    if (hotel.offers.isNotEmpty) ...[
                      const Divider(height: 20),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          l10n.hotelRoomRatesTitle,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      for (final offer in hotel.offers)
                        _Row(
                          _offerName(offer, l10n.hotelRoomRatesTitle),
                          _offerPrice(offer, hotel.priceCurrencyCode),
                        ),
                    ],
                    _Row(l10n.hotelNightsCount, l10n.hotelNightsValue(nights)),
                    _Row(
                      l10n.hotelSubtotal,
                      _formatAvailablePrice(hotel, pricing.subtotal, l10n),
                    ),
                    _Row(
                      '${l10n.hotelTaxesFees} '
                      '(${hotel.taxAndFeesPercentage.toStringAsFixed(0)}%)',
                      _formatAvailablePrice(hotel, pricing.taxAndFees, l10n),
                    ),
                    const Divider(height: 20),
                    _Row(l10n.hotelTotal,
                        _formatAvailablePrice(hotel, pricing.totalPrice, l10n),
                        isBold: true, color: AppColors.primary),
                  ]),
                ).animate().fade(delay: 200.ms),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: _isBooking || isSoldOut ? null : _book,
                  icon: _isBooking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.hotel_rounded),
                  label: Text(isSoldOut
                      ? l10n.hotelSoldOut
                      : _isBooking
                          ? l10n.hotelBookingInProgress
                          : l10n.hotelBookNow),
                ).animate().fade(delay: 280.ms),
                const SizedBox(height: 20),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String _offerName(Map<String, dynamic> offer, String fallback) {
    final roomName = offer['room_name']?.toString().trim() ?? '';
    final rateName = offer['name']?.toString().trim() ?? '';
    final parts = [roomName, rateName].where((value) => value.isNotEmpty);
    final label = parts.join(' · ');
    return label.isEmpty ? fallback : label;
  }

  String _offerPrice(Map<String, dynamic> offer, String fallbackCurrency) {
    final amount = double.tryParse(
      '${offer['total_amount'] ?? offer['stay_total'] ?? ''}',
    );
    if (amount == null || !amount.isFinite) return '—';
    final currency = (offer['total_currency'] ??
            offer['price_currency'] ??
            offer['currency'] ??
            fallbackCurrency)
        .toString();
    final locale = Localizations.localeOf(context).languageCode;
    if (currency.toUpperCase() == 'LYD') {
      return formatCurrencyAmount(amount, 'LYD', locale: locale);
    }
    return '$currency ${amount.toStringAsFixed(2)}';
  }

  Widget _hotelReviewsSection(HotelModel hotel, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.hotelGuestReviews,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: () => _writeHotelReview(hotel),
              icon: const Icon(Icons.star_rate_rounded),
              label: Text(l10n.writeAReview),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<ApiResult<List<ReviewModel>>>(
          future: _hotelReviewsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final result = snapshot.data;
            if (snapshot.hasError || result == null || result.isFailure) {
              return Text(
                l10n.genericError,
                style: const TextStyle(color: AppColors.textSecondary),
              );
            }
            final reviews = result.data ?? const <ReviewModel>[];
            if (reviews.isEmpty) {
              return Text(
                l10n.hotelNoGuestReviews,
                style: const TextStyle(color: AppColors.textSecondary),
              );
            }
            return Column(
              children: [
                for (final review in reviews.take(5))
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(review.userName.isEmpty
                            ? '?'
                            : review.userName.substring(0, 1).toUpperCase()),
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(review.userName)),
                          const Icon(Icons.star_rounded,
                              color: Colors.amber, size: 18),
                          Text(review.rating.toStringAsFixed(1)),
                        ],
                      ),
                      subtitle:
                          review.comment.isEmpty ? null : Text(review.comment),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  final bool isBold;
  final Color? color;
  const _Row(this.label, this.value, {this.isBold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                  fontSize: isBold ? 16 : 14,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
}

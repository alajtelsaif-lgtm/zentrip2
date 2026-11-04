import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../global_widgets/app_network_image.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../global_widgets/booking_load_error.dart';
import '../../../../global_widgets/booking_loading_overlay.dart';
import '../../../../global_widgets/booking_confirmation_screen.dart';
import '../../../../global_widgets/payment_checkout_screen.dart';
import '../../../../features/notifications/logic/notifications_store.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/booking_model.dart';
import '../../logic/car_controller.dart';
import '../car_labels.dart';

class CarDetailScreen extends StatefulWidget {
  const CarDetailScreen({super.key});
  @override
  State<CarDetailScreen> createState() => _CarDetailScreenState();
}

class _CarDetailScreenState extends State<CarDetailScreen> {
  CarController? _ctrl;
  bool _isBooking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctrl ??= ModalRoute.of(context)?.settings.arguments as CarController?;
  }

  Future<void> _book() async {
    final car = _ctrl?.selectedCar;
    if (car == null) {
      AppSnackbar.error(context, AppLocalizations.of(context).genericError);
      return;
    }
    if (car.availableVehicles < 1) {
      AppSnackbar.error(context, AppLocalizations.of(context).carSoldOut);
      return;
    }
    final days = _ctrl?.searchParams?.days ?? 1;
    final pricing = car.pricingForDays(days);
    final pickupDate = _ctrl?.searchParams?.pickupDate ?? DateTime.now();
    final returnDate = _ctrl?.searchParams?.returnDate ??
        pickupDate.add(const Duration(days: 1));
    final totalPrice = pricing.totalPrice;
    final ref =
        'ZT-C-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final l10n = AppLocalizations.of(context);

    final availability = await ApiService.instance.checkBookingAvailability(
      type: BookingType.car,
      title: '${car.brand} ${car.model}',
      startDate: pickupDate,
      endDate: returnDate,
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

    final payment = await PaymentCheckoutScreen.start(context,
        amountUsd: totalPrice,
        description: '${car.brand} ${car.model}',
        referenceId: ref);
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
      type: BookingType.car,
      title: '${car.brand} ${car.model}',
      subtitle: car.pickupLocation,
      date: pickupDate,
      endDate: returnDate,
      price: totalPrice,
      refCode: ref,
      status: 'upcoming',
      imageUrl: car.imageUrl,
      partnerListingId: car.partnerListingId,
    );
    final createResult = await BookingLoadingOverlay.run(
      context,
      title: AppLocalizations.of(context).hotelBookingInProgress,
      subtitle: '${car.brand} ${car.model}',
      serviceIcon: Icons.directions_car_rounded,
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
            : createResult.errorMessage ?? l10n.genericError,
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isBooking = false);
    AppSnackbar.success(context, l10n.carBookedSuccess);
    await NotificationsStore.instance.add(
        kind: NotifKind.booking,
        title: l10n.notifBookingConfirmedTitle,
        subtitle: '${car.brand} ${car.model}');
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingConfirmationScreen(
          serviceName: AppLocalizations.of(context).quickActionCars,
          primaryText: '${car.brand} ${car.model}',
          secondaryText: car.pickupLocation,
          reference: ref,
          dateLabel:
              MaterialLocalizations.of(context).formatMediumDate(pickupDate),
          priceLabel: '\$${totalPrice.toStringAsFixed(2)}',
          serviceIcon: Icons.directions_car_rounded,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    final car = ctrl?.selectedCar;
    final days = ctrl?.searchParams?.days ?? 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    if (car == null) return const BookingLoadError();
    final pricing = car.pricingForDays(days);
    final isSoldOut = car.availableVehicles < 1;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(car.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 8)])),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  AppNetworkImage(
                    url: car.imageUrl,
                    fallbackIcon: Icons.directions_car_rounded,
                    fallbackGradient: AppColors.destinationGradients[
                        car.id.hashCode.abs() %
                            AppColors.destinationGradients.length],
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x33000000), Color(0xAA000000)],
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
                // Specs
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _SpecChip(Icons.people_rounded,
                        l10n.carSeatsCount(car.seats), AppColors.primary),
                    _SpecChip(Icons.luggage_rounded,
                        l10n.carBagsCount(car.bags), AppColors.accentTeal),
                    _SpecChip(
                        Icons.settings_rounded,
                        car.transmission == 'automatic'
                            ? l10n.carTransmissionAuto
                            : l10n.carTransmissionManual,
                        AppColors.primary),
                    _SpecChip(
                        Icons.ac_unit_rounded,
                        car.hasAC ? l10n.carHasAc : l10n.carNoAc,
                        car.hasAC ? AppColors.accentGreen : AppColors.textHint),
                    _SpecChip(
                        car.fuelType == 'electric'
                            ? Icons.bolt_rounded
                            : Icons.local_gas_station_rounded,
                        carFuelLabel(l10n, car.fuelType),
                        AppColors.accentPurple),
                    _SpecChip(Icons.star_rounded, car.rating.toStringAsFixed(1),
                        Colors.amber.shade700),
                  ],
                ).animate().fade(duration: 300.ms),
                const SizedBox(height: 20),
                // Features
                if (car.features.isNotEmpty) ...[
                  Text(l10n.carFeatures,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  ...car.features.map((f) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          const Icon(Icons.check_circle_rounded,
                              color: AppColors.accentGreen, size: 16),
                          const SizedBox(width: 10),
                          Text(f, style: const TextStyle(fontSize: 13)),
                        ]),
                      )),
                  const SizedBox(height: 16),
                ],
                // Price
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.border)),
                  child: Column(children: [
                    _PriceRow(l10n.carPricePerDay,
                        '\$${car.pricePerDay.toStringAsFixed(0)}'),
                    _PriceRow(l10n.carSubtotal,
                        '\$${pricing.subtotal.toStringAsFixed(0)}'),
                    _PriceRow(l10n.carNumberOfDays, l10n.carDaysCount(days)),
                    _PriceRow(l10n.carInsurance,
                        '\$${car.insuranceFee.toStringAsFixed(0)}'),
                    _PriceRow(l10n.carServiceFee,
                        '\$${car.serviceFee.toStringAsFixed(0)}'),
                    const Divider(height: 20),
                    _PriceRow(l10n.carTotal,
                        '\$${car.totalPriceForDays(days).toStringAsFixed(0)}',
                        isBold: true, color: AppColors.primary),
                  ]),
                ).animate().fade(delay: 150.ms),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: _isBooking || isSoldOut ? null : _book,
                  icon: _isBooking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.directions_car_rounded),
                  label: Text(isSoldOut
                      ? l10n.carSoldOut
                      : _isBooking
                          ? l10n.carBooking
                          : l10n.carBookNow),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary),
                ).animate().fade(delay: 220.ms),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SpecChip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 12))
      ]),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label, value;
  final bool isBold;
  final Color? color;
  const _PriceRow(this.label, this.value, {this.isBold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            Text(value,
                style: TextStyle(
                    fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                    fontSize: isBold ? 16 : 14,
                    color: color)),
          ],
        ),
      );
}

import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/utils/date_time_utils.dart';
import '../../../../global_widgets/app_network_image.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../global_widgets/confirm_dialog.dart';
import '../../../../global_widgets/currency_amount_text.dart';
import '../../../../global_widgets/review_form_sheet.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../l10n/app_localizations.dart';
import '../../logic/trips_controller.dart';

extension TripKindStyle on TripKind {
  IconData get icon => switch (this) {
        TripKind.flight => Icons.flight_rounded,
        TripKind.hotel => Icons.hotel_rounded,
        TripKind.car => Icons.directions_car_rounded,
        TripKind.tour => Icons.local_activity_rounded,
        TripKind.transfer => Icons.local_taxi_rounded,
      };

  Color get color => switch (this) {
        TripKind.flight => AppColors.primary,
        TripKind.hotel => AppColors.accentTeal,
        TripKind.car => AppColors.accentOrange,
        TripKind.tour => AppColors.accentPurple,
        TripKind.transfer => AppColors.accentTeal,
      };

  String label(AppLocalizations l10n) => switch (this) {
        TripKind.flight => l10n.tripsKindFlight,
        TripKind.hotel => l10n.tripsKindHotel,
        TripKind.car => l10n.tripsKindCar,
        TripKind.tour => l10n.tripsKindTour,
        TripKind.transfer => l10n.tripsKindTransfer,
      };
}

extension TripTabStyle on TripTab {
  Color get color => switch (this) {
        TripTab.upcoming => AppColors.primary,
        TripTab.active => AppColors.accentGreen,
        TripTab.completed => AppColors.textSecondary,
        TripTab.cancelled => AppColors.accentRed,
      };

  String label(AppLocalizations l10n) => switch (this) {
        TripTab.upcoming => l10n.upcoming,
        TripTab.active => l10n.tripsTabActive,
        TripTab.completed => l10n.completed,
        TripTab.cancelled => l10n.cancelled,
      };
}

class TripItemCard extends StatelessWidget {
  final TripItem item;
  final bool isDark;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  const TripItemCard({
    super.key,
    required this.item,
    required this.isDark,
    required this.l10n,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final kind = item.kind;
    final dates = item.end.difference(item.start).inHours < 24 &&
            item.start.day == item.end.day
        ? DateTimeUtils.formatDate(item.start, locale: locale)
        : '${DateTimeUtils.formatShortDate(item.start, locale: locale)} - ${DateTimeUtils.formatDate(item.end, locale: locale)}';

    return Opacity(
      opacity: item.status == TripTab.cancelled ? 0.8 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          clipBehavior: Clip.antiAlias,
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
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 120,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColorFiltered(
                      colorFilter: item.status == TripTab.completed ||
                              item.status == TripTab.cancelled
                          ? const ColorFilter.mode(
                              Colors.grey, BlendMode.saturation)
                          : const ColorFilter.mode(
                              Colors.transparent, BlendMode.dst),
                      child: AppNetworkImage(
                        url: item.imageUrl,
                        fallbackIcon: kind.icon,
                        fallbackGradient: LinearGradient(
                          colors: [
                            kind.color,
                            kind.color.withValues(alpha: 0.6)
                          ],
                        ),
                      ),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x55000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                    PositionedDirectional(
                      top: 10,
                      start: 10,
                      child: _Pill(
                        icon: kind.icon,
                        text: kind.label(l10n),
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                    PositionedDirectional(
                      top: 10,
                      end: 10,
                      child: _Pill(
                        text: item.status.label(l10n),
                        color: item.status.color.withValues(alpha: 0.95),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    if (item.isSimulated) ...[
                      const SizedBox(height: 7),
                      _Pill(
                        text: l10n.flightSimulationBadge,
                        color: AppColors.primary,
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    if (item.flight?.selectedSeats.isNotEmpty == true) ...[
                      const SizedBox(height: 5),
                      Text(
                        '${l10n.tripSeatsLabel}: ${item.flight!.selectedSeats.join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                    if (item.flight?.extras.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${l10n.tripExtrasLabel}: ${item.flight!.extras.join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(dates,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Divider(
                        height: 1,
                        color:
                            isDark ? AppColors.darkBorder : AppColors.divider),
                    const SizedBox(height: 10),
                    Row(children: [
                      if (item.reference != null && item.reference!.isNotEmpty)
                        Expanded(
                          child: Text(
                              '${l10n.tripsRefLabel}: ${item.reference}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 0.4,
                                  color: AppColors.textSecondary)),
                        )
                      else
                        const Spacer(),
                      if (item.price != null)
                        Text(
                            item.priceCurrencyCode.toUpperCase() == 'LYD'
                                ? formatProviderMoney(
                                    item.price!,
                                    item.priceCurrencyCode,
                                    locale: Localizations.localeOf(context)
                                        .languageCode,
                                  )
                                : item.isSimulated
                                    ? '${item.priceCurrencyCode} ${item.price!.toStringAsFixed(2)}'
                                    : '\$${item.price!.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: AppColors.primary)),
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

class _Pill extends StatelessWidget {
  final IconData? icon;
  final String text;
  final Color color;
  const _Pill({this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(9)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Details sheet for hotel/car/tour bookings (flights open their own screen).
Future<bool?> showBookingDetailsSheet(BuildContext context, TripItem item) {
  final booking = item.booking;
  final transfer = item.transfer;
  if (booking == null && transfer == null) return Future.value(false);
  final locale = Localizations.localeOf(context).languageCode;
  final canCancel =
      item.status == TripTab.upcoming || item.status == TripTab.active;
  return showModalBottomSheet<bool>(
    context: context,
    builder: (sheetContext) {
      var isCancelling = false;
      return StatefulBuilder(
        builder: (context, setModalState) {
          final l10n = AppLocalizations.of(context);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(item.subtitle,
                      style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  _DetailLine(
                      Icons.calendar_today_outlined,
                      DateTimeUtils.formatDate(
                          transfer?.pickupTime ?? booking!.date,
                          locale: locale)),
                  if (transfer != null) ...[
                    _DetailLine(Icons.trip_origin_rounded,
                        '${l10n.transferPickupLabel}: ${transfer.pickupLocation}'),
                    _DetailLine(Icons.location_on_outlined,
                        '${l10n.transferDropoffLabel}: ${transfer.dropoffLocation}'),
                    _DetailLine(Icons.directions_car_rounded,
                        '${l10n.transferVehicleLabel}: ${transfer.vehicleType}'),
                    _DetailLine(Icons.schedule_rounded,
                        l10n.transferMinutes(transfer.durationMinutes)),
                  ],
                  if (booking?.refCode != null)
                    _DetailLine(
                        Icons.confirmation_num_rounded, booking!.refCode!),
                  if ((booking?.price ?? transfer?.price) != null)
                    _DetailLine(
                      Icons.attach_money_rounded,
                      '',
                      trailing: CurrencyAmountText(
                        amount: (booking?.price ?? transfer?.price)!,
                        decimalDigits: 0,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (booking != null && item.canReview) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          ReviewFormSheet.show(context,
                              itemId: booking.id, itemType: booking.type.name);
                        },
                        icon: const Icon(Icons.rate_review_outlined, size: 16),
                        label: Text(l10n.writeAReview),
                      ),
                    ),
                  ],
                  if (booking != null && canCancel) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: isCancelling
                            ? null
                            : () async {
                                final confirmed = await showAppConfirmDialog(
                                  context,
                                  title: l10n.cancelBookingConfirmTitle,
                                  message: l10n.cancelBookingConfirmMessage,
                                  confirmLabel: l10n.cancelBooking,
                                  isDanger: true,
                                );
                                if (!confirmed || !context.mounted) return;
                                setModalState(() => isCancelling = true);
                                final result = await ApiService.instance
                                    .cancelBooking(booking);
                                if (!context.mounted) return;
                                if (result.isFailure) {
                                  setModalState(() => isCancelling = false);
                                  AppSnackbar.error(
                                    context,
                                    result.errorMessage ?? l10n.genericError,
                                  );
                                  return;
                                }
                                AppSnackbar.success(
                                    context, l10n.bookingCancelledSuccess);
                                Navigator.of(sheetContext).pop(true);
                              },
                        icon: isCancelling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cancel_outlined, size: 16),
                        label: Text(isCancelling
                            ? l10n.cancellingTrip
                            : l10n.cancelBooking),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _DetailLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? trailing;
  const _DetailLine(this.icon, this.text, {this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: trailing ??
                Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

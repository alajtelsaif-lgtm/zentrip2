import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/utils/date_time_utils.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../global_widgets/boarding_pass_card.dart';
import '../../../../global_widgets/confirm_dialog.dart';
import '../../../../global_widgets/ticket_qr_screen.dart';
import '../../../../features/notifications/logic/notifications_store.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/trip_model.dart';

class TripDetailsScreen extends StatefulWidget {
  final TripModel trip;
  const TripDetailsScreen({super.key, required this.trip});

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  late TripModel _trip;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
  }

  Future<void> _shareTrip() async {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final date = DateTimeUtils.formatDate(_trip.departureDate, locale: locale);
    final text = l10n.tripShareText(
        _trip.originCode, _trip.destinationCode, date, _trip.flightNumber);
    await Share.share(text);
  }

  Future<void> _cancelTrip() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showAppConfirmDialog(
      context,
      title: l10n.cancelTripConfirmTitle,
      message: l10n.cancelTripConfirmMessage,
      confirmLabel: l10n.cancelTrip,
      isDanger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _isCancelling = true);
    final result = await ApiService.instance.cancelFlightTrip(_trip);
    if (!mounted) return;
    setState(() => _isCancelling = false);
    if (result.isFailure) {
      AppSnackbar.error(context, result.errorMessage ?? l10n.genericError);
      return;
    }
    AppSnackbar.success(context, l10n.flightRefundRequested);
    await NotificationsStore.instance.add(
      kind: NotifKind.cancel,
      title: l10n.notifTripCancelledTitle,
      subtitle: '${_trip.originCode} → ${_trip.destinationCode}',
    );
    if (!mounted) return;
    // الرحلة اتحذفت نهائيًا، فمفيش داعي نفضل في نفس الشاشة — نرجع على طول.
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).languageCode;
    final trip = _trip;
    final bookedAmount = trip.bookingDisplayAmount ?? trip.price ?? 0;
    final bookedCurrency = trip.bookingDisplayAmount == null
        ? trip.priceCurrencyCode
        : trip.bookingCurrencyCode;
    final bookedPriceLabel = formatBookingCurrencyAmount(
      bookedAmount,
      bookedCurrency,
      locale: locale,
      decimalDigits: 2,
    );
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(l10n.tripDetails,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textPrimary)),
              background: Container(
                  decoration:
                      const BoxDecoration(gradient: AppColors.primaryGradient)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                BoardingPassCard(trip: trip)
                    .animate()
                    .fade(duration: 400.ms)
                    .slideY(begin: 0.1, end: 0),
                const SizedBox(height: 24),
                _DetailSection(
                    title: l10n.tripsFlightInfo,
                    isDark: isDark,
                    children: [
                      _DetailRow(l10n.flightNumber, trip.flightNumber,
                          Icons.flight_rounded),
                      _DetailRow(l10n.tripsAirline, trip.airline ?? '-',
                          Icons.airlines_rounded),
                      _DetailRow(l10n.seatClass, trip.seatClass ?? 'Economy',
                          Icons.airline_seat_recline_normal_rounded),
                      _DetailRow(
                          l10n.tripsTripType,
                          trip.isDirect ? l10n.direct : l10n.withStop,
                          Icons.connecting_airports_rounded),
                    ]).animate().fade(delay: 200.ms),
                const SizedBox(height: 16),
                _DetailSection(
                    title: l10n.tripsSchedule,
                    isDark: isDark,
                    children: [
                      _DetailRow(
                          l10n.departureDate,
                          DateTimeUtils.formatDate(trip.departureDate,
                              locale: locale),
                          Icons.calendar_today_outlined),
                      if (trip.returnDate != null)
                        _DetailRow(
                            l10n.returnDate,
                            DateTimeUtils.formatDate(trip.returnDate!,
                                locale: locale),
                            Icons.calendar_today_outlined),
                    ]).animate().fade(delay: 280.ms),
                if (trip.bookingRef != null ||
                    trip.selectedSeats.isNotEmpty ||
                    trip.extras.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _DetailSection(
                      title: l10n.tripsBookingDetails,
                      isDark: isDark,
                      children: [
                        _DetailRow(l10n.bookingRef, trip.bookingRef!,
                            Icons.confirmation_num_rounded),
                        if (trip.bookingDisplayAmount != null ||
                            trip.price != null)
                          _DetailRow(
                            l10n.tripsTotalPrice,
                            bookedPriceLabel,
                            Icons.attach_money_rounded,
                          ),
                        if (trip.selectedSeats.isNotEmpty)
                          _DetailRow(
                              l10n.tripSeatsLabel,
                              trip.selectedSeats.join(', '),
                              Icons.airline_seat_recline_normal_rounded),
                        if (trip.extras.isNotEmpty)
                          _DetailRow(l10n.tripExtrasLabel,
                              trip.extras.join(', '), Icons.luggage_rounded),
                      ]).animate().fade(delay: 360.ms),
                ],
                if (trip.refundStatus != null) ...[
                  const SizedBox(height: 16),
                  _DetailSection(
                    title: l10n.flightRefundStatusTitle,
                    isDark: isDark,
                    children: [
                      _DetailRow(
                          l10n.flightRefundPendingLabel,
                          l10n.flightRefundPendingValue,
                          Icons.hourglass_top_rounded),
                      _DetailRow(
                          l10n.flightRefundMethodLabel,
                          l10n.flightRefundOriginalMethod,
                          Icons.credit_card_rounded),
                    ],
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => TicketQrScreen(
                                  title:
                                      '${trip.originCode} → ${trip.destinationCode}',
                                  subtitle: trip.flightNumber,
                                  refCode:
                                      trip.bookingRef ?? trip.id.toString(),
                                  details: [
                                    if (trip.selectedSeats.isNotEmpty)
                                      '${l10n.tripSeatsLabel}: ${trip.selectedSeats.join(', ')}',
                                    if (trip.extras.isNotEmpty)
                                      '${l10n.tripExtrasLabel}: ${trip.extras.join(', ')}',
                                  ],
                                ))),
                    icon: const Icon(Icons.qr_code_rounded, size: 16),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        l10n.yourTicket,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ).animate().fade(delay: 420.ms),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _shareTrip,
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: Text(l10n.share),
                  ),
                ).animate().fade(delay: 440.ms),
                if (trip.status == 'upcoming') ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isCancelling ? null : _cancelTrip,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accentRed,
                        side: const BorderSide(color: AppColors.accentRed),
                      ),
                      icon: _isCancelling
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.accentRed))
                          : const Icon(Icons.cancel_outlined, size: 16),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _isCancelling ? l10n.cancellingTrip : l10n.cancelTrip,
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ).animate().fade(delay: 500.ms),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isDark;
  const _DetailSection(
      {required this.title, required this.children, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          Divider(
              height: 1,
              color: isDark ? AppColors.darkBorder : AppColors.divider),
          ...children.map((c) => Column(children: [
                c,
                if (c != children.last)
                  Divider(
                      height: 1,
                      color: isDark ? AppColors.darkBorder : AppColors.divider,
                      indent: 52)
              ])),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _DetailRow(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13))),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ],
      ),
    );
  }
}

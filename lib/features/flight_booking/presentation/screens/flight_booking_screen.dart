import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../global_widgets/booking_load_error.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_model.dart';
import '../../../../models/flight_price_breakdown.dart';
import '../../logic/flight_controller.dart';
import 'flight_primary_button.dart';
import 'seat_selection16line_screen.dart';
import 'seat_selection_screen.dart';

class FlightBookingScreen extends StatefulWidget {
  const FlightBookingScreen({super.key});

  @override
  State<FlightBookingScreen> createState() => _FlightBookingScreenState();
}

class _FlightBookingScreenState extends State<FlightBookingScreen> {
  FlightController? _ctrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctrl ??= ModalRoute.of(context)?.settings.arguments as FlightController?;
  }

  void _book() {
    final flight = _ctrl?.selectedFlight;
    final controller = _ctrl;
    if (flight == null || controller == null) return;
    final search = controller.searchParams;
    final passengerCount = search?.passengers ?? 1;
    final seatClass = search?.seatClass ?? 'economy';
    final selection = flight.usesTwoByTwoSeatLayout
        ? SeatSelection16LineScreen(
            flight: flight,
            passengerCount: passengerCount,
            seatClass: seatClass,
            returnDate: search?.returnDate,
            rowCount: flight.seatRows,
          )
        : SeatSelectionScreen(
            flight: flight,
            passengerCount: passengerCount,
            seatClass: seatClass,
            returnDate: search?.returnDate,
            rowCount: flight.seatRows,
          );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => selection),
    );
  }

  String _formatPrice(FlightModel flight, double amount) {
    final prefix = flight.isDuffelOffer ? '${flight.priceCurrencyCode} ' : '\$';
    return '$prefix${amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final ctrl = _ctrl;
    final flight = ctrl?.selectedFlight;
    final seatClass = ctrl?.searchParams?.seatClass ?? 'economy';
    final passengerCount = ctrl?.searchParams?.passengers ?? 1;
    final fare = switch (seatClass) {
      'business' => flight?.businessPrice ?? flight?.economyPrice ?? 0,
      'first' => flight?.firstPrice ?? flight?.economyPrice ?? 0,
      _ => flight?.economyPrice ?? 0,
    };
    final breakdown = flight == null
        ? null
        : FlightPriceBreakdown.forSearch(
            flight: flight,
            passengers: passengerCount,
            seatClass: seatClass,
          );
    final basePrice = flight?.isDuffelOffer == true
        ? flight!.economyPrice
        : fare * passengerCount;
    final totalPrice = breakdown?.total ?? 0;
    final user = ApiService.instance.currentUser;
    if (flight == null) return const BookingLoadError();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.flightConfirmBookingTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Flight summary ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10))
                ],
              ),
              child: Column(children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(flight.originCode,
                                style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                            Text(flight.originCity,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12)),
                          ]),
                      Column(children: [
                        const Icon(Icons.flight_rounded,
                            color: Colors.white, size: 20),
                        Container(
                            width: 80,
                            height: 1.5,
                            color: Colors.white.withValues(alpha: 0.3),
                            margin: const EdgeInsets.symmetric(vertical: 4)),
                      ]),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(flight.destinationCode,
                                style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                            Text(flight.destinationCity,
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12)),
                          ]),
                    ]),
                const SizedBox(height: 14),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(flight.airline,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      Text(flight.flightNumber,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8))),
                      Text(flight.duration,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8))),
                    ]),
              ]),
            ).animate().fade(duration: 400.ms).slideY(begin: 0.1, end: 0),
            const SizedBox(height: 20),

            // ── Passenger info ────────────────────────────────────────
            _Section(
                title: l10n.flightPassengerInfo,
                isDark: isDark,
                children: [
                  _InfoRow(l10n.nameLabel, user?.name ?? l10n.flightDemoUser),
                  _InfoRow(l10n.emailLabel, user?.email ?? 'demo@zentrip.app'),
                  _InfoRow(l10n.phoneLabel, user?.phone ?? '+201000000000'),
                ]).animate().fade(delay: 150.ms),
            const SizedBox(height: 16),

            // ── Price breakdown ───────────────────────────────────────
            _Section(title: l10n.flightPriceDetails, isDark: isDark, children: [
              if (flight.isDuffelOffer)
                _InfoRow(
                  l10n.flightDuffelTotal(passengerCount),
                  _formatPrice(flight, basePrice),
                )
              else ...[
                _InfoRow(
                  l10n.flightTicketPrice,
                  _formatPrice(flight, breakdown!.subtotal),
                ),
                _InfoRow(
                  l10n.flightTaxesFees,
                  _formatPrice(flight, breakdown.taxesAndFees ?? 0),
                ),
                _InfoRow(l10n.flightServiceFee,
                    _formatPrice(flight, breakdown.serviceFee ?? 0)),
              ],
              const Divider(),
              _InfoRow(l10n.flightTotal, _formatPrice(flight, totalPrice),
                  isBold: true, color: AppColors.primary),
            ]).animate().fade(delay: 220.ms),
            const SizedBox(height: 28),

            // ── Book now ──────────────────────────────────────────────
            FlightPrimaryButton(
              label: flight.isDuffelOffer
                  ? l10n.flightChooseSeatsAndContinue
                  : 'Choose seats and continue',
              icon: Icons.event_seat_rounded,
              onPressed: _book,
            ).animate().fade(delay: 300.ms),
            const SizedBox(height: 10),
            Text(l10n.flightTermsNotice,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textHint)),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isDark;
  const _Section(
      {required this.title, required this.children, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
        child: Column(children: children),
      ),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? color;
  const _InfoRow(this.label, this.value, {this.isBold = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
}

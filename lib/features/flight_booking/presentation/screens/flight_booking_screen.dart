import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../global_widgets/booking_load_error.dart';
import '../../../../global_widgets/booking_loading_overlay.dart';
import '../../../../global_widgets/payment_checkout_screen.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_booking_model.dart';
import '../../../../models/flight_model.dart';
import '../../../../models/trip_model.dart';
import '../../logic/flight_controller.dart';
import 'booking_confirmed_screen.dart';
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
  bool _isProcessing = false;

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
    if (flight.isDuffelOffer) {
      _bookDuffelFlight(
        flight: flight,
        passengerCount: passengerCount,
        seatClass: seatClass,
        returnDate: search?.returnDate,
      );
      return;
    }
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

  Future<void> _bookDuffelFlight({
    required FlightModel flight,
    required int passengerCount,
    required String seatClass,
    required DateTime? returnDate,
  }) async {
    if (_isProcessing) return;
    final totalPrice = flight.comparisonTotal(
      passengers: passengerCount,
      seatClass: seatClass,
    );
    if (totalPrice == null || totalPrice <= 0) {
      AppSnackbar.error(context, AppLocalizations.of(context).genericError);
      return;
    }

    setState(() => _isProcessing = true);
    final reference = 'ZT-D-${DateTime.now().microsecondsSinceEpoch}';
    final l10n = AppLocalizations.of(context);
    try {
      final paid = await PaymentCheckoutScreen.start(
        context,
        amountUsd: totalPrice,
        currencyCode: flight.priceCurrencyCode,
        description: '${flight.airline} ${flight.flightNumber}',
        referenceId: reference,
      );
      if (!mounted) return;
      if (!paid) {
        AppSnackbar.error(context, l10n.paymentFailedMessage);
        return;
      }

      final trip = TripModel(
        id: DateTime.now().millisecondsSinceEpoch,
        originCode: flight.originCode,
        originCity: flight.originCity,
        destinationCode: flight.destinationCode,
        destinationCity: flight.destinationCity,
        departureDate: flight.departureTime,
        arrivalDate: flight.arrivalTime,
        returnDate: returnDate,
        flightNumber: flight.flightNumber,
        airline: flight.airline,
        airlineLogoUrl: flight.airlineLogoUrl,
        isDirect: flight.isDirect,
        seatClass: seatClass,
        price: totalPrice,
        bookingRef: reference,
        passengerCount: passengerCount,
      );
      final result = await BookingLoadingOverlay.run(
        context,
        title: l10n.flightBookingInProgress,
        subtitle: '${flight.originCode} → ${flight.destinationCode}',
        serviceIcon: Icons.flight_takeoff_rounded,
        action: () => ApiService.instance.createFlightTrip(trip),
      );
      if (!mounted) return;
      if (result.isFailure || result.data == null) {
        final message = result.errorMessage == 'FLIGHT_SCHEDULE_CONFLICT'
            ? l10n.flightScheduleConflict
            : result.errorMessage ?? l10n.genericError;
        AppSnackbar.error(context, message);
        return;
      }

      final savedTrip = result.data!;
      final confirmation = FlightBookingConfirmation(
        trip: savedTrip,
        reference: savedTrip.bookingRef ?? reference,
        seats: const [],
        totalPrice: totalPrice,
      );
      final draft = FlightBookingDraft(
        flight: flight,
        passengerCount: passengerCount,
        seatClass: seatClass,
        seats: const [],
        returnDate: returnDate,
        totalPrice: totalPrice,
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookingConfirmedScreen(
            draft: draft,
            initialConfirmation: confirmation,
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Duffel simulated flight booking failed: $error\n$stackTrace');
      if (mounted) AppSnackbar.error(context, l10n.genericError);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
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
    final basePrice = flight?.isDuffelOffer == true
        ? flight!.economyPrice
        : fare * passengerCount;
    final totalPrice = flight?.isDuffelOffer == true
        ? flight!.comparisonTotal(
                passengers: passengerCount, seatClass: seatClass) ??
            0
        : basePrice * 1.12 + 12;
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
                  _formatPrice(flight, fare * passengerCount),
                ),
                _InfoRow(
                  l10n.flightTaxesFees,
                  _formatPrice(flight, fare * passengerCount * 0.12),
                ),
                _InfoRow(l10n.flightServiceFee, _formatPrice(flight, 12)),
              ],
              const Divider(),
              _InfoRow(l10n.flightTotal, _formatPrice(flight, totalPrice),
                  isBold: true, color: AppColors.primary),
            ]).animate().fade(delay: 220.ms),
            const SizedBox(height: 28),

            // ── Book now ──────────────────────────────────────────────
            FlightPrimaryButton(
              label: flight.isDuffelOffer
                  ? l10n.flightContinueToPayment
                  : 'Choose seats and continue',
              icon: flight.isDuffelOffer
                  ? Icons.payment_rounded
                  : Icons.event_seat_rounded,
              onPressed: _isProcessing ? null : _book,
              loading: _isProcessing,
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

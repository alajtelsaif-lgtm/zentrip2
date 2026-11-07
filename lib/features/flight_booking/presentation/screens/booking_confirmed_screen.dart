import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../features/notifications/logic/notifications_store.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_booking_model.dart';
import '../../../../models/flight_model.dart';
import 'flight_primary_button.dart';

class BookingConfirmedScreen extends StatefulWidget {
  final FlightBookingDraft draft;
  final FlightBookingConfirmation? initialConfirmation;

  const BookingConfirmedScreen({
    super.key,
    required this.draft,
    this.initialConfirmation,
  });

  @override
  State<BookingConfirmedScreen> createState() => _BookingConfirmedScreenState();
}

class _BookingConfirmedScreenState extends State<BookingConfirmedScreen> {
  FlightBookingConfirmation? _confirmation;
  String? _error;
  bool _loading = true;

  String get _flightId {
    final flight = widget.draft.flight;
    return flight.partnerListingId?.toString() ??
        flight.id.replaceFirst(RegExp(r'^partner-'), '');
  }

  @override
  void initState() {
    super.initState();
    final initialConfirmation = widget.initialConfirmation;
    if (initialConfirmation != null) {
      _confirmation = initialConfirmation;
      _loading = false;
    } else {
      _confirmBooking();
    }
  }

  Future<void> _confirmBooking() async {
    if (_loading && _confirmation != null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ApiService.instance.confirmFlightBooking(
        flightId: _flightId,
        seats: widget.draft.seats,
        seatClass: widget.draft.seatClass,
        returnDate: widget.draft.returnDate,
        extras: widget.draft.extras,
        paymentAttemptId: widget.draft.paymentAttemptId,
        packageOfferId: widget.draft.packageOffer?.id,
      );
      if (!mounted) return;
      if (result.isFailure || result.data == null) {
        setState(() {
          _loading = false;
          _error = result.errorMessage ??
              AppLocalizations.of(context).flightConfirmationError;
        });
        return;
      }
      setState(() {
        _confirmation = result.data;
        _loading = false;
      });
      unawaited(NotificationsStore.instance.refreshAfterBooking(
        title: AppLocalizations.of(context).notifBookingConfirmedTitle,
        subtitle:
            '${widget.draft.flight.originCity} → ${widget.draft.flight.destinationCity}',
        bookingRef: result.data!.reference,
      ));
    } catch (error, stackTrace) {
      debugPrint('Flight booking confirmation failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _backToHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        foregroundColor: Colors.white,
        title: Text(l10n.flightBookingConfirmed),
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    l10n.flightBookingInProgress,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          : _error != null
              ? _ConfirmationError(
                  message: _error!,
                  onRetry: _confirmBooking,
                  onBack: _backToHome,
                )
              : _confirmation == null
                  ? _ConfirmationError(
                      message: l10n.flightConfirmationError,
                      onRetry: _confirmBooking,
                      onBack: _backToHome,
                    )
                  : _receipt(context, _confirmation!, l10n),
    );
  }

  Widget _receipt(
    BuildContext context,
    FlightBookingConfirmation confirmation,
    AppLocalizations l10n,
  ) {
    final flight = widget.draft.flight;
    final seats =
        confirmation.seats.isEmpty ? widget.draft.seats : confirmation.seats;
    final extras =
        confirmation.extras.isEmpty ? widget.draft.extras : confirmation.extras;
    final passengerName =
        ApiService.instance.currentUser?.name.trim().isNotEmpty == true
            ? ApiService.instance.currentUser!.name
            : null;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(
            MaterialLocalizations.of(context)
                .formatMediumDate(flight.departureTime),
            style: const TextStyle(
              color: AppColors.darkTextSecondary,
              fontSize: 12,
            ),
          ),
          if (flight.isDuffelOffer) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  l10n.flightSimulationBadge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${flight.originCity} to ${flight.destinationCity}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          FlightTicketCard(
            flight: flight,
            reference: confirmation.reference,
            seats: seats,
            seatClass: widget.draft.seatClass,
            totalPrice: confirmation.totalPrice,
            passengerName: passengerName,
          ),
          if (widget.draft.packageOffer case final offer?) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    offer.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.hotelNightsSummary(offer.durationNights),
                    style: const TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${l10n.packageStayTotal}: \$${(offer.hotelPricePerNight * offer.durationNights * widget.draft.passengerCount).toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final extra in extras)
                  _TicketExtraChip(
                    label: extra == 'extra_baggage'
                        ? l10n.flightExtraBaggage
                        : l10n.flightFlexibleTicket,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 28),
          _BackHomeButton(label: l10n.flightBackToHome, onPressed: _backToHome),
        ],
      ),
    );
  }
}

class FlightTicketCard extends StatelessWidget {
  final FlightModel flight;
  final String reference;
  final List<String> seats;
  final String seatClass;
  final double totalPrice;
  final String? passengerName;

  const FlightTicketCard({
    super.key,
    required this.flight,
    required this.reference,
    required this.seats,
    required this.seatClass,
    required this.totalPrice,
    this.passengerName,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localizations = MaterialLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSecondary,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.flight_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        flight.airline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        seatClass.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      TimeOfDay.fromDateTime(flight.departureTime)
                          .format(context),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TicketFlightLine(
                        duration: _formatDuration(flight.durationMinutes),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      TimeOfDay.fromDateTime(flight.arrivalTime)
                          .format(context),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TicketRoutePoint(
                      code: flight.originCode,
                      city: flight.originCity,
                    ),
                    _TicketRoutePoint(
                      code: flight.destinationCode,
                      city: flight.destinationCity,
                      alignEnd: true,
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Divider(height: 1, color: AppColors.border),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        localizations.formatMediumDate(flight.departureTime),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Flexible(
                      child: _TicketDetail(
                        alignEnd: true,
                        label: l10n.flightAircraft,
                        value: flight.aircraftName,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _TicketDetail(
                        label: l10n.flightPassengerInfo,
                        value: passengerName ?? l10n.flightDemoUser,
                      ),
                    ),
                    Expanded(
                      child: _TicketDetail(
                        label: l10n.flightSelectedSeats,
                        value: seats.isEmpty ? '—' : seats.join(', '),
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _TicketDetail(
                        label: l10n.flightNumber,
                        value: flight.flightNumber,
                      ),
                    ),
                    Expanded(
                      child: _TicketDetail(
                        label: l10n.flightDuration,
                        value: _formatDuration(flight.durationMinutes),
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 26,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final dashCount = (constraints.maxWidth / 9).floor();
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(
                          dashCount,
                          (_) => Container(
                            width: 4,
                            height: 1.2,
                            color: AppColors.border,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: -12,
                  child: _TicketNotch(),
                ),
                Positioned(
                  right: -12,
                  child: _TicketNotch(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _TicketDetail(
                        label: l10n.flightBookingReferenceLabel,
                        value: reference,
                        valueSize: 17,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _TicketDetail(
                      label: l10n.flightTotal,
                      value:
                          '${flight.isDuffelOffer ? '${flight.priceCurrencyCode} ' : '\$'}${totalPrice.toStringAsFixed(2)}',
                      valueSize: 17,
                      alignEnd: true,
                    ),
                    const SizedBox(width: 10),
                    Semantics(
                      button: true,
                      label: '${l10n.yourTicket}: $reference',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => _showTicketQr(context, reference, l10n),
                        child: QrImageView(
                          data: reference,
                          size: 54,
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.H,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 58,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _BarcodePainter(reference),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(int minutes) {
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return hours == 0
        ? '${remainingMinutes}m'
        : '${hours}h ${remainingMinutes}m';
  }

  static Future<void> _showTicketQr(
    BuildContext context,
    String reference,
    AppLocalizations l10n,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: reference,
                size: 240,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.H,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.flightBookingReferenceLabel,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              SelectableText(
                reference,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketRoutePoint extends StatelessWidget {
  final String code;
  final String city;
  final bool alignEnd;

  const _TicketRoutePoint({
    required this.code,
    required this.city,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            city,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      );
}

class _TicketDetail extends StatelessWidget {
  final String label;
  final String value;
  final bool alignEnd;
  final double valueSize;

  const _TicketDetail({
    required this.label,
    required this.value,
    this.alignEnd = false,
    this.valueSize = 13,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: valueSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
}

class _TicketFlightLine extends StatelessWidget {
  final String duration;

  const _TicketFlightLine({required this.duration});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            duration,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const _TicketRouteDot(),
              Expanded(
                child: Container(height: 1, color: AppColors.border),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.flight_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              Expanded(
                child: Container(height: 1, color: AppColors.border),
              ),
              const _TicketRouteDot(),
            ],
          ),
        ],
      );
}

class _TicketRouteDot extends StatelessWidget {
  const _TicketRouteDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: AppColors.textPrimary,
          shape: BoxShape.circle,
        ),
      );
}

class _TicketNotch extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: AppColors.darkBackground,
          shape: BoxShape.circle,
        ),
      );
}

class _BarcodePainter extends CustomPainter {
  final String seed;

  const _BarcodePainter(this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    if (seed.isEmpty || size.isEmpty) return;
    final paint = Paint()..color = AppColors.textPrimary;
    var state = seed.hashCode & 0x7fffffff;
    var x = 0.0;
    while (x < size.width) {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      final width = 1.2 + (state % 3).toDouble();
      if ((state & 4) != 0) {
        canvas.drawRect(
          Rect.fromLTWH(x, 0, width, size.height),
          paint,
        );
      }
      x += width + 1.4;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter oldDelegate) => oldDelegate.seed != seed;
}

class _TicketExtraChip extends StatelessWidget {
  final String label;

  const _TicketExtraChip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.darkSurfaceSecondary,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              size: 16,
              color: AppColors.primaryLight,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _BackHomeButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _BackHomeButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: 260,
          height: 56,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.home_rounded, size: 20),
              label: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shadowColor: Colors.transparent,
                elevation: 0,
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ),
      );
}

class _ConfirmationError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const _ConfirmationError({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.accentRed, size: 52),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            FlightPrimaryButton(
              label: l10n.retry,
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onBack,
              child: Text(l10n.flightBackToHome),
            ),
          ],
        ),
      ),
    );
  }
}

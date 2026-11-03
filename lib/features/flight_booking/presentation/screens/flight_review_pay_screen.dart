import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_model.dart';
import 'flight_checkout_shared_components.dart';
import 'flight_passengers_screen.dart';

class FlightReviewPayScreen extends StatefulWidget {
  final FlightModel flight;
  final List<FlightCheckoutPassenger> passengers;
  final List<String> seats;
  final String fareLabel;
  final String currencyCode;
  final double totalPrice;
  final List<FlightPriceLine> priceLines;
  final String? savedPaymentLabel;
  final String? savedPaymentExpiry;
  final bool acceptedFareRules;
  final ValueChanged<bool> onFareRulesChanged;
  final Future<void> Function()? onPay;
  final bool paying;
  final VoidCallback? onBack;
  final ValueChanged<String>? onPromoCodeChanged;

  const FlightReviewPayScreen({
    super.key,
    required this.flight,
    required this.passengers,
    required this.seats,
    required this.fareLabel,
    required this.currencyCode,
    required this.totalPrice,
    required this.priceLines,
    required this.acceptedFareRules,
    required this.onFareRulesChanged,
    required this.onPay,
    this.savedPaymentLabel,
    this.savedPaymentExpiry,
    this.paying = false,
    this.onBack,
    this.onPromoCodeChanged,
  });

  @override
  State<FlightReviewPayScreen> createState() => _FlightReviewPayScreenState();
}

class _FlightReviewPayScreenState extends State<FlightReviewPayScreen> {
  late bool _acceptedFareRules;

  @override
  void initState() {
    super.initState();
    _acceptedFareRules = widget.acceptedFareRules;
  }

  @override
  void didUpdateWidget(covariant FlightReviewPayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.acceptedFareRules != widget.acceptedFareRules) {
      _acceptedFareRules = widget.acceptedFareRules;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = CheckoutLabels(l10n);
    final flight = widget.flight;
    final passengers = widget.passengers;
    final seats = widget.seats;
    final fareLabel = widget.fareLabel;
    final currencyCode = widget.currencyCode;
    final totalPrice = widget.totalPrice;
    final priceLines = widget.priceLines;
    final savedPaymentLabel = widget.savedPaymentLabel;
    final savedPaymentExpiry = widget.savedPaymentExpiry;
    final onPay = widget.onPay;
    final paying = widget.paying;
    final onBack = widget.onBack;
    final onPromoCodeChanged = widget.onPromoCodeChanged;
    final total = checkoutMoney(currencyCode, totalPrice);
    final canPay = _acceptedFareRules && onPay != null;
    return CheckoutScaffold(
      header: FlightBookingFlowHeader(
        title: labels.reviewPay,
        activeStep: 3,
        onBack: onBack,
      ),
      footer: CheckoutFooter(
        total: total,
        caption: labels.acceptTermsBelow,
        buttonLabel: labels.payAmount(total),
        onPressed: null,
        onAsyncPressed: canPay ? onPay : null,
        loading: paying,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 17),
        children: [
          _ItineraryCard(flight: flight, labels: labels),
          const SizedBox(height: 10),
          CheckoutPanel(
            padding: const EdgeInsets.all(13),
            child: Column(
              children: [
                for (final passenger in passengers)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const CheckoutIconTile(
                            icon: Icons.person_outline_rounded),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                passenger.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              if (passenger.email.isNotEmpty)
                                Text(
                                  passenger.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 10),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (passengers.isEmpty)
                  Text(labels.noPassengerData,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          CheckoutPanel(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Column(
              children: [
                Row(
                  children: [
                    CheckoutIconTile(
                      icon: savedPaymentLabel == null
                          ? Icons.lock_outline_rounded
                          : Icons.credit_card_rounded,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        savedPaymentLabel ?? labels.simulatedPayment,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (savedPaymentExpiry?.isNotEmpty == true)
                      Text(
                        savedPaymentExpiry!,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                      ),
                  ],
                ),
                if (onPromoCodeChanged != null) ...[
                  const Divider(height: 1),
                  _PromoEntry(onChanged: onPromoCodeChanged, labels: labels),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          CheckoutPanel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(labels.priceDetails,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 9),
                for (final line in priceLines)
                  CheckoutDataRow(
                    label: line.label,
                    value: line.value ??
                        checkoutMoney(currencyCode, line.amount ?? 0),
                  ),
                if (seats.isNotEmpty)
                  CheckoutDataRow(label: labels.seats, value: seats.join(', ')),
                const Divider(height: 20),
                CheckoutDataRow(
                  label: l10n.flightTotal,
                  value: total,
                  emphasis: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _acceptedFareRules,
            onChanged: (value) {
              final accepted = value ?? false;
              setState(() => _acceptedFareRules = accepted);
              widget.onFareRulesChanged(accepted);
            },
            activeColor: AppColors.primary,
            title: Text(
              labels.fareRules(fareLabel),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11, height: 1.35),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 14, color: AppColors.textHint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  labels.securePayment(currencyCode),
                  style:
                      const TextStyle(color: AppColors.textHint, fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

@immutable
class FlightPriceLine {
  final String label;
  final double? amount;
  final String? value;

  const FlightPriceLine({required this.label, this.amount, this.value})
      : assert(amount != null || value != null);
}

class _PromoEntry extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final CheckoutLabels labels;
  const _PromoEntry({required this.onChanged, required this.labels});

  @override
  State<_PromoEntry> createState() => _PromoEntryState();
}

class _PromoEntryState extends State<_PromoEntry> {
  bool _open = false;
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const CheckoutIconTile(
                      icon: Icons.confirmation_number_outlined),
                  const SizedBox(width: 10),
                  Expanded(child: Text(widget.labels.promoCode)),
                  Icon(_open ? Icons.remove_rounded : Icons.add_rounded,
                      size: 19, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _controller,
                onChanged: widget.onChanged,
                decoration: checkoutInputDecoration(
                    widget.labels.promoCode, Icons.local_offer_outlined),
              ),
            ),
        ],
      );
}

class _ItineraryCard extends StatelessWidget {
  final FlightModel flight;
  final CheckoutLabels labels;
  const _ItineraryCard({required this.flight, required this.labels});

  @override
  Widget build(BuildContext context) => CheckoutPanel(
        padding: const EdgeInsets.all(13),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _AirportTime(
                    code: flight.originCode,
                    city: flight.originCity,
                    time: checkoutClock(flight.departureTime),
                    alignment: CrossAxisAlignment.start,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Text(flight.duration,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 10)),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.circle,
                              size: 6, color: AppColors.primary),
                          Expanded(
                            child: Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              color: AppColors.border,
                            ),
                          ),
                          const Icon(Icons.flight_rounded,
                              size: 15, color: AppColors.primary),
                          Expanded(
                            child: Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              color: AppColors.border,
                            ),
                          ),
                          const Icon(Icons.circle,
                              size: 6, color: AppColors.primary),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _AirportTime(
                    code: flight.destinationCode,
                    city: flight.destinationCity,
                    time: checkoutClock(flight.arrivalTime),
                    alignment: CrossAxisAlignment.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${flight.airline} · ${flight.flightNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10),
                  ),
                ),
                Text(
                  flight.isDirect ? labels.direct : labels.stops(flight.stops),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      );
}

class _AirportTime extends StatelessWidget {
  final String code;
  final String city;
  final String time;
  final CrossAxisAlignment alignment;
  const _AirportTime({
    required this.code,
    required this.city,
    required this.time,
    required this.alignment,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: alignment,
        children: [
          Text(code,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800)),
          Text(time,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          Text(city,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
        ],
      );
}

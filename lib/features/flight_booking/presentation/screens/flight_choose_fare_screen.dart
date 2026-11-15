import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/price_comparison.dart';
import '../../../../global_widgets/flight_currency_selector.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_model.dart';
import '../../../../models/flight_seat_map.dart';
import 'flight_checkout_shared_components.dart';

class FlightChooseFareScreen extends StatelessWidget {
  final FlightModel flight;
  final List<FlightSeatFare> fares;
  final String? selectedFareId;
  final int passengerCount;
  final String currencyCode;
  final PriceComparison comparison;
  final ValueChanged<String> onCurrencyChanged;
  final double? totalPrice;
  final bool showAvailability;
  final ValueChanged<FlightSeatFare> onFareSelected;
  final VoidCallback? onContinue;
  final VoidCallback? onBack;

  const FlightChooseFareScreen({
    super.key,
    required this.flight,
    required this.fares,
    required this.selectedFareId,
    required this.passengerCount,
    required this.currencyCode,
    required this.comparison,
    required this.onCurrencyChanged,
    required this.onFareSelected,
    required this.onContinue,
    this.totalPrice,
    this.showAvailability = true,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = CheckoutLabels(l10n);
    FlightSeatFare? selected;
    for (final fare in fares) {
      if (fare.id == selectedFareId) {
        selected = fare;
        break;
      }
    }
    final amount = totalPrice ?? (selected?.price ?? 0) * passengerCount;
    return CheckoutScaffold(
      header: FlightBookingFlowHeader(
        title: labels.chooseFare,
        activeStep: 0,
        onBack: onBack,
      ),
      footer: CheckoutFooter(
        total: checkoutMoney(
          currencyCode,
          amount,
          locale: Localizations.localeOf(context).languageCode,
        ),
        caption: labels.travellerPrice(passengerCount),
        buttonLabel: labels.continueLabel,
        onPressed: onContinue,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 18),
        children: [
          CheckoutRouteCaption(flight: flight),
          const SizedBox(height: 18),
          FlightCurrencySelector(
            comparison: comparison,
            onChanged: onCurrencyChanged,
          ),
          Text(labels.chooseYourFare,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(labels.fareSubheading,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 15),
          if (fares.isEmpty)
            CheckoutEmptyPanel(message: labels.noFareData)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 8.0;
                final columns = constraints.maxWidth < 350 ? 1 : 3;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: fares
                      .map((fare) => SizedBox(
                            width: width,
                            child: _FareChoiceCard(
                              fare: fare,
                              currencyCode: currencyCode,
                              comparison: comparison,
                              sourceCurrencyCode: flight.isDuffelOffer
                                  ? flight.priceCurrencyCode
                                  : 'USD',
                              selected: fare.id == selectedFareId,
                              showAvailability: showAvailability,
                              onTap: () => onFareSelected(fare),
                            ),
                          ))
                      .toList(),
                );
              },
            ),
          const SizedBox(height: 15),
          if (selected != null)
            CheckoutPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const CheckoutIconTile(
                          icon: Icons.confirmation_number_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(selected.label,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CheckoutDataRow(
                    label: labels.farePrice,
                    value: checkoutMoney(
                      currencyCode,
                      comparison.convert(
                            selected.price,
                            flight.isDuffelOffer
                                ? flight.priceCurrencyCode
                                : 'USD',
                          ) ??
                          selected.price,
                      locale: Localizations.localeOf(context).languageCode,
                    ),
                  ),
                  if (showAvailability)
                    CheckoutDataRow(
                      label: labels.availableSeats,
                      value: selected.availableSeats.toString(),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          CheckoutRouteCaption(flight: flight, compact: true),
        ],
      ),
    );
  }
}

class _FareChoiceCard extends StatelessWidget {
  final FlightSeatFare fare;
  final String currencyCode;
  final PriceComparison comparison;
  final String sourceCurrencyCode;
  final bool selected;
  final bool showAvailability;
  final VoidCallback onTap;

  const _FareChoiceCard({
    required this.fare,
    required this.currencyCode,
    required this.comparison,
    required this.sourceCurrencyCode,
    required this.selected,
    required this.showAvailability,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 90),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: selected ? AppColors.primarySurface : AppColors.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(fare.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: selected ? AppColors.primary : AppColors.border,
                    size: 17,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  checkoutMoney(
                    currencyCode,
                    comparison.convert(fare.price, sourceCurrencyCode) ??
                        fare.price,
                    locale: Localizations.localeOf(context).languageCode,
                  ),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16),
                ),
              ),
              const SizedBox(height: 3),
              if (showAvailability)
                Text(
                  '${fare.availableSeats}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10),
                ),
            ],
          ),
        ),
      );
}

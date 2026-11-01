import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../features/price_alerts/logic/price_alerts_store.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_model.dart';
import '../../../../routes/app_routes.dart';
import '../../logic/flight_controller.dart';

class FlightResultsScreen extends StatefulWidget {
  const FlightResultsScreen({super.key});

  @override
  State<FlightResultsScreen> createState() => _FlightResultsScreenState();
}

class _FlightResultsScreenState extends State<FlightResultsScreen> {
  FlightController? _ctrl;
  bool _priceCheckDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctrl ??= ModalRoute.of(context)?.settings.arguments as FlightController?;
    if (!_priceCheckDone && _ctrl != null) {
      _priceCheckDone = true;
      PriceAlertsStore.instance.checkResults(_ctrl!.results,
          promoTitle: AppLocalizations.of(context).notifPriceDropTitle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final ctrl = _ctrl;
    if (ctrl == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
            '${ctrl.searchParams?.originCode ?? ''} → ${ctrl.searchParams?.destinationCode ?? ''}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: ListenableBuilder(
            listenable: ctrl,
            builder: (_, __) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  _SortChip(
                      label: l10n.cheapest,
                      selected: ctrl.sort == FlightSort.cheapest,
                      onTap: () => ctrl.setSort(FlightSort.cheapest)),
                  const SizedBox(width: 8),
                  _SortChip(
                      label: l10n.fastest,
                      selected: ctrl.sort == FlightSort.fastest,
                      onTap: () => ctrl.setSort(FlightSort.fastest)),
                ],
              ),
            ),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (_, __) {
          if (ctrl.isLoading) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  if (ctrl.searchParams?.isFlexible == true) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        l10n.flightFlexibleSearchLoading,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }
          if (ctrl.results.isEmpty) {
            return Center(
              child: Text(
                ctrl.hasSearchError ? l10n.genericError : l10n.flightNoResults,
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: ctrl.results.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return _FlightResultsHeader(controller: ctrl, l10n: l10n);
              }
              final flight = ctrl.results[i - 1];
              return _FlightCard(
                flight: flight,
                isDark: isDark,
                l10n: l10n,
                onSelect: () {
                  ctrl.selectFlight(flight);
                  Navigator.pushNamed(context, AppRoutes.flightBooking,
                      arguments: ctrl);
                },
              )
                  .animate(delay: Duration(milliseconds: 80 * i))
                  .fade()
                  .slideY(begin: 0.05, end: 0);
            },
          );
        },
      ),
    );
  }
}

class _FlightResultsHeader extends StatelessWidget {
  final FlightController controller;
  final AppLocalizations l10n;

  const _FlightResultsHeader({
    required this.controller,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final params = controller.searchParams;
    final departureLabel = params == null
        ? l10n.searchFlights
        : params.isFlexible
            ? [
                ...params.flexibleDepartureMonths.map((month) =>
                    MaterialLocalizations.of(context).formatMonthYear(month)),
                '${params.flexibleTripDurationDays} ${l10n.flightDays}',
              ].join(' · ')
            : MaterialLocalizations.of(context)
                .formatMediumDate(params.departureDate);
    return Container(
      height: 194,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -12,
            top: -22,
            child: Icon(
              Icons.public_rounded,
              size: 170,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.flight_takeoff_rounded,
                      color: Colors.white70, size: 16),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      departureLabel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${controller.results.length} ${l10n.quickActionFlights}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  _RouteAirport(
                    code: params?.originCode ?? '',
                    city: params?.originCity ?? '',
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        children: [
                          Icon(Icons.flight_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(height: 7),
                          Divider(height: 1, color: Colors.white38),
                        ],
                      ),
                    ),
                  ),
                  _RouteAirport(
                    code: params?.destinationCode ?? '',
                    city: params?.destinationCity ?? '',
                    alignEnd: true,
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.event_available_rounded,
                      color: Colors.white70, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    '${params?.passengers ?? 1} · ${l10n.homeTravelersLabel}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    switch (params?.seatClass) {
                      'business' => l10n.business,
                      'first' => l10n.firstClass,
                      _ => l10n.economy,
                    },
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ).animate().fade(duration: 300.ms);
  }
}

class _RouteAirport extends StatelessWidget {
  final String code;
  final String city;
  final bool alignEnd;

  const _RouteAirport({
    required this.code,
    required this.city,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          code,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 31,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        Text(
          city,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SortChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13)),
      ),
    );
  }
}

class _FlightCard extends StatefulWidget {
  final FlightModel flight;
  final bool isDark;
  final VoidCallback onSelect;
  final AppLocalizations l10n;
  const _FlightCard(
      {required this.flight,
      required this.isDark,
      required this.onSelect,
      required this.l10n});

  @override
  State<_FlightCard> createState() => _FlightCardState();
}

class _FlightCardState extends State<_FlightCard> {
  FlightModel get flight => widget.flight;
  bool get isDark => widget.isDark;
  AppLocalizations get l10n => widget.l10n;
  VoidCallback get onSelect => widget.onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(flight.airline,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.primary)),
                  const SizedBox(height: 2),
                  Text(
                    MaterialLocalizations.of(context)
                        .formatMediumDate(flight.departureTime),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              Row(children: [
                if (!flight.priceIsTotal && flight.priceCurrencyCode == 'USD')
                  ListenableBuilder(
                    listenable: PriceAlertsStore.instance,
                    builder: (_, __) {
                      final tracking = PriceAlertsStore.instance.isTracking(
                          flight.originCode,
                          flight.destinationCode,
                          flight.departureTime);
                      return InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () async {
                          if (tracking) {
                            await PriceAlertsStore.instance.untrack(
                                flight.originCode,
                                flight.destinationCode,
                                flight.departureTime);
                          } else {
                            await PriceAlertsStore.instance.track(
                              originCode: flight.originCode,
                              destinationCode: flight.destinationCode,
                              departureDate: flight.departureTime,
                              priceUsd: flight.economyPrice,
                            );
                          }
                        },
                        child: Icon(
                            tracking
                                ? Icons.notifications_active_rounded
                                : Icons.notifications_none_rounded,
                            size: 20,
                            color: tracking
                                ? AppColors.accentOrange
                                : AppColors.textSecondary),
                      );
                    },
                  ),
              ]),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(children: [
                Text(
                    '${flight.departureTime.hour.toString().padLeft(2, '0')}:${flight.departureTime.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800)),
                Text(flight.originCode,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ]),
              Expanded(
                child: Column(children: [
                  Text(flight.duration,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                  Row(children: [
                    Expanded(
                        child: Container(height: 1.5, color: AppColors.border)),
                    const Icon(Icons.flight_rounded,
                        color: AppColors.primary, size: 18),
                    Expanded(
                        child: Container(height: 1.5, color: AppColors.border)),
                  ]),
                ]),
              ),
              Column(children: [
                Text(
                    '${flight.arrivalTime.hour.toString().padLeft(2, '0')}:${flight.arrivalTime.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800)),
                Text(flight.destinationCode,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ]),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (flight.seatsAvailable >= 0)
                Text(l10n.seatsLeft(flight.seatsAvailable),
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.accentRed,
                        fontWeight: FontWeight.w600)),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                    flight.priceCurrencyCode == 'USD'
                        ? '\$'
                        : '${flight.priceCurrencyCode} ',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                Text(flight.economyPrice.toStringAsFixed(0),
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
                Text(l10n.perPerson,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ]),
            ],
          ),
          const SizedBox(height: 12),
          if (flight.isDuffelOffer)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.flightDuffelBookingUnavailable,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: flight.isDuffelOffer ? null : onSelect,
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
              child: Text(l10n.flightSelectThis),
            ),
          ),
        ],
      ),
    );
  }
}

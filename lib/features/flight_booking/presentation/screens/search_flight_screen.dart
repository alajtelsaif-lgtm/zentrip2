import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../features/price_alerts/logic/price_alerts_store.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_model.dart';
import '../../../../routes/app_routes.dart';
import '../../logic/flight_controller.dart';
import 'flight_search_screen.dart';
import 'flight_primary_button.dart';
import 'seat_selection16line_screen.dart';
import 'seat_selection_screen.dart';

class SearchFlightScreen extends StatefulWidget {
  final FlightSearchParams? initialSearch;
  final FlightController? controller;

  const SearchFlightScreen({
    super.key,
    this.initialSearch,
    this.controller,
  });

  @override
  State<SearchFlightScreen> createState() => _SearchFlightScreenState();
}

class _SearchFlightScreenState extends State<SearchFlightScreen> {
  FlightController? _controller;
  FlightSearchParams? _params;
  String? _error;
  bool _initialized = false;
  bool _ownsController = false;
  bool _priceAlertsChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    final suppliedController =
        widget.controller ?? (routeArgs is FlightController ? routeArgs : null);
    final suppliedParams = widget.initialSearch ??
        (routeArgs is FlightSearchParams ? routeArgs : null);

    if (suppliedController != null) {
      _controller = suppliedController;
      _params = suppliedController.searchParams;
      if (suppliedController.results.isNotEmpty) {
        _checkPriceAlerts();
      } else if (_params != null && !suppliedController.isLoading) {
        unawaited(_search(_params!));
      }
    } else if (suppliedParams != null) {
      _params = suppliedParams;
      _controller = FlightController();
      _ownsController = true;
      unawaited(_search(suppliedParams));
    }
  }

  Future<void> _search(FlightSearchParams params) async {
    try {
      await _controller!.search(params);
      if (!mounted) return;
      _checkPriceAlerts();
    } catch (error, stackTrace) {
      debugPrint('Flight search failed: $error\n$stackTrace');
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _retry() {
    final params = _params;
    if (params == null || _controller == null) return;
    setState(() => _error = null);
    unawaited(_search(params));
  }

  void _checkPriceAlerts() {
    if (_priceAlertsChecked || _controller == null || !mounted) return;
    _priceAlertsChecked = true;
    PriceAlertsStore.instance.checkResults(
      _controller!.results,
      promoTitle: AppLocalizations.of(context).notifPriceDropTitle,
    );
  }

  void _editSearch() {
    final params = _params;
    if (params == null) {
      Navigator.pushNamed(context, AppRoutes.flightSearch);
      return;
    }
    Navigator.pushNamed(
      context,
      AppRoutes.flightSearch,
      arguments: FlightSearchRouteArgs(
        originCode: params.originCode,
        originCity: params.originCity,
        destinationCode: params.destinationCode,
        destinationCity: params.destinationCity,
        roundTrip: params.isRoundTrip,
        departureDate: params.departureDate,
        returnDate: params.returnDate,
        passengers: params.passengers,
        seatClass: params.seatClass,
      ),
    );
  }

  void _selectDepartureDate(DateTime date) {
    final current = _params;
    if (current == null ||
        (current.departureDate.year == date.year &&
            current.departureDate.month == date.month &&
            current.departureDate.day == date.day)) {
      return;
    }
    if (current.isRoundTrip &&
        current.returnDate != null &&
        DateUtils.dateOnly(date)
            .isAfter(DateUtils.dateOnly(current.returnDate!))) {
      return;
    }
    final updated = FlightSearchParams(
      originCode: current.originCode,
      originCity: current.originCity,
      destinationCode: current.destinationCode,
      destinationCity: current.destinationCity,
      departureDate: DateTime(date.year, date.month, date.day),
      returnDate: current.returnDate,
      passengers: current.passengers,
      seatClass: current.seatClass,
      isRoundTrip: current.isRoundTrip,
    );
    setState(() {
      _params = updated;
      _error = null;
      _priceAlertsChecked = false;
    });
    unawaited(_search(updated));
  }

  void _selectFlight(FlightModel flight) {
    final controller = _controller;
    final params = _params ?? controller?.searchParams;
    if (controller == null || params == null) return;

    controller.selectFlight(flight);
    final seatScreen = flight.usesTwoByTwoSeatLayout
        ? SeatSelection16LineScreen(
            flight: flight,
            passengerCount: params.passengers,
            seatClass: params.seatClass,
            returnDate: params.returnDate,
            rowCount: flight.seatRows,
          )
        : SeatSelectionScreen(
            flight: flight,
            passengerCount: params.passengers,
            seatClass: params.seatClass,
            returnDate: params.returnDate,
            rowCount: flight.seatRows,
          );
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => seatScreen));
  }

  @override
  void dispose() {
    if (_ownsController) _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.flightSelectTitle),
        actions: [
          IconButton(
            tooltip: l10n.searchFlights,
            onPressed: _editSearch,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: controller == null || _params == null
          ? _MissingSearch(onSearch: _editSearch)
          : ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                if (controller.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                    ),
                  );
                }
                if (_error != null) {
                  return _SearchError(
                    message: l10n.flightSearchError,
                    retryLabel: l10n.retry,
                    onRetry: _retry,
                    onEdit: _editSearch,
                    editLabel: l10n.searchFlightsBtn,
                  );
                }
                if (controller.results.isEmpty) {
                  return _NoFlights(
                    params: _params!,
                    onEdit: _editSearch,
                    onSelectDepartureDate: _selectDepartureDate,
                  );
                }
                return _FlightResults(
                  controller: controller,
                  params: _params!,
                  onEdit: _editSearch,
                  onSelect: _selectFlight,
                  onSelectDepartureDate: _selectDepartureDate,
                  l10n: l10n,
                );
              },
            ),
    );
  }
}

class _FlightResults extends StatelessWidget {
  final FlightController controller;
  final FlightSearchParams params;
  final VoidCallback onEdit;
  final ValueChanged<FlightModel> onSelect;
  final ValueChanged<DateTime> onSelectDepartureDate;
  final AppLocalizations l10n;

  const _FlightResults({
    required this.controller,
    required this.params,
    required this.onEdit,
    required this.onSelect,
    required this.onSelectDepartureDate,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        _SearchSummary(params: params, onEdit: onEdit, l10n: l10n),
        FlightDateSelector(
          departureDate: params.departureDate,
          lastDate: params.isRoundTrip ? params.returnDate : null,
          onSelected: onSelectDepartureDate,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${controller.results.length} ${l10n.flightResults.toLowerCase()}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              _SortChip(
                label: l10n.cheapest,
                selected: controller.sort == FlightSort.cheapest,
                onTap: () => controller.setSort(FlightSort.cheapest),
              ),
              const SizedBox(width: 8),
              _SortChip(
                label: l10n.fastest,
                selected: controller.sort == FlightSort.fastest,
                onTap: () => controller.setSort(FlightSort.fastest),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: controller.results.length,
            itemBuilder: (context, index) => _FlightCard(
              flight: controller.results[index],
              params: params,
              isDark: isDark,
              onSelect: () => onSelect(controller.results[index]),
              l10n: l10n,
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchSummary extends StatelessWidget {
  final FlightSearchParams params;
  final VoidCallback onEdit;
  final AppLocalizations l10n;

  const _SearchSummary({
    required this.params,
    required this.onEdit,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateText = MaterialLocalizations.of(context)
        .formatMediumDate(params.departureDate);
    final returnText = params.returnDate == null
        ? null
        : MaterialLocalizations.of(context)
            .formatMediumDate(params.returnDate!);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: isDark ? 0.12 : 0.2),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: 20,
            child: Icon(
              Icons.public_rounded,
              size: 144,
              color: Colors.white.withValues(alpha: 0.035),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 15,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      returnText == null
                          ? dateText
                          : '$dateText  ·  $returnText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.searchFlights,
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      minimumSize: const Size(36, 36),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _RouteEndpoint(
                      city: params.originCity,
                      code: params.originCode,
                      alignEnd: false,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 56,
                          height: 20,
                          child: CustomPaint(
                            painter: _RouteLinePainter(
                              color: Colors.white.withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                        Icon(
                          Icons.flight_rounded,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.96),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _RouteEndpoint(
                      city: params.destinationCity,
                      code: params.destinationCode,
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 13,
                runSpacing: 7,
                alignment: WrapAlignment.center,
                children: [
                  _SummaryLabel(
                    icon: Icons.people_alt_rounded,
                    text: '${params.passengers} · ${l10n.homeTravelersLabel}',
                  ),
                  _SummaryLabel(
                    icon: Icons.airline_seat_recline_extra,
                    text: _seatClassLabel(params.seatClass, l10n),
                  ),
                  _SummaryLabel(
                    icon: Icons.sync_alt_rounded,
                    text: params.isRoundTrip ? l10n.roundTrip : l10n.oneWay,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteEndpoint extends StatelessWidget {
  final String city;
  final String code;
  final bool alignEnd;

  const _RouteEndpoint({
    required this.city,
    required this.code,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAlignEnd =
        alignEnd != (Directionality.of(context) == TextDirection.rtl);
    return Column(
      crossAxisAlignment:
          effectiveAlignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          city,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment:
              effectiveAlignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            code,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              height: 1.05,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _RouteLinePainter extends CustomPainter {
  final Color color;

  const _RouteLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(1, size.height - 2)
      ..quadraticBezierTo(
        size.width * 0.48,
        -size.height * 0.3,
        size.width - 1,
        size.height - 2,
      );
    canvas.drawPath(path, paint);
    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(1, size.height - 2), 2.2, pointPaint);
    canvas.drawCircle(Offset(size.width - 1, size.height - 2), 2.2, pointPaint);
  }

  @override
  bool shouldRepaint(covariant _RouteLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class FlightDateSelector extends StatelessWidget {
  final DateTime departureDate;
  final DateTime? lastDate;
  final ValueChanged<DateTime> onSelected;

  const FlightDateSelector({
    super.key,
    required this.departureDate,
    this.lastDate,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final firstDate = DateTime(
      departureDate.year,
      departureDate.month,
      departureDate.day,
    );
    final today = DateUtils.dateOnly(DateTime.now());
    final endDate = lastDate == null
        ? DateTime(firstDate.year + 1, firstDate.month, firstDate.day)
        : DateUtils.dateOnly(lastDate!);
    final dayCount =
        (endDate.difference(firstDate).inDays + 1).clamp(1, 7).toInt();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.flightDateLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Text(
                materialL10n.formatMonthYear(firstDate),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: l10n.flightDateLabel,
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: firstDate,
                    firstDate: firstDate.isBefore(today) ? firstDate : today,
                    lastDate: endDate,
                  );
                  if (picked != null) onSelected(picked);
                },
                icon: const Icon(Icons.calendar_month_rounded, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: dayCount,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final date = firstDate.add(Duration(days: index));
                return _FlightDateCard(
                  date: date,
                  selected: index == 0,
                  onTap: () => onSelected(date),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FlightDateCard extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final VoidCallback onTap;

  const _FlightDateCard({
    required this.date,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);
    final weekday = materialL10n.narrowWeekdays[date.weekday % 7];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = theme.colorScheme.surface;
    return SizedBox(
      width: 64,
      child: Material(
        color: selected ? AppColors.primary : background,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? AppColors.primaryLight
                    : isDark
                        ? AppColors.darkBorder
                        : AppColors.border,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  weekday,
                  style: TextStyle(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.76)
                        : isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${date.day}',
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SummaryLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

class _FlightCard extends StatelessWidget {
  final FlightModel flight;
  final FlightSearchParams params;
  final bool isDark;
  final VoidCallback onSelect;
  final AppLocalizations l10n;

  const _FlightCard({
    required this.flight,
    required this.params,
    required this.isDark,
    required this.onSelect,
    required this.l10n,
  });

  double get _fare => switch (params.seatClass.toLowerCase()) {
        'business' => flight.businessPrice ?? flight.economyPrice,
        'first' => flight.firstPrice ?? flight.economyPrice,
        _ => flight.economyPrice,
      };

  @override
  Widget build(BuildContext context) {
    final baseFare = _fare * params.passengers;
    final taxes = baseFare * 0.12;
    const serviceFee = 12.0;
    final total = baseFare + taxes + serviceFee;
    final available = flight.seatsAvailable >= params.passengers;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final border = isDark ? AppColors.darkBorder : AppColors.border;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _AirlineLogo(flight: flight),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      flight.airline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      flight.flightNumber,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                l10n.seatsLeft(flight.seatsAvailable),
                style: TextStyle(
                  color:
                      available ? AppColors.textSecondary : AppColors.accentRed,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _AirportTime(
                time: flight.departureTime,
                code: flight.originCode,
                city: flight.originCity,
                alignEnd: false,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    children: [
                      Text(
                        flight.duration,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1.5,
                              color: AppColors.border,
                            ),
                          ),
                          const Icon(Icons.flight_rounded,
                              color: AppColors.primary, size: 17),
                          Expanded(
                            child: Container(
                              height: 1.5,
                              color: AppColors.border,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        flight.isDirect
                            ? l10n.flightDirect
                            : l10n.flightStops(flight.stops),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _AirportTime(
                time: flight.arrivalTime,
                code: flight.destinationCode,
                city: flight.destinationCity,
                alignEnd: true,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1),
          ),
          _PriceLine(
            label:
                '${l10n.flightTicketPrice} · ${params.passengers} × \$${_fare.toStringAsFixed(2)}',
            amount: baseFare,
          ),
          const SizedBox(height: 5),
          _PriceLine(label: l10n.flightTaxesFees, amount: taxes),
          const SizedBox(height: 5),
          _PriceLine(label: l10n.flightServiceFee, amount: serviceFee),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${l10n.flightTotal} · ${_seatClassLabel(params.seatClass, l10n)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '\$${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FlightPrimaryButton(
            label: l10n.flightSelectThis,
            onPressed: available ? onSelect : null,
            icon: Icons.event_seat_rounded,
          ),
        ],
      ),
    );
  }
}

class _AirportTime extends StatelessWidget {
  final DateTime time;
  final String code;
  final String city;
  final bool alignEnd;

  const _AirportTime({
    required this.time,
    required this.code,
    required this.city,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    final alignment =
        alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return SizedBox(
      width: 82,
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Text(
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          Text(
            code,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            city,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _AirlineLogo extends StatelessWidget {
  final FlightModel flight;

  const _AirlineLogo({required this.flight});

  @override
  Widget build(BuildContext context) {
    final logo = flight.airlineLogoUrl;
    return CircleAvatar(
      radius: 21,
      backgroundColor: AppColors.primarySurface,
      foregroundImage: logo == null || logo.isEmpty ? null : NetworkImage(logo),
      onForegroundImageError: logo == null || logo.isEmpty
          ? null
          : (error, stackTrace) =>
              debugPrint('Airline logo failed to load: $error'),
      child: flight.airlineCode.isEmpty
          ? const Icon(Icons.flight_rounded, color: AppColors.primary, size: 19)
          : Text(
              flight.airlineCode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

class _PriceLine extends StatelessWidget {
  final String label;
  final double amount;

  const _PriceLine({required this.label, required this.amount});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
}

class _NoFlights extends StatelessWidget {
  final FlightSearchParams params;
  final VoidCallback onEdit;
  final ValueChanged<DateTime> onSelectDepartureDate;

  const _NoFlights({
    required this.params,
    required this.onEdit,
    required this.onSelectDepartureDate,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        _SearchSummary(params: params, onEdit: onEdit, l10n: l10n),
        FlightDateSelector(
          departureDate: params.departureDate,
          lastDate: params.isRoundTrip ? params.returnDate : null,
          onSelected: onSelectDepartureDate,
        ),
      ],
    );
  }
}

class _SearchError extends StatelessWidget {
  final String message;
  final String retryLabel;
  final String editLabel;
  final VoidCallback onRetry;
  final VoidCallback onEdit;

  const _SearchError({
    required this.message,
    required this.retryLabel,
    required this.editLabel,
    required this.onRetry,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) => _MessageState(
        icon: Icons.cloud_off_rounded,
        title: message,
        buttonLabel: retryLabel,
        onPressed: onRetry,
        secondaryLabel: editLabel,
        onSecondaryPressed: onEdit,
      );
}

class _MissingSearch extends StatelessWidget {
  final VoidCallback onSearch;

  const _MissingSearch({required this.onSearch});

  @override
  Widget build(BuildContext context) => _MessageState(
        icon: Icons.search_rounded,
        title: AppLocalizations.of(context).searchFlights,
        buttonLabel: AppLocalizations.of(context).searchFlightsBtn,
        onPressed: onSearch,
      );
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String buttonLabel;
  final VoidCallback onPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.buttonLabel,
    required this.onPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 54, color: AppColors.primaryLight),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onPressed,
                child: Text(buttonLabel),
              ),
              if (secondaryLabel != null && onSecondaryPressed != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSecondaryPressed,
                  child: Text(secondaryLabel!),
                ),
              ],
            ],
          ),
        ),
      );
}

String _seatClassLabel(String seatClass, AppLocalizations l10n) =>
    switch (seatClass.toLowerCase()) {
      'business' => l10n.business,
      'first' => l10n.firstClass,
      _ => l10n.economy,
    };

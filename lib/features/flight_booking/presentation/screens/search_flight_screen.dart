import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shimmer/shimmer.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../features/price_alerts/logic/price_alerts_store.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_model.dart';
import '../../../../routes/app_routes.dart';
import '../../logic/flight_controller.dart';
import 'flight_search_screen.dart';

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
      if (mounted) {
        setState(() =>
            _error = AppLocalizations.of(context).flightProviderUnavailable);
      }
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
      flexibleDepartureMonths: current.flexibleDepartureMonths,
      flexibleTripDurationDays: current.flexibleTripDurationDays,
      flexibleWeekendsOnly: current.flexibleWeekendsOnly,
    );
    setState(() {
      _params = updated;
      _error = null;
      _priceAlertsChecked = false;
    });
    unawaited(_search(updated));
  }

  void _selectSeatClass(String seatClass) {
    final current = _params;
    if (current == null || current.seatClass == seatClass) return;
    final updated = FlightSearchParams(
      originCode: current.originCode,
      originCity: current.originCity,
      destinationCode: current.destinationCode,
      destinationCity: current.destinationCity,
      departureDate: current.departureDate,
      returnDate: current.returnDate,
      passengers: current.passengers,
      seatClass: seatClass,
      isRoundTrip: current.isRoundTrip,
      flexibleDepartureMonths: current.flexibleDepartureMonths,
      flexibleTripDurationDays: current.flexibleTripDurationDays,
      flexibleWeekendsOnly: current.flexibleWeekendsOnly,
    );
    setState(() {
      _params = updated;
      _error = null;
      _priceAlertsChecked = false;
    });
    unawaited(_search(updated));
  }

  Future<void> _showFlightFilters() async {
    final controller = _controller;
    if (controller == null) return;
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(l10n.cheapest),
              trailing: controller.sort == FlightSort.cheapest
                  ? const Icon(Icons.check_rounded, color: AppColors.primary)
                  : null,
              onTap: () {
                controller.setSort(FlightSort.cheapest);
                Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: Text(l10n.fastest),
              trailing: controller.sort == FlightSort.fastest
                  ? const Icon(Icons.check_rounded, color: AppColors.primary)
                  : null,
              onTap: () {
                controller.setSort(FlightSort.fastest);
                Navigator.pop(sheetContext);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _selectFlight(FlightModel flight) {
    final controller = _controller;
    final params = _params ?? controller?.searchParams;
    if (controller == null || params == null) return;

    controller.selectFlight(flight);
    Navigator.of(context).pushNamed(
      AppRoutes.flightBooking,
      arguments: controller,
    );
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
    if (controller == null) {
      return _buildScaffold(context, controller, l10n);
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _buildScaffold(context, controller, l10n),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    FlightController? controller,
    AppLocalizations l10n,
  ) {
    Widget body;
    if (controller == null || _params == null) {
      body = _MissingSearch(onSearch: _editSearch);
    } else {
      body = _FlightResults(
        controller: controller,
        params: _params!,
        onEdit: _editSearch,
        onFilter: _showFlightFilters,
        onBack: () => Navigator.of(context).maybePop(),
        onSelect: _selectFlight,
        onSelectDepartureDate: _selectDepartureDate,
        onSelectSeatClass: _selectSeatClass,
        onRetry: _retry,
        error: _error,
        l10n: l10n,
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: controller == null || _params == null
          ? AppBar(title: Text(l10n.flightSelectTitle))
          : null,
      body: body,
    );
  }
}

class _FlightResults extends StatelessWidget {
  final FlightController controller;
  final FlightSearchParams params;
  final VoidCallback onEdit;
  final VoidCallback onFilter;
  final VoidCallback onBack;
  final ValueChanged<FlightModel> onSelect;
  final ValueChanged<DateTime> onSelectDepartureDate;
  final ValueChanged<String> onSelectSeatClass;
  final VoidCallback onRetry;
  final String? error;
  final AppLocalizations l10n;

  const _FlightResults({
    required this.controller,
    required this.params,
    required this.onEdit,
    required this.onFilter,
    required this.onBack,
    required this.onSelect,
    required this.onSelectDepartureDate,
    required this.onSelectSeatClass,
    required this.onRetry,
    required this.error,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final failed = controller.hasSearchError || error != null;
    final airlineCount = controller.results
        .map((flight) => flight.airline.trim().toLowerCase())
        .where((airline) => airline.isNotEmpty)
        .toSet()
        .length;
    return SafeArea(
      top: true,
      child: Column(
        children: [
          _SearchSummary(
            params: params,
            duration: controller.results.isEmpty
                ? null
                : _formatFlightDuration(
                    controller.results.first.durationMinutes,
                    l10n,
                  ),
            onFilter: onFilter,
            onBack: onBack,
            l10n: l10n,
          ),
          FlightDateSelector(
            departureDate: params.departureDate,
            selectedDate: params.departureDate,
            lastDate: params.isRoundTrip ? params.returnDate : null,
            onSelected: onSelectDepartureDate,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 13, 20, 9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.flightAirlinesCount(airlineCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                        ),
                  ),
                ),
                _CabinSelectorChip(
                  label: _seatClassLabel(params.seatClass, l10n),
                  onTap: () => _showCabinSelector(
                    context,
                    params.seatClass,
                    onSelectSeatClass,
                    l10n,
                  ),
                ),
              ],
            ),
          ),
          if (controller.hasProviderWarning && !failed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.flightProviderWarning,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ),
          Expanded(
            child: controller.isLoading
                ? ListView.builder(
                    key: const ValueKey('flight-loading-skeletons'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: 3,
                    itemBuilder: (_, __) => const _FlightCardSkeleton(),
                  )
                : failed
                    ? _SearchError(
                        message: error ?? l10n.flightProviderUnavailable,
                        retryLabel: l10n.retry,
                        onRetry: onRetry,
                        onEdit: onEdit,
                        editLabel: l10n.searchFlightsBtn,
                      )
                    : controller.results.isEmpty
                        ? _NoFlights(
                            params: params,
                            onEdit: onEdit,
                          )
                        : ListView.builder(
                            key: const ValueKey('flight-results-list'),
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: controller.results.length,
                            itemBuilder: (context, index) => _FlightCard(
                              flight: controller.results[index],
                              params: params,
                              isDark: isDark,
                              onSelect: () =>
                                  onSelect(controller.results[index]),
                              l10n: l10n,
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _SearchSummary extends StatelessWidget {
  final FlightSearchParams params;
  final String? duration;
  final VoidCallback onFilter;
  final VoidCallback onBack;
  final AppLocalizations l10n;

  const _SearchSummary({
    required this.params,
    required this.duration,
    required this.onFilter,
    required this.onBack,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = Localizations.localeOf(context).toString();
    final routeDateText =
        DateFormat('dd MMM yyyy', locale).format(params.departureDate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 18),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(30),
        ),
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
                  IconButton(
                    tooltip: l10n.goBack,
                    onPressed: onBack,
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      minimumSize: const Size(38, 38),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  ),
                  Expanded(
                    child: Text(
                      l10n.flightSelectTitle,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.searchFlights,
                    onPressed: onFilter,
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
              const SizedBox(height: 8),
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
                  Expanded(
                    flex: 2,
                    child: _RouteArc(
                      duration: duration,
                      date: routeDateText,
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
        Text(
          city,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _RouteArc extends StatelessWidget {
  final String? duration;
  final String date;

  const _RouteArc({required this.duration, required this.date});

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (duration != null)
          Text(
            duration!,
            maxLines: 1,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        Text(
          date,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 31,
          width: double.infinity,
          child: CustomPaint(
            painter: _RouteLinePainter(
              color: Colors.white.withValues(alpha: 0.78),
              rtl: rtl,
            ),
            child: Align(
              alignment: rtl ? Alignment.centerRight : Alignment.centerLeft,
              child: Transform.rotate(
                angle: rtl ? 3.141592653589793 : 0,
                child: const Icon(
                  Icons.flight_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RouteLinePainter extends CustomPainter {
  final Color color;
  final bool rtl;

  const _RouteLinePainter({required this.color, required this.rtl});

  @override
  void paint(Canvas canvas, Size size) {
    final startX = rtl ? size.width - 2 : 2.0;
    final endX = rtl ? 2.0 : size.width - 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(startX, size.height - 2)
      ..quadraticBezierTo(
        size.width / 2,
        -size.height * 0.25,
        endX,
        size.height - 2,
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dashLength = 4.0;
      const gapLength = 3.5;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            (distance + dashLength).clamp(0, metric.length),
          ),
          paint,
        );
        distance += dashLength + gapLength;
      }
    }
    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(startX, size.height - 2), 2.2, pointPaint);
    canvas.drawCircle(Offset(endX, size.height - 2), 2.2, pointPaint);
  }

  @override
  bool shouldRepaint(covariant _RouteLinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.rtl != rtl;
}

class FlightDateSelector extends StatelessWidget {
  final DateTime departureDate;
  final DateTime? selectedDate;
  final DateTime? lastDate;
  final ValueChanged<DateTime> onSelected;

  const FlightDateSelector({
    super.key,
    required this.departureDate,
    this.selectedDate,
    this.lastDate,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final firstDate = DateTime(
      departureDate.year,
      departureDate.month,
      departureDate.day,
    );
    final today = DateUtils.dateOnly(DateTime.now());
    final endDate =
        DateTime(firstDate.year + 1, firstDate.month, firstDate.day);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.flightDateLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate ?? departureDate,
                    firstDate: firstDate.isBefore(today) ? firstDate : today,
                    lastDate: endDate,
                  );
                  if (picked != null &&
                      (lastDate == null || !picked.isAfter(lastDate!))) {
                    onSelected(picked);
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: Text(l10n.flightCalendar),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 62,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 350;
                return Row(
                  children: List.generate(7, (index) {
                    final date = firstDate.add(Duration(days: index));
                    final isAfterReturn = lastDate != null &&
                        DateUtils.dateOnly(date)
                            .isAfter(DateUtils.dateOnly(lastDate!));
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          end: index == 6 ? 0 : 5,
                        ),
                        child: _FlightDateCard(
                          key: ValueKey(
                            'flight-date-${date.year}-${date.month}-${date.day}',
                          ),
                          date: date,
                          compact: compact,
                          selected: DateUtils.isSameDay(
                            date,
                            selectedDate ?? departureDate,
                          ),
                          enabled: !isAfterReturn,
                          onTap: () => onSelected(date),
                        ),
                      ),
                    );
                  }),
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
  final bool compact;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _FlightDateCard({
    super.key,
    required this.date,
    required this.compact,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final weekday = compact
        ? materialL10n.narrowWeekdays[date.weekday % 7]
        : DateFormat.E(locale).format(date);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = theme.colorScheme.surface;
    return SizedBox(
      child: Material(
        color: selected ? AppColors.primary : background,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: !enabled
                    ? (isDark ? AppColors.darkBorder : AppColors.border)
                    : selected
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
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.76)
                        : isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  materialL10n.formatDecimal(date.day),
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : !enabled
                            ? AppColors.textHint
                            : isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary,
                    fontSize: 16,
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

class _CabinSelectorChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _CabinSelectorChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.grid_view_rounded,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 15, color: AppColors.primary),
              ],
            ),
          ),
        ),
      );
}

Future<void> _showCabinSelector(
  BuildContext context,
  String selected,
  ValueChanged<String> onSelected,
  AppLocalizations l10n,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in [
            ('economy', l10n.economy),
            ('business', l10n.business),
            ('first', l10n.firstClass),
          ])
            ListTile(
              title: Text(option.$2),
              trailing: selected.toLowerCase() == option.$1
                  ? const Icon(Icons.check_rounded, color: AppColors.primary)
                  : null,
              onTap: () {
                Navigator.pop(sheetContext);
                onSelected(option.$1);
              },
            ),
        ],
      ),
    ),
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
    final baseTotal =
        flight.priceIsTotal ? flight.economyPrice : _fare * params.passengers;
    final total =
        flight.priceIsTotal ? baseTotal : baseTotal + (baseTotal * 0.12) + 12.0;
    final perPerson = total / params.passengers;
    final available =
        flight.isDuffelOffer || flight.seatsAvailable >= params.passengers;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final border = isDark ? AppColors.darkBorder : AppColors.border;
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat('EEE d MMM', locale)
        .format(flight.departureTime)
        .toUpperCase();

    return Opacity(
      opacity: available ? 1 : 0.65,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: border),
          boxShadow: isDark
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.055),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: available ? onSelect : null,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 34,
                          padding: const EdgeInsetsDirectional.only(
                            start: 13,
                            end: 7,
                          ),
                          alignment: AlignmentDirectional.centerStart,
                          color: AppColors.primary,
                          child: Text(
                            flight.airline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 84,
                        height: 34,
                        alignment: Alignment.center,
                        color: AppColors.primary,
                        child: Text(
                          date,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(11, 13, 9, 10),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: _AirportTime(
                                        label: l10n.from.toUpperCase(),
                                        time: flight.departureTime,
                                        code: flight.originCode,
                                        city: flight.originCity,
                                        alignEnd: false,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 3,
                                      child: _FlightTimeline(
                                        duration: _formatFlightDuration(
                                          flight.durationMinutes,
                                          l10n,
                                        ),
                                        direct: flight.isDirect,
                                        stops: flight.stops,
                                        l10n: l10n,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: _AirportTime(
                                        label: l10n.to.toUpperCase(),
                                        time: flight.arrivalTime,
                                        code: flight.destinationCode,
                                        city: flight.destinationCity,
                                        alignEnd: true,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 13),
                                Container(height: 1, color: AppColors.divider),
                                const SizedBox(height: 9),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _TicketMetadata(
                                        label: l10n.flightNumber.toUpperCase(),
                                        value: flight.flightNumber,
                                      ),
                                    ),
                                    Expanded(
                                      child: _TicketMetadata(
                                        label: l10n.travelClass.toUpperCase(),
                                        value: _seatClassLabel(
                                          params.seatClass,
                                          l10n,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _TicketMetadata(
                                        label:
                                            l10n.flightSeatsLabel.toUpperCase(),
                                        value: flight.seatsAvailable < 0
                                            ? '—'
                                            : l10n.seatsLeft(
                                                flight.seatsAvailable,
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const _TicketSeparator(),
                        SizedBox(
                          width: 70,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(5, 13, 5, 8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  l10n.flightFare.toUpperCase(),
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    formatProviderMoney(
                                      perPerson,
                                      flight.priceCurrencyCode,
                                    ),
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Text(
                                  l10n.flightPerPerson,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 8,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                const _TicketBarcode(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AirportTime extends StatelessWidget {
  final String label;
  final DateTime time;
  final String code;
  final String city;
  final bool alignEnd;

  const _AirportTime({
    required this.label,
    required this.time,
    required this.code,
    required this.city,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final alignRight = alignEnd != isRtl;
    final alignment =
        alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 7,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          code,
          maxLines: 1,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          city,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 8,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            TimeOfDay.fromDateTime(time).format(context),
            maxLines: 1,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _FlightTimeline extends StatelessWidget {
  final String duration;
  final bool direct;
  final int stops;
  final AppLocalizations l10n;

  const _FlightTimeline({
    required this.duration,
    required this.direct,
    required this.stops,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        children: [
          Text(
            duration,
            maxLines: 1,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _DashedLine()),
              Transform.rotate(
                angle: rtl ? 3.141592653589793 : 0,
                child: const Icon(
                  Icons.flight_rounded,
                  size: 14,
                  color: AppColors.primary,
                ),
              ),
              Expanded(child: _DashedLine()),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            direct ? l10n.flightDirect : l10n.flightStops(stops),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 7,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _HorizontalDashPainter(),
        child: const SizedBox(height: 1),
      );
}

class _HorizontalDashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 5) {
      canvas.drawLine(
        Offset(x, 0),
        Offset((x + 2.5).clamp(0.0, size.width).toDouble(), 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TicketMetadata extends StatelessWidget {
  final String label;
  final String value;

  const _TicketMetadata({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 7,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _TicketSeparator extends StatelessWidget {
  const _TicketSeparator();

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _VerticalTicketSeparator(
          color: AppColors.border,
          cutoutColor: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: const SizedBox(width: 12),
      );
}

class _VerticalTicketSeparator extends CustomPainter {
  final Color color;
  final Color cutoutColor;

  const _VerticalTicketSeparator({
    required this.color,
    required this.cutoutColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 6) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(
          size.width / 2,
          (y + 3).clamp(0.0, size.height).toDouble(),
        ),
        line,
      );
    }
    final cutout = Paint()..color = cutoutColor;
    canvas
      ..drawCircle(Offset(size.width / 2, 0), 5, cutout)
      ..drawCircle(Offset(size.width / 2, size.height), 5, cutout);
  }

  @override
  bool shouldRepaint(covariant _VerticalTicketSeparator oldDelegate) =>
      oldDelegate.color != color || oldDelegate.cutoutColor != cutoutColor;
}

class _TicketBarcode extends StatelessWidget {
  const _TicketBarcode();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 54,
        height: 21,
        child: CustomPaint(painter: _BarcodePainter()),
      );
}

class _BarcodePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const pattern = [1, 2, 1, 1, 3, 1, 2, 1, 1, 3, 1, 2, 2, 1, 1, 3, 2, 1];
    final paint = Paint()..color = AppColors.textPrimary;
    var x = 0.0;
    for (var index = 0; index < pattern.length && x < size.width; index++) {
      final width = pattern[index].toDouble();
      canvas.drawRect(Rect.fromLTWH(x, 0, width, size.height), paint);
      x += width + 1;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FlightCardSkeleton extends StatelessWidget {
  const _FlightCardSkeleton();

  @override
  Widget build(BuildContext context) => Container(
        height: 154,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Shimmer.fromColors(
            baseColor: AppColors.border,
            highlightColor: AppColors.surface,
            child: Column(
              children: [
                Container(height: 34, color: AppColors.surfaceSecondary),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Expanded(child: _SkeletonBlock(height: 37)),
                            SizedBox(width: 12),
                            Expanded(child: _SkeletonBlock(height: 25)),
                            SizedBox(width: 12),
                            Expanded(child: _SkeletonBlock(height: 37)),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(child: _SkeletonBlock(height: 19)),
                            SizedBox(width: 8),
                            Expanded(child: _SkeletonBlock(height: 19)),
                            SizedBox(width: 8),
                            Expanded(child: _SkeletonBlock(height: 19)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _SkeletonBlock extends StatelessWidget {
  final double height;

  const _SkeletonBlock({required this.height});

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(6),
        ),
      );
}

class _NoFlights extends StatelessWidget {
  final FlightSearchParams params;
  final VoidCallback onEdit;

  const _NoFlights({
    required this.params,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dateText = MaterialLocalizations.of(context)
        .formatMediumDate(params.departureDate);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.flight_rounded,
                  size: 42, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text(
                l10n.flightNoResultsForSearch(
                  params.originCode,
                  params.destinationCode,
                  dateText,
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: onEdit,
                child: Text(l10n.searchFlightsBtn),
              ),
            ],
          ),
        ),
      ),
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
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
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
                    if (secondaryLabel != null &&
                        onSecondaryPressed != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: onSecondaryPressed,
                        child: Text(secondaryLabel!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
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

String _formatFlightDuration(int durationMinutes, AppLocalizations l10n) =>
    l10n.flightDurationShort(
      durationMinutes ~/ 60,
      durationMinutes % 60,
    );

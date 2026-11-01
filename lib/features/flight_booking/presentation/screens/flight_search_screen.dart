import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/current_location_service.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_model.dart';
import '../../../../routes/app_routes.dart';
import '../../logic/flight_controller.dart';
import '../../logic/flexible_flight_selection.dart';
import '../widgets/flexible_flight_dates_button.dart';

/// مفتاح تخزين آخر وجهة تم البحث عنها، يُستخدم من شاشة SearchFlightsScreen
/// (لعرض اقتراح "كرر آخر بحث") ومن هذه الشاشة نفسها.
class FlightSearchHistory {
  static const _codeKey = 'last_flight_dest_code';
  static const _cityKey = 'last_flight_dest_city';

  static Future<({String code, String city})?> lastDestination() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_codeKey);
    final city = prefs.getString(_cityKey);
    if (code == null || city == null) return null;
    return (code: code, city: city);
  }

  static Future<void> saveDestination(String code, String city) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_codeKey, code);
    await prefs.setString(_cityKey, city);
  }
}

class FlightSearchRouteArgs {
  final String originCode;
  final String originCity;
  final String destinationCode;
  final String destinationCity;
  final bool roundTrip;
  final DateTime? departureDate;
  final DateTime? returnDate;
  final int? passengers;
  final String? seatClass;

  const FlightSearchRouteArgs({
    required this.originCode,
    required this.originCity,
    required this.destinationCode,
    required this.destinationCity,
    this.roundTrip = false,
    this.departureDate,
    this.returnDate,
    this.passengers,
    this.seatClass,
  });
}

class FlightSearchScreen extends StatefulWidget {
  /// وجهة مبدئية تُملأ تلقائيًا (قادمة من باقة سياحية أو من آخر بحث).
  final String? initialDestinationCode;
  final String? initialDestinationCity;
  final String? initialOriginCode;
  final String? initialOriginCity;
  final DateTime? initialDepartureDate;
  final DateTime? initialReturnDate;
  final int? initialPassengers;
  final bool initialRoundTrip;
  final String? initialSeatClass;
  final bool autoSearch;
  const FlightSearchScreen({
    super.key,
    this.initialDestinationCode,
    this.initialDestinationCity,
    this.initialOriginCode,
    this.initialOriginCity,
    this.initialDepartureDate,
    this.initialReturnDate,
    this.initialPassengers,
    this.initialRoundTrip = false,
    this.initialSeatClass,
    this.autoSearch = false,
  });

  @override
  State<FlightSearchScreen> createState() => _FlightSearchScreenState();
}

class _FlightSearchScreenState extends State<FlightSearchScreen> {
  final _locationService = const CurrentLocationService();
  bool _isRoundTrip = false;
  int _passengers = 1;
  String _class = 'economy';
  String _fromCode = 'MRA', _fromCity = '';
  String _toCode = 'MJI', _toCity = '';
  bool _citiesInitialized = false;
  bool _autoSearchScheduled = false;
  bool _isLoadingOriginLocation = false;
  bool _originEdited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_citiesInitialized) {
      final l10n = AppLocalizations.of(context);
      _fromCode = widget.initialOriginCode ??
          AirportOption.byCity(widget.initialOriginCity ?? '')?.code ??
          _fromCode;
      _fromCity = widget.initialOriginCity ?? _cityForCode(_fromCode, l10n);
      _toCode = widget.initialDestinationCode ?? 'MJI';
      _toCity = widget.initialDestinationCity ?? _cityForCode(_toCode, l10n);
      if (widget.initialDestinationCode != null &&
          widget.initialDestinationCity == null) {
        _toCity = _cityForCode(widget.initialDestinationCode!, l10n);
      }
      _departure = widget.initialDepartureDate ?? _departure;
      _return = widget.initialReturnDate;
      _isRoundTrip = widget.initialRoundTrip;
      _class = widget.initialSeatClass ?? _class;
      _passengers = widget.initialPassengers ?? _passengers;
      _citiesInitialized = true;
      if (widget.initialOriginCode == null &&
          widget.initialOriginCity == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_loadCurrentAirport());
        });
      }
      if (widget.autoSearch && !_autoSearchScheduled) {
        _autoSearchScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _search();
        });
      }
    }
  }

  DateTime _departure = DateTime.now().add(const Duration(days: 7));
  DateTime? _return;
  FlexibleFlightSelection? _flexibleFlightSelection;

  Future<void> _loadCurrentAirport() async {
    setState(() => _isLoadingOriginLocation = true);
    try {
      final position = await _locationService.getPosition();
      final airport = AirportOption.nearestTo(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      if (airport == null) {
        return;
      }
      if (!_originEdited &&
          widget.initialOriginCode == null &&
          widget.initialOriginCity == null) {
        setState(() {
          _fromCode = airport.code;
          _fromCity = _cityForCode(
            airport.code,
            AppLocalizations.of(context),
          );
        });
      }
    } on CurrentLocationException catch (error) {
      debugPrint('Flight origin location unavailable: ${error.reason}');
    } finally {
      if (mounted) setState(() => _isLoadingOriginLocation = false);
    }
  }

  String _cityForCode(String code, AppLocalizations l10n) => switch (code) {
        'MJI' => l10n.cityTripoli,
        'MRA' => l10n.cityMisrata,
        'BEN' => l10n.cityBenghazi,
        'SEB' => l10n.citySebha,
        _ => AirportOption.byCode(code)?.city ?? code,
      };

  Future<void> _pickAirport({required bool isOrigin}) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showModalBottomSheet<AirportOption>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        var query = '';
        return SafeArea(
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              final airports = AirportOption.supported
                  .where((airport) => airport.matches(query))
                  .toList();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        l10n.selectAirportTitle,
                        style: Theme.of(sheetContext).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: TextField(
                      autofocus: false,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: l10n.partnerAirportSearch,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) => setSheetState(() => query = value),
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: airports.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final airport = airports[index];
                        final label =
                            '${_cityForCode(airport.code, l10n)} [${airport.code}]';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primarySurface,
                            child: Text(airport.code,
                                style: const TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800)),
                          ),
                          title: Text.rich(_highlightMatch(label, query)),
                          subtitle: Text.rich(_highlightMatch(
                            '${airport.airportName} · ${airport.country}',
                            query,
                          )),
                          onTap: () => Navigator.pop(sheetContext, airport),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (isOrigin) {
        _originEdited = true;
        _fromCode = selected.code;
        _fromCity = _cityForCode(selected.code, l10n);
      } else {
        _toCode = selected.code;
        _toCity = _cityForCode(selected.code, l10n);
      }
    });
  }

  TextSpan _highlightMatch(String value, String query) {
    final normalizedQuery = query.trim();
    final start = value.toLowerCase().indexOf(normalizedQuery.toLowerCase());
    if (start < 0 || normalizedQuery.isEmpty) return TextSpan(text: value);
    final end = start + normalizedQuery.length;
    return TextSpan(children: [
      TextSpan(text: value.substring(0, start)),
      TextSpan(
        text: value.substring(start, end),
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
      TextSpan(text: value.substring(end)),
    ]);
  }

  void _swap() {
    setState(() {
      _originEdited = true;
      final tC = _fromCode;
      final tCt = _fromCity;
      _fromCode = _toCode;
      _fromCity = _toCity;
      _toCode = tC;
      _toCity = tCt;
    });
  }

  Future<void> _search() async {
    final l10n = AppLocalizations.of(context);
    if (_fromCode == _toCode) {
      AppSnackbar.error(context, l10n.selectDifferentAirports);
      return;
    }
    final params = FlightSearchParams(
      originCode: _fromCode,
      originCity: _fromCity,
      destinationCode: _toCode,
      destinationCity: _toCity,
      departureDate: _departure,
      returnDate: _isRoundTrip ? _return : null,
      passengers: _passengers,
      seatClass: _class,
      isRoundTrip: _isRoundTrip,
      flexibleDepartureMonths:
          _flexibleFlightSelection?.departureMonths ?? const [],
      flexibleTripDurationDays: _flexibleFlightSelection?.tripDurationDays ?? 7,
      flexibleWeekendsOnly: _flexibleFlightSelection?.weekendsOnly ?? false,
    );
    unawaited(FlightSearchHistory.saveDestination(_toCode, _toCity));
    if (!mounted) return;
    Navigator.pushNamed(context, AppRoutes.flightResults, arguments: params);
  }

  void _setRoundTrip(bool roundTrip) {
    setState(() {
      _isRoundTrip = roundTrip;
      if (roundTrip && _flexibleFlightSelection != null) {
        _return = _departure.add(
          Duration(days: _flexibleFlightSelection!.tripDurationDays),
        );
      } else if (roundTrip && _return == null) {
        _return = _departure.add(const Duration(days: 7));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 60,
            title: Text(l10n.searchFlights),
            flexibleSpace: const FlexibleSpaceBar(
                background: DecoratedBox(
                    decoration:
                        BoxDecoration(gradient: AppColors.primaryGradient))),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Trip type ─────────────────────────────────────────
                Row(
                  children: [
                    _TripTypeChip(
                        label: l10n.oneWay,
                        selected: !_isRoundTrip,
                        onTap: () => _setRoundTrip(false)),
                    const SizedBox(width: 10),
                    _TripTypeChip(
                        label: l10n.roundTrip,
                        selected: _isRoundTrip,
                        onTap: () => _setRoundTrip(true)),
                  ],
                ).animate().fade(duration: 300.ms),
                const SizedBox(height: 20),

                // ── Route card ────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color:
                            isDark ? AppColors.darkBorder : AppColors.border),
                    boxShadow: isDark
                        ? []
                        : [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 16,
                                offset: const Offset(0, 6))
                          ],
                  ),
                  child: Column(
                    children: [
                      _AirportField(
                          code: _fromCode,
                          city: _fromCity,
                          label: l10n.from,
                          icon: Icons.flight_takeoff_rounded,
                          trailing: _isLoadingOriginLocation
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : null,
                          onTap: () => _pickAirport(isOrigin: true)),
                      Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 60,
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.divider),
                      Stack(
                        alignment: AlignmentDirectional.centerEnd,
                        children: [
                          _AirportField(
                              code: _toCode,
                              city: _toCity,
                              label: l10n.to,
                              icon: Icons.flight_land_rounded,
                              onTap: () => _pickAirport(isOrigin: false)),
                          Positioned(
                            right: 12,
                            child: GestureDetector(
                              onTap: _swap,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.swap_vert_rounded,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ).animate().fade(delay: 100.ms).slideY(begin: 0.05, end: 0),
                const SizedBox(height: 16),

                // ── Dates ─────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                        child: _DateField(
                            label: l10n.departureDate,
                            date: _departure,
                            icon: Icons.flight_takeoff_rounded,
                            l10n: l10n,
                            onTap: () async {
                              final d = await showDatePicker(
                                  context: context,
                                  initialDate: _departure,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 365)));
                              if (d != null) {
                                setState(() {
                                  _departure = d;
                                  _flexibleFlightSelection = null;
                                });
                              }
                            })),
                    if (_isRoundTrip) ...[
                      const SizedBox(width: 10),
                      Expanded(
                          child: _DateField(
                              label: l10n.returnDate,
                              date: _return,
                              icon: Icons.flight_land_rounded,
                              l10n: l10n,
                              onTap: () async {
                                final d = await showDatePicker(
                                    context: context,
                                    initialDate: _return ??
                                        _departure.add(const Duration(days: 7)),
                                    firstDate: _departure,
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 365)));
                                if (d != null) {
                                  setState(() {
                                    _return = d;
                                    _flexibleFlightSelection = null;
                                  });
                                }
                              })),
                    ],
                  ],
                ).animate().fade(delay: 180.ms),
                FlexibleFlightDatesButton(
                  selection: _flexibleFlightSelection,
                  onChanged: (selection) {
                    if (selection == null ||
                        selection.departureMonths.isEmpty) {
                      return;
                    }
                    final firstMonth = selection.departureMonths.reduce(
                      (a, b) => a.isBefore(b) ? a : b,
                    );
                    final now = DateTime.now();
                    final departureAnchor = firstMonth.year == now.year &&
                            firstMonth.month == now.month
                        ? DateTime(now.year, now.month, now.day)
                        : firstMonth;
                    setState(() {
                      _flexibleFlightSelection = selection;
                      _departure = departureAnchor;
                      if (_isRoundTrip) {
                        _return = departureAnchor.add(
                          Duration(days: selection.tripDurationDays),
                        );
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),

                // ── Passengers + Class ────────────────────────────────
                Row(
                  children: [
                    Expanded(
                        child: _PassengersField(
                            count: _passengers,
                            onChanged: (v) => setState(() => _passengers = v),
                            l10n: l10n)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _ClassSelector(
                            selected: _class,
                            onChanged: (v) => setState(() => _class = v),
                            l10n: l10n)),
                  ],
                ).animate().fade(delay: 240.ms),
                const SizedBox(height: 28),

                // ── Search button ─────────────────────────────────────
                ElevatedButton.icon(
                  onPressed: _search,
                  icon: const Icon(Icons.search_rounded),
                  label: Text(l10n.searchFlightsBtn),
                ).animate().fade(delay: 320.ms),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripTypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TripTypeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 14)),
      ),
    );
  }
}

class _AirportField extends StatelessWidget {
  final String code, city, label;
  final IconData icon;
  final Widget? trailing;
  final VoidCallback onTap;
  const _AirportField(
      {required this.code,
      required this.city,
      required this.label,
      required this.icon,
      this.trailing,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Row(children: [
                Text(code,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
                const SizedBox(width: 8),
                Text(city,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500)),
              ]),
            ]),
            if (trailing != null) ...[
              const Spacer(),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final IconData icon;
  final VoidCallback onTap;
  final AppLocalizations l10n;
  const _DateField(
      {required this.label,
      required this.date,
      required this.icon,
      required this.onTap,
      required this.l10n});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(icon, color: AppColors.primary, size: 16),
            const SizedBox(width: 6),
            Text(
              date != null
                  ? '${date!.day}/${date!.month}/${date!.year}'
                  : l10n.flightSelectDate,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: date != null ? null : AppColors.textHint),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _PassengersField extends StatelessWidget {
  final int count;
  final void Function(int) onChanged;
  final AppLocalizations l10n;
  const _PassengersField(
      {required this.count, required this.onChanged, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.flightPassengersLabel,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(children: [
          GestureDetector(
              onTap: count > 1 ? () => onChanged(count - 1) : null,
              child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.remove_rounded,
                      color: AppColors.primary, size: 16))),
          Expanded(
              child: Text(l10n.flightPersonCount(count),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          GestureDetector(
              onTap: count < 9 ? () => onChanged(count + 1) : null,
              child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.add_rounded,
                      color: AppColors.primary, size: 16))),
        ]),
      ]),
    );
  }
}

class _ClassSelector extends StatelessWidget {
  final String selected;
  final void Function(String) onChanged;
  final AppLocalizations l10n;
  const _ClassSelector(
      {required this.selected, required this.onChanged, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () async {
        final result = await showModalBottomSheet<String>(
          context: context,
          builder: (_) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              for (final c in [
                ('economy', l10n.economy),
                ('business', l10n.business),
                ('first', l10n.firstClass)
              ])
                ListTile(
                    title: Text(c.$2),
                    trailing: selected == c.$1
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.pop(context, c.$1)),
              const SizedBox(height: 16),
            ],
          ),
        );
        if (result != null) onChanged(result);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.flightClassLabel,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.airline_seat_recline_extra_rounded,
                color: AppColors.primary, size: 16),
            const SizedBox(width: 6),
            Text(
              switch (selected) {
                'business' => l10n.business,
                'first' => l10n.firstClass,
                _ => l10n.economy
              },
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            const Icon(Icons.expand_more_rounded,
                color: AppColors.textSecondary, size: 18),
          ]),
        ]),
      ),
    );
  }
}

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/current_location_service.dart';
import '../../../../global_widgets/booking_loading_overlay.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_model.dart';
import '../../../../models/hotel_destination_suggestion.dart';
import '../../../../routes/app_routes.dart';
import '../../logic/hotel_controller.dart';

/// مفتاح تخزين آخر مدينة تم البحث عنها، يُستخدم من شاشة SearchHotelsScreen
/// (لعرض اقتراح "كرر آخر بحث") ومن هذه الشاشة نفسها.
class HotelSearchHistory {
  static const _cityKey = 'last_hotel_city';

  static Future<String?> lastCity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cityKey);
  }

  static Future<void> saveCity(String city) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cityKey, city);
  }
}

class HotelSearchScreen extends StatefulWidget {
  /// مدينة مبدئية تُملأ تلقائيًا (قادمة من باقة سياحية أو من آخر بحث).
  final String? initialCity;
  final DateTime? initialCheckIn;
  final DateTime? initialCheckOut;
  final int? initialGuests;
  final CurrentLocationService locationService;
  final HotelController? controller;
  const HotelSearchScreen({
    super.key,
    this.initialCity,
    this.initialCheckIn,
    this.initialCheckOut,
    this.initialGuests,
    this.locationService = const CurrentLocationService(),
    this.controller,
  });

  @override
  State<HotelSearchScreen> createState() => _HotelSearchScreenState();
}

class _HotelSearchScreenState extends State<HotelSearchScreen> {
  late final HotelController _ctrl;
  bool _ownsController = false;
  final _cityCtrl = TextEditingController();
  final _destinationFocusNode = FocusNode();
  HotelDestinationSuggestion? _selectedDestination;
  bool _destinationError = false;
  bool _cityInitialized = false;
  bool _isLoadingNearby = false;
  String? _locationMessage;
  CurrentLocationError? _locationError;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? HotelController();
    _ownsController = widget.controller == null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_cityInitialized) {
      final initialCity = widget.initialCity?.trim();
      if (initialCity != null && initialCity.isNotEmpty) {
        _cityCtrl.text = initialCity;
      }
      final today = _dateOnly(DateTime.now());
      final lastBookableDate = today.add(const Duration(days: 330));
      _checkIn = _dateOnly(widget.initialCheckIn ?? _checkIn);
      _checkOut = _dateOnly(widget.initialCheckOut ?? _checkOut);
      if (_checkIn.isBefore(today)) _checkIn = today;
      if (!_checkIn.isBefore(lastBookableDate)) {
        _checkIn = lastBookableDate.subtract(const Duration(days: 1));
      }
      if (_checkOut.isAfter(lastBookableDate)) {
        _checkOut = lastBookableDate;
      }
      if (!_checkOut.isAfter(_checkIn)) {
        _checkOut = _checkIn.add(const Duration(days: 1));
      }
      _guests = (widget.initialGuests ?? _guests).clamp(_rooms, 20).toInt();
      _cityInitialized = true;
    }
  }

  DateTime _checkIn = DateTime.now().add(const Duration(days: 7));
  DateTime _checkOut = DateTime.now().add(const Duration(days: 10));
  int _rooms = 1;
  int _guests = 2;
  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  int get _nightCount =>
      DateTime.utc(_checkOut.year, _checkOut.month, _checkOut.day)
          .difference(DateTime.utc(_checkIn.year, _checkIn.month, _checkIn.day))
          .inDays
          .clamp(1, 99)
          .toInt();

  void _onDestinationChanged(String value) {
    _selectedDestination = null;
    _destinationError = false;
    _ctrl.updateDestinationQuery(
      value,
      languageCode: Localizations.localeOf(context).languageCode,
    );
    if (_locationMessage != null || _locationError != null) {
      setState(() {
        _locationMessage = null;
        _locationError = null;
      });
    } else {
      setState(() {});
    }
  }

  void _selectDestination(HotelDestinationSuggestion suggestion) {
    final language = Localizations.localeOf(context).languageCode;
    setState(() {
      _selectedDestination = suggestion;
      _cityCtrl.text = suggestion.displayName(language);
      _destinationError = false;
      _locationMessage = null;
      _locationError = null;
    });
    _ctrl.clearDestinationSuggestions();
    _destinationFocusNode.unfocus();
  }

  Future<void> _selectFirstDestination() async {
    if (_selectedDestination != null) return;
    await _ctrl.loadDestinationSuggestionsNow(
      _cityCtrl.text,
      languageCode: Localizations.localeOf(context).languageCode,
    );
    if (!mounted || _ctrl.destinationSuggestions.isEmpty) return;
    _selectDestination(_ctrl.destinationSuggestions.first);
  }

  Future<void> _search() async {
    if (_selectedDestination == null) {
      await _selectFirstDestination();
    }
    if (!mounted) return;
    final selected = _selectedDestination;
    if (selected == null) {
      setState(() => _destinationError = true);
      return;
    }
    final language = Localizations.localeOf(context).languageCode;
    final visibleCity = selected.displayName(language);
    final city = selected.name;
    if (_checkOut.isBefore(_checkIn.add(const Duration(days: 1)))) {
      setState(() => _checkOut = _checkIn.add(const Duration(days: 1)));
    }
    final params = HotelSearchParams(
      city: city,
      destinationCode: selected.destinationCode,
      latitude: selected.latitude,
      longitude: selected.longitude,
      checkIn: _checkIn,
      checkOut: _checkOut,
      rooms: _rooms,
      guests: _guests,
    );
    setState(() {
      _destinationError = false;
      _locationMessage = null;
      _locationError = null;
    });
    await BookingLoadingOverlay.run<void>(
      context,
      title: AppLocalizations.of(context).hotelSearching,
      subtitle: visibleCity,
      serviceIcon: Icons.hotel_rounded,
      action: () => _ctrl.search(params),
    );
    unawaited(HotelSearchHistory.saveCity(visibleCity));
    if (!mounted) return;
    Navigator.pushNamed(context, AppRoutes.hotelResults, arguments: _ctrl);
  }

  Future<void> _searchNearby() async {
    setState(() {
      _isLoadingNearby = true;
      _locationMessage = null;
      _locationError = null;
      _destinationError = false;
    });
    try {
      late final CurrentPlace place;
      try {
        place = await widget.locationService.getCurrentPlace();
      } on CurrentLocationException catch (error) {
        if (mounted) {
          setState(() {
            _locationMessage = _locationErrorMessage(
              error.reason,
              AppLocalizations.of(context),
            );
            _locationError = error.reason;
          });
        }
        return;
      }
      final position = place.position;
      final nearestAirport = AirportOption.nearestTo(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      final city = AirportOption.byCity(place.city ?? '')?.city ??
          nearestAirport?.city ??
          place.city ??
          AppLocalizations.of(context).hotelNearbyTitle;
      final detected = HotelDestinationSuggestion(
        name: city,
        localizedName: place.city,
        countryName: place.country,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _selectDestination(detected);
      final params = HotelSearchParams(
        city: city,
        checkIn: _checkIn,
        checkOut: _checkOut,
        rooms: _rooms,
        guests: _guests,
      );
      await BookingLoadingOverlay.run<void>(
        context,
        title: AppLocalizations.of(context).hotelSearching,
        subtitle: city,
        serviceIcon: Icons.hotel_rounded,
        action: () async {
          await _ctrl.searchNearby(
            params,
            latitude: position.latitude,
            longitude: position.longitude,
          );
        },
      );
      if (!mounted) return;
      Navigator.pushNamed(context, AppRoutes.hotelResults, arguments: _ctrl);
    } finally {
      if (mounted) setState(() => _isLoadingNearby = false);
    }
  }

  String _locationErrorMessage(
    CurrentLocationError error,
    AppLocalizations l10n,
  ) =>
      switch (error) {
        CurrentLocationError.serviceDisabled =>
          l10n.nearbyLocationServiceDisabled,
        CurrentLocationError.permissionDenied =>
          l10n.nearbyLocationPermissionDenied,
        CurrentLocationError.permissionDeniedForever =>
          l10n.nearbyLocationPermissionDeniedForever,
        CurrentLocationError.unableToDetermine =>
          l10n.nearbyLocationUnableToDetermine,
      };

  Future<void> _openLocationSettings() async {
    final reason = _locationError;
    try {
      if (reason == CurrentLocationError.serviceDisabled) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {
      // Keep the inline permission message visible if the settings app cannot open.
    }
  }

  Future<void> _pickDateRange() async {
    final today = _dateOnly(DateTime.now());
    final lastDate = today.add(const Duration(days: 330));
    final latestStart = lastDate.subtract(const Duration(days: 1));
    final initialStart = _checkIn.isBefore(today)
        ? today
        : _checkIn.isAfter(latestStart)
            ? latestStart
            : _checkIn;
    final requestedEnd = _checkOut.isAfter(initialStart)
        ? _checkOut
        : initialStart.add(const Duration(days: 1));
    final initialEnd = requestedEnd.isAfter(lastDate) ? lastDate : requestedEnd;
    final range = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: lastDate,
      initialDateRange: DateTimeRange(
        start: initialStart,
        end: initialEnd,
      ),
    );
    if (range == null || !mounted) return;
    setState(() {
      _checkIn = _dateOnly(range.start);
      _checkOut = _dateOnly(range.end);
      if (!_checkOut.isAfter(_checkIn)) {
        _checkOut = _checkIn.add(const Duration(days: 1));
      }
    });
  }

  TextSpan _highlightSuggestion(String value) {
    final query = _cityCtrl.text.trim();
    final start = value.toLowerCase().indexOf(query.toLowerCase());
    if (query.isEmpty || start < 0) return TextSpan(text: value);
    final end = start + query.length;
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

  @override
  void dispose() {
    if (_ownsController) _ctrl.dispose();
    _cityCtrl.dispose();
    _destinationFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
          title: Text(l10n.searchHotels),
          flexibleSpace: const DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.primaryGradient))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Destination ──────────────────────────────────────────────
          _Label(l10n.destination),
          const SizedBox(height: 8),
          _InputBox(
            isDark: isDark,
            child: TextField(
              controller: _cityCtrl,
              focusNode: _destinationFocusNode,
              textInputAction: TextInputAction.search,
              onChanged: _onDestinationChanged,
              onSubmitted: (_) => _selectFirstDestination(),
              decoration: InputDecoration(
                hintText: l10n.hotelDestinationHint,
                prefixIcon:
                    const Icon(Icons.search_rounded, color: AppColors.primary),
                suffixIcon: _isLoadingNearby
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: l10n.useCurrentLocation,
                        onPressed: _searchNearby,
                        icon: const Icon(Icons.my_location_rounded),
                      ),
                border: InputBorder.none,
                filled: false,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ).animate().fade(duration: 300.ms),
          ListenableBuilder(
            listenable: _ctrl,
            builder: (context, _) {
              final query = _cityCtrl.text.trim();
              if (query.length < 2 || _selectedDestination != null) {
                return const SizedBox.shrink();
              }
              Widget? content;
              if (_ctrl.isLoadingDestinationSuggestions) {
                content = ListTile(
                  dense: true,
                  leading: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text(l10n.hotelLoadingDestinations),
                );
              } else if (_ctrl.hasDestinationSuggestionError) {
                content = ListTile(
                  dense: true,
                  leading: const Icon(Icons.error_outline_rounded),
                  title: Text(l10n.hotelDestinationSuggestionsError),
                );
              } else if (_ctrl.destinationSuggestions.isEmpty) {
                content = ListTile(
                  dense: true,
                  leading: const Icon(Icons.search_off_rounded),
                  title: Text(l10n.hotelNoDestinationSuggestions),
                );
              } else {
                content = ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: _ctrl.destinationSuggestions.map((suggestion) {
                      final displayName = suggestion.displayName(
                        Localizations.localeOf(context).languageCode,
                      );
                      final country = suggestion.displayCountry(
                        Localizations.localeOf(context).languageCode,
                      );
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text.rich(_highlightSuggestion(displayName)),
                        subtitle: country.isEmpty ? null : Text(country),
                        onTap: () => _selectDestination(suggestion),
                      );
                    }).toList(growable: false),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Material(
                  elevation: 5,
                  borderRadius: BorderRadius.circular(12),
                  child: content,
                ),
              );
            },
          ),
          if (_destinationError)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 12, top: 6),
              child: Text(
                l10n.hotelSelectDestination,
                style:
                    const TextStyle(color: AppColors.accentRed, fontSize: 12),
              ),
            ),
          if (_locationMessage != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 12, top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _locationMessage!,
                      style: const TextStyle(
                          color: AppColors.accentRed, fontSize: 12),
                    ),
                  ),
                  if (_locationError != null)
                    TextButton.icon(
                      onPressed: _openLocationSettings,
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      label: Text(l10n.openLocationSettings),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // ── Dates ─────────────────────────────────────────────────────
          Row(children: [
            Expanded(
                child: _DatePick(
                    label: l10n.checkIn,
                    date: _checkIn,
                    icon: Icons.login_rounded,
                    isDark: isDark,
                    onTap: _pickDateRange)),
            const SizedBox(width: 12),
            Expanded(
                child: _DatePick(
                    label: l10n.checkOut,
                    date: _checkOut,
                    icon: Icons.logout_rounded,
                    isDark: isDark,
                    onTap: _pickDateRange)),
          ]).animate().fade(delay: 100.ms),
          const SizedBox(height: 16),

          // ── Rooms + Guests ────────────────────────────────────────────
          Row(children: [
            Expanded(
                child: _Stepper(
                    label: l10n.hotelRoomsLabel,
                    icon: Icons.hotel_rounded,
                    value: _rooms,
                    isDark: isDark,
                    min: 1,
                    max: 10,
                    onChanged: (v) => setState(() {
                          _rooms = v;
                          if (_guests < v) _guests = v;
                        }))),
            const SizedBox(width: 12),
            Expanded(
                child: _Stepper(
                    label: l10n.hotelGuestsLabel,
                    icon: Icons.people_rounded,
                    value: _guests,
                    isDark: isDark,
                    min: _rooms,
                    max: 20,
                    onChanged: (v) => setState(() => _guests = v))),
          ]).animate().fade(delay: 180.ms),

          // ── Summary ───────────────────────────────────────────────────
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.nights_stay_rounded,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 10),
              Text(
                  '${l10n.hotelNightsSummary(_nightCount)} · '
                  '${l10n.hotelRoomsSummary(_rooms)} · '
                  '${l10n.hotelGuestsSummary(_guests)}',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ]),
          ).animate().fade(delay: 240.ms),
          const SizedBox(height: 28),

          // ── Search ─────────────────────────────────────────────────────
          ListenableBuilder(
            listenable: _ctrl,
            builder: (_, __) => Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _ctrl.isLoading || _isLoadingNearby ? null : _search,
                    icon: _ctrl.isLoading && !_isLoadingNearby
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.search_rounded),
                    label: Text(_ctrl.isLoading && !_isLoadingNearby
                        ? l10n.hotelSearching
                        : l10n.searchHotelsBtn),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _ctrl.isLoading || _isLoadingNearby
                        ? null
                        : _searchNearby,
                    icon: _isLoadingNearby
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.near_me_outlined),
                    label: Text(l10n.hotelSearchNearby),
                  ),
                ),
              ],
            ),
          ).animate().fade(delay: 300.ms),
        ]),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: AppColors.textSecondary));
}

class _InputBox extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const _InputBox({required this.child, required this.isDark});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border)),
        child: child,
      );
}

class _DatePick extends StatelessWidget {
  final String label;
  final DateTime date;
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  const _DatePick(
      {required this.label,
      required this.date,
      required this.icon,
      required this.isDark,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Row(children: [
            Icon(icon, color: AppColors.primary, size: 16),
            const SizedBox(width: 6),
            Text('${date.day}/${date.month}/${date.year}',
                style: const TextStyle(fontWeight: FontWeight.w700))
          ]),
        ]),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final IconData icon;
  final int value, min, max;
  final bool isDark;
  final void Function(int) onChanged;
  const _Stepper(
      {required this.label,
      required this.icon,
      required this.value,
      required this.isDark,
      required this.min,
      required this.max,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: AppColors.primary, size: 14),
          const SizedBox(width: 5),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary))
        ]),
        const SizedBox(height: 8),
        Row(children: [
          GestureDetector(
              onTap: value > min ? () => onChanged(value - 1) : null,
              child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.remove_rounded,
                      color: AppColors.primary, size: 16))),
          Expanded(
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 18))),
          GestureDetector(
              onTap: value < max ? () => onChanged(value + 1) : null,
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

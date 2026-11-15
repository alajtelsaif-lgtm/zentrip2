import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/current_location_service.dart';
import '../../../../global_widgets/app_network_image.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../global_widgets/booking_loading_overlay.dart';
import '../../../../global_widgets/currency_amount_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_model.dart';
import '../../../../models/car_model.dart';
import '../../../../routes/app_routes.dart';
import '../../logic/car_controller.dart';
import '../car_labels.dart';

class CarRentalScreen extends StatefulWidget {
  final String? initialCity;
  final CurrentLocationService locationService;

  const CarRentalScreen({
    super.key,
    this.initialCity,
    this.locationService = const CurrentLocationService(),
  });

  @override
  State<CarRentalScreen> createState() => _CarRentalScreenState();
}

class _CarRentalScreenState extends State<CarRentalScreen> {
  final _ctrl = CarController();
  final _cityCtrl = TextEditingController();
  DateTime _pickup = DateTime.now().add(const Duration(days: 7));
  DateTime _return = DateTime.now().add(const Duration(days: 10));
  String _type = 'all';
  bool _searched = false;
  bool _isLoadingLocation = false;
  bool _isLoadingNearby = false;
  String? _locationMessage;
  TextEditingController? _autocompleteController;

  @override
  void initState() {
    super.initState();
    final initialCity = widget.initialCity?.trim();
    if (initialCity != null && initialCity.isNotEmpty) {
      _cityCtrl.text = initialCity;
    }
  }

  Future<void> _loadCurrentCity({bool overrideExisting = false}) async {
    if (mounted) {
      setState(() {
        _isLoadingLocation = true;
        _locationMessage = null;
      });
    }

    try {
      final place = await widget.locationService.getCurrentPlace();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final airport = AirportOption.nearestTo(
        place.position.latitude,
        place.position.longitude,
      );
      final city = AirportOption.byCity(place.city ?? '')?.city ??
          airport?.city ??
          place.city;
      if ((overrideExisting || _cityCtrl.text.trim().isEmpty) && city != null) {
        _cityCtrl.text = city;
        _autocompleteController?.text = city;
      }
      setState(() {
        _isLoadingLocation = false;
        _locationMessage = city == null ? l10n.currentCityUnavailable : null;
      });
    } on CurrentLocationException catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _isLoadingLocation = false;
        _locationMessage = _locationErrorMessage(error.reason, l10n);
      });
    } finally {
      if (mounted && _isLoadingLocation) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

  String _locationErrorMessage(
      CurrentLocationError error, AppLocalizations l10n) {
    switch (error) {
      case CurrentLocationError.serviceDisabled:
        return l10n.nearbyLocationServiceDisabled;
      case CurrentLocationError.permissionDenied:
        return l10n.nearbyLocationPermissionDenied;
      case CurrentLocationError.permissionDeniedForever:
        return l10n.nearbyLocationPermissionDeniedForever;
      case CurrentLocationError.unableToDetermine:
        return l10n.nearbyLocationUnableToDetermine;
    }
  }

  Future<void> _search() async {
    final city = _cityCtrl.text.trim();
    if (city.isEmpty) {
      AppSnackbar.error(
        context,
        _locationMessage ??
            AppLocalizations.of(context).carPickupLocationRequired,
      );
      return;
    }
    final params = CarSearchParams(
        city: city, pickupDate: _pickup, returnDate: _return, carType: _type);
    await BookingLoadingOverlay.run<void>(
      context,
      title: AppLocalizations.of(context).carRentalTitle,
      subtitle: city,
      serviceIcon: Icons.directions_car_rounded,
      action: () => _ctrl.search(params),
    );
    if (mounted) setState(() => _searched = true);
  }

  Future<void> _searchNearby() async {
    setState(() {
      _isLoadingNearby = true;
      _locationMessage = null;
    });
    try {
      late final Position position;
      try {
        position = await widget.locationService.getPosition();
      } on CurrentLocationException catch (error) {
        if (mounted) {
          setState(() => _locationMessage = _locationErrorMessage(
                error.reason,
                AppLocalizations.of(context),
              ));
        }
        return;
      }
      final nearestAirport = AirportOption.nearestTo(
        position.latitude,
        position.longitude,
      );
      if (nearestAirport == null) {
        if (mounted) {
          setState(() => _locationMessage =
              AppLocalizations.of(context).nearbyLocationUnableToDetermine);
        }
        return;
      }
      if (!mounted) return;
      final params = CarSearchParams(
        city: _cityCtrl.text.trim().isEmpty
            ? nearestAirport.city
            : _cityCtrl.text.trim(),
        pickupDate: _pickup,
        returnDate: _return,
        carType: _type,
      );
      await BookingLoadingOverlay.run<void>(
        context,
        title: AppLocalizations.of(context).carRentalTitle,
        subtitle: params.city,
        serviceIcon: Icons.directions_car_rounded,
        action: () async {
          await _ctrl.searchNearby(
            params,
            latitude: position.latitude,
            longitude: position.longitude,
          );
        },
      );
      if (!mounted) return;
      setState(() => _searched = true);
    } finally {
      if (mounted) setState(() => _isLoadingNearby = false);
    }
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
    _ctrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.carRentalTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Search form ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.border)),
            child: Column(children: [
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _cityCtrl.text),
                optionsBuilder: (value) =>
                    ApiService.instance.searchCarLocations(value.text),
                onSelected: (selection) {
                  _cityCtrl.text = selection;
                  if (_locationMessage != null) {
                    setState(() => _locationMessage = null);
                  }
                },
                optionsViewBuilder: (context, onSelected, options) => Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Material(
                    elevation: 5,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: options
                            .map((option) => ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.place_outlined),
                                  title:
                                      Text.rich(_highlightSuggestion(option)),
                                  onTap: () => onSelected(option),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                ),
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  _autocompleteController = controller;
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: (value) {
                      _cityCtrl.text = value;
                      if (_locationMessage != null) {
                        setState(() => _locationMessage = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: l10n.carPickupCityHint,
                      prefixIcon: const Icon(Icons.place_rounded,
                          color: AppColors.primary),
                      suffixIcon: _isLoadingLocation
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              tooltip: l10n.useCurrentLocation,
                              onPressed: () =>
                                  _loadCurrentCity(overrideExisting: true),
                              icon: const Icon(Icons.my_location_rounded),
                            ),
                      border: InputBorder.none,
                      filled: false,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  );
                },
              ),
              if (_locationMessage != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12, top: 4),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _locationMessage!,
                      style: const TextStyle(
                          color: AppColors.accentRed, fontSize: 12),
                    ),
                  ),
                ),
              Divider(
                  height: 1,
                  color: isDark ? AppColors.darkBorder : AppColors.divider),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _DateTile(
                        label: l10n.carPickup,
                        date: _pickup,
                        isDark: isDark,
                        onTap: () async {
                          final d = await showDatePicker(
                              context: context,
                              initialDate: _pickup,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365)));
                          if (d != null) setState(() => _pickup = d);
                        })),
                const SizedBox(width: 10),
                Expanded(
                    child: _DateTile(
                        label: l10n.carDropoff,
                        date: _return,
                        isDark: isDark,
                        onTap: () async {
                          final d = await showDatePicker(
                              context: context,
                              initialDate: _return,
                              firstDate: _pickup.add(const Duration(days: 1)),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365)));
                          if (d != null) setState(() => _return = d);
                        })),
              ]),
            ]),
          ).animate().fade(duration: 300.ms),
          const SizedBox(height: 16),
          // ── Car type ─────────────────────────────────────────────────
          Text(l10n.carType,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (t, l) in [
                ('all', l10n.carTypeAll),
                ('economy', l10n.economy),
                ('suv', l10n.suv),
                ('luxury', l10n.luxury),
                ('electric', l10n.carTypeElectric),
                ('van', l10n.van)
              ])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _type = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                          color: _type == t
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: _type == t
                                  ? AppColors.primary
                                  : AppColors.border)),
                      child: Text(l,
                          style: TextStyle(
                              color: _type == t
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontWeight: _type == t
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 13)),
                    ),
                  ),
                ),
            ]),
          ).animate().fade(delay: 100.ms),
          const SizedBox(height: 20),
          ListenableBuilder(
            listenable: _ctrl,
            builder: (_, __) => ElevatedButton.icon(
              onPressed: _ctrl.isLoading ? null : _search,
              icon: _ctrl.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search_rounded),
              label: Text(
                  _ctrl.isLoading ? l10n.carSearching : l10n.carSearchButton),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ).animate().fade(delay: 180.ms),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed:
                _isLoadingNearby || _ctrl.isLoading ? null : _searchNearby,
            icon: _isLoadingNearby
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.near_me_rounded),
            label: Text(l10n.hotelSearchNearby),
          ),

          // ── Results ───────────────────────────────────────────────────
          if (_searched) ...[
            const SizedBox(height: 28),
            Text(l10n.carResults,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            ListenableBuilder(
              listenable: _ctrl,
              builder: (_, __) {
                if (_ctrl.results.isEmpty) {
                  return Center(child: Text(l10n.carNoResults));
                }
                return Column(
                  children: _ctrl.results
                      .asMap()
                      .entries
                      .map((e) => _CarCard(
                            car: e.value,
                            days: _ctrl.searchParams?.days ?? 1,
                            isDark: isDark,
                            onTap: () {
                              _ctrl.selectCar(e.value);
                              Navigator.pushNamed(context, AppRoutes.carDetail,
                                  arguments: _ctrl);
                            },
                          )
                              .animate(
                                  delay: Duration(milliseconds: 80 * e.key))
                              .fade()
                              .slideY(begin: 0.05, end: 0))
                      .toList(),
                );
              },
            ),
          ],
        ]),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final bool isDark;
  final VoidCallback onTap;
  const _DateTile(
      {required this.label,
      required this.date,
      required this.isDark,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.primary)),
          const SizedBox(height: 4),
          Text('${date.day}/${date.month}/${date.year}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.primary)),
        ]),
      ),
    );
  }
}

class _CarCard extends StatelessWidget {
  final CarModel car;
  final int days;
  final bool isDark;
  final VoidCallback onTap;
  const _CarCard(
      {required this.car,
      required this.days,
      required this.isDark,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gradient = AppColors.destinationGradients[
        car.id.hashCode.abs() % AppColors.destinationGradients.length];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Photo ──
          AspectRatio(
            aspectRatio: 16 / 8.5,
            child: Stack(fit: StackFit.expand, children: [
              AppNetworkImage(
                  url: car.imageUrl,
                  fallbackIcon: Icons.directions_car_rounded,
                  fallbackGradient: gradient),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(_categoryLabel(l10n, car.category),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_rounded,
                        color: Colors.amber, size: 13),
                    const SizedBox(width: 3),
                    Text(car.rating.toStringAsFixed(1),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(car.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 10, runSpacing: 4, children: [
                        _Spec(Icons.people_rounded,
                            l10n.carSeatsCount(car.seats)),
                        _Spec(
                            Icons.luggage_rounded, l10n.carBagsCount(car.bags)),
                        _Spec(
                            Icons.settings_rounded,
                            car.transmission == 'automatic'
                                ? l10n.carTransmissionAutoShort
                                : l10n.carTransmissionManualShort),
                        _Spec(
                            car.fuelType == 'electric'
                                ? Icons.bolt_rounded
                                : Icons.local_gas_station_rounded,
                            carFuelLabel(l10n, car.fuelType)),
                      ]),
                    ]),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                CurrencyAmountText(
                    amount: car.totalPriceForDays(days),
                    decimalDigits: 0,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: AppColors.primary)),
                CurrencyAmountText(
                    amount: car.pricePerDay,
                    decimalDigits: 0,
                    suffix: ' ${l10n.carPerDaySuffix}',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textSecondary)),
                Text(l10n.carDaysCount(days),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
                if (car.availableVehicles < 1)
                  Text(l10n.carSoldOut,
                      style: const TextStyle(
                          color: AppColors.accentRed,
                          fontWeight: FontWeight.w700,
                          fontSize: 11)),
                const SizedBox(height: 6),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(l10n.book,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12))),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  String _categoryLabel(AppLocalizations l10n, String c) => switch (c) {
        'economy' => l10n.economy,
        'suv' => l10n.suv,
        'luxury' => l10n.luxury,
        'electric' => l10n.carTypeElectric,
        'van' => l10n.van,
        _ => c,
      };
}

class _Spec extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Spec(this.icon, this.label);
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: AppColors.textSecondary),
        const SizedBox(width: 3),
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary))
      ]);
}

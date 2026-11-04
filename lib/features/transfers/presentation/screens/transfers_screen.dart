import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/current_location_service.dart';
import '../../../../global_widgets/app_network_image.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../global_widgets/booking_loading_overlay.dart';
import '../../../../global_widgets/booking_confirmation_screen.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/transfer_model.dart';
import '../../logic/transfers_controller.dart';
import '../../../../core/services/api_service.dart';
import '../../../../global_widgets/payment_checkout_screen.dart';

class TransferSearchRouteArgs {
  final String initialFromLocation;
  final String initialToLocation;

  const TransferSearchRouteArgs({
    required this.initialFromLocation,
    required this.initialToLocation,
  });
}

class TransfersScreen extends StatefulWidget {
  final String? initialFromLocation;
  final String? initialToLocation;

  const TransfersScreen({
    super.key,
    this.initialFromLocation,
    this.initialToLocation,
  });

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  final _ctrl = TransferController();
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  DateTime _pickupDateTime = DateTime.now().add(const Duration(days: 3));
  int _passengers = 1;
  bool _isBooking = false;
  bool _hasSearched = false;
  LatLng? _pickupPoint;
  LatLng? _dropoffPoint;

  @override
  void initState() {
    super.initState();
    _fromCtrl.text = widget.initialFromLocation ?? '';
    _toCtrl.text = widget.initialToLocation ?? '';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();
    if (from.isEmpty || to.isEmpty) {
      AppSnackbar.error(
          context, AppLocalizations.of(context).transferLocationRequired);
      return;
    }
    _ctrl.fromLocation = from;
    _ctrl.toLocation = to;
    _ctrl.date = _pickupDateTime;
    _ctrl.passengers = _passengers;
    await BookingLoadingOverlay.run<void>(
      context,
      title: AppLocalizations.of(context).quickActionTransfers,
      subtitle: '$from  →  $to',
      serviceIcon: Icons.local_taxi_rounded,
      action: _ctrl.search,
    );
    if (mounted) setState(() => _hasSearched = true);
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _pickupDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _pickupDateTime = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _pickupDateTime.hour,
        _pickupDateTime.minute,
      );
      _hasSearched = false;
    });
  }

  Future<void> _selectTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_pickupDateTime),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _pickupDateTime = DateTime(
        _pickupDateTime.year,
        _pickupDateTime.month,
        _pickupDateTime.day,
        selected.hour,
        selected.minute,
      );
      _hasSearched = false;
    });
  }

  void _swapLocations() {
    final pickup = _fromCtrl.text;
    _fromCtrl.text = _toCtrl.text;
    _toCtrl.text = pickup;
    final pickupPoint = _pickupPoint;
    _pickupPoint = _dropoffPoint;
    _dropoffPoint = pickupPoint;
    setState(() => _hasSearched = false);
  }

  Future<void> _chooseMapLocation({required bool pickup}) async {
    final l10n = AppLocalizations.of(context);
    final point = await showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _TaxiMapPointPicker(
        title:
            pickup ? l10n.taxiSelectPickupOnMap : l10n.taxiSelectDropoffOnMap,
        initialPoint: pickup ? _pickupPoint : _dropoffPoint,
        confirmLabel: l10n.taxiConfirmMapPoint,
        serviceDisabledMessage: l10n.taxiLocationServiceDisabled,
        permissionDeniedMessage: l10n.taxiLocationPermissionDenied,
        permissionDeniedForeverMessage:
            l10n.taxiLocationPermissionDeniedForever,
        locationUnavailableMessage: l10n.taxiLocationUnavailable,
        retryLabel: l10n.retry,
        settingsLabel: l10n.openSettings,
        useCurrentLocationLabel: l10n.taxiUseCurrentLocation,
      ),
    );
    if (point == null || !mounted) return;

    setState(() {
      if (pickup) {
        _pickupPoint = point;
      } else {
        _dropoffPoint = point;
      }
      _hasSearched = false;
    });

    try {
      final placemarks = await Geocoding()
          .placemarkFromCoordinates(point.latitude, point.longitude);
      if (!mounted) return;
      final place = placemarks.isEmpty ? null : placemarks.first;
      final address = [
        place?.name,
        place?.street,
        place?.locality,
        place?.administrativeArea,
      ]
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toSet()
          .join(', ');
      final location = address.isNotEmpty
          ? address
          : '${point.latitude.toStringAsFixed(6)}, '
              '${point.longitude.toStringAsFixed(6)}';
      setState(() {
        (pickup ? _fromCtrl : _toCtrl).text = location;
      });
    } catch (_) {
      if (!mounted) return;
      (pickup ? _fromCtrl : _toCtrl).text =
          '${point.latitude.toStringAsFixed(6)}, '
          '${point.longitude.toStringAsFixed(6)}';
      AppSnackbar.error(context, l10n.taxiMapAddressLookupFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
          title: Text(l10n.transferBookingTitle),
          flexibleSpace: Container(
              decoration:
                  const BoxDecoration(gradient: AppColors.primaryGradient))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                l10n.transferRouteTitle,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                l10n.transferSubtitle,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color:
                            isDark ? AppColors.darkBorder : AppColors.border)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LocationField(
                          controller: _fromCtrl,
                          label: l10n.transferPickupLabel,
                          hint: l10n.transferFromHint,
                          icon: Icons.radio_button_checked_rounded,
                          color: AppColors.accentGreen,
                          isDark: isDark,
                          mapTooltip: l10n.taxiSelectPickupOnMap,
                          onMapTap: () => _chooseMapLocation(pickup: true),
                          onChanged: () {
                            _pickupPoint = null;
                            setState(() => _hasSearched = false);
                          }),
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 25),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 1,
                                color: isDark
                                    ? AppColors.darkBorder
                                    : AppColors.border,
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.swapLocations,
                              onPressed: _swapLocations,
                              icon: const Icon(Icons.swap_vert_rounded,
                                  color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                      _LocationField(
                          controller: _toCtrl,
                          label: l10n.transferDropoffLabel,
                          hint: l10n.transferToHint,
                          icon: Icons.location_on_rounded,
                          color: AppColors.accentRed,
                          isDark: isDark,
                          mapTooltip: l10n.taxiSelectDropoffOnMap,
                          onMapTap: () => _chooseMapLocation(pickup: false),
                          onChanged: () {
                            _dropoffPoint = null;
                            setState(() => _hasSearched = false);
                          }),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final dateTime = _DateTimeField(
                            date: MaterialLocalizations.of(context)
                                .formatMediumDate(_pickupDateTime),
                            time: MaterialLocalizations.of(context)
                                .formatTimeOfDay(
                              TimeOfDay.fromDateTime(_pickupDateTime),
                            ),
                            dateLabel: l10n.transferChooseDate,
                            timeLabel: l10n.transferChooseTime,
                            onDateTap: _selectDate,
                            onTimeTap: _selectTime,
                          );
                          if (constraints.maxWidth < 420) {
                            return Column(
                              children: [
                                dateTime.dateButton,
                                const SizedBox(height: 10),
                                dateTime.timeButton,
                                const SizedBox(height: 14),
                                _PassengerSelector(
                                  passengers: _passengers,
                                  label: l10n.transferPassengers,
                                  onChanged: (value) => setState(() {
                                    _passengers = value;
                                    _hasSearched = false;
                                  }),
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: dateTime.dateButton),
                              const SizedBox(width: 10),
                              Expanded(child: dateTime.timeButton),
                              const SizedBox(width: 10),
                              _PassengerSelector(
                                passengers: _passengers,
                                label: l10n.transferPassengers,
                                onChanged: (value) => setState(() {
                                  _passengers = value;
                                  _hasSearched = false;
                                }),
                              ),
                            ],
                          );
                        },
                      ),
                    ]),
              ).animate().fade(duration: 300.ms),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ListenableBuilder(
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
                    label: Text(_ctrl.isLoading
                        ? l10n.transferSearching
                        : l10n.transferSearchButton),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: AppColors.primary,
                    ),
                  ),
                ),
              ).animate().fade(delay: 150.ms),
              if (_hasSearched) ...[
                const SizedBox(height: 26),
                Text(
                  l10n.transferVehicleOptions,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
              ],
              ListenableBuilder(
                listenable: _ctrl,
                builder: (_, __) {
                  if (_ctrl.isLoading) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary));
                  }
                  if (!_hasSearched) return const SizedBox.shrink();
                  if (_hasSearched && _ctrl.results.isEmpty) {
                    return _EmptyRides(
                      message: l10n.transferNoSuitableRides,
                      isDark: isDark,
                    );
                  }
                  return Column(
                    children: _ctrl.results
                        .asMap()
                        .entries
                        .map((e) => _TransferCard(
                              transfer: e.value,
                              isDark: isDark,
                              passengers: _passengers,
                              isBooking: _isBooking,
                              onBook: () async {
                                if (_isBooking) return;
                                _isBooking = true;
                                setState(() {});
                                final bookingL10n =
                                    AppLocalizations.of(context);

                                try {
                                  final transfer = e.value;
                                  final ref =
                                      'ZT-T-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
                                  final total = transfer.priceUSD;

                                  final availability = await ApiService.instance
                                      .checkTransferAvailability(
                                    pickupTime: transfer.pickupTime,
                                    durationMinutes:
                                        transfer.durationMinutes,
                                  );
                                  if (!context.mounted) return;
                                  if (availability.isFailure ||
                                      availability.data != true) {
                                    AppSnackbar.error(
                                      context,
                                      availability.isFailure
                                          ? availability.errorMessage ??
                                              bookingL10n.genericError
                                          : bookingL10n.transferScheduleConflict,
                                    );
                                    return;
                                  }

                                  final payment =
                                      await PaymentCheckoutScreen.start(
                                    context,
                                    amountUsd: total,
                                    description:
                                        '${transfer.providerName} - ${transfer.vehicleType}',
                                    referenceId: ref,
                                  );

                                  if (!context.mounted) return;
                                  if (payment?.paid != true) {
                                    AppSnackbar.error(context,
                                        bookingL10n.paymentFailedMessage);
                                    return;
                                  }

                                  final result =
                                      await BookingLoadingOverlay.run(
                                    context,
                                    title: bookingL10n.transferBookedSuccess,
                                    subtitle:
                                        '${transfer.pickupLocation} → ${transfer.dropoffLocation}',
                                    serviceIcon: Icons.local_taxi_rounded,
                                    action: () => ApiService.instance
                                        .createTransferBooking(
                                      transfer,
                                      passengers: _passengers,
                                      referenceId: ref,
                                      paymentAttemptId: payment?.attemptId,
                                    ),
                                  );

                                  if (!context.mounted) return;

                                  if (result.isFailure) {
                                    AppSnackbar.error(
                                      context,
                                      result.errorMessage ==
                                              'TAXI_SCHEDULE_CONFLICT'
                                          ? bookingL10n.transferScheduleConflict
                                          : result.errorMessage ??
                                              bookingL10n.genericError,
                                    );
                                    return;
                                  }

                                  AppSnackbar.success(context,
                                      bookingL10n.transferBookedSuccess);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          BookingConfirmationScreen(
                                        serviceName: bookingL10n
                                            .quickActionTransfers,
                                        primaryText: transfer.pickupLocation,
                                        secondaryText:
                                            transfer.dropoffLocation,
                                        reference: ref,
                                        dateLabel:
                                            MaterialLocalizations.of(context)
                                                .formatMediumDate(
                                          transfer.pickupTime,
                                        ),
                                        priceLabel:
                                            '\$${total.toStringAsFixed(2)}',
                                        serviceIcon:
                                            Icons.local_taxi_rounded,
                                      ),
                                    ),
                                  );
                                } finally {
                                  if (mounted) {
                                    setState(() => _isBooking = false);
                                  }
                                }
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
          ),
        ),
      ),
    );
  }
}

class _LocationField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Color color;
  final bool isDark;
  final String mapTooltip;
  final VoidCallback onMapTap;
  final VoidCallback onChanged;
  const _LocationField(
      {required this.controller,
      required this.label,
      required this.hint,
      required this.icon,
      required this.color,
      required this.isDark,
      required this.mapTooltip,
      required this.onMapTap,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: color),
        suffixIcon: IconButton(
          tooltip: mapTooltip,
          onPressed: onMapTap,
          icon: const Icon(Icons.map_outlined, color: AppColors.primary),
        ),
        filled: true,
        fillColor: isDark
            ? AppColors.darkSurfaceSecondary
            : AppColors.surfaceSecondary,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

class _TaxiMapPointPicker extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final String serviceDisabledMessage;
  final String permissionDeniedMessage;
  final String permissionDeniedForeverMessage;
  final String locationUnavailableMessage;
  final String retryLabel;
  final String settingsLabel;
  final String useCurrentLocationLabel;
  final LatLng? initialPoint;

  const _TaxiMapPointPicker({
    required this.title,
    required this.confirmLabel,
    required this.serviceDisabledMessage,
    required this.permissionDeniedMessage,
    required this.permissionDeniedForeverMessage,
    required this.locationUnavailableMessage,
    required this.retryLabel,
    required this.settingsLabel,
    required this.useCurrentLocationLabel,
    this.initialPoint,
  });

  @override
  State<_TaxiMapPointPicker> createState() => _TaxiMapPointPickerState();
}

class _TaxiMapPointPickerState extends State<_TaxiMapPointPicker> {
  final _locationService = const CurrentLocationService();
  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  LatLng? _selectedPoint;
  bool _isLoadingLocation = true;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _selectedPoint = widget.initialPoint;
    _loadCurrentLocation();
  }

  Future<void> _loadCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationError = null;
    });

    try {
      final position = await _locationService.getPosition();
      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentLocation = point;
        _isLoadingLocation = false;
        _locationError = null;
      });
    } on CurrentLocationException catch (error) {
      if (!mounted) return;
      setState(() {
        _locationError = switch (error.reason) {
          CurrentLocationError.serviceDisabled =>
            widget.serviceDisabledMessage,
          CurrentLocationError.permissionDenied =>
            widget.permissionDeniedMessage,
          CurrentLocationError.permissionDeniedForever =>
            widget.permissionDeniedForeverMessage,
          CurrentLocationError.unableToDetermine =>
            widget.locationUnavailableMessage,
        };
        _isLoadingLocation = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationError = widget.locationUnavailableMessage;
        _isLoadingLocation = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mapCenter = widget.initialPoint ?? _currentLocation;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(widget.title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: _isLoadingLocation
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _locationError != null && mapCenter == null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_off_rounded,
                                  color: AppColors.accentRed, size: 42),
                              const SizedBox(height: 12),
                              Text(_locationError!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isDark
                                        ? AppColors.darkTextSecondary
                                        : AppColors.textSecondary,
                                  )),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _loadCurrentLocation,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        widget.retryLabel,
                                        maxLines: 1,
                                        softWrap: false,
                                      ),
                                    ),
                                  ),
                                  if (_locationError ==
                                      widget.permissionDeniedForeverMessage)
                                    OutlinedButton.icon(
                                      onPressed: Geolocator.openAppSettings,
                                      icon: const Icon(Icons.settings_rounded),
                                      label: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          widget.settingsLabel,
                                          maxLines: 1,
                                          softWrap: false,
                                        ),
                                      ),
                                    ),
                                  if (_locationError ==
                                      widget.serviceDisabledMessage)
                                    OutlinedButton.icon(
                                      onPressed:
                                          Geolocator.openLocationSettings,
                                      icon: const Icon(Icons.settings_rounded),
                                      label: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          widget.settingsLabel,
                                          maxLines: 1,
                                          softWrap: false,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: mapCenter!,
                              initialZoom: 16,
                              onTap: (_, point) =>
                                  setState(() => _selectedPoint = point),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.zentrip.app',
                              ),
                              MarkerLayer(
                                markers: [
                                  if (_currentLocation != null)
                                    Marker(
                                      point: _currentLocation!,
                                      width: 24,
                                      height: 24,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white, width: 3),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.25),
                                              blurRadius: 5,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (_selectedPoint != null)
                                    Marker(
                                      point: _selectedPoint!,
                                      width: 48,
                                      height: 48,
                                      child: const Icon(
                                        Icons.location_pin,
                                        color: AppColors.accentRed,
                                        size: 46,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: FloatingActionButton.small(
                              heroTag: 'taxi-map-my-location',
                              tooltip: widget.useCurrentLocationLabel,
                              onPressed: () {
                                final point = _currentLocation;
                                if (point == null) {
                                  _loadCurrentLocation();
                                  return;
                                }
                                _mapController.move(point, 16);
                                setState(() => _selectedPoint = point);
                              },
                              child: const Icon(Icons.my_location_rounded),
                            ),
                          ),
                        ],
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _selectedPoint == null
                    ? null
                    : () => Navigator.pop(context, _selectedPoint),
                icon: const Icon(Icons.check_rounded),
                label: Text(widget.confirmLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateTimeField {
  final Widget dateButton;
  final Widget timeButton;

  _DateTimeField({
    required String date,
    required String time,
    required String dateLabel,
    required String timeLabel,
    required VoidCallback onDateTap,
    required VoidCallback onTimeTap,
  })  : dateButton = _SelectionButton(
          icon: Icons.calendar_today_rounded,
          label: dateLabel,
          value: date,
          onTap: onDateTap,
        ),
        timeButton = _SelectionButton(
          icon: Icons.schedule_rounded,
          label: timeLabel,
          value: time,
          onTap: onTimeTap,
        );
}

class _SelectionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SelectionButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        alignment: AlignmentDirectional.centerStart,
        side:
            BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                        fontSize: 10)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PassengerSelector extends StatelessWidget {
  final int passengers;
  final String label;
  final ValueChanged<int> onChanged;

  const _PassengerSelector({
    required this.passengers,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: label,
              visualDensity: VisualDensity.compact,
              onPressed:
                  passengers > 1 ? () => onChanged(passengers - 1) : null,
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10)),
                Text('$passengers',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
              ],
            ),
            IconButton(
              tooltip: label,
              visualDensity: VisualDensity.compact,
              onPressed:
                  passengers < 12 ? () => onChanged(passengers + 1) : null,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
            ),
          ],
        ),
      );
}

class _TransferCard extends StatelessWidget {
  final TransferModel transfer;
  final bool isDark;
  final int passengers;
  final bool isBooking;
  final VoidCallback onBook;
  const _TransferCard(
      {required this.transfer,
      required this.isDark,
      required this.passengers,
      required this.isBooking,
      required this.onBook});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 104,
                  height: 82,
                  child: AppNetworkImage(
                    url: transfer.vehicleImageUrl,
                    fallbackIcon: switch (transfer.vehicleType) {
                      'van' => Icons.airport_shuttle_rounded,
                      'bus' => Icons.directions_bus_rounded,
                      _ => Icons.local_taxi_rounded,
                    },
                    fallbackGradient: AppColors.destinationGradients[
                        transfer.vehicleType == 'van' ? 1 : 0],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            transfer.vehicleName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ),
                        if (transfer.driverRating != null) ...[
                          const Icon(Icons.star_rounded,
                              size: 16, color: Colors.amber),
                          Text(transfer.driverRating!.toStringAsFixed(1),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      transfer.providerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 5,
                      children: [
                        _RideFact(
                          icon: Icons.people_alt_outlined,
                          text: l10n
                              .transferUpToPassengers(transfer.maxPassengers),
                        ),
                        _RideFact(
                          icon: Icons.luggage_outlined,
                          text: l10n.carBagsCount(transfer.maxLuggage),
                        ),
                        _RideFact(
                          icon: Icons.schedule_rounded,
                          text: l10n.transferMinutes(transfer.durationMinutes),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (transfer.includedServices.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: transfer.includedServices.take(3).map((service) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accentGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    service,
                    style: const TextStyle(
                        color: AppColors.accentGreen, fontSize: 10),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 14),
          Divider(
              height: 1,
              color: isDark ? AppColors.darkBorder : AppColors.divider),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.transferRidePriceNote,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text('\$${transfer.priceUSD.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                            color: AppColors.primary)),
                    Text(l10n.transferPassengersCount(passengers),
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 10)),
                  ],
                ),
              ),
              FilledButton(
                onPressed: isBooking ? null : onBook,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: isBooking
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(l10n.book,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RideFact extends StatelessWidget {
  final IconData icon;
  final String text;

  const _RideFact({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      );
}

class _EmptyRides extends StatelessWidget {
  final String message;
  final bool isDark;

  const _EmptyRides({required this.message, required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
        child: Column(
          children: [
            const Icon(Icons.local_taxi_rounded,
                color: AppColors.primary, size: 38),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      );
}

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_model.dart';
import '../../../../models/flight_seat_map.dart';
import '../../logic/flight_controller.dart';
import 'flight_checkout_shared_components.dart';
import 'flight_choose_fare_screen.dart';
import 'flight_passengers_screen.dart';
import 'flight_seat_selection.dart';

/// Coordinates the fare and passenger steps before the existing seat/payment
/// flow. Passenger details stay in memory and do not change legacy storage.
class FlightBookingFlowScreen extends StatefulWidget {
  final FlightController? controller;
  final FlightSeatMapLoader? seatMapLoader;

  const FlightBookingFlowScreen({
    super.key,
    this.controller,
    this.seatMapLoader,
  });

  @override
  State<FlightBookingFlowScreen> createState() =>
      _FlightBookingFlowScreenState();
}

class _FlightBookingFlowScreenState extends State<FlightBookingFlowScreen> {
  FlightController? _controller;
  FlightSeatMap? _seatMap;
  List<FlightCheckoutPassenger> _passengers = const [];
  String? _selectedFareId;
  String? _loadError;
  int _step = 0;
  bool _initialized = false;
  bool _loading = true;

  FlightModel? get _flight => _controller?.selectedFlight;
  FlightSearchParams? get _params => _controller?.searchParams;
  int get _passengerCount => (_params?.passengers ?? 1).clamp(1, 9);
  String get _seatClass => _params?.seatClass ?? 'economy';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    _controller = widget.controller ?? (args is FlightController ? args : null);
    final flight = _flight;
    if (flight == null) {
      _loadError = AppLocalizations.of(context).flightSearchError;
      _loading = false;
      return;
    }
    _loadFareData();
  }

  Future<void> _loadFareData() async {
    final flight = _flight;
    if (flight == null) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final map = flight.isDuffelOffer
          ? _singleDuffelOfferMap(flight)
          : await _loadPartnerSeatMap(flight);
      if (!mounted) return;
      final initialFare = map.fares.where(
        (fare) => fare.id.toLowerCase() == _seatClass.toLowerCase(),
      );
      setState(() {
        _seatMap = map;
        _selectedFareId =
            initialFare.isNotEmpty ? initialFare.first.id : map.fares.first.id;
        _passengers = _createPassengers();
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Could not load flight fare data: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _loadError = AppLocalizations.of(context).flightProviderUnavailable;
        _loading = false;
      });
    }
  }

  Future<FlightSeatMap> _loadPartnerSeatMap(FlightModel flight) async {
    final id = flight.partnerListingId?.toString() ??
        flight.id.replaceFirst(RegExp(r'^partner-'), '');
    if (!RegExp(r'^\d+$').hasMatch(id)) {
      throw const FormatException('Flight listing ID is unavailable.');
    }
    final result = await (widget.seatMapLoader ??
        ApiService.instance.getFlightSeatMap)(id);
    if (result.isFailure || result.data == null) {
      throw StateError(result.errorMessage ?? 'Fare data is unavailable.');
    }
    return result.data!;
  }

  FlightSeatMap _singleDuffelOfferMap(FlightModel flight) {
    final total = flight.comparisonTotal(
          passengers: _passengerCount,
          seatClass: _seatClass,
        ) ??
        0;
    if (!total.isFinite || total <= 0) {
      throw const FormatException('The selected offer has no valid price.');
    }
    final localizedLabel =
        CheckoutLabels(AppLocalizations.of(context)).fareForClass(_seatClass);
    return FlightSeatMap(
      rowCount: 1,
      seatLetters: const ['A', 'B', 'C', 'D'],
      extraLegroomRows: const {},
      occupiedSeats: const {},
      fares: [
        FlightSeatFare(
          id: _seatClass,
          label: localizedLabel,
          price: total,
          availableSeats: 0,
          sharedInventory: false,
        ),
      ],
      cabins: const [
        FlightSeatCabin(
          id: 'offer',
          name: 'Offer',
          rows: [1],
          totalSeats: 4,
          availableSeats: 0,
        ),
      ],
      extraLegroomFee: 0,
      taxRate: 0,
      bookingFee: 0,
      extras: const {},
    );
  }

  List<FlightCheckoutPassenger> _createPassengers() {
    final user = ApiService.instance.currentUser;
    return List.generate(
      _passengerCount,
      (index) => FlightCheckoutPassenger(
        name: index == 0 ? (user?.name ?? '') : '',
        email: index == 0 ? (user?.email ?? '') : '',
        phone: index == 0 ? (user?.phone ?? '') : '',
      ),
    );
  }

  FlightSeatFare? get _selectedFare {
    for (final fare in _seatMap?.fares ?? const <FlightSeatFare>[]) {
      if (fare.id == _selectedFareId) return fare;
    }
    return null;
  }

  double get _totalPrice {
    final flight = _flight;
    final fare = _selectedFare;
    final map = _seatMap;
    if (flight == null || fare == null || map == null) return 0;
    if (flight.isDuffelOffer) {
      return flight.comparisonTotal(
            passengers: _passengerCount,
            seatClass: _seatClass,
          ) ??
          0;
    }
    return fare.price * _passengerCount * (1 + map.taxRate) + map.bookingFee;
  }

  void _continueToPassengers() {
    if (_selectedFare == null) return;
    setState(() => _step = 1);
  }

  Future<void> _continueToSeats() async {
    final flight = _flight;
    final map = _seatMap;
    final fare = _selectedFare;
    final params = _params;
    if (flight == null || map == null || fare == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FlightSeatSelectionScreen(
          flight: flight,
          passengerCount: _passengerCount,
          seatClass: params?.seatClass ?? 'economy',
          returnDate: params?.returnDate,
          seatsPerSide: flight.usesTwoByTwoSeatLayout ? 2 : 3,
          rowCount: map.rowCount,
          initialSeatMap: flight.isDuffelOffer ? null : map,
          initialFareId: fare.id,
          passengers: List.unmodifiable(_passengers),
          reviewFlowEnabled: true,
        ),
      ),
    );
  }

  void _updatePassenger(FlightPassengerUpdate update) {
    if (update.index < 0 || update.index >= _passengers.length) return;
    setState(() {
      final next = [..._passengers];
      next[update.index] = update.passenger;
      _passengers = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final flight = _flight;
    if (flight == null) {
      return _FlowError(
        message: _loadError ?? AppLocalizations.of(context).flightSearchError,
        onBack: () => Navigator.of(context).maybePop(),
      );
    }
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    if (_loadError != null || _seatMap == null) {
      return _FlowError(
        message: _loadError ??
            AppLocalizations.of(context).flightProviderUnavailable,
        onBack: () => Navigator.of(context).maybePop(),
        onRetry: _loadFareData,
      );
    }
    final currency = flight.isDuffelOffer ? flight.priceCurrencyCode : 'USD';
    if (_step == 0) {
      return FlightChooseFareScreen(
        flight: flight,
        fares: _seatMap!.fares,
        selectedFareId: _selectedFareId,
        passengerCount: _passengerCount,
        currencyCode: currency,
        totalPrice: _totalPrice,
        showAvailability: !flight.isDuffelOffer,
        onFareSelected: (fare) => setState(() => _selectedFareId = fare.id),
        onContinue: _selectedFare == null ? null : _continueToPassengers,
        onBack: () => Navigator.of(context).maybePop(),
      );
    }
    return FlightPassengersScreen(
      flight: flight,
      passengers: _passengers,
      fareLabel: _selectedFare?.label ?? '',
      currencyCode: currency,
      totalPrice: _totalPrice,
      onPassengerChanged: _updatePassenger,
      onContinue:
          _passengers.any((passenger) => passenger.name.trim().isNotEmpty)
              ? _continueToSeats
              : null,
      onBack: () => setState(() => _step = 0),
    );
  }
}

class _FlowError extends StatelessWidget {
  final String message;
  final VoidCallback onBack;
  final VoidCallback? onRetry;
  const _FlowError({
    required this.message,
    required this.onBack,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(AppLocalizations.of(context).flightConfirmBookingTitle),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.textHint, size: 34),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                if (onRetry != null) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onRetry,
                    child: Text(AppLocalizations.of(context).retry),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

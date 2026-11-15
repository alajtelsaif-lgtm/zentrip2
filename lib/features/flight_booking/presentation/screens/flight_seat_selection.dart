import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/api_result.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/price_comparison.dart';
import '../../../../global_widgets/flight_currency_selector.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../global_widgets/payment_checkout_screen.dart';
import '../../../../models/flight_booking_model.dart';
import '../../../../models/flight_model.dart';
import '../../../../models/flight_seat_map.dart';
import '../../../../models/trip_model.dart';
import '../../../../models/travel_package_model.dart';
import '../../../../l10n/app_localizations.dart';
import 'booking_confirmed_screen.dart';
import 'flight_checkout_shared_components.dart';
import 'flight_passengers_screen.dart';
import 'flight_primary_button.dart';
import 'flight_review_pay_screen.dart';
import 'flight_seat_map_view.dart';
import 'flight_seat_widgets.dart';

const _navy = Color(0xFF1E1B4B);
const _page = Color(0xFFF3F5FA);
const _ink = Color(0xFF172033);
const _line = Color(0xFFE7EAF1);

typedef FlightSeatMapLoader = Future<ApiResult<FlightSeatMap>> Function(String);
typedef FlightPaymentLauncher = Future<bool> Function(
  BuildContext context, {
  required double amount,
  required String currencyCode,
  required String description,
  required String referenceId,
});
typedef FlightTripCreator = Future<ApiResult<TripModel>> Function(TripModel);

class FlightSeatSelectionScreen extends StatefulWidget {
  final FlightModel flight;
  final int passengerCount;
  final String seatClass;
  final DateTime? returnDate;
  final int seatsPerSide;
  final int rowCount;
  final FlightSeatMapLoader? seatMapLoader;
  final FlightPaymentLauncher? paymentLauncher;
  final FlightTripCreator? tripCreator;
  final FlightSeatMap? initialSeatMap;
  final String? initialFareId;
  final PriceComparison? comparison;
  final List<FlightCheckoutPassenger> passengers;
  final bool reviewFlowEnabled;
  final TravelPackage? packageOffer;

  const FlightSeatSelectionScreen({
    super.key,
    required this.flight,
    required this.passengerCount,
    required this.seatClass,
    required this.returnDate,
    required this.seatsPerSide,
    required this.rowCount,
    this.seatMapLoader,
    this.paymentLauncher,
    this.tripCreator,
    this.initialSeatMap,
    this.initialFareId,
    this.comparison,
    this.passengers = const [],
    this.reviewFlowEnabled = false,
    this.packageOffer,
  });

  @override
  State<FlightSeatSelectionScreen> createState() =>
      _FlightSeatSelectionScreenState();
}

class _FlightSeatSelectionScreenState extends State<FlightSeatSelectionScreen>
    with WidgetsBindingObserver {
  FlightSeatMap? _seatMap;
  final Set<String> _selectedSeats = {};
  final Set<String> _heldSeats = {};
  final Set<String> _selectedExtras = {};
  bool _loading = true;
  bool _submitting = false;
  bool _refreshing = false;
  String? _seatError;
  String? _lostSeatMessage;
  String? _selectedFareId;
  String? _selectedCabinId;
  bool _acceptedFareRules = false;
  bool _reviewPushed = false;
  bool _seatsSkipped = false;
  Timer? _refreshTimer;
  String get _sourceCurrency =>
      widget.flight.isDuffelOffer ? widget.flight.priceCurrencyCode : 'USD';
  String get _currencyCode => widget.comparison?.currency ?? _sourceCurrency;

  double _toDisplay(double amount, [String? sourceCurrency]) =>
      widget.comparison?.convert(amount, sourceCurrency ?? _sourceCurrency) ??
      amount;

  String? get _flightId {
    final id = widget.flight.partnerListingId?.toString() ??
        widget.flight.id.replaceFirst(RegExp(r'^partner-'), '');
    return RegExp(r'^\d+$').hasMatch(id) ? id : null;
  }

  FlightSeatFare? get _fare {
    final map = _seatMap;
    if (map == null || map.fares.isEmpty) return null;
    for (final fare in map.fares) {
      if (fare.id == _selectedFareId) return fare;
    }
    return map.fares.first;
  }

  FlightSeatCabin? get _cabin {
    final map = _seatMap;
    if (map == null || map.cabins.isEmpty) return null;
    for (final cabin in map.cabins) {
      if (cabin.id == _selectedCabinId) return cabin;
    }
    return map.cabins.first;
  }

  double get _sourceFlightTotalPrice {
    if (widget.flight.isDuffelOffer) {
      return widget.flight.comparisonTotal(
            passengers: widget.passengerCount,
            seatClass: widget.seatClass,
          ) ??
          0;
    }
    final map = _seatMap;
    final fare = _fare;
    if (map == null || fare == null) return 0;
    final premiumCount = _selectedSeats.where((seat) {
      final row = int.tryParse(seat.substring(0, seat.length - 1));
      return row != null && map.extraLegroomRows.contains(row);
    }).length;
    final extras = _selectedExtras.fold<double>(
      0,
      (sum, key) => sum + (map.extras[key] ?? 0),
    );
    final subtotal = fare.price * widget.passengerCount +
        premiumCount * map.extraLegroomFee +
        extras;
    return subtotal * (1 + map.taxRate) + map.bookingFee;
  }

  double get _totalPrice =>
      _toDisplay(_sourceFlightTotalPrice) +
      _toDisplay(_packageStayTotal, 'USD');

  @override
  void initState() {
    super.initState();
    widget.comparison?.addListener(_currencyChanged);
    WidgetsBinding.instance.addObserver(this);
    final initialMap = widget.initialSeatMap;
    if (initialMap != null) {
      _seatMap = initialMap;
      _selectedFareId =
          initialMap.fares.any((fare) => fare.id == widget.initialFareId)
              ? widget.initialFareId
              : initialMap.fares.first.id;
      _selectedCabinId = initialMap.cabins.first.id;
      _loading = false;
    } else {
      _loadSeatMap();
    }
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadSeatMap(),
    );
  }

  void _currencyChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.comparison?.removeListener(_currencyChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadSeatMap();
  }

  Future<void> _loadSeatMap() async {
    if (_submitting || _refreshing) return;
    if (widget.flight.isDuffelOffer) {
      final rows = List<int>.generate(12, (index) => index + 1);
      const letters = ['A', 'B', 'C', 'D', 'E', 'F'];
      final passengers = widget.passengerCount < 1 ? 1 : widget.passengerCount;
      final total = widget.flight.comparisonTotal(
            passengers: passengers,
            seatClass: widget.seatClass,
          ) ??
          0;
      final fareId = widget.seatClass.toLowerCase();
      final genericMap = FlightSeatMap(
        rowCount: rows.length,
        seatLetters: letters,
        extraLegroomRows: const {},
        occupiedSeats: const {},
        fares: [
          FlightSeatFare(
            id: fareId,
            label: widget.seatClass,
            price: total > 0 ? total / passengers : 1,
            availableSeats: rows.length * letters.length,
            sharedInventory: false,
          ),
        ],
        cabins: [
          FlightSeatCabin(
            id: 'simulation',
            name: 'Simulation',
            rows: rows,
            totalSeats: rows.length * letters.length,
            availableSeats: rows.length * letters.length,
          ),
        ],
        extraLegroomFee: 0,
        taxRate: 0,
        bookingFee: 0,
        extras: const {},
      );
      if (!mounted) return;
      setState(() {
        _seatMap = genericMap;
        _selectedFareId = fareId;
        _selectedCabinId = 'simulation';
        _loading = false;
        _refreshing = false;
        _seatError = null;
      });
      return;
    }
    final flightId = _flightId;
    if (flightId == null) {
      setState(() {
        _loading = false;
        _seatError = AppLocalizations.of(context).seatListingMissing;
      });
      return;
    }
    setState(() {
      _refreshing = true;
      if (_seatMap == null) _loading = true;
      _seatError = null;
    });
    final result = await (widget.seatMapLoader ??
        ApiService.instance.getFlightSeatMap)(flightId);
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _loading = false;
      if (result.isFailure || result.data == null) {
        _seatError = result.errorMessage ?? AppLocalizations.of(context).seatLoadFailed;
      } else {
        final nextMap = result.data!;
        final validSeats = <String>{
          for (final cabin in nextMap.cabins)
            for (final row in cabin.rows)
              for (final letter in nextMap.seatLetters) '$row$letter',
        };
        final unavailableSelected = _selectedSeats
            .where((seat) =>
                !validSeats.contains(seat) ||
                nextMap.occupiedSeats.contains(seat))
            .toList();
        if (unavailableSelected.isNotEmpty) {
          for (final seat in unavailableSelected) {
            _selectedSeats.remove(seat);
            _heldSeats.remove(seat);
          }
          _lostSeatMessage =
              AppLocalizations.of(context).seatNoLongerAvailable;
        }
        _seatMap = nextMap;
        _selectedExtras.removeWhere((key) => !nextMap.extras.containsKey(key));
        if (!nextMap.fares.any((fare) => fare.id == _selectedFareId)) {
          final matchingFare = nextMap.fares.where((fare) =>
              fare.label.toLowerCase() == widget.seatClass.toLowerCase());
          _selectedFareId = matchingFare.isNotEmpty
              ? matchingFare.first.id
              : nextMap.fares.first.id;
        }
        if (!nextMap.cabins.any((cabin) => cabin.id == _selectedCabinId)) {
          _selectedCabinId = nextMap.cabins.first.id;
        }
      }
    });
    if (_lostSeatMessage != null && mounted) {
      AppSnackbar.info(context, _lostSeatMessage!);
      _lostSeatMessage = null;
    }
  }

  void _selectFare(FlightSeatFare fare) {
    if (_submitting ||
        _refreshing ||
        fare.availableSeats < widget.passengerCount) {
      return;
    }
    setState(() => _selectedFareId = fare.id);
  }

  void _toggleSeat(String seat) {
    final map = _seatMap;
    if (_submitting ||
        _refreshing ||
        _loading ||
        _seatError != null ||
        map == null ||
        (map.occupiedSeats.contains(seat) && !_heldSeats.contains(seat))) {
      return;
    }
    if (_selectedSeats.contains(seat)) {
      HapticFeedback.selectionClick();
      setState(() {
        _seatsSkipped = false;
        _selectedSeats.remove(seat);
        _heldSeats.remove(seat);
      });
      return;
    }
    if (_selectedSeats.length >= widget.passengerCount) {
      AppSnackbar.info(
        context,
        AppLocalizations.of(context).selectUpToSeats(widget.passengerCount),
      );
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _seatsSkipped = false;
      _selectedSeats.add(seat);
    });
  }

  Future<void> _openReview({bool skipSeats = false}) async {
    final map = _seatMap;
    final fare = _fare;
    if (!widget.reviewFlowEnabled ||
        _loading ||
        _refreshing ||
        _seatError != null ||
        map == null ||
        fare == null) {
      return;
    }
    if (skipSeats) {
      setState(() {
        _selectedSeats.clear();
        _heldSeats.clear();
        _seatsSkipped = true;
      });
    } else if (_selectedSeats.length != widget.passengerCount) {
      AppSnackbar.info(
        context,
        CheckoutLabels(AppLocalizations.of(context))
            .chooseSeatsOrSkip(widget.passengerCount),
      );
      return;
    }
    if (_reviewPushed) return;
    _reviewPushed = true;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FlightReviewPayScreen(
          flight: widget.flight,
          passengers: widget.passengers,
          seats: _selectedSeats.toList()..sort(),
          fareLabel: fare.label,
          currencyCode: _currencyCode,
          totalPrice: _totalPrice,
          priceLines: _reviewPriceLines(map, fare),
          acceptedFareRules: _acceptedFareRules,
          onFareRulesChanged: (accepted) =>
              setState(() => _acceptedFareRules = accepted),
          onPay: _proceedToPayment,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
    if (mounted) _reviewPushed = false;
  }

  List<FlightPriceLine> _reviewPriceLines(
    FlightSeatMap map,
    FlightSeatFare fare,
  ) {
    final labels = CheckoutLabels(AppLocalizations.of(context));
    if (widget.flight.isDuffelOffer) {
      return [
        FlightPriceLine(
          label: AppLocalizations.of(context).flightTicketPrice,
          amount: _toDisplay(_sourceFlightTotalPrice),
        ),
        if (_packageStayTotal > 0)
          FlightPriceLine(
            label: AppLocalizations.of(context).packageStayTotal,
            amount: _toDisplay(_packageStayTotal, 'USD'),
          ),
      ];
    }
    final fareAmount = fare.price * widget.passengerCount;
    final premiumCount = _selectedSeats.where((seat) {
      final row = int.tryParse(seat.substring(0, seat.length - 1));
      return row != null && map.extraLegroomRows.contains(row);
    }).length;
    final seatAmount = premiumCount * map.extraLegroomFee;
    final extrasAmount = _selectedExtras.fold<double>(
      0,
      (sum, key) => sum + (map.extras[key] ?? 0),
    );
    final tax = (fareAmount + seatAmount + extrasAmount) * map.taxRate;
    return [
      FlightPriceLine(
        label: AppLocalizations.of(context).flightTicketPrice,
        amount: _toDisplay(fareAmount),
      ),
      if (seatAmount > 0)
        FlightPriceLine(label: labels.seats, amount: _toDisplay(seatAmount)),
      if (extrasAmount > 0)
        FlightPriceLine(
          label: AppLocalizations.of(context).flightServiceFee,
          amount: _toDisplay(extrasAmount),
        ),
      if (tax > 0)
        FlightPriceLine(
          label: AppLocalizations.of(context).flightTaxesFees,
          amount: _toDisplay(tax),
        ),
      if (map.bookingFee > 0)
        FlightPriceLine(
          label: AppLocalizations.of(context).flightServiceFee,
          amount: _toDisplay(map.bookingFee),
        ),
      if (_packageStayTotal > 0)
        FlightPriceLine(
          label: AppLocalizations.of(context).packageStayTotal,
          amount: _toDisplay(_packageStayTotal, 'USD'),
        ),
    ];
  }

  double get _packageStayTotal => widget.packageOffer == null
      ? 0
      : widget.packageOffer!.hotelPricePerNight *
          widget.packageOffer!.durationNights *
          widget.passengerCount;

  Future<void> _proceedToPayment() async {
    final flightId = _flightId;
    final isDuffel = widget.flight.isDuffelOffer;
    final fare = _fare;
    final map = _seatMap;
    if (_submitting ||
        (!isDuffel && flightId == null) ||
        fare == null ||
        map == null ||
        _seatError != null ||
        _loading ||
        _refreshing) {
      return;
    }
    if (_selectedSeats.length != widget.passengerCount &&
        !(widget.reviewFlowEnabled &&
            _seatsSkipped &&
            _selectedSeats.isEmpty)) {
      AppSnackbar.error(
        context,
        AppLocalizations.of(context).selectSeatsToContinue(widget.passengerCount),
      );
      return;
    }
    if (fare.availableSeats < widget.passengerCount) {
      AppSnackbar.error(context, AppLocalizations.of(context).fareNotEnoughSeats);
      return;
    }

    final selectedSeats = _selectedSeats.toList()..sort();
    final selectedExtras = _selectedExtras.toList()..sort();
    final bookingTotal = _totalPrice;
    if (!bookingTotal.isFinite || bookingTotal <= 0) {
      AppSnackbar.error(context, AppLocalizations.of(context).genericError);
      return;
    }
    setState(() => _submitting = true);
    if (!isDuffel) {
      final availability = await ApiService.instance.checkFlightAvailability(
        departureDate: widget.flight.departureTime,
        arrivalDate: widget.flight.arrivalTime,
        returnDate: widget.returnDate,
      );
      if (!mounted) return;
      if (availability.isFailure || availability.data != true) {
        setState(() => _submitting = false);
        AppSnackbar.error(
          context,
          availability.isFailure
              ? availability.errorMessage ??
                  AppLocalizations.of(context).flightAvailabilityUnverified
              : AppLocalizations.of(context).flightConflictsBooking,
        );
        return;
      }
      if (selectedSeats.isNotEmpty) {
        final reservation = await ApiService.instance.reserveFlightSeats(
          flightId: flightId!,
          seats: selectedSeats,
        );
        if (!mounted) return;
        if (reservation.isFailure) {
          setState(() => _submitting = false);
          AppSnackbar.error(
            context,
            reservation.errorMessage ?? AppLocalizations.of(context).seatsNoLongerAvailable,
          );
          await _loadSeatMap();
          return;
        }
        setState(() {
          _heldSeats
            ..clear()
            ..addAll(selectedSeats);
        });
      }
    }

    final requestReference = isDuffel
        ? 'ZT-SIM-DUF-${DateTime.now().microsecondsSinceEpoch}'
        : 'flight-$flightId-${DateTime.now().microsecondsSinceEpoch}';
    final paymentLauncher = widget.paymentLauncher;
    int? paymentAttemptId;
    final bool paid;
    if (paymentLauncher == null) {
      final payment = await PaymentCheckoutScreen.start(
        context,
        amountUsd: bookingTotal,
        currencyCode: _currencyCode,
        description: widget.packageOffer == null
            ? '${widget.flight.flightNumber} seat booking'
            : '${widget.packageOffer!.title} · ${widget.flight.flightNumber}',
        referenceId: requestReference,
      );
      paymentAttemptId = payment?.attemptId;
      paid = payment?.paid == true;
    } else {
      paid = await paymentLauncher(
        context,
        amount: bookingTotal,
        currencyCode: _currencyCode,
        description: widget.packageOffer == null
            ? '${widget.flight.flightNumber} seat booking'
            : '${widget.packageOffer!.title} · ${widget.flight.flightNumber}',
        referenceId: requestReference,
      );
    }
    if (!mounted) return;
    if (!paid) {
      if (isDuffel) {
        setState(() => _submitting = false);
        AppSnackbar.error(
            context, AppLocalizations.of(context).paymentNotCompletedNoTrip);
        return;
      }
      final release =
          await ApiService.instance.releaseFlightSeatReservation(flightId!);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _heldSeats.clear();
      });
      AppSnackbar.error(
        context,
        release.isFailure
            ? AppLocalizations.of(context).paymentHoldNotReleased(release.errorMessage ?? '')
            : AppLocalizations.of(context).paymentHoldReleased,
      );
      await _loadSeatMap();
      return;
    }

    if (isDuffel) {
      final trip = TripModel(
        id: DateTime.now().millisecondsSinceEpoch,
        originCode: widget.flight.originCode,
        originCity: widget.flight.originCity,
        destinationCode: widget.flight.destinationCode,
        destinationCity: widget.flight.destinationCity,
        departureDate: widget.flight.departureTime,
        arrivalDate: widget.flight.arrivalTime,
        returnDate: widget.returnDate,
        flightNumber: widget.flight.flightNumber,
        airline: widget.flight.airline,
        airlineLogoUrl: widget.flight.airlineLogoUrl,
        isDirect: widget.flight.isDirect,
        seatClass: fare.id,
        price: _sourceFlightTotalPrice,
        bookingRef: requestReference,
        passengerCount: widget.passengerCount,
        source: 'duffel',
        sourceOfferId: widget.flight.duffelOfferId ?? widget.flight.id,
        priceCurrencyCode: widget.flight.priceCurrencyCode,
        bookingDisplayAmount: bookingTotal,
        bookingCurrencyCode: _currencyCode,
        isSimulated: true,
        selectedSeats: selectedSeats,
        extras: selectedExtras,
      );
      final saved = widget.tripCreator != null
          ? await widget.tripCreator!(trip)
          : await ApiService.instance.createFlightTrip(
              trip,
              paymentAttemptId: paymentAttemptId,
            );
      if (!mounted) return;
      if (saved.isFailure || saved.data == null) {
        setState(() => _submitting = false);
        AppSnackbar.error(
          context,
          saved.errorMessage ?? AppLocalizations.of(context).genericError,
        );
        return;
      }
      final savedTrip = saved.data!;
      final confirmation = FlightBookingConfirmation(
        trip: savedTrip,
        reference: savedTrip.bookingRef ?? requestReference,
        seats: selectedSeats,
        totalPrice: bookingTotal,
        extras: selectedExtras,
      );
      final draft = FlightBookingDraft(
        flight: widget.flight,
        passengerCount: widget.passengerCount,
        seatClass: fare.id,
        seats: selectedSeats,
        returnDate: widget.returnDate,
        totalPrice: bookingTotal,
        currencyCode: _currencyCode,
        extras: selectedExtras,
        paymentAttemptId: paymentAttemptId,
        packageOffer: widget.packageOffer,
      );
      if (_reviewPushed) Navigator.of(context).pop();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BookingConfirmedScreen(
            draft: draft,
            initialConfirmation: confirmation,
          ),
        ),
      );
      if (mounted) setState(() => _submitting = false);
      return;
    }

    final draft = FlightBookingDraft(
      flight: widget.flight,
      passengerCount: widget.passengerCount,
      seatClass: fare.id,
      seats: selectedSeats,
      returnDate: widget.returnDate,
      totalPrice: bookingTotal,
      currencyCode: _currencyCode,
      extras: selectedExtras,
      paymentAttemptId: paymentAttemptId,
      packageOffer: widget.packageOffer,
    );
    if (_reviewPushed) Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BookingConfirmedScreen(draft: draft)),
    );
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reviewFlowEnabled) return _buildCheckoutFlow(context);
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        backgroundColor: _page,
        foregroundColor: _ink,
        elevation: 0,
        title: Text(AppLocalizations.of(context).chooseSeats,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).refreshAvailability,
            onPressed: _submitting || _refreshing ? null : _loadSeatMap,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 7, 16, 20),
                    children: [
                      FlightSelectionHeader(flight: widget.flight),
                      if (widget.comparison != null) ...[
                        FlightCurrencySelector(
                          comparison: widget.comparison!,
                          onChanged: CurrencyService.instance.selectCode,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (widget.flight.isDuffelOffer) ...[
                        const SizedBox(height: 8),
                        Text(
                          AppLocalizations.of(context)
                              .flightSimulatedSeatMapNotice,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 19),
                      if (_seatMap != null) _fareCards(_seatMap!),
                      const SizedBox(height: 19),
                      if (_seatMap != null && !widget.flight.isDuffelOffer)
                        _cabinSelector(_seatMap!),
                      const SizedBox(height: 13),
                      _seatMapPanel(),
                      if (_seatMap != null) ...[
                        const SizedBox(height: 14),
                        _legend(),
                        const SizedBox(height: 18),
                        _extrasPanel(_seatMap!),
                        const SizedBox(height: 14),
                        _priceBreakdown(_seatMap!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 9, 16, 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 728),
                child: FlightPrimaryButton(
                  label: AppLocalizations.of(context).proceedToPaymentAmount(
                    checkoutMoney(
                      _currencyCode,
                      _totalPrice,
                      locale: Localizations.localeOf(context).languageCode,
                    ),
                  ),
                  icon: Icons.lock_rounded,
                  loading: _submitting,
                  onPressed: _seatMap != null &&
                          !_loading &&
                          !_refreshing &&
                          _seatError == null &&
                          (_fare?.availableSeats ?? 0) >=
                              widget.passengerCount &&
                          _selectedSeats.length == widget.passengerCount
                      ? _proceedToPayment
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutFlow(BuildContext context) {
    final labels = CheckoutLabels(AppLocalizations.of(context));
    final map = _seatMap;
    final canContinue = map != null &&
        !_loading &&
        !_refreshing &&
        _seatError == null &&
        (_fare?.availableSeats ?? 0) >= widget.passengerCount &&
        _selectedSeats.length == widget.passengerCount &&
        !_submitting;
    return Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        child: Column(
          children: [
            FlightBookingFlowHeader(
              title: labels.chooseSeats,
              activeStep: 2,
              onBack: () => Navigator.of(context).pop(),
              onSkip: _submitting ? null : () => _openReview(skipSeats: true),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    children: [
                      if (widget.comparison != null)
                        FlightCurrencySelector(
                          comparison: widget.comparison!,
                          onChanged: CurrencyService.instance.selectCode,
                        ),
                      if (widget.flight.isDuffelOffer) ...[
                        Text(
                          AppLocalizations.of(context)
                              .flightSimulatedSeatMapNotice,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (map != null && map.cabins.length > 1)
                        _cabinSelector(map),
                      if (map != null && map.cabins.length > 1)
                        const SizedBox(height: 12),
                      _seatMapPanel(),
                      if (map != null) ...[
                        const SizedBox(height: 14),
                        _legend(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            CheckoutFooter(
              total: checkoutMoney(
                widget.flight.isDuffelOffer
                    ? widget.flight.priceCurrencyCode
                    : 'USD',
                _totalPrice,
                locale: Localizations.localeOf(context).languageCode,
              ),
              caption: labels.travellerPrice(widget.passengerCount),
              buttonLabel: labels.continueLabel,
              onPressed: canContinue ? _openReview : null,
              loading: _submitting,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fareCards(FlightSeatMap map) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: 10,
          children: [
            for (final fare in map.fares)
              SizedBox(
                width: width,
                child: FlightFareCard(
                  fare: fare,
                  currencyCode: widget.flight.isDuffelOffer
                      ? widget.flight.priceCurrencyCode
                      : 'USD',
                  showAvailability: !widget.flight.isDuffelOffer,
                  selected: fare.id == _fare?.id,
                  enabled: !_submitting &&
                      !_refreshing &&
                      _seatError == null &&
                      fare.availableSeats >= widget.passengerCount,
                  onTap: () => _selectFare(fare),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _cabinSelector(FlightSeatMap map) {
    final cabin = _cabin;
    if (cabin == null) return const SizedBox.shrink();
    return FlightCabinSelector(
      cabin: cabin,
      cabins: map.cabins,
      selectedCabinId: cabin.id,
      enabled: !_submitting && !_refreshing && _seatError == null,
      onCabinSelected: (selected) =>
          setState(() => _selectedCabinId = selected.id),
    );
  }

  Widget _seatMapPanel() {
    final map = _seatMap;
    final cabin = _cabin;
    if (_loading && map == null) return const FlightSeatMapSkeleton();
    if (_seatError != null) {
      return FlightSeatErrorPanel(
        message: _seatError!,
        retrying: _refreshing,
        onRetry: _loadSeatMap,
      );
    }
    if (map == null || cabin == null) {
      return FlightSeatErrorPanel(
        message: AppLocalizations.of(context).seatAvailabilityUnavailable,
        retrying: false,
        onRetry: null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_refreshing)
          const LinearProgressIndicator(
            minHeight: 2,
            color: _navy,
            backgroundColor: _line,
          ),
        if (_lostSeatMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_lostSeatMessage!,
                style: const TextStyle(
                    color: Color(0xFF9B4F37), fontWeight: FontWeight.w600)),
          ),
        FlightSeatMapView(
          rows: cabin.rows,
          seatLetters: map.seatLetters,
          extraLegroomRows: map.extraLegroomRows,
          occupiedSeats: map.occupiedSeats.difference(_heldSeats),
          selectedSeats: _selectedSeats,
          showPassengerNumbers: widget.passengerCount > 1,
          enabled:
              !_submitting && !_loading && !_refreshing && _seatError == null,
          onSeatTap: _toggleSeat,
        ),
      ],
    );
  }

  Widget _legend() => const FlightSeatLegend();

  Widget _extrasPanel(FlightSeatMap map) => FlightExtrasPanel(
        extras: map.extras,
        selectedExtras: _selectedExtras,
        enabled: !_submitting && !_refreshing && _seatError == null,
        onChanged: (key, selected) => setState(() {
          if (selected) {
            _selectedExtras.add(key);
          } else {
            _selectedExtras.remove(key);
          }
        }),
      );

  Widget _priceBreakdown(FlightSeatMap map) {
    final fare = _fare;
    if (fare == null) return const SizedBox.shrink();
    if (widget.flight.isDuffelOffer) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(AppLocalizations.of(context).flightTotal,
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w700)),
            ),
            Text(
              checkoutMoney(
                _currencyCode,
                _totalPrice,
                locale: Localizations.localeOf(context).languageCode,
              ),
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }
    return FlightPriceBreakdown(
      map: map,
      fare: fare,
      passengerCount: widget.passengerCount,
      selectedSeats: _selectedSeats,
      selectedExtras: _selectedExtras,
      totalPrice: _totalPrice,
    );
  }
}

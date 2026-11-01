import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../features/flight_booking/logic/flight_controller.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/current_location_service.dart';
import '../../../../features/attractions/logic/attractions_controller.dart';
import '../../../../features/transfers/presentation/screens/transfers_screen.dart';
import '../../../../global_widgets/app_network_image.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/attraction_model.dart';
import '../../../../models/flight_model.dart';
import '../../../../models/travel_package_model.dart';
import '../../../../routes/app_routes.dart';
import 'packages_list_screen.dart';

class AppColors {
  static const primary = Color(0xFF2B35A8);
  static const bg = Color(0xFFF3F5FB);
  static const text = Color(0xFF14183A);
  static const muted = Color(0xFF8A90A8);
  static const field = Color(0xFFF6F7FB);
  static const toggleBg = Color(0xFFF1F3F9);
  static const tint = Color(0xFFE9ECFA);
  static const divider = Color(0xFFE3E6F0);
}

class HomeScreen extends StatefulWidget {
  final CurrentLocationService locationService;

  const HomeScreen({
    super.key,
    this.locationService = const CurrentLocationService(),
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _roundTrip = true;
  DateTime _departureDate = DateTime.now().add(const Duration(days: 7));
  DateTime? _returnDate = DateTime.now().add(const Duration(days: 14));
  int _passengers = 1;
  String _seatClass = 'economy';
  bool _isSearchingFlights = false;
  bool _isLoadingCurrentLocation = false;
  bool _originEdited = false;
  List<AirportOption> _airports = AirportOption.supported;
  List<TravelPackage> _offers = [];
  List<AttractionModel> _monuments = [];
  bool _offersLoading = true;
  bool _monumentsLoading = true;
  bool _offersFailed = false;
  bool _monumentsFailed = false;

  String _fromCode = 'MRA';
  String _fromName = 'Misrata';
  String _toCode = 'MJI';
  String _toName = 'Tripoli';

  @override
  void initState() {
    super.initState();
    _loadAirports();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadHomeSections();
      _loadCurrentAirport();
    });
  }

  Future<void> _loadCurrentAirport() async {
    if (_isLoadingCurrentLocation) return;
    setState(() => _isLoadingCurrentLocation = true);
    try {
      final position = await widget.locationService.getPosition();
      final airport = AirportOption.nearestTo(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      if (airport == null) {
        AppSnackbar.error(
          context,
          AppLocalizations.of(context).nearbyLocationUnableToDetermine,
        );
        return;
      }
      if (!_originEdited) {
        setState(() {
          _fromCode = airport.code;
          _fromName = airport.city;
        });
      }
    } on CurrentLocationException catch (error) {
      if (!mounted) return;
      AppSnackbar.error(
        context,
        _locationErrorMessage(error.reason, AppLocalizations.of(context)),
      );
    } finally {
      if (mounted) setState(() => _isLoadingCurrentLocation = false);
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

  Future<void> _loadAirports() async {
    try {
      final airports = await ApiService.instance.searchAirports('');
      if (!mounted || airports.isEmpty) return;
      setState(() => _airports = airports);
    } catch (error) {
      debugPrint(
          'Airport directory unavailable; using built-in airports: $error');
    }
  }

  Future<void> _loadHomeSections() async {
    await Future.wait([_loadOffers(), _loadMonuments()]);
  }

  Future<void> _loadOffers() async {
    try {
      final result = await ApiService.instance.getOffers();
      if (!mounted) return;
      final offers = result.data ?? [];
      offers.sort((a, b) {
        if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
        return a.pricePerPerson.compareTo(b.pricePerPerson);
      });
      setState(() {
        _offers = offers;
        _offersFailed = result.isFailure;
        _offersLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _offersFailed = true;
        _offersLoading = false;
      });
    }
  }

  Future<void> _loadMonuments() async {
    try {
      final destination = _airportByCity(_toName);
      final monuments = await AttractionsController.loadFeaturedMonuments(
        city: _toName,
        country: destination?.country ?? 'Libya',
        language: Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      setState(() {
        _monuments = monuments;
        _monumentsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _monumentsFailed = true;
        _monumentsLoading = false;
      });
    }
  }

  void _swap() {
    setState(() {
      _originEdited = true;
      final c = _fromCode, n = _fromName;
      _fromCode = _toCode;
      _fromName = _toName;
      _toCode = c;
      _toName = n;
    });
  }

  void _setTripType(bool roundTrip) {
    setState(() {
      _roundTrip = roundTrip;
      if (roundTrip && _returnDate == null) {
        _returnDate = _departureDate.add(const Duration(days: 7));
      }
    });
  }

  String get _fromCity => _airportByCode(_fromCode)?.city ?? _fromName;

  String get _toCity => _airportByCode(_toCode)?.city ?? _toName;

  AirportOption? _airportByCode(String code) {
    for (final airport in _airports) {
      if (airport.code == code) return airport;
    }
    return AirportOption.byCode(code);
  }

  AirportOption? _airportByCity(String city) {
    for (final airport in _airports) {
      if (airport.city.toLowerCase() == city.trim().toLowerCase()) {
        return airport;
      }
    }
    return AirportOption.byCity(city);
  }

  Future<void> _chooseAirport({required bool origin}) async {
    final selected = await showModalBottomSheet<AirportOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _AirportPickerSheet(
        airports: _airports,
        onSearch: ApiService.instance.searchAirports,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _airports = [
        ..._airports.where((airport) => airport.code != selected.code),
        selected,
      ];
      if (origin) {
        _originEdited = true;
        _fromCode = selected.code;
        _fromName = selected.city;
      } else {
        _toCode = selected.code;
        _toName = selected.city;
        _monuments = [];
        _monumentsLoading = true;
        _monumentsFailed = false;
      }
    });
    if (!origin) _loadMonuments();
  }

  Future<void> _chooseDate({required bool departure}) async {
    final initial =
        departure ? _departureDate : (_returnDate ?? _departureDate);
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: departure ? DateTime.now() : _departureDate,
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (departure) {
        _departureDate = selected;
        if (_returnDate != null && _returnDate!.isBefore(selected)) {
          _returnDate = selected.add(const Duration(days: 7));
        }
      } else {
        _returnDate = selected;
      }
    });
  }

  Future<void> _choosePassengers() async {
    var selected = _passengers;
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).passengers),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: selected > 1
                    ? () => setDialogState(() => selected--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$selected'),
              IconButton(
                onPressed: selected < 9
                    ? () => setDialogState(() => selected++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: Text(MaterialLocalizations.of(context).okButtonLabel),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) setState(() => _passengers = result);
  }

  Future<void> _chooseSeatClass() async {
    final l10n = AppLocalizations.of(context);
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in [
            ('economy', l10n.economy),
            ('business', l10n.business),
            ('first', l10n.firstClass),
          ])
            ListTile(
              title: Text(option.$2),
              trailing: _seatClass == option.$1
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(sheetContext, option.$1),
            ),
        ],
      ),
    );
    if (selected != null && mounted) setState(() => _seatClass = selected);
  }

  Future<void> _searchFlights() async {
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
      departureDate: _departureDate,
      returnDate: _roundTrip ? _returnDate : null,
      passengers: _passengers,
      seatClass: _seatClass,
      isRoundTrip: _roundTrip,
    );
    setState(() => _isSearchingFlights = true);
    try {
      await Navigator.pushNamed(
        context,
        AppRoutes.flightResults,
        arguments: params,
      );
    } finally {
      if (mounted) setState(() => _isSearchingFlights = false);
    }
  }

  void _openHotels() {
    Navigator.pushNamed(context, AppRoutes.hotelSearch);
  }

  void _openCars() {
    Navigator.pushNamed(context, AppRoutes.carRental);
  }

  void _openTaxi() {
    Navigator.pushNamed(
      context,
      AppRoutes.transfers,
      arguments: TransferSearchRouteArgs(
        initialFromLocation: _fromCity,
        initialToLocation: _toCity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final l10n = AppLocalizations.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: _loadHomeSections,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                Stack(
                  children: [
                    _Header(topPad: topPad),
                    Padding(
                      padding: EdgeInsets.only(top: topPad + 140),
                      child: _SearchCard(
                        roundTrip: _roundTrip,
                        onTripChanged: _setTripType,
                        fromCode: _fromCode,
                        fromName: _fromName,
                        toCode: _toCode,
                        toName: _toName,
                        onSwap: _swap,
                        onPickOrigin: () => _chooseAirport(origin: true),
                        onPickDestination: () => _chooseAirport(origin: false),
                        departureDate: _departureDate,
                        returnDate: _returnDate,
                        passengers: _passengers,
                        seatClass: _seatClass,
                        onPickDepartureDate: () => _chooseDate(departure: true),
                        onPickReturnDate: () => _chooseDate(departure: false),
                        onPickPassengers: _choosePassengers,
                        onPickSeatClass: _chooseSeatClass,
                        isSearching: _isSearchingFlights,
                        onSearch: _searchFlights,
                      ),
                    ),
                  ],
                ),

                // ---------- NEW: Rent Car / Taxi / Hotels ----------
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ServiceButton(
                          icon: Icons.directions_car_filled_outlined,
                          label: l10n.quickActionCars,
                          onTap: _openCars,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ServiceButton(
                          icon: Icons.local_taxi_outlined,
                          label: l10n.quickActionTransfers,
                          onTap: _openTaxi,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ServiceButton(
                          icon: Icons.hotel_outlined,
                          label: l10n.quickActionHotels,
                          onTap: _openHotels,
                        ),
                      ),
                    ],
                  ),
                ),
                // ----------------------------------------------------

                const SizedBox(height: 24),
                _HomeSectionHeader(
                  title: l10n.homeMonuments,
                  onViewAll: () =>
                      Navigator.pushNamed(context, AppRoutes.attractions),
                ),
                const SizedBox(height: 12),
                _HomeMonumentsSection(
                  monuments: _monuments,
                  isLoading: _monumentsLoading,
                  hasError: _monumentsFailed,
                  onRetry: _loadMonuments,
                  onTap: (monument) => Navigator.pushNamed(
                    context,
                    AppRoutes.attractionDetail,
                    arguments: monument,
                  ),
                ),
                const SizedBox(height: 24),
                _HomeSectionHeader(
                  title: l10n.homeOffers,
                  onViewAll: () => Navigator.pushNamed(
                    context,
                    AppRoutes.packagesList,
                    arguments: PackagesListArgs(
                      kind: PackagesListKind.deals,
                      packages: _offers,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _HomeOffersSection(
                  offers: _offers,
                  isLoading: _offersLoading,
                  hasError: _offersFailed,
                  onRetry: _loadOffers,
                  onTap: (offer) => Navigator.pushNamed(
                    context,
                    AppRoutes.packageDetail,
                    arguments: offer,
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

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({required this.title, required this.onViewAll});

  final String title;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
          TextButton(onPressed: onViewAll, child: Text(l10n.viewAll)),
        ],
      ),
    );
  }
}

class _HomeMonumentsSection extends StatelessWidget {
  const _HomeMonumentsSection({
    required this.monuments,
    required this.isLoading,
    required this.hasError,
    required this.onRetry,
    required this.onTap,
  });

  final List<AttractionModel> monuments;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onRetry;
  final ValueChanged<AttractionModel> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (isLoading) {
      return const SizedBox(
        height: 190,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (monuments.isEmpty) {
      return _HomeSectionMessage(
        message: l10n.homeNoDestinations,
        retryLabel: hasError ? l10n.retry : null,
        onRetry: onRetry,
      );
    }
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: monuments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final monument = monuments[index];
          return SizedBox(
            width: 220,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onTap(monument),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppNetworkImage(
                        url: monument.imageUrl,
                        fallbackIcon: Icons.account_balance_rounded,
                        width: double.infinity,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            monument.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            monument.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeOffersSection extends StatelessWidget {
  const _HomeOffersSection({
    required this.offers,
    required this.isLoading,
    required this.hasError,
    required this.onRetry,
    required this.onTap,
  });

  final List<TravelPackage> offers;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onRetry;
  final ValueChanged<TravelPackage> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (isLoading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (offers.isEmpty) {
      return _HomeSectionMessage(
        message: hasError ? l10n.homeOffersLoadError : l10n.homeNoOffers,
        retryLabel: hasError ? l10n.retry : null,
        onRetry: onRetry,
      );
    }
    return SizedBox(
      height: 240,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: offers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final offer = offers[index];
          return SizedBox(
            width: 240,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onTap(offer),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AppNetworkImage(
                            url: offer.imageUrl,
                            fallbackIcon: offer.icon,
                          ),
                          if (offer.isFeatured)
                            Align(
                              alignment: AlignmentDirectional.topStart,
                              child: Container(
                                margin: const EdgeInsets.all(10),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.94),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  l10n.homeFeaturedOffer,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offer.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${offer.location}, ${offer.country}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                              Text(
                                '${l10n.homeStartingFrom} \$${offer.pricePerPerson.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeSectionMessage extends StatelessWidget {
  const _HomeSectionMessage({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String? retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Center(
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center),
            if (retryLabel != null)
              TextButton(onPressed: onRetry, child: Text(retryLabel!)),
          ],
        ),
      ),
    );
  }
}

// ======================= HEADER =======================

class _Header extends StatelessWidget {
  const _Header({required this.topPad});
  final double topPad;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: topPad + 190,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _DotMapPainter())),
          Positioned(
            left: 20,
            top: topPad + 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.greeting,
                  style: TextStyle(fontSize: 13, color: Color(0xFFC9D0F5)),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.homeSearchTitle,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 20,
            top: topPad + 22,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(50),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.notifications_none_rounded,
                      color: Colors.white, size: 22),
                  Positioned(
                    top: 9,
                    right: 10,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF5A524),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DotMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withAlpha(56);
    final blobs = <Rect>[
      Rect.fromCenter(
          center: Offset(size.width * 0.55, size.height * 0.30),
          width: size.width * 0.28,
          height: size.height * 0.24),
      Rect.fromCenter(
          center: Offset(size.width * 0.74, size.height * 0.36),
          width: size.width * 0.32,
          height: size.height * 0.30),
      Rect.fromCenter(
          center: Offset(size.width * 0.88, size.height * 0.58),
          width: size.width * 0.24,
          height: size.height * 0.26),
      Rect.fromCenter(
          center: Offset(size.width * 0.50, size.height * 0.62),
          width: size.width * 0.16,
          height: size.height * 0.20),
    ];
    const step = 9.0;
    for (final b in blobs) {
      for (double x = b.left; x < b.right; x += step) {
        for (double y = b.top; y < b.bottom; y += step) {
          final dx = (x - b.center.dx) / (b.width / 2);
          final dy = (y - b.center.dy) / (b.height / 2);
          if (dx * dx + dy * dy <= 1) {
            canvas.drawCircle(Offset(x, y), 1.8, paint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ======================= SEARCH CARD =======================

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.roundTrip,
    required this.onTripChanged,
    required this.fromCode,
    required this.fromName,
    required this.toCode,
    required this.toName,
    required this.onSwap,
    required this.onPickOrigin,
    required this.onPickDestination,
    required this.departureDate,
    required this.returnDate,
    required this.passengers,
    required this.seatClass,
    required this.onPickDepartureDate,
    required this.onPickReturnDate,
    required this.onPickPassengers,
    required this.onPickSeatClass,
    required this.isSearching,
    required this.onSearch,
  });

  final bool roundTrip;
  final ValueChanged<bool> onTripChanged;
  final String fromCode, fromName, toCode, toName;
  final VoidCallback onSwap;
  final VoidCallback onPickOrigin, onPickDestination;
  final DateTime departureDate;
  final DateTime? returnDate;
  final int passengers;
  final String seatClass;
  final VoidCallback onPickDepartureDate, onPickReturnDate;
  final VoidCallback onPickPassengers, onPickSeatClass;
  final bool isSearching;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // One way / Round trip
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.toggleBg,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _TripTab(
                    label: l10n.oneWay,
                    selected: !roundTrip,
                    onTap: () => onTripChanged(false),
                  ),
                ),
                Expanded(
                  child: _TripTab(
                    label: l10n.roundTrip,
                    selected: roundTrip,
                    onTap: () => onTripChanged(true),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // From / To
          Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 54),
                    child: _AirportRow(
                      caption: l10n.from,
                      code: fromCode,
                      name: fromName,
                      filledDot: false,
                      onTap: onPickOrigin,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(28, 8, 54, 8),
                    child: Divider(height: 1, color: AppColors.divider),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 54),
                    child: _AirportRow(
                      caption: l10n.to,
                      code: toCode,
                      name: toName,
                      filledDot: true,
                      onTap: onPickDestination,
                    ),
                  ),
                ],
              ),
              PositionedDirectional(
                end: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Material(
                    color: AppColors.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onSwap,
                      child: const SizedBox(
                        width: 42,
                        height: 42,
                        child: Icon(Icons.swap_vert_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Date / Passenger / Class
          Row(
            children: [
              Expanded(
                child: _SelectField(
                  label: l10n.departureDate,
                  icon: Icons.calendar_today_outlined,
                  value: MaterialLocalizations.of(context)
                      .formatMediumDate(departureDate),
                  onTap: onPickDepartureDate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SelectField(
                  label: l10n.returnDate,
                  icon: Icons.calendar_today_outlined,
                  value: roundTrip && returnDate != null
                      ? MaterialLocalizations.of(context)
                          .formatMediumDate(returnDate!)
                      : '—',
                  onTap: roundTrip ? onPickReturnDate : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SelectField(
                  label: l10n.passengers,
                  icon: Icons.people_outline_rounded,
                  value: '$passengers',
                  onTap: onPickPassengers,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SelectField(
                  label: l10n.travelClass,
                  icon: Icons.grid_view_rounded,
                  value: switch (seatClass) {
                    'business' => l10n.business,
                    'first' => l10n.firstClass,
                    _ => l10n.economy,
                  },
                  onTap: onPickSeatClass,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Search Flight
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: isSearching ? null : onSearch,
              icon: isSearching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search_rounded, size: 20),
              label: Text(
                l10n.searchFlightsBtn,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripTab extends StatelessWidget {
  const _TripTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.text,
          ),
        ),
      ),
    );
  }
}

class _AirportRow extends StatelessWidget {
  const _AirportRow({
    required this.caption,
    required this.code,
    required this.name,
    required this.filledDot,
    required this.onTap,
  });

  final String caption, code, name;
  final bool filledDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: filledDot ? AppColors.text : Colors.white,
                shape: BoxShape.circle,
                border: filledDot
                    ? null
                    : Border.all(color: AppColors.primary, width: 3),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caption,
                    style:
                        const TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        code,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF5C627A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AirportPickerSheet extends StatefulWidget {
  const _AirportPickerSheet({
    required this.airports,
    required this.onSearch,
  });

  final List<AirportOption> airports;
  final Future<List<AirportOption>> Function(String query) onSearch;

  @override
  State<_AirportPickerSheet> createState() => _AirportPickerSheetState();
}

class _AirportPickerSheetState extends State<_AirportPickerSheet> {
  final _queryController = TextEditingController();
  late List<AirportOption> _results = widget.airports;
  bool _isLoading = false;
  int _requestId = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    final requestId = ++_requestId;
    final localMatches =
        widget.airports.where((airport) => airport.matches(query)).toList();
    setState(() {
      _results = localMatches;
      _isLoading = query.trim().length >= 2;
    });
    if (query.trim().length < 2) return;
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _fetchSearchResults(query, requestId),
    );
  }

  Future<void> _fetchSearchResults(String query, int requestId) async {
    try {
      final matches = await widget.onSearch(query);
      if (!mounted || requestId != _requestId) return;
      setState(() => _results = matches);
    } catch (error) {
      debugPrint(
          'Airport directory search failed; filtering local list: $error');
      if (!mounted || requestId != _requestId) return;
      setState(() => _results =
          widget.airports.where((airport) => airport.matches(query)).toList());
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            Text(
              l10n.selectAirportTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _queryController,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: l10n.selectAirportTitle,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            if (_isLoading) const LinearProgressIndicator(),
            Expanded(
              child: _results.isEmpty
                  ? Center(child: Text(l10n.noResults))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final airport = _results[index];
                        return ListTile(
                          title: Text('${airport.city} [${airport.code}]'),
                          subtitle: Text(
                            '${airport.airportName} · ${airport.country}',
                          ),
                          onTap: () => Navigator.pop(context, airport),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.field,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: AppColors.muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ======================= SERVICE BUTTONS (NEW) =======================

class _ServiceButton extends StatefulWidget {
  const _ServiceButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_ServiceButton> createState() => _ServiceButtonState();
}

class _ServiceButtonState extends State<_ServiceButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.tint,
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, size: 22, color: AppColors.primary),
              ),
              const SizedBox(height: 8),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

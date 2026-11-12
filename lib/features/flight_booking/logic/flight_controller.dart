import 'package:flutter/foundation.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/services/price_comparison.dart';
import '../../../models/flight_model.dart';
import '../../../models/flight_price_breakdown.dart';

class FlightSearchParams {
  final String originCode;
  final String originCity;
  final String destinationCode;
  final String destinationCity;
  final DateTime departureDate;
  final DateTime? returnDate;
  final int passengers;
  final String seatClass; // 'economy' | 'business' | 'first'
  final bool isRoundTrip;
  final List<DateTime> flexibleDepartureMonths;
  final int flexibleTripDurationDays;
  final bool flexibleWeekendsOnly;

  const FlightSearchParams({
    required this.originCode,
    required this.originCity,
    required this.destinationCode,
    required this.destinationCity,
    required this.departureDate,
    this.returnDate,
    this.passengers = 1,
    this.seatClass = 'economy',
    this.isRoundTrip = false,
    this.flexibleDepartureMonths = const [],
    this.flexibleTripDurationDays = 7,
    this.flexibleWeekendsOnly = false,
  });

  bool get isFlexible => flexibleDepartureMonths.isNotEmpty;
}

enum FlightSort { cheapest, fastest }

class FlightController extends ChangeNotifier {
  final PriceComparison comparison;
  final Future<List<FlightModel>> Function(FlightSearchParams)? searchFlights;
  double? maxBudget;
  List<FlightModel> _all = [];

  FlightController({PriceComparison? comparison, this.searchFlights})
      : comparison = comparison ??
            PriceComparison(
              loadRates: ApiService.instance.exchangeRates,
              initialCurrency: CurrencyService.instance.selected.code,
            ) {
    this.comparison.addListener(_comparisonChanged);
  }

  void _comparisonChanged() {
    _applySort();
    notifyListeners();
  }

  double? comparisonPrice(FlightModel flight) {
    // A Partner listing has no return leg. Do not rank its one-way price
    // against a Duffel round-trip total.
    if (searchParams?.isRoundTrip == true && !flight.isDuffelOffer) return null;
    if (flight.comparisonTotal(
          passengers: searchParams?.passengers ?? 1,
          seatClass: searchParams?.seatClass ?? 'economy',
        ) ==
        null) {
      return null;
    }
    final total = FlightPriceBreakdown.forSearch(
      flight: flight,
      passengers: searchParams?.passengers ?? 1,
      seatClass: searchParams?.seatClass ?? 'economy',
    ).total;
    return comparison.convert(total, flight.priceCurrencyCode);
  }

  void setMaxBudget(double? value) {
    maxBudget = value != null && value.isFinite && value >= 0 ? value : null;
    _applySort();
    notifyListeners();
  }

  int get unpricedCount => _all.where((f) => comparisonPrice(f) == null).length;
  Iterable<String> get sourceCurrencies => _all.map((f) => f.priceCurrencyCode);

  @override
  void dispose() {
    comparison.removeListener(_comparisonChanged);
    comparison.dispose();
    super.dispose();
  }

  FlightSearchParams? searchParams;
  List<FlightModel> results = [];
  bool isLoading = false;
  bool hasSearchError = false;
  bool hasProviderWarning = false;
  FlightSort sort = FlightSort.cheapest;
  FlightModel? selectedFlight;
  int _searchRevision = 0;

  Future<void> search(FlightSearchParams params) async {
    final revision = ++_searchRevision;
    searchParams = params;
    isLoading = true;
    hasSearchError = false;
    hasProviderWarning = false;
    results = [];
    _all = [];
    notifyListeners();
    comparison.refresh();
    try {
      var providerWarnings = <String>[];
      final flights = searchFlights != null
          ? await searchFlights!(params)
          : await ApiService.instance.searchFlights(
              originCode: params.originCode,
              destinationCode: params.destinationCode,
              originCity: params.originCity,
              destinationCity: params.destinationCity,
              departureDate: params.departureDate,
              returnDate: params.returnDate,
              isRoundTrip: params.isRoundTrip,
              adults: params.passengers,
              seatClass: params.seatClass,
              flexibleDepartureMonths: params.flexibleDepartureMonths,
              flexibleTripDurationDays: params.flexibleTripDurationDays,
              flexibleWeekendsOnly: params.flexibleWeekendsOnly,
              onWarnings: (warnings) => providerWarnings = warnings,
            );
      if (revision != _searchRevision) return;
      hasProviderWarning = providerWarnings.isNotEmpty;
      _all = flights;
      _applySort();
    } catch (_) {
      if (revision != _searchRevision) return;
      results = [];
      hasProviderWarning = false;
      hasSearchError = true;
    } finally {
      if (revision == _searchRevision) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  void setSort(FlightSort s) {
    sort = s;
    _applySort();
    notifyListeners();
  }

  void selectFlight(FlightModel flight) {
    selectedFlight = flight;
    notifyListeners();
  }

  void _applySort() {
    results = _all.where((f) {
      final price = comparisonPrice(f);
      return maxBudget == null || (price != null && price <= maxBudget!);
    }).toList();
    if (sort == FlightSort.cheapest) {
      results.sort((a, b) {
        final order =
            comparison.compare(comparisonPrice(a), comparisonPrice(b));
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    } else {
      results.sort((a, b) => a.durationMinutes.compareTo(b.durationMinutes));
    }
  }
}

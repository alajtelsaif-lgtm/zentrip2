import 'package:flutter/foundation.dart';
import '../../../core/services/api_service.dart';
import '../../../models/flight_model.dart';

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
  });
}

enum FlightSort { cheapest, fastest }

class FlightController extends ChangeNotifier {
  FlightSearchParams? searchParams;
  List<FlightModel> results = [];
  bool isLoading = false;
  FlightSort sort = FlightSort.cheapest;
  FlightModel? selectedFlight;

  Future<void> search(FlightSearchParams params) async {
    searchParams = params;
    isLoading = true;
    results = [];
    notifyListeners();
    try {
      results = await ApiService.instance.searchFlights(
        originCode: params.originCode,
        destinationCode: params.destinationCode,
        originCity: params.originCity,
        destinationCity: params.destinationCity,
        departureDate: params.departureDate,
        returnDate: params.returnDate,
        isRoundTrip: params.isRoundTrip,
        adults: params.passengers,
        seatClass: params.seatClass,
      );
      _applySort();
    } finally {
      isLoading = false;
      notifyListeners();
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
    if (sort == FlightSort.cheapest) {
      results.sort((a, b) {
        // Amounts in different currencies are not directly comparable.
        final currencyOrder =
            a.priceCurrencyCode.compareTo(b.priceCurrencyCode);
        if (currencyOrder != 0) return currencyOrder;
        return a.economyPrice.compareTo(b.economyPrice);
      });
    } else {
      results.sort((a, b) => a.durationMinutes.compareTo(b.durationMinutes));
    }
  }
}

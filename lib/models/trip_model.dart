class TripModel {
  final int id;
  final String originCode;
  final String originCity;
  final String destinationCode;
  final String destinationCity;
  final DateTime departureDate;
  final DateTime? arrivalDate;
  final DateTime? returnDate;
  final String flightNumber;
  final String? airline;
  final String? airlineLogoUrl;
  final bool isDirect;
  final String? seatClass;
  final double? price;
  final String? bookingRef;
  final String status; // 'upcoming' | 'completed' | 'cancelled'
  final String? refundStatus;
  final String? refundMethod;
  final int? partnerListingId;
  final int passengerCount;
  final String source;
  final String? sourceOfferId;
  final String priceCurrencyCode;
  final bool isSimulated;
  final List<String> selectedSeats;
  final List<String> extras;

  const TripModel({
    required this.id,
    required this.originCode,
    required this.originCity,
    required this.destinationCode,
    required this.destinationCity,
    required this.departureDate,
    this.arrivalDate,
    this.returnDate,
    required this.flightNumber,
    this.airline,
    this.airlineLogoUrl,
    required this.isDirect,
    this.seatClass = 'Economy',
    this.price,
    this.bookingRef,
    this.status = 'upcoming',
    this.refundStatus,
    this.refundMethod,
    this.partnerListingId,
    this.passengerCount = 1,
    this.source = 'partner',
    this.sourceOfferId,
    this.priceCurrencyCode = 'USD',
    this.isSimulated = false,
    this.selectedSeats = const [],
    this.extras = const [],
  });

  static int _intFromDynamic(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? double.tryParse(value)?.toInt() ?? fallback;
    }
    return fallback;
  }

  static double _doubleFromDynamic(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static bool _boolFromDynamic(dynamic value, [bool fallback = true]) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is String) {
      final text = value.trim().toLowerCase();
      if (text == '1' || text == 'true' || text == 'yes') return true;
      if (text == '0' || text == 'false' || text == 'no') return false;
    }
    if (value is num) return value != 0;
    return fallback;
  }

  factory TripModel.fromJson(Map<String, dynamic> json) => TripModel(
        id: _intFromDynamic(json['id']),
        originCode: (json['origin_code'] ?? '').toString(),
        originCity: (json['origin_city'] ?? '').toString(),
        destinationCode: (json['destination_code'] ?? '').toString(),
        destinationCity: (json['destination_city'] ?? '').toString(),
        departureDate:
            DateTime.tryParse((json['departure_date'] ?? '').toString()) ??
                DateTime.now(),
        arrivalDate: json['arrival_date'] == null ||
                (json['arrival_date'] ?? '').toString().isEmpty
            ? null
            : DateTime.tryParse((json['arrival_date'] ?? '').toString()),
        returnDate: json['return_date'] == null ||
                (json['return_date'] ?? '').toString().isEmpty
            ? null
            : DateTime.tryParse((json['return_date'] ?? '').toString()),
        flightNumber: (json['flight_number'] ?? '').toString(),
        airline: json['airline']?.toString(),
        airlineLogoUrl: json['airline_logo_url']?.toString(),
        isDirect: _boolFromDynamic(json['is_direct'], true),
        seatClass: json['seat_class']?.toString() ?? 'Economy',
        price: json['price'] == null ? null : _doubleFromDynamic(json['price']),
        bookingRef: json['booking_ref']?.toString(),
        status: (json['status'] ?? 'upcoming').toString(),
        refundStatus: json['refund_status']?.toString(),
        refundMethod: json['refund_method']?.toString(),
        partnerListingId: json['partner_listing_id'] == null
            ? null
            : _intFromDynamic(json['partner_listing_id']),
        passengerCount: _intFromDynamic(json['passenger_count'], 1),
        source: (json['source'] ?? 'partner').toString(),
        sourceOfferId: json['duffel_offer_id']?.toString(),
        priceCurrencyCode:
            (json['price_currency'] ?? 'USD').toString().toUpperCase(),
        isSimulated: _boolFromDynamic(json['is_simulated'], false),
        selectedSeats: _stringList(json['selected_seats']),
        extras: _stringList(json['extras']),
      );

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .where((item) => item != null)
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'origin_code': originCode,
        'origin_city': originCity,
        'destination_code': destinationCode,
        'destination_city': destinationCity,
        'departure_date': departureDate.toUtc().toIso8601String(),
        'arrival_date': arrivalDate?.toUtc().toIso8601String(),
        'return_date': returnDate?.toUtc().toIso8601String(),
        'flight_number': flightNumber,
        'airline': airline,
        'airline_logo_url': airlineLogoUrl,
        'is_direct': isDirect,
        'seat_class': seatClass,
        'price': price,
        'booking_ref': bookingRef,
        'status': status,
        'refund_status': refundStatus,
        'refund_method': refundMethod,
        'partner_listing_id': partnerListingId,
        'passenger_count': passengerCount,
        'source': source,
        'duffel_offer_id': sourceOfferId,
        'price_currency': priceCurrencyCode,
        'is_simulated': isSimulated,
        'selected_seats': selectedSeats,
        'extras': extras,
      };

  TripModel copyWith({
    String? status,
    String? refundStatus,
    String? refundMethod,
    int? partnerListingId,
    int? passengerCount,
    String? source,
    String? sourceOfferId,
    String? priceCurrencyCode,
    bool? isSimulated,
    List<String>? selectedSeats,
    List<String>? extras,
  }) =>
      TripModel(
        id: id,
        originCode: originCode,
        originCity: originCity,
        destinationCode: destinationCode,
        destinationCity: destinationCity,
        departureDate: departureDate,
        arrivalDate: arrivalDate,
        returnDate: returnDate,
        flightNumber: flightNumber,
        airline: airline,
        airlineLogoUrl: airlineLogoUrl,
        isDirect: isDirect,
        seatClass: seatClass,
        price: price,
        bookingRef: bookingRef,
        status: status ?? this.status,
        refundStatus: refundStatus ?? this.refundStatus,
        refundMethod: refundMethod ?? this.refundMethod,
        partnerListingId: partnerListingId ?? this.partnerListingId,
        passengerCount: passengerCount ?? this.passengerCount,
        source: source ?? this.source,
        sourceOfferId: sourceOfferId ?? this.sourceOfferId,
        priceCurrencyCode: priceCurrencyCode ?? this.priceCurrencyCode,
        isSimulated: isSimulated ?? this.isSimulated,
        selectedSeats: selectedSeats ?? this.selectedSeats,
        extras: extras ?? this.extras,
      );
}

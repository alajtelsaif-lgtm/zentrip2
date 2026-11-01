import 'dart:math' as math;

class AirportOption {
  final String code;
  final String icaoCode;
  final String city;
  final String airportName;
  final String country;
  final String region;
  final double? latitude;
  final double? longitude;
  final String airportType;
  final bool isMajor;
  final bool scheduledService;
  final String isoCountry;
  final String keywords;
  final String? wikipediaLink;
  final String sourceProvider;
  final double? distanceKm;

  const AirportOption({
    required this.code,
    this.icaoCode = '',
    required this.city,
    required this.airportName,
    required this.country,
    this.region = '',
    this.latitude,
    this.longitude,
    this.airportType = '',
    this.isMajor = false,
    this.scheduledService = true,
    this.isoCountry = '',
    this.keywords = '',
    this.wikipediaLink,
    this.sourceProvider = '',
    this.distanceKm,
  });

  String get label => '$city [$code]';
  String get priorityLabel => isMajor ? 'major' : 'minor';

  factory AirportOption.fromJson(Map<String, dynamic> json) {
    final airport = AirportOption(
      code: (json['code'] ?? '').toString().trim().toUpperCase(),
      icaoCode: (json['icao_code'] ?? '').toString().trim().toUpperCase(),
      city: (json['city'] ?? '').toString(),
      airportName:
          (json['airport_name'] ?? json['airportName'] ?? '').toString(),
      country: (json['country'] ?? '').toString(),
      region: (json['region'] ?? '').toString(),
      latitude: _doubleOrNull(json['latitude']),
      longitude: _doubleOrNull(json['longitude']),
      airportType: (json['airport_type'] ?? '').toString(),
      isMajor: _asBool(json['is_major']) ||
          (json['priority'] ?? '').toString().toLowerCase() == 'major',
      scheduledService: _asBool(json['scheduled_service'], fallback: false),
      isoCountry: (json['iso_country'] ?? '').toString().trim().toUpperCase(),
      keywords: (json['keywords'] ?? '').toString(),
      wikipediaLink: json['wikipedia_link']?.toString(),
      sourceProvider: (json['source_provider'] ?? '').toString(),
      distanceKm: _doubleOrNull(json['distance_km']),
    );
    if (airport.code.isNotEmpty) _directory[airport.code] = airport;
    return airport;
  }

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return '$city $code $icaoCode $airportName $country $region $keywords'
        .toLowerCase()
        .contains(normalized);
  }

  static const _defaults = <AirportOption>[
    AirportOption(
      code: 'MJI',
      city: 'Tripoli',
      airportName: 'Mitiga International Airport',
      country: 'Libya',
      region: 'Western Libya',
    ),
    AirportOption(
      code: 'MRA',
      city: 'Misrata',
      airportName: 'Misrata International Airport',
      country: 'Libya',
      region: 'Central Libya',
    ),
    AirportOption(
      code: 'BEN',
      city: 'Benghazi',
      airportName: 'Benina International Airport',
      country: 'Libya',
      region: 'Eastern Libya',
    ),
    AirportOption(
      code: 'SEB',
      city: 'Sebha',
      airportName: 'Sebha Airport',
      country: 'Libya',
      region: 'Southern Libya',
    ),
    AirportOption(
      code: 'CAI',
      city: 'Cairo',
      airportName: 'Cairo International Airport',
      country: 'Egypt',
      region: 'North Africa',
    ),
    AirportOption(
      code: 'TUN',
      city: 'Tunis',
      airportName: 'Tunis-Carthage International Airport',
      country: 'Tunisia',
      region: 'North Africa',
    ),
    AirportOption(
      code: 'IST',
      city: 'Istanbul',
      airportName: 'Istanbul Airport',
      country: 'Turkiye',
      region: 'Europe',
    ),
    AirportOption(
      code: 'JED',
      city: 'Jeddah',
      airportName: 'King Abdulaziz International Airport',
      country: 'Saudi Arabia',
      region: 'Middle East',
    ),
    AirportOption(
      code: 'DXB',
      city: 'Dubai',
      airportName: 'Dubai International Airport',
      country: 'United Arab Emirates',
      region: 'Middle East',
    ),
    AirportOption(
      code: 'DPS',
      city: 'Bali',
      airportName: 'Ngurah Rai International Airport',
      country: 'Indonesia',
      region: 'Southeast Asia',
    ),
    AirportOption(
      code: 'CGK',
      city: 'Jakarta',
      airportName: 'Soekarno-Hatta International Airport',
      country: 'Indonesia',
      region: 'Southeast Asia',
    ),
  ];

  static final Map<String, AirportOption> _directory = {
    for (final airport in _defaults) airport.code: airport,
  };

  static List<AirportOption> get supported =>
      List.unmodifiable(_directory.values);

  static AirportOption? byCode(String code) {
    return _directory[code.trim().toUpperCase()];
  }

  static AirportOption? byCity(String city) {
    for (final airport in _directory.values) {
      if (airport.city.toLowerCase() == city.trim().toLowerCase()) {
        return airport;
      }
    }
    return null;
  }

  static AirportOption? nearestTo(double latitude, double longitude) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        (latitude == 0 && longitude == 0)) {
      return null;
    }

    AirportOption? nearest;
    var nearestDistance = double.infinity;
    for (final airport in _directory.values) {
      final coordinates = airport.latitude != null && airport.longitude != null
          ? (airport.latitude!, airport.longitude!)
          : _coordinates[airport.code];
      if (coordinates == null) continue;
      final distance = _distanceInKm(
        latitude,
        longitude,
        coordinates.$1,
        coordinates.$2,
      );
      if (distance < nearestDistance) {
        nearest = airport;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  static const _coordinates = <String, (double, double)>{
    'MJI': (32.8949, 13.2760),
    'MRA': (32.3250, 15.0610),
    'BEN': (32.0968, 20.2695),
    'SEB': (26.9869, 14.4725),
    'CAI': (30.1219, 31.4056),
    'TUN': (36.8510, 10.2272),
    'IST': (41.2753, 28.7519),
    'JED': (21.6796, 39.1565),
    'DXB': (25.2532, 55.3657),
    'DPS': (-8.7482, 115.1672),
    'CGK': (-6.1256, 106.6559),
  };

  static double _distanceInKm(
    double latitude1,
    double longitude1,
    double latitude2,
    double longitude2,
  ) {
    const earthRadiusKm = 6371.0;
    final latDelta = _radians(latitude2 - latitude1);
    final lonDelta = _radians(longitude2 - longitude1);
    final a = math.sin(latDelta / 2) * math.sin(latDelta / 2) +
        math.cos(_radians(latitude1)) *
            math.cos(_radians(latitude2)) *
            math.sin(lonDelta / 2) *
            math.sin(lonDelta / 2);
    final boundedA = a.clamp(0.0, 1.0);
    return earthRadiusKm *
        2 *
        math.atan2(math.sqrt(boundedA), math.sqrt(1 - boundedA));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  static double? _doubleOrNull(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static bool _asBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case 'yes':
        case '1':
          return true;
        case 'false':
        case 'no':
        case '0':
          return false;
      }
    }
    return fallback;
  }
}

class AirportSearchResult {
  final String queryType;
  final List<AirportOption> airports;
  final List<AirportSearchLandmark> landmarks;
  final int total;
  final bool hasMore;
  final String? message;

  const AirportSearchResult({
    required this.queryType,
    required this.airports,
    required this.landmarks,
    required this.total,
    required this.hasMore,
    this.message,
  });

  factory AirportSearchResult.fromJson(Map<String, dynamic> json) {
    final rawAirports = json['airports'] as List? ?? const [];
    final rawLandmarks = json['landmarks'] as List? ?? const [];
    return AirportSearchResult(
      queryType: (json['query_type'] ?? 'search').toString(),
      airports: rawAirports
          .whereType<Map>()
          .map((item) => AirportOption.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false),
      landmarks: rawLandmarks
          .whereType<Map>()
          .map((item) => AirportSearchLandmark.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false),
      total: _readInt(json['total']),
      hasMore: json['has_more'] == true,
      message: json['message']?.toString(),
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class AirportSearchLandmark {
  final String name;
  final String city;
  final String country;
  final String category;
  final String? imageUrl;
  final String? imageSource;
  final String? wikipediaUrl;
  final String sourceAttribution;
  final double? latitude;
  final double? longitude;
  final double? distanceKm;
  final AirportOption? nearestAirport;

  const AirportSearchLandmark({
    required this.name,
    required this.city,
    required this.country,
    required this.category,
    required this.sourceAttribution,
    this.imageUrl,
    this.imageSource,
    this.wikipediaUrl,
    this.latitude,
    this.longitude,
    this.distanceKm,
    this.nearestAirport,
  });

  factory AirportSearchLandmark.fromJson(Map<String, dynamic> json) {
    final rawAirport = json['nearest_airport'];
    final airport = rawAirport is Map
        ? AirportOption.fromJson(Map<String, dynamic>.from(rawAirport))
        : null;
    return AirportSearchLandmark(
      name: (json['name'] ?? '').toString(),
      city: (json['city'] ?? '').toString(),
      country: (json['country'] ?? '').toString(),
      category: (json['highlight_category'] ?? json['category'] ?? 'Landmark')
          .toString(),
      imageUrl: json['image_url']?.toString(),
      imageSource: json['image_source']?.toString(),
      wikipediaUrl: json['wikipedia_url']?.toString(),
      sourceAttribution: (json['source_attribution'] ?? '').toString(),
      latitude: AirportOption._doubleOrNull(json['latitude']),
      longitude: AirportOption._doubleOrNull(json['longitude']),
      distanceKm: AirportOption._doubleOrNull(json['distance_km']),
      nearestAirport: airport,
    );
  }
}

class FlightModel {
  final String id;
  final String airline;
  final String airlineCode;
  final String flightNumber;
  final String originCode;
  final String originCity;
  final String destinationCode;
  final String destinationCity;
  final DateTime departureTime;
  final DateTime arrivalTime;
  final int durationMinutes;
  final bool isDirect;
  final int stops;
  final double economyPrice;
  final double? businessPrice;
  final double? firstPrice;
  final int seatsAvailable;
  final String? airlineLogoUrl;
  final int? partnerListingId;
  final bool isActive;
  final String aircraftName;
  final String seatLayout;
  final int seatRows;

  const FlightModel({
    required this.id,
    required this.airline,
    required this.airlineCode,
    required this.flightNumber,
    required this.originCode,
    required this.originCity,
    required this.destinationCode,
    required this.destinationCity,
    required this.departureTime,
    required this.arrivalTime,
    required this.durationMinutes,
    required this.isDirect,
    required this.stops,
    required this.economyPrice,
    this.businessPrice,
    this.firstPrice,
    required this.seatsAvailable,
    this.airlineLogoUrl,
    this.partnerListingId,
    this.isActive = true,
    this.aircraftName = '',
    this.seatLayout = '3-3',
    this.seatRows = 30,
  });

  bool get usesTwoByTwoSeatLayout =>
      RegExp(r'^2\s*[-x×+]\s*2$').hasMatch(seatLayout.trim().toLowerCase());

  static String _stringFromDynamic(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return value.toString();
  }

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

  static bool _boolFromDynamic(dynamic value, [bool fallback = false]) {
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

  static String _airportCode(dynamic code, dynamic city) {
    final value = _stringFromDynamic(code).trim();
    return value.isNotEmpty
        ? value
        : AirportOption.byCity(_stringFromDynamic(city))?.code ?? '';
  }

  static String _airportCity(dynamic city, dynamic code) {
    final value = _stringFromDynamic(city).trim();
    return value.isNotEmpty
        ? value
        : AirportOption.byCode(_stringFromDynamic(code).trim().toUpperCase())
                ?.city ??
            '';
  }

  String get duration {
    final h = durationMinutes ~/ 60;
    final m = durationMinutes % 60;
    return '${h}h ${m}m';
  }

  factory FlightModel.fromJson(Map<String, dynamic> json) {
    final seatLayout = _stringFromDynamic(
      json['seat_layout'] ??
          json['seat_configuration'] ??
          json['aircraft_layout'],
      '3-3',
    );
    final aircraftName = _stringFromDynamic(
      json['aircraft_name'] ?? json['aircraft_model'],
      RegExp(r'^2\s*[-x×+]\s*2$').hasMatch(seatLayout.trim().toLowerCase())
          ? 'ATR 72'
          : 'Airbus A320',
    );
    final defaultSeatRows =
        RegExp(r'^2\s*[-x×+]\s*2$').hasMatch(seatLayout.trim().toLowerCase())
            ? 16
            : 30;
    return FlightModel(
      id: _stringFromDynamic(json['id']),
      airline: _stringFromDynamic(json['airline']),
      airlineCode: _stringFromDynamic(json['airline_code']),
      flightNumber: _stringFromDynamic(json['flight_number']),
      originCode: _airportCode(json['origin_code'], json['origin_city']),
      originCity: _airportCity(json['origin_city'], json['origin_code']),
      destinationCode:
          _airportCode(json['destination_code'], json['destination_city']),
      destinationCity:
          _airportCity(json['destination_city'], json['destination_code']),
      departureTime:
          DateTime.tryParse(_stringFromDynamic(json['departure_time'])) ??
              DateTime.now(),
      arrivalTime:
          DateTime.tryParse(_stringFromDynamic(json['arrival_time'])) ??
              DateTime.now(),
      durationMinutes: _intFromDynamic(json['duration_minutes']),
      isDirect: _boolFromDynamic(json['is_direct'], true),
      stops: _intFromDynamic(json['stops'], 0),
      economyPrice: _doubleFromDynamic(json['economy_price']),
      businessPrice: json['business_price'] == null
          ? null
          : _doubleFromDynamic(json['business_price']),
      firstPrice: json['first_price'] == null
          ? null
          : _doubleFromDynamic(json['first_price']),
      seatsAvailable: _intFromDynamic(json['seats_available'], 0),
      airlineLogoUrl: json['airline_logo_url'] == null
          ? null
          : _stringFromDynamic(json['airline_logo_url']),
      partnerListingId: json['partner_listing_id'] == null
          ? null
          : _intFromDynamic(json['partner_listing_id']),
      isActive: _boolFromDynamic(
            json['is_active'] ?? json['active'],
            !_isInactiveStatus(json['status']),
          ) &&
          !_isInactiveStatus(json['status']),
      aircraftName: aircraftName,
      seatLayout: seatLayout,
      seatRows: _intFromDynamic(
        json['seat_rows'] ?? json['row_count'],
        defaultSeatRows,
      ),
    );
  }

  static bool _isInactiveStatus(dynamic value) {
    final status = _stringFromDynamic(value).trim().toLowerCase();
    return const {'inactive', 'paused', 'draft', 'cancelled', 'canceled'}
        .contains(status);
  }

  bool matchesSearch({
    required String originCode,
    required String destinationCode,
    required String originCity,
    required String destinationCity,
    required DateTime departureDate,
    required int passengers,
  }) {
    final originMatches = _matchesAirport(
      originCode,
      originCity,
      this.originCode,
      this.originCity,
    );
    final destinationMatches = _matchesAirport(
      destinationCode,
      destinationCity,
      this.destinationCode,
      this.destinationCity,
    );
    return isActive &&
        originMatches &&
        destinationMatches &&
        departureTime.year == departureDate.year &&
        departureTime.month == departureDate.month &&
        departureTime.day == departureDate.day &&
        seatsAvailable >= passengers;
  }

  static bool _matchesAirport(
    String requestedCode,
    String requestedCity,
    String flightCode,
    String flightCity,
  ) {
    final normalizedCode = requestedCode.trim().toUpperCase();
    final codeMatches = normalizedCode.isNotEmpty &&
        flightCode.trim().isNotEmpty &&
        flightCode.trim().toUpperCase() == normalizedCode;
    final normalizedCity = requestedCity.trim().toLowerCase();
    final cityMatches = normalizedCity.isNotEmpty &&
        flightCity.trim().toLowerCase() == normalizedCity;
    return codeMatches || cityMatches;
  }
}

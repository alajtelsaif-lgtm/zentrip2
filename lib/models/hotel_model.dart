import 'dart:convert';

import 'package:flutter/foundation.dart';

class HotelModel {
  static const _fallbackImageUrl =
      'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=900&auto=format&fit=crop';

  final String id;
  final String name;
  final String city;
  final String country;
  final String locationName;
  final String? googleMapsUrl;
  final String? placeId;
  final double googleRating;
  final int googleReviewCount;
  final double pricePerNight;
  final bool hasComparisonPrice;
  final double taxAndFeesPercentage;
  final int availableRooms;
  final String? imageUrl;
  final List<String> galleryImages;
  final List<String> amenities;
  final String description;
  final int stars;
  final double? latitude;
  final double? longitude;
  final int? partnerListingId;
  final String? partnerName;
  final double? distanceMeters;
  final List<Map<String, dynamic>> roomTypes;
  final List<Map<String, dynamic>> availabilitySchedule;
  final String status;
  final bool isActive;
  final String? locationInput;
  final String? googlePlaceId;
  final String source;
  final String priceCurrencyCode;
  final String? providerSearchResultId;
  final String? providerAccommodationId;
  final bool availabilityKnown;
  final String ratingSource;
  final double? reviewScore;
  final List<Map<String, dynamic>> offers;

  const HotelModel({
    required this.id,
    required this.name,
    required this.city,
    required this.country,
    required this.locationName,
    this.googleMapsUrl,
    this.placeId,
    required this.googleRating,
    required this.googleReviewCount,
    required this.pricePerNight,
    this.hasComparisonPrice = true,
    this.taxAndFeesPercentage = 12,
    this.availableRooms = 0,
    this.imageUrl,
    this.galleryImages = const [],
    required this.amenities,
    required this.description,
    required this.stars,
    this.latitude,
    this.longitude,
    this.partnerListingId,
    this.partnerName,
    this.distanceMeters,
    this.roomTypes = const [],
    this.availabilitySchedule = const [],
    this.status = 'published',
    this.isActive = true,
    this.locationInput,
    this.googlePlaceId,
    this.source = 'partner',
    this.priceCurrencyCode = 'USD',
    this.providerSearchResultId,
    this.providerAccommodationId,
    this.availabilityKnown = true,
    this.ratingSource = 'unknown',
    this.reviewScore,
    this.offers = const [],
  });

  bool get isDuffelOffer => source == 'duffel';
  bool get isRapidApiOffer => source == 'rapidapi';

  /// The search contract supplies a per-room, per-night provider amount.
  double? get comparisonNightlyPrice =>
      hasComparisonPrice && pricePerNight.isFinite && pricePerNight >= 0
          ? pricePerNight
          : null;

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
    final parsed = value is num
        ? value.toDouble()
        : value is String
            ? double.tryParse(value)
            : null;
    if (parsed != null && parsed.isFinite) return parsed;
    return fallback;
  }

  static Map<String, dynamic> _attributesFrom(Map<String, dynamic> json) {
    final raw = json['attributes'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        return const {};
      }
    }
    return const {};
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .where((item) => item != null)
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static bool _boolFromDynamic(dynamic value, [bool fallback = false]) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case '1':
        case 'true':
        case 'yes':
          return true;
        case '0':
        case 'false':
        case 'no':
          return false;
      }
    }
    return fallback;
  }

  static List<Map<String, dynamic>> _objectList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static double? _coordinateFrom(Object? value) {
    final parsed =
        value is num ? value.toDouble() : double.tryParse('$value'.trim());
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static (double?, double?) _coordinatesFromInput(String value) {
    String decoded;
    try {
      decoded = Uri.decodeComponent(value);
    } on FormatException {
      return (null, null);
    }
    final match = RegExp(
      r'!3d(-?\d{1,2}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)'
      r'|@?(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)'
      r'|[?&](?:q|query|center)=(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(decoded);
    if (match == null) return (null, null);
    final latitude = double.tryParse(
      match.group(1) ?? match.group(3) ?? match.group(5)!,
    );
    final longitude = double.tryParse(
      match.group(2) ?? match.group(4) ?? match.group(6)!,
    );
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return (null, null);
    }
    return (latitude, longitude);
  }

  int get starRating => stars;
  bool get isFeatured => stars >= 5;
  String get address => locationName;
  double get rating => googleRating;
  int get reviewCount => googleReviewCount;
  bool get hasGoogleRating => googleRating > 0;
  List<String> get photos => [
        if (imageUrl != null && imageUrl!.isNotEmpty) imageUrl!,
        ...galleryImages.where((url) => url.isNotEmpty && url != imageUrl),
      ];

  HotelPriceBreakdown pricingFor(
    int numberOfNights, {
    int rooms = 1,
  }) {
    if (numberOfNights < 1) {
      throw ArgumentError.value(
          numberOfNights, 'numberOfNights', 'must be positive');
    }
    if (rooms < 1) {
      throw ArgumentError.value(rooms, 'rooms', 'must be positive');
    }
    final subtotal = pricePerNight * numberOfNights * rooms;
    final taxAndFees = subtotal * taxAndFeesPercentage / 100;
    return HotelPriceBreakdown(
      subtotal: subtotal,
      taxAndFees: taxAndFees,
      totalPrice: subtotal + taxAndFees,
    );
  }

  HotelModel withDistanceMeters(double distance) => HotelModel(
        id: id,
        name: name,
        city: city,
        country: country,
        locationName: locationName,
        googleMapsUrl: googleMapsUrl,
        placeId: placeId,
        googleRating: googleRating,
        googleReviewCount: googleReviewCount,
        pricePerNight: pricePerNight,
        hasComparisonPrice: hasComparisonPrice,
        taxAndFeesPercentage: taxAndFeesPercentage,
        availableRooms: availableRooms,
        imageUrl: imageUrl,
        galleryImages: galleryImages,
        amenities: amenities,
        description: description,
        stars: stars,
        latitude: latitude,
        longitude: longitude,
        partnerListingId: partnerListingId,
        partnerName: partnerName,
        distanceMeters: distance,
        roomTypes: roomTypes,
        availabilitySchedule: availabilitySchedule,
        status: status,
        isActive: isActive,
        locationInput: locationInput,
        googlePlaceId: googlePlaceId,
        source: source,
        priceCurrencyCode: priceCurrencyCode,
        providerSearchResultId: providerSearchResultId,
        providerAccommodationId: providerAccommodationId,
        availabilityKnown: availabilityKnown,
        ratingSource: ratingSource,
        reviewScore: reviewScore,
        offers: offers,
      );

  HotelModel withRoomOffers({
    required List<Map<String, dynamic>> roomTypes,
    required List<Map<String, dynamic>> offers,
    double? pricePerNight,
    String? priceCurrencyCode,
  }) =>
      HotelModel(
        id: id,
        name: name,
        city: city,
        country: country,
        locationName: locationName,
        googleMapsUrl: googleMapsUrl,
        placeId: placeId,
        googleRating: googleRating,
        googleReviewCount: googleReviewCount,
        pricePerNight: pricePerNight ?? this.pricePerNight,
        hasComparisonPrice: pricePerNight == null
            ? hasComparisonPrice
            : pricePerNight.isFinite && pricePerNight >= 0,
        taxAndFeesPercentage: taxAndFeesPercentage,
        availableRooms: availableRooms,
        imageUrl: imageUrl,
        galleryImages: galleryImages,
        amenities: amenities,
        description: description,
        stars: stars,
        latitude: latitude,
        longitude: longitude,
        partnerListingId: partnerListingId,
        partnerName: partnerName,
        distanceMeters: distanceMeters,
        roomTypes: List.unmodifiable(roomTypes),
        availabilitySchedule: availabilitySchedule,
        status: status,
        isActive: isActive,
        locationInput: locationInput,
        googlePlaceId: googlePlaceId,
        source: source,
        priceCurrencyCode: priceCurrencyCode ?? this.priceCurrencyCode,
        providerSearchResultId: providerSearchResultId,
        providerAccommodationId: providerAccommodationId,
        availabilityKnown: availabilityKnown,
        ratingSource: ratingSource,
        reviewScore: reviewScore,
        offers: List.unmodifiable(offers),
      );

  factory HotelModel.fromJson(Map<String, dynamic> json) {
    final attributes = _attributesFrom(json);
    final locationInput = _stringFromDynamic(
      json['google_maps_url'] ??
          json['location_input'] ??
          attributes['google_maps_url'] ??
          attributes['location_input'],
    );
    final parsedCoordinates = _coordinatesFromInput(locationInput);
    final latitude =
        _coordinateFrom(json['latitude'] ?? attributes['latitude']) ??
            parsedCoordinates.$1;
    final longitude =
        _coordinateFrom(json['longitude'] ?? attributes['longitude']) ??
            parsedCoordinates.$2;
    final status =
        _stringFromDynamic(json['status'] ?? attributes['status'], 'published');
    final activeValue = json['active'] ??
        json['is_active'] ??
        attributes['active'] ??
        attributes['is_active'];
    final locationName = _stringFromDynamic(
      json['location_name'] ?? attributes['location_name'],
      _stringFromDynamic(
        json['address'] ?? attributes['address'],
        [
          json['neighborhood'] ?? attributes['neighborhood'],
          json['city'],
        ].where((part) => part != null && '$part'.trim().isNotEmpty).join(', '),
      ),
    );

    final rawGoogleRating =
        json['google_rating'] ?? attributes['google_rating'] ?? json['rating'];
    final rawGoogleReviewCount = json['google_review_count'] ??
        attributes['google_review_count'] ??
        json['review_count'];
    final googleRating = _doubleFromDynamic(rawGoogleRating);
    final googleReviewCount = _intFromDynamic(rawGoogleReviewCount);
    if (kDebugMode && _stringFromDynamic(json['id']).startsWith('partner-')) {
      debugPrint(
        '[HotelModel] Google rating parse for ${json['id']}: '
        'rating=$rawGoogleRating (${rawGoogleRating.runtimeType}) '
        '-> $googleRating; reviews=$rawGoogleReviewCount '
        '(${rawGoogleReviewCount.runtimeType}) -> $googleReviewCount',
      );
    }

    return HotelModel(
      id: _stringFromDynamic(json['id']),
      name: _stringFromDynamic(json['name'] ?? json['title']),
      city: _stringFromDynamic(json['city']),
      country: _stringFromDynamic(json['country']),
      locationName: locationName,
      googleMapsUrl: _nullableString(
        json['google_maps_url'] ??
            attributes['google_maps_url'] ??
            locationInput,
      ),
      placeId: _nullableString(
        json['place_id'] ??
            json['google_place_id'] ??
            attributes['place_id'] ??
            attributes['google_place_id'],
      ),
      googleRating: googleRating,
      googleReviewCount: googleReviewCount,
      pricePerNight: _doubleFromDynamic(
        json['price_per_night'] ?? json['price'],
      ),
      hasComparisonPrice: _validComparisonPrice(
        json['price_per_night'] ?? json['price'],
      ),
      taxAndFeesPercentage: _doubleFromDynamic(
        json['tax_and_fees_percentage'] ??
            attributes['tax_and_fees_percentage'],
        12,
      ),
      availableRooms: _intFromDynamic(
        json['available_rooms'] ?? attributes['available_rooms'],
      ),
      imageUrl: json['image_url'] == null ||
              _stringFromDynamic(json['image_url']).trim().isEmpty
          ? _fallbackImageUrl
          : _stringFromDynamic(json['image_url']),
      galleryImages: _stringList(
        json['gallery_images'] ?? attributes['gallery_images'],
      ),
      amenities: _stringList(json['amenities'] ?? attributes['amenities']),
      description: _stringFromDynamic(json['description']),
      stars: _intFromDynamic(json['stars'] ?? attributes['stars']),
      latitude: latitude,
      longitude: longitude,
      partnerListingId: json['partner_listing_id'] == null
          ? null
          : _intFromDynamic(json['partner_listing_id']),
      partnerName: json['partner_name']?.toString(),
      distanceMeters: json['distance_meters'] == null
          ? null
          : _doubleFromDynamic(json['distance_meters']),
      roomTypes: _objectList(json['room_types'] ?? attributes['room_types']),
      availabilitySchedule: _objectList(
        json['availability_schedule'] ?? attributes['availability_schedule'],
      ),
      status: status,
      isActive: _boolFromDynamic(activeValue, true),
      locationInput: locationInput.isEmpty ? null : locationInput,
      googlePlaceId: _stringFromDynamic(
        json['google_place_id'] ?? attributes['google_place_id'],
      ),
      source: _stringFromDynamic(json['source'], 'partner').toLowerCase(),
      priceCurrencyCode: _stringFromDynamic(
        json['price_currency'] ?? json['currency'],
        'USD',
      ).toUpperCase(),
      providerSearchResultId: _nullableString(
        json['provider_search_result_id'],
      ),
      providerAccommodationId: _nullableString(
        json['provider_accommodation_id'],
      ),
      availabilityKnown: _boolFromDynamic(
        json['availability_known'],
        true,
      ),
      ratingSource: _stringFromDynamic(
        json['rating_source'],
        _stringFromDynamic(json['source'], 'unknown') == 'partner'
            ? 'google_places'
            : _stringFromDynamic(json['source'], 'unknown'),
      ),
      reviewScore: _coordinateFrom(json['review_score']),
      offers: _objectList(json['offers'] ?? attributes['offers']),
    );
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static bool _validComparisonPrice(Object? value) {
    final parsed = double.tryParse(value?.toString() ?? '');
    return parsed != null && parsed.isFinite && parsed >= 0;
  }
}

class HotelPriceBreakdown {
  final double subtotal;
  final double taxAndFees;
  final double totalPrice;

  const HotelPriceBreakdown({
    required this.subtotal,
    required this.taxAndFees,
    required this.totalPrice,
  });
}

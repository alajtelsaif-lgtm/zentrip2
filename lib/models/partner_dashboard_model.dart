import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'admin_dashboard_model.dart';

class PartnerDashboardData {
  final String companyName;
  final String serviceType;
  final int listingCount;
  final int activeListingCount;
  final int reservationCount;
  final int customerCount;
  final double bookedValue;
  final List<PartnerReservation> recentReservations;

  const PartnerDashboardData({
    required this.companyName,
    required this.serviceType,
    required this.listingCount,
    required this.activeListingCount,
    required this.reservationCount,
    required this.customerCount,
    required this.bookedValue,
    required this.recentReservations,
  });

  factory PartnerDashboardData.fromJson(Map<String, dynamic> json) {
    final company = _jsonObject(json['company']);
    final summary = _jsonObject(json['summary']);
    final rawReservations = json['recent_reservations'];
    final reservations = rawReservations is List ? rawReservations : const [];
    return PartnerDashboardData(
      companyName: _displayString(company['name']) ?? 'Partner account',
      serviceType: _displayString(company['service_type']) ?? '',
      listingCount: _asInt(summary['listing_count']),
      activeListingCount: _asInt(summary['active_listing_count']),
      reservationCount: _asInt(summary['reservation_count']),
      customerCount: _asInt(summary['customer_count']),
      bookedValue: _asDouble(summary['booked_value']),
      recentReservations: reservations
          .whereType<Map>()
          .map((item) => PartnerReservation.fromJson(_jsonObject(item)))
          .toList(growable: false),
    );
  }
}

class PartnerReservation extends AdminReservation {
  final String customerEmail;
  final String customerPhone;
  final int? listingId;

  const PartnerReservation({
    required super.id,
    required super.type,
    required super.title,
    required super.customerName,
    required super.reservationDate,
    required super.amount,
    required super.status,
    required this.customerEmail,
    required this.customerPhone,
    required this.listingId,
  });

  factory PartnerReservation.fromJson(Map<String, dynamic> json) =>
      PartnerReservation(
        id: _displayString(json['id']) ?? '',
        type: _displayString(json['type']) ?? '',
        title: _displayString(json['title']) ?? '',
        customerName: _displayString(json['customer_name']) ?? '',
        reservationDate: DateTime.tryParse('${json['reservation_date'] ?? ''}'),
        amount: _asDouble(json['amount']),
        status: _displayString(json['status']) ?? '',
        customerEmail: _displayString(json['customer_email']) ?? '',
        customerPhone: _displayString(json['customer_phone']) ?? '',
        listingId: json['partner_listing_id'] == null
            ? null
            : _asInt(json['partner_listing_id']),
      );
}

class PartnerListing {
  final int? id;
  final String type;
  final String title;
  final String city;
  final String country;
  final String description;
  final String imageUrl;
  final double price;
  final bool active;
  final Map<String, dynamic> attributes;

  const PartnerListing({
    this.id,
    required this.type,
    required this.title,
    required this.city,
    required this.country,
    required this.description,
    required this.imageUrl,
    required this.price,
    required this.active,
    this.attributes = const {},
  });

  String? get listingCode => attributes['listing_code']?.toString();
  String get locationName => _firstNonEmpty([
        attributes['location_name'],
        attributes['address'],
        attributes['neighborhood'],
        attributes['district'],
        attributes['landmark'],
        city,
      ]);
  String? get googleMapsUrl => _nullableString(attributes['google_maps_url']);
  String? get placeId => _nullableString(
        attributes['place_id'] ?? attributes['google_place_id'],
      );
  List<String> get amenities => _stringList(attributes['amenities']);
  List<String> get galleryImages => _stringList(attributes['gallery_images']);
  double get googleRating => _asDouble(attributes['google_rating']);
  int get googleReviewCount => _asInt(attributes['google_review_count']);
  int get availableRooms => _asInt(attributes['available_rooms']);
  double get taxAndFeesPercentage =>
      _asDouble(attributes['tax_and_fees_percentage'], fallback: 12);

  /// Optional database-backed fields to display only when they contain data.
  /// Null-heavy records stay intact for edits without creating blank UI rows.
  Map<String, Object?> get nonEmptyAttributes {
    return Map<String, Object?>.fromEntries(
      attributes.entries.where((entry) => _hasDisplayValue(entry.value)),
    );
  }

  factory PartnerListing.fromJson(Map<String, dynamic> json) {
    final rawAttributes = json['attributes'];
    final Map<String, dynamic> attributes = <String, dynamic>{};
    if (rawAttributes is Map<String, dynamic>) {
      attributes.addAll(rawAttributes);
    } else if (rawAttributes is Map) {
      attributes.addAll(_jsonObject(rawAttributes));
    } else if (rawAttributes is String && rawAttributes.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAttributes);
        if (decoded is Map) {
          attributes.addAll(_jsonObject(decoded));
        }
      } on FormatException {
        // Keep the listing usable when optional JSONB data is malformed.
      }
    }
    for (final key in const [
      'address',
      'location_name',
      'district',
      'neighborhood',
      'landmark',
      'amenities',
      'google_maps_url',
      'place_id',
      'google_rating',
      'google_review_count',
      'tax_and_fees_percentage',
      'available_rooms',
      'stars',
      'room_types',
      'availability_schedule',
      'gallery_images',
      'latitude',
      'longitude',
      'location_input',
      'google_place_id',
    ]) {
      if (json.containsKey(key) &&
          json[key] != null &&
          (!attributes.containsKey(key) ||
              key == 'google_rating' ||
              key == 'google_review_count')) {
        attributes[key] = json[key];
      }
    }
    if (kDebugMode && json['type'] == 'hotel') {
      debugPrint(
        '[PartnerListing] Google rating parse for listing ${json['id']}: '
        'rating=${attributes['google_rating']} '
        '(${attributes['google_rating'].runtimeType}) -> '
        '${_asDouble(attributes['google_rating'])}; '
        'reviews=${attributes['google_review_count']} '
        '(${attributes['google_review_count'].runtimeType}) -> '
        '${_asInt(attributes['google_review_count'])}',
      );
    }
    return PartnerListing(
      id: json['id'] == null ? null : _asInt(json['id']),
      type: '${json['type'] ?? ''}',
      title: _displayString(json['title']) ?? '',
      city: _displayString(json['city']) ?? '',
      country: _displayString(json['country']) ?? '',
      description: _displayString(json['description']) ?? '',
      imageUrl: _displayString(json['image_url']) ?? '',
      price: _asDouble(json['price']),
      active: json['active'] == true ||
          json['active'] == 1 ||
          json['active'] == '1' ||
          json['active'] == 'true' ||
          const {'active', 'published'}
              .contains('${json['status'] ?? ''}'.toLowerCase()),
      attributes: attributes,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'city': city,
        'country': country,
        'description': description,
        'image_url': type == 'flight' ? null : imageUrl,
        'price': price,
        'active': active,
        if (type == 'hotel') 'available_rooms': availableRooms,
        'attributes': attributes,
      };

  PartnerListing copyWith({
    String? type,
    String? title,
    String? city,
    String? country,
    String? description,
    String? imageUrl,
    double? price,
    bool? active,
    Map<String, dynamic>? attributes,
  }) =>
      PartnerListing(
        id: id,
        type: type ?? this.type,
        title: title ?? this.title,
        city: city ?? this.city,
        country: country ?? this.country,
        description: description ?? this.description,
        imageUrl: imageUrl ?? this.imageUrl,
        price: price ?? this.price,
        active: active ?? this.active,
        attributes: attributes ?? this.attributes,
      );
}

int _asInt(dynamic value) {
  if (value is num) return value.isFinite ? value.toInt() : 0;
  return int.tryParse('$value') ?? 0;
}

double _asDouble(dynamic value, {double fallback = 0}) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed != null && parsed.isFinite ? parsed : fallback;
}

String _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = _displayString(value);
    if (text != null) return text;
  }
  return '';
}

List<String> _stringList(dynamic value) => value is List
    ? value
        .where((item) => _hasDisplayValue(item))
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty && item.toLowerCase() != 'null')
        .toList()
    : const [];

String? _nullableString(Object? value) {
  return _displayString(value);
}

String? _displayString(Object? value) {
  if (value == null || value is Map || value is List) return null;
  final text = value.toString().trim();
  if (text.isEmpty ||
      text.toLowerCase() == 'null' ||
      text.toLowerCase() == 'undefined') {
    return null;
  }
  return text;
}

bool _hasDisplayValue(Object? value) {
  if (value == null || value is Map) return false;
  if (value is String) return _displayString(value) != null;
  if (value is Iterable) return value.any(_hasDisplayValue);
  return true;
}

Map<String, dynamic> _jsonObject(Object? value) {
  if (value is! Map) return <String, dynamic>{};
  return <String, dynamic>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

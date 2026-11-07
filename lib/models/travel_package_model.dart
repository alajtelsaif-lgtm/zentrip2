import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import 'flight_model.dart';

class TravelPackage {
  final String id;
  final String title;
  final String location;
  final String country;
  final String destinationCode;
  final String description;
  final String imageUrl;
  final double pricePerPerson;
  final double flightPricePerPerson;
  final double hotelPricePerNight;
  final int durationNights;
  final double rating;
  final int reviewCount;
  final LinearGradient gradient;
  final IconData icon;
  final List<String> highlights;
  final bool isFeatured;
  final String badge;
  final String
      category; // 'beach' | 'city' | 'mountain' | 'desert' | 'cultural'
  final int? partnerListingId;
  final int? flightListingId;
  final FlightModel? flight;

  const TravelPackage({
    required this.id,
    required this.title,
    required this.location,
    required this.country,
    this.destinationCode = '',
    required this.description,
    required this.imageUrl,
    required this.pricePerPerson,
    required this.flightPricePerPerson,
    required this.hotelPricePerNight,
    required this.durationNights,
    required this.rating,
    required this.reviewCount,
    required this.gradient,
    required this.icon,
    required this.highlights,
    this.isFeatured = false,
    this.badge = '',
    this.category = 'city',
    this.partnerListingId,
    this.flightListingId,
    this.flight,
  });

  String get durationLabel => '$durationNights nights';

  /// إجمالي سعر العرض للشخص الواحد (تذكرة + إقامة الليالي كلها).
  double get totalPricePerPerson =>
      flightPricePerPerson + (hotelPricePerNight * durationNights);

  /// أيقونة مناسبة حسب فئة العرض — بتتحسب تلقائيًا لو العرض جاي من API
  /// حقيقي (الداشبورد بيبعت category كنص بس، مش أيقونة Flutter).
  static IconData iconForCategory(String category) => switch (category) {
        'beach' => Icons.beach_access,
        'mountain' => Icons.terrain,
        'desert' => Icons.wb_sunny_outlined,
        'cultural' => Icons.temple_buddhist,
        _ => Icons.location_city,
      };

  factory TravelPackage.fromJson(Map<String, dynamic> json) {
    final category = (json['category'] ?? 'city').toString();
    final id = (json['id'] ?? '').toString();
    final rawFlight = json['flight'];
    final flight = rawFlight is Map
        ? FlightModel.fromJson(Map<String, dynamic>.from(rawFlight))
        : null;
    return TravelPackage(
      id: id,
      title: (json['title'] ?? '').toString(),
      location: (json['location'] ?? '').toString(),
      country: (json['country'] ?? '').toString(),
      destinationCode: (json['destination_code'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      imageUrl: (json['image_url'] ?? '').toString(),
      pricePerPerson: _parseDouble(
          json['total_price_per_person'] ?? json['price_per_person']),
      flightPricePerPerson: _parseDouble(
        json['flight_price_per_person'],
        flight?.economyPrice ?? 0,
      ),
      hotelPricePerNight: _parseDouble(json['hotel_price_per_night']),
      durationNights: _parseInt(json['duration_nights']),
      rating: _parseDouble(json['rating']),
      reviewCount: _parseInt(json['review_count']),
      // الداشبورد بيدير بيانات نصية بس (لون/تصنيف)، فالـ gradient بيتحدد
      // تلقائيًا من الـ id عشان كل عرض ياخد شكل ثابت ومختلف عن اللي جنبه.
      gradient: AppColors.destinationGradients[
          id.hashCode.abs() % AppColors.destinationGradients.length],
      icon: iconForCategory(category),
      highlights: (json['highlights'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      isFeatured: json['is_featured'] == true ||
          const {'1', 'true'}.contains(
              json['is_featured']?.toString().toLowerCase()),
      badge: (json['badge'] ?? '').toString(),
      category: category,
      partnerListingId: json['partner_listing_id'] == null
          ? null
          : _parseInt(json['partner_listing_id']),
      flightListingId: json['flight_listing_id'] == null
          ? null
          : _parseInt(json['flight_listing_id']),
      flight: flight,
    );
  }

  static int _parseInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? double.tryParse(value)?.toInt() ?? fallback;
    }
    return fallback;
  }

  static double _parseDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'location': location,
        'country': country,
        'destination_code': destinationCode,
        'description': description,
        'image_url': imageUrl,
        'price_per_person': pricePerPerson,
        'flight_price_per_person': flightPricePerPerson,
        'hotel_price_per_night': hotelPricePerNight,
        'duration_nights': durationNights,
        'rating': rating,
        'review_count': reviewCount,
        'highlights': highlights,
        'is_featured': isFeatured,
        'badge': badge,
        'category': category,
        'partner_listing_id': partnerListingId,
        'flight_listing_id': flightListingId,
      };
}

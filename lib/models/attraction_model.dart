class AttractionModel {
  final String id;
  final String name;
  final String city;
  final String country;
  final String description;
  final String
      category; // 'landmark' | 'museum' | 'park' | 'beach' | 'restaurant' | 'shopping'
  final String categoryTag;
  final double rating;
  final int reviewCount;
  final int visitCount;
  final int countryVisitCount;
  final double? entryFee;
  final String? imageUrl;
  final double latitude;
  final double longitude;
  final String? openingHours;
  final List<String> tags;
  final double? distanceKm;
  final String? bestTimeToVisit;
  final int? partnerListingId;
  final String? partnerName;
  final String? sourceProvider;
  final String? sourceAttribution;
  final String? wikidataId;
  final String? wikipediaUrl;
  final String? nameEn;
  final String? nameAr;

  const AttractionModel({
    required this.id,
    required this.name,
    required this.city,
    required this.country,
    required this.description,
    required this.category,
    required this.rating,
    required this.reviewCount,
    this.visitCount = 0,
    this.countryVisitCount = 0,
    this.categoryTag = '',
    this.entryFee,
    this.imageUrl,
    required this.latitude,
    required this.longitude,
    this.openingHours,
    required this.tags,
    this.distanceKm,
    this.bestTimeToVisit,
    this.partnerListingId,
    this.partnerName,
    this.sourceProvider,
    this.sourceAttribution,
    this.wikidataId,
    this.wikipediaUrl,
    this.nameEn,
    this.nameAr,
  });

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

  bool get isFree => entryFee == null || entryFee == 0;

  String get title => name;
  String get location =>
      [city, country].where((part) => part.trim().isNotEmpty).join(', ');
  String get categoryLabel => categoryTag.isNotEmpty ? categoryTag : category;
  String get workingHours => openingHours ?? '';
  bool get isExternal => sourceProvider != null && sourceProvider!.isNotEmpty;

  factory AttractionModel.fromJson(Map<String, dynamic> json) {
    final location = _stringFromDynamic(json['location']);
    final locationParts = location.split(',');
    final locationCity = locationParts.first.trim();
    final locationCountry =
        locationParts.length > 1 ? locationParts[1].trim() : '';
    return AttractionModel(
      id: _stringFromDynamic(json['id']),
      name: _stringFromDynamic(json['name'], _stringFromDynamic(json['title'])),
      city: _stringFromDynamic(json['city'], locationCity),
      country: _stringFromDynamic(json['country'], locationCountry),
      description: _stringFromDynamic(json['description']),
      category: _stringFromDynamic(json['category']),
      rating: _doubleFromDynamic(json['rating']),
      reviewCount: _intFromDynamic(json['review_count']),
      visitCount: _intFromDynamic(json['visit_count']),
      countryVisitCount: _intFromDynamic(json['country_visit_count']),
      categoryTag: _stringFromDynamic(json['category_tag']),
      entryFee: json['entry_fee'] == null
          ? null
          : _doubleFromDynamic(json['entry_fee']),
      imageUrl: json['image_url'] == null
          ? null
          : _stringFromDynamic(json['image_url']),
      latitude: _doubleFromDynamic(json['latitude']),
      longitude: _doubleFromDynamic(json['longitude']),
      openingHours: json['opening_hours'] == null &&
              json['working_hours'] == null
          ? null
          : _stringFromDynamic(json['opening_hours'] ?? json['working_hours']),
      tags: (json['tags'] as List? ?? []).map((e) => e.toString()).toList(),
      distanceKm: json['distance_km'] == null
          ? null
          : _doubleFromDynamic(json['distance_km']),
      bestTimeToVisit: json['best_time_to_visit'] == null
          ? null
          : _stringFromDynamic(json['best_time_to_visit']),
      partnerListingId: json['partner_listing_id'] == null
          ? null
          : _intFromDynamic(json['partner_listing_id']),
      partnerName: json['partner_name']?.toString(),
      sourceProvider: json['source_provider']?.toString(),
      sourceAttribution: json['source_attribution']?.toString(),
      wikidataId: json['wikidata_id']?.toString(),
      wikipediaUrl: json['wikipedia_url']?.toString(),
      nameEn: json['name_en']?.toString(),
      nameAr: json['name_ar']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': name,
        'location': location,
        'category_tag': categoryTag,
        'category': category,
        'rating': rating,
        'review_count': reviewCount,
        'description': description,
        'working_hours': openingHours ?? '',
        'best_time_to_visit': bestTimeToVisit ?? '',
        'entry_fee': entryFee,
        'image_url': imageUrl ?? '',
        'tags': tags,
        if (sourceProvider != null) 'source_provider': sourceProvider,
        if (sourceAttribution != null) 'source_attribution': sourceAttribution,
        if (wikidataId != null) 'wikidata_id': wikidataId,
        if (wikipediaUrl != null) 'wikipedia_url': wikipediaUrl,
        if (nameEn != null) 'name_en': nameEn,
        if (nameAr != null) 'name_ar': nameAr,
      };
}

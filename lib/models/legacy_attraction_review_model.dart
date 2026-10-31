class LegacyAttractionPartner {
  final int id;
  final String name;
  final String slug;
  final String status;
  final List<String> accounts;
  final List<LegacyAttractionListing> listings;
  final DateTime? reviewedAt;
  final String? reviewedByName;

  const LegacyAttractionPartner({
    required this.id,
    required this.name,
    required this.slug,
    required this.status,
    required this.accounts,
    required this.listings,
    required this.reviewedAt,
    required this.reviewedByName,
  });

  bool get isActive => status.toLowerCase() == 'active';
  bool get isReviewed => reviewedAt != null;

  factory LegacyAttractionPartner.fromJson(Map<String, dynamic> json) =>
      LegacyAttractionPartner(
        id: _legacyInt(json['id']),
        name: '${json['name'] ?? ''}',
        slug: '${json['slug'] ?? ''}',
        status: '${json['status'] ?? 'inactive'}',
        accounts: (json['accounts'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        listings: (json['listings'] as List? ?? const [])
            .map((item) => LegacyAttractionListing.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
        reviewedAt: DateTime.tryParse('${json['reviewed_at'] ?? ''}'),
        reviewedByName: json['reviewed_by_name']?.toString(),
      );
}

class LegacyAttractionListing {
  final int id;
  final String type;
  final String title;
  final String city;
  final String country;
  final String description;
  final String imageUrl;
  final double price;
  final bool active;
  final Map<String, dynamic> attributes;
  final double googleRating;
  final int googleReviewCount;
  final String? locationName;
  final String? googleMapsUrl;
  final String? placeId;

  const LegacyAttractionListing({
    required this.id,
    required this.type,
    required this.title,
    required this.city,
    required this.country,
    required this.description,
    required this.imageUrl,
    required this.price,
    required this.active,
    required this.attributes,
    required this.googleRating,
    required this.googleReviewCount,
    required this.locationName,
    required this.googleMapsUrl,
    required this.placeId,
  });

  bool get canMapToPlace => type.toLowerCase() == 'attraction';

  factory LegacyAttractionListing.fromJson(Map<String, dynamic> json) =>
      LegacyAttractionListing(
        id: _legacyInt(json['id']),
        type: '${json['type'] ?? ''}',
        title: '${json['title'] ?? ''}',
        city: '${json['city'] ?? ''}',
        country: '${json['country'] ?? ''}',
        description: '${json['description'] ?? ''}',
        imageUrl: '${json['image_url'] ?? ''}',
        price: _legacyDouble(json['price']),
        active: json['active'] == true ||
            json['active'] == 1 ||
            json['active']?.toString().toLowerCase() == 'true',
        attributes: Map<String, dynamic>.from(
            json['attributes'] as Map? ?? const {}),
        googleRating: _legacyDouble(json['google_rating']),
        googleReviewCount: _legacyInt(json['google_review_count']),
        locationName: json['location_name']?.toString(),
        googleMapsUrl: json['google_maps_url']?.toString(),
        placeId: json['place_id']?.toString(),
      );
}

int _legacyInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double _legacyDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

class AttractionRecentDestination {
  final String city;
  final String country;
  final DateTime? createdAt;

  const AttractionRecentDestination({
    required this.city,
    this.country = '',
    this.createdAt,
  });

  factory AttractionRecentDestination.fromJson(Map<String, dynamic> json) {
    final city = json['city']?.toString().trim() ?? '';
    final country = json['country']?.toString().trim() ?? '';
    final createdAt = DateTime.tryParse(
      json['created_at']?.toString() ?? '',
    );
    return AttractionRecentDestination(
      city: city,
      country: country,
      createdAt: createdAt,
    );
  }
}

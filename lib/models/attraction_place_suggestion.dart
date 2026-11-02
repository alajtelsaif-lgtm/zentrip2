class AttractionPlaceSuggestion {
  final String label;
  final String city;
  final String country;
  final String countryCode;
  final String resultType;
  final String placeId;
  final double? latitude;
  final double? longitude;
  final double? south;
  final double? west;
  final double? north;
  final double? east;

  const AttractionPlaceSuggestion({
    required this.label,
    required this.city,
    required this.country,
    required this.countryCode,
    required this.resultType,
    this.placeId = '',
    this.latitude,
    this.longitude,
    this.south,
    this.west,
    this.north,
    this.east,
  });

  bool get isCountry => resultType.toLowerCase() == 'country';

  factory AttractionPlaceSuggestion.fromJson(Map<String, dynamic> json) {
    String read(String key) => json[key]?.toString().trim() ?? '';
    double? readDouble(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    }

    return AttractionPlaceSuggestion(
      label: read('label'),
      city: read('city'),
      country: read('country'),
      countryCode: read('country_code'),
      resultType: read('result_type'),
      placeId: read('place_id'),
      latitude: readDouble('latitude'),
      longitude: readDouble('longitude'),
      south: readDouble('bbox_south') ?? readDouble('south'),
      west: readDouble('bbox_west') ?? readDouble('west'),
      north: readDouble('bbox_north') ?? readDouble('north'),
      east: readDouble('bbox_east') ?? readDouble('east'),
    );
  }
}

class AttractionPlaceSuggestion {
  final String label;
  final String city;
  final String country;
  final String countryCode;
  final String resultType;

  const AttractionPlaceSuggestion({
    required this.label,
    required this.city,
    required this.country,
    required this.countryCode,
    required this.resultType,
  });

  bool get isCountry => resultType.toLowerCase() == 'country';

  factory AttractionPlaceSuggestion.fromJson(Map<String, dynamic> json) {
    String read(String key) => json[key]?.toString().trim() ?? '';
    return AttractionPlaceSuggestion(
      label: read('label'),
      city: read('city'),
      country: read('country'),
      countryCode: read('country_code'),
      resultType: read('result_type'),
    );
  }
}

class HotelDestinationSuggestion {
  final String name;
  final String? localizedName;
  final String? countryName;
  final String? countryNameLocalized;
  final String? countryCode;
  final String? placeId;
  final String? destinationCode;
  final String type;
  final double? latitude;
  final double? longitude;

  const HotelDestinationSuggestion({
    required this.name,
    this.localizedName,
    this.countryName,
    this.countryNameLocalized,
    this.countryCode,
    this.placeId,
    this.destinationCode,
    this.type = 'city',
    this.latitude,
    this.longitude,
  });

  factory HotelDestinationSuggestion.fromJson(Map<String, dynamic> json) {
    double? coordinate(Object? value) {
      if (value is num && value.isFinite) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    }

    String? optionalText(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    final name = optionalText(json['name']) ??
        optionalText(json['name_en']) ??
        optionalText(json['city']) ??
        '';
    if (name.isEmpty) {
      throw const FormatException('Destination suggestion has no name');
    }

    return HotelDestinationSuggestion(
      name: name,
      localizedName:
          optionalText(json['localized_name']) ?? optionalText(json['name_ar']),
      countryName:
          optionalText(json['country_name']) ?? optionalText(json['country']),
      countryNameLocalized: optionalText(json['country_name_localized']) ??
          optionalText(json['country_name_ar']),
      countryCode: optionalText(json['country_code'])?.toUpperCase(),
      placeId: optionalText(json['place_id']),
      destinationCode:
          optionalText(json['destination_code']) ?? optionalText(json['code']),
      type: optionalText(json['type']) ?? 'city',
      latitude: coordinate(json['latitude'] ?? json['lat']),
      longitude: coordinate(json['longitude'] ?? json['lon']),
    );
  }

  String displayName(String languageCode) {
    if (languageCode.toLowerCase().startsWith('ar') &&
        localizedName?.isNotEmpty == true) {
      return localizedName!;
    }
    return name;
  }

  String displayCountry(String languageCode) {
    if (languageCode.toLowerCase().startsWith('ar') &&
        countryNameLocalized?.isNotEmpty == true) {
      return countryNameLocalized!;
    }
    return countryName ?? '';
  }

  static List<HotelDestinationSuggestion> popularMatches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) return const [];
    return _popular
        .where((destination) =>
            destination.name.toLowerCase().contains(normalized) ||
            (destination.localizedName?.contains(normalized) ?? false) ||
            (destination.countryName?.toLowerCase().contains(normalized) ??
                false) ||
            (destination.countryNameLocalized?.contains(normalized) ?? false))
        .take(12)
        .toList(growable: false);
  }

  static const List<HotelDestinationSuggestion> _popular = [
    HotelDestinationSuggestion(
      name: 'London',
      localizedName: 'لندن',
      countryName: 'United Kingdom',
      countryNameLocalized: 'المملكة المتحدة',
      latitude: 51.5072,
      longitude: -0.1276,
    ),
    HotelDestinationSuggestion(
      name: 'Paris',
      localizedName: 'باريس',
      countryName: 'France',
      countryNameLocalized: 'فرنسا',
      latitude: 48.8566,
      longitude: 2.3522,
    ),
    HotelDestinationSuggestion(
      name: 'Dubai',
      localizedName: 'دبي',
      countryName: 'United Arab Emirates',
      countryNameLocalized: 'الإمارات العربية المتحدة',
      latitude: 25.2048,
      longitude: 55.2708,
    ),
    HotelDestinationSuggestion(
      name: 'Cairo',
      localizedName: 'القاهرة',
      countryName: 'Egypt',
      countryNameLocalized: 'مصر',
      latitude: 30.0444,
      longitude: 31.2357,
    ),
    HotelDestinationSuggestion(
      name: 'Tripoli',
      localizedName: 'طرابلس',
      countryName: 'Libya',
      countryNameLocalized: 'ليبيا',
      latitude: 32.8872,
      longitude: 13.1913,
    ),
    HotelDestinationSuggestion(
      name: 'Istanbul',
      localizedName: 'إسطنبول',
      countryName: 'Türkiye',
      countryNameLocalized: 'تركيا',
      latitude: 41.0082,
      longitude: 28.9784,
    ),
    HotelDestinationSuggestion(
      name: 'Tunis',
      localizedName: 'تونس',
      countryName: 'Tunisia',
      countryNameLocalized: 'تونس',
      latitude: 36.8065,
      longitude: 10.1815,
    ),
  ];
}

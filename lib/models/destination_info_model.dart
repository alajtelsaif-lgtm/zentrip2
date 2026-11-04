class WeatherInfo {
  final double tempCelsius;
  final String condition; // 'sunny' | 'cloudy' | 'rainy' | 'clear'
  final String cityName;
  final bool isSample;

  const WeatherInfo(
      {required this.tempCelsius,
      required this.condition,
      required this.cityName,
      this.isSample = false});

  static double _doubleFromDynamic(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  factory WeatherInfo.fromJson(Map<String, dynamic> j) => WeatherInfo(
        tempCelsius: _doubleFromDynamic(j['temp_c']),
        condition: (j['condition'] ?? '').toString(),
        cityName: (j['city'] ?? '').toString(),
        isSample: j['is_sample'] == true,
      );
}

class VisaInfo {
  final String
      requirement; // 'visa_free' | 'visa_on_arrival' | 'e_visa' | 'visa_required'
  final String notes;
  final bool isSample;

  const VisaInfo({
    required this.requirement,
    required this.notes,
    this.isSample = false,
  });

  factory VisaInfo.fromJson(Map<String, dynamic> j) => VisaInfo(
        requirement: (j['requirement'] ?? '').toString(),
        notes: (j['notes'] ?? '').toString(),
        isSample: j['is_sample'] == true,
      );
}

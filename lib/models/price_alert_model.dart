class PriceAlert {
  final String id;
  final String originCode;
  final String destinationCode;
  final DateTime departureDate;
  final double referencePriceUsd;
  final DateTime createdAt;

  const PriceAlert({
    required this.id,
    required this.originCode,
    required this.destinationCode,
    required this.departureDate,
    required this.referencePriceUsd,
    required this.createdAt,
  });

  static double _doubleFromDynamic(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  PriceAlert copyWith({double? referencePriceUsd}) => PriceAlert(
        id: id,
        originCode: originCode,
        destinationCode: destinationCode,
        departureDate: departureDate,
        referencePriceUsd: referencePriceUsd ?? this.referencePriceUsd,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'origin_code': originCode,
        'destination_code': destinationCode,
        'departure_date': departureDate.toIso8601String(),
        'reference_price': referencePriceUsd,
        'created_at': createdAt.toIso8601String(),
      };

  factory PriceAlert.fromJson(Map<String, dynamic> j) => PriceAlert(
        id: (j['id'] ?? '').toString(),
        originCode: (j['origin_code'] ?? '').toString(),
        destinationCode: (j['destination_code'] ?? '').toString(),
        departureDate:
            DateTime.tryParse((j['departure_date'] ?? '').toString()) ??
                DateTime.now(),
        referencePriceUsd: _doubleFromDynamic(
            j['reference_price_usd'] ?? j['reference_price']),
        createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ??
            DateTime.now(),
      );
}

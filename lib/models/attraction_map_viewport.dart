import 'attraction_model.dart';

class AttractionMapCluster {
  final double latitude;
  final double longitude;
  final int count;
  final List<AttractionModel> places;

  const AttractionMapCluster({
    required this.latitude,
    required this.longitude,
    required this.count,
    this.places = const [],
  });

  factory AttractionMapCluster.fromJson(Map<String, dynamic> json) {
    double readDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    final rawPlaces = json['places'];
    return AttractionMapCluster(
      latitude: readDouble(json['latitude']),
      longitude: readDouble(json['longitude']),
      count: json['count'] is num
          ? (json['count'] as num).toInt()
          : int.tryParse(json['count']?.toString() ?? '') ?? 0,
      places: rawPlaces is List
          ? rawPlaces
              .whereType<Map>()
              .map((place) => AttractionModel.fromJson(
                    Map<String, dynamic>.from(place),
                  ))
              .toList()
          : const [],
    );
  }
}

class AttractionMapViewport {
  final List<AttractionModel> attractions;
  final List<AttractionMapCluster> clusters;
  final List<String> warnings;

  const AttractionMapViewport({
    required this.attractions,
    this.clusters = const [],
    this.warnings = const [],
  });

  factory AttractionMapViewport.fromJson(Map<String, dynamic> json) {
    List<AttractionModel> parsePlaces(dynamic raw) => raw is List
        ? raw
            .whereType<Map>()
            .map((place) => AttractionModel.fromJson(
                  Map<String, dynamic>.from(place),
                ))
            .toList()
        : <AttractionModel>[];

    final rawClusters = json['clusters'];
    final rawWarnings = json['warnings'];
    return AttractionMapViewport(
      attractions: parsePlaces(json['attractions']),
      clusters: rawClusters is List
          ? rawClusters
              .whereType<Map>()
              .map((cluster) => AttractionMapCluster.fromJson(
                    Map<String, dynamic>.from(cluster),
                  ))
              .toList()
          : const [],
      warnings: rawWarnings is List
          ? rawWarnings.map((warning) => warning.toString()).toList()
          : const [],
    );
  }
}

import 'attraction_model.dart';

class AttractionSearchPage {
  final List<AttractionModel> attractions;
  final int totalCount;
  final bool hasMore;
  final List<String> warnings;

  const AttractionSearchPage({
    required this.attractions,
    required this.totalCount,
    required this.hasMore,
    this.warnings = const [],
  });

  factory AttractionSearchPage.fromJson(Map<String, dynamic> json) {
    final raw = json['attractions'];
    final attractions = raw is List
        ? raw
            .whereType<Map>()
            .map((item) =>
                AttractionModel.fromJson(Map<String, dynamic>.from(item)))
            .toList()
        : <AttractionModel>[];
    final rawWarnings = json['warnings'];
    final warnings = rawWarnings is List
        ? rawWarnings.map((item) => item.toString()).toList()
        : <String>[];
    final rawCount = json['total_count'];
    final totalCount = rawCount is num
        ? rawCount.toInt()
        : int.tryParse(rawCount?.toString() ?? '') ?? attractions.length;
    return AttractionSearchPage(
      attractions: attractions,
      totalCount: totalCount,
      hasMore: json['has_more'] == true,
      warnings: warnings,
    );
  }
}

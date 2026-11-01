import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/features/attractions/logic/attractions_controller.dart';
import 'package:zentrip/models/attraction_model.dart';

void main() {
  test('featured places rank by visits, then rating', () {
    final places = [
      _place(id: 'rating-leader', visits: 3, rating: 4.9),
      _place(id: 'visit-leader', visits: 9, rating: 4.1),
      _place(id: 'visit-tie-high-rating', visits: 9, rating: 4.8),
      _place(id: 'non-monument', category: 'cafe', visits: 100, rating: 5),
    ];

    final ranked = AttractionsController.rankFeaturedMonuments(places);

    expect(
      ranked.map((place) => place.id),
      ['visit-tie-high-rating', 'visit-leader', 'rating-leader'],
    );
  });

  test('unrated provider places use distance as the final ranking signal', () {
    final places = [
      _place(id: 'far', visits: 0, rating: 0, distanceKm: 8.0),
      _place(id: 'near', visits: 0, rating: 0, distanceKm: 1.2),
    ];

    final ranked = AttractionsController.rankFeaturedMonuments(places);

    expect(ranked.map((place) => place.id), ['near', 'far']);
  });

  test('attraction JSON reads place and country visit totals', () {
    final place = AttractionModel.fromJson({
      'id': 'featured',
      'name': 'Featured place',
      'city': 'Tripoli',
      'country': 'Libya',
      'category': 'landmark',
      'rating': 4.5,
      'review_count': 20,
      'visit_count': 41,
      'country_visit_count': 72,
      'source_provider': 'geoapify',
      'source_attribution': 'Geoapify · OpenStreetMap contributors',
      'wikidata_id': 'Q123',
      'description': '',
      'latitude': 0,
      'longitude': 0,
      'tags': <String>[],
    });

    expect(place.visitCount, 41);
    expect(place.countryVisitCount, 72);
    expect(place.isExternal, isTrue);
    expect(place.wikidataId, 'Q123');
  });
}

AttractionModel _place({
  required String id,
  required int visits,
  required double rating,
  String category = 'landmark',
  double? distanceKm,
}) =>
    AttractionModel(
      id: id,
      name: id,
      city: 'Tripoli',
      country: 'Libya',
      description: '',
      category: category,
      rating: rating,
      reviewCount: 0,
      visitCount: visits,
      distanceKm: distanceKm,
      latitude: 0,
      longitude: 0,
      tags: const [],
    );

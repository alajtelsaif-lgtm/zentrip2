import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/models/attraction_map_viewport.dart';

void main() {
  test('viewport response safely parses places, clusters and warnings', () {
    final viewport = AttractionMapViewport.fromJson({
      'attractions': [
        {
          'id': 'P0001',
          'name': 'Leptis Magna',
          'city': 'Khoms',
          'country': 'Libya',
          'category': 'historical',
          'latitude': 32.638,
          'longitude': 14.293,
          'tags': [],
        }
      ],
      'clusters': [
        {
          'latitude': 32.638,
          'longitude': 14.293,
          'count': 2,
          'places': [
            {
              'id': 'P0001',
              'name': 'Leptis Magna',
              'latitude': 32.638,
              'longitude': 14.293,
              'tags': [],
            },
            {
              'id': 'P0002',
              'name': 'Museum',
              'latitude': 32.639,
              'longitude': 14.294,
              'tags': [],
            }
          ],
        }
      ],
      'warnings': ['Showing cached results.'],
    });

    expect(viewport.attractions.single.name, 'Leptis Magna');
    expect(viewport.clusters.single.count, 2);
    expect(viewport.clusters.single.places, hasLength(2));
    expect(viewport.warnings, ['Showing cached results.']);
  });

  test('viewport parser accepts empty and malformed optional collections', () {
    final viewport = AttractionMapViewport.fromJson({
      'attractions': null,
      'clusters': 'invalid',
      'warnings': null,
    });

    expect(viewport.attractions, isEmpty);
    expect(viewport.clusters, isEmpty);
    expect(viewport.warnings, isEmpty);
  });
}

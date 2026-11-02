import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/core/services/api_service.dart';
import 'package:zentrip/features/attractions/logic/attractions_controller.dart';
import 'package:zentrip/models/attraction_model.dart';

void main() {
  test('city search is debounced and reports an unresolved city', () async {
    var requestCount = 0;
    var requestedCity = '';
    final controller = AttractionsController(
      searchAttractions: ({
        required String city,
        String? country,
        String? language,
      }) async {
        requestCount++;
        requestedCity = city;
        throw const AttractionCityNotFoundException();
      },
    );

    controller.search('Trip', language: 'ar');
    controller.search('Tripoli', language: 'ar');
    expect(requestCount, 0);

    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(requestCount, 1);
    expect(requestedCity, 'Tripoli');
    expect(controller.cityNotFound, isTrue);
    expect(controller.isLoading, isFalse);
    controller.dispose();
  });

  test('landmarks screen filters non-landmark provider records', () async {
    final controller = AttractionsController(
      searchAttractions: ({
        required String city,
        String? country,
        String? language,
      }) async =>
          [
            _place(id: 'landmark', category: 'landmark'),
            _place(id: 'cafe', category: 'cafe'),
            _place(id: 'market', category: 'shopping'),
          ],
    );

    await controller.load(city: 'Tripoli', country: 'Libya');

    expect(controller.results.map((place) => place.id), ['landmark']);
    controller.dispose();
  });
}

AttractionModel _place({required String id, required String category}) =>
    AttractionModel(
      id: id,
      name: id,
      city: 'Tripoli',
      country: 'Libya',
      description: '',
      category: category,
      rating: 0,
      reviewCount: 0,
      latitude: 32.8,
      longitude: 13.2,
      tags: const [],
    );

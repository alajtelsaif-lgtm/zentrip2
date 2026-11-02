import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentrip/core/services/api_service.dart';
import 'package:zentrip/core/services/current_location_service.dart';
import 'package:zentrip/features/attractions/logic/attractions_controller.dart';
import 'package:zentrip/models/attraction_model.dart';
import 'package:zentrip/models/attraction_place_suggestion.dart';
import 'package:zentrip/models/attraction_search_page.dart';
import 'package:zentrip/models/attraction_recent_destination.dart';

void main() {
  test('debounces place suggestions and ignores an older query', () async {
    var suggestionRequests = 0;
    final controller = AttractionsController(
      searchSuggestions: (query, {language}) async {
        suggestionRequests++;
        return [
          AttractionPlaceSuggestion(
            label: query,
            city: query,
            country: 'Libya',
            countryCode: 'ly',
            resultType: 'city',
          ),
        ];
      },
    );

    final oldSuggestions = controller.suggestionsFor('Tr', language: 'en');
    final latestSuggestions =
        controller.suggestionsFor('Tripoli', language: 'en');
    expect(await oldSuggestions, isEmpty);
    expect((await latestSuggestions).single.label, 'Tripoli');
    expect(suggestionRequests, 1);
    controller.dispose();
  });

  test('clearing a destination invalidates pending data and resets errors',
      () async {
    SharedPreferences.setMockInitialValues({});
    final controller = AttractionsController(
      searchAttractions: ({
        required String city,
        String? country,
        String? language,
      }) async =>
          [_place(id: 'paris-place', category: 'historical')],
    );

    await controller.load(city: 'Paris', country: 'fr');
    expect(controller.results, hasLength(1));

    controller.clearSearch();

    expect(controller.results, isEmpty);
    expect(controller.searchQuery, isEmpty);
    expect(controller.hasError, isFalse);
    expect(controller.cityNotFound, isFalse);
    expect(controller.isLoading, isFalse);
    expect(controller.hasMore, isFalse);
    controller.dispose();
  });

  test('search reports a place that Geoapify could not resolve', () async {
    final controller = AttractionsController(
      searchSuggestions: (query, {language}) async => const [],
      searchAttractions: ({
        required String city,
        String? country,
        String? language,
      }) async {
        throw const AttractionCityNotFoundException();
      },
    );

    await controller.searchPlace('No Such Place');

    expect(controller.cityNotFound, isTrue);
    expect(controller.isLoading, isFalse);
    expect(controller.results, isEmpty);
    controller.dispose();
  });

  test('only country-type suggestions trigger country searches', () async {
    String? searchedCity;
    String? searchedCountry;
    final controller = AttractionsController(
      searchAttractions: ({
        required String city,
        String? country,
        String? language,
      }) async {
        searchedCity = city;
        searchedCountry = country;
        return [_place(id: 'verified', category: 'historical')];
      },
    );
    const city = AttractionPlaceSuggestion(
      label: 'Tripoli, Iowa, United States',
      city: '',
      country: 'United States',
      countryCode: 'us',
      resultType: 'city',
    );
    const country = AttractionPlaceSuggestion(
      label: 'Libya',
      city: '',
      country: 'Libya',
      countryCode: 'ly',
      resultType: 'country',
    );

    await controller.loadSuggestion(city);
    expect(searchedCity, city.label);
    expect(searchedCountry, 'us');

    await controller.loadSuggestion(country);
    expect(searchedCity, '');
    expect(searchedCountry, 'ly');
    controller.dispose();
  });

  test('last successful place is used when location is unavailable', () async {
    SharedPreferences.setMockInitialValues({
      'attraction_last_city': 'Rabat',
      'attraction_last_country': 'ma',
      'attraction_last_display': 'Rabat, Morocco',
    });
    String? searchedCity;
    String? searchedCountry;
    final controller = AttractionsController(
      loadCurrentPlace: () async {
        throw const CurrentLocationException(
            CurrentLocationError.permissionDenied);
      },
      searchAttractions: ({
        required String city,
        String? country,
        String? language,
      }) async {
        searchedCity = city;
        searchedCountry = country;
        return [_place(id: 'kasbah', category: 'historical')];
      },
    );

    final display = await controller.loadDefault();

    expect(display, 'Rabat, Morocco');
    expect(searchedCity, 'Rabat');
    expect(searchedCountry, 'ma');
    expect(controller.results.single.id, 'kasbah');
    controller.dispose();
  });

  test('a newer saved booking destination wins over local search history',
      () async {
    SharedPreferences.setMockInitialValues({
      'attraction_last_city': 'Rabat',
      'attraction_last_country': 'ma',
      'attraction_last_display': 'Rabat, Morocco',
      'attraction_last_search_at': '2026-10-01T10:00:00Z',
    });
    String? searchedCity;
    String? searchedCountry;
    final controller = AttractionsController(
      loadRecentDestination: () async => AttractionRecentDestination(
        city: 'Kyoto',
        country: 'jp',
        createdAt: DateTime.parse('2026-10-20T10:00:00Z'),
      ),
      loadCurrentPlace: () async => throw StateError('should not use location'),
      searchAttractions: ({
        required String city,
        String? country,
        String? language,
      }) async {
        searchedCity = city;
        searchedCountry = country;
        return [_place(id: 'kyoto-temple', category: 'historical')];
      },
    );

    final display = await controller.loadDefault();

    expect(display, 'Kyoto');
    expect(searchedCity, 'Kyoto');
    expect(searchedCountry, 'jp');
    controller.dispose();
  });

  test('selected place coordinates and bounds reach the search request',
      () async {
    double? searchedLatitude;
    double? searchedLongitude;
    double? searchedSouth;
    String? searchedPlaceId;
    final controller = AttractionsController(
      searchPage: ({
        required String city,
        String? category,
        String? country,
        String? language,
        double? latitude,
        double? longitude,
        double? south,
        double? west,
        double? north,
        double? east,
        String? placeId,
        int limit = 40,
        int offset = 0,
      }) async {
        searchedLatitude = latitude;
        searchedLongitude = longitude;
        searchedSouth = south;
        searchedPlaceId = placeId;
        return AttractionSearchPage(
          attractions: [_place(id: 'museum', category: 'museum')],
          totalCount: 1,
          hasMore: false,
        );
      },
    );

    await controller.loadSuggestion(const AttractionPlaceSuggestion(
      label: 'Museum, Rome',
      city: 'Rome',
      country: 'Italy',
      countryCode: 'it',
      resultType: 'city',
      placeId: 'geo-place-1',
      latitude: 41.9,
      longitude: 12.5,
      south: 41.8,
      west: 12.4,
      north: 42.0,
      east: 12.6,
    ));

    expect(searchedLatitude, 41.9);
    expect(searchedLongitude, 12.5);
    expect(searchedSouth, 41.8);
    expect(searchedPlaceId, 'geo-place-1');
    controller.dispose();
  });

  test('loads the next verified landmark page when more results exist',
      () async {
    final requestedOffsets = <int>[];
    final controller = AttractionsController(
      searchPage: ({
        required String city,
        String? category,
        String? country,
        String? language,
        double? latitude,
        double? longitude,
        double? south,
        double? west,
        double? north,
        double? east,
        String? placeId,
        int limit = 40,
        int offset = 0,
      }) async {
        requestedOffsets.add(offset);
        if (offset == 0) {
          return AttractionSearchPage(
            attractions: List.generate(
              40,
              (index) => _place(id: 'landmark-$index', category: 'historical'),
            ),
            totalCount: 41,
            hasMore: true,
          );
        }
        return AttractionSearchPage(
          attractions: [_place(id: 'landmark-40', category: 'historical')],
          totalCount: 41,
          hasMore: false,
        );
      },
    );

    await controller.load(city: 'Rome');
    await controller.loadMore();

    expect(requestedOffsets, [0, 40]);
    expect(controller.results, hasLength(41));
    expect(controller.hasMore, isFalse);
    controller.dispose();
  });

  test('chips filter allowed places and exclude generic records', () async {
    final controller = AttractionsController(
      searchAttractions: ({
        required String city,
        String? country,
        String? language,
      }) async =>
          [
        _place(id: 'landmark', category: 'historical'),
        _place(id: 'beach', category: 'beach'),
        _place(id: 'cafe', category: 'cafe'),
        _place(id: 'market', category: 'shopping'),
      ],
    );

    await controller.load(city: 'Tripoli', country: 'ly');
    expect(
      controller.results.map((place) => place.id),
      ['landmark', 'beach'],
    );
    controller.setCategory('beach');
    expect(controller.results.map((place) => place.id), ['beach']);
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

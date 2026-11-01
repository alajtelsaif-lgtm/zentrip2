import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/models/flight_model.dart';

void main() {
  test('airport registry supplies canonical Libya city codes', () {
    expect(AirportOption.byCode('MJI')?.city, 'Tripoli');
    expect(AirportOption.byCity(' tripoli ')?.code, 'MJI');
    expect(AirportOption.byCode('MRA')?.city, 'Misrata');
    expect(AirportOption.byCode('BEN')?.city, 'Benghazi');
    expect(AirportOption.byCode('SEB')?.city, 'Sebha');
    expect(AirportOption.byCode('MIP'), isNull);
  });

  test('airport search matches partial city, airport, and code values', () {
    expect(AirportOption.supported.where((airport) => airport.matches('mis')),
        contains(AirportOption.byCode('MRA')));
    expect(AirportOption.supported.where((airport) => airport.matches('MJI')),
        contains(AirportOption.byCode('MJI')));
    expect(
        AirportOption.supported
            .where((airport) => airport.matches('western libya')),
        contains(AirportOption.byCode('MJI')));
  });

  test('nearest supported airport maps current coordinates to its city', () {
    expect(AirportOption.nearestTo(32.3250, 15.0610)?.code, 'MRA');
    expect(AirportOption.nearestTo(30.1219, 31.4056)?.code, 'CAI');
    expect(AirportOption.nearestTo(91, 0), isNull);
    expect(AirportOption.nearestTo(0, 0), isNull);
  });

  test('global directory parses codes coordinates and landmark airport', () {
    final result = AirportSearchResult.fromJson({
      'query_type': 'landmark',
      'total': 1,
      'airports': [
        {
          'code': 'CDG',
          'icao_code': 'LFPG',
          'city': 'Paris',
          'airport_name': 'Charles de Gaulle Airport',
          'country': 'France',
          'latitude': 49.0097,
          'longitude': 2.5479,
          'is_major': true,
          'scheduled_service': true,
        },
      ],
      'landmarks': [
        {
          'name': 'Eiffel Tower',
          'highlight_category': 'Architecture',
          'image_url': 'https://commons.wikimedia.org/example.jpg',
          'nearest_airport': {
            'code': 'CDG',
            'icao_code': 'LFPG',
            'city': 'Paris',
            'country': 'France',
            'distance_km': 26.4,
          },
        },
      ],
    });
    expect(result.airports.single.icaoCode, 'LFPG');
    expect(result.airports.single.isMajor, isTrue);
    expect(result.airports.single.latitude, 49.0097);
    expect(result.landmarks.single.nearestAirport?.code, 'CDG');
    expect(result.landmarks.single.nearestAirport?.distanceKm, 26.4);
    expect(result.landmarks.single.category, 'Architecture');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/models/hotel_destination_suggestion.dart';

void main() {
  test('parses city country code and place ID from backend suggestions', () {
    final suggestion = HotelDestinationSuggestion.fromJson({
      'name': 'New York',
      'country_name': 'United States',
      'country_code': 'US',
      'place_id': 'geoapify-new-york',
      'type': 'city',
      'latitude': 40.7127281,
      'longitude': -74.0060152,
    });

    expect(suggestion.name, 'New York');
    expect(suggestion.countryCode, 'US');
    expect(suggestion.placeId, 'geoapify-new-york');
    expect(suggestion.latitude, 40.7127281);
    expect(suggestion.longitude, -74.0060152);
  });

  test('keeps provider-specific fields optional for catalog suggestions', () {
    final suggestion = HotelDestinationSuggestion.fromJson({
      'name': 'London',
      'country_name': 'United Kingdom',
      'type': 'city',
    });

    expect(suggestion.countryCode, isNull);
    expect(suggestion.placeId, isNull);
  });
}

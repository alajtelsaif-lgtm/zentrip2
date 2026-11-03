import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/models/hotel_model.dart';
import 'package:zentrip/models/mock_data_service.dart';

void main() {
  test('hotel photos keep the cover first and include gallery images', () {
    final hotel = HotelModel.fromJson({
      'id': 'partner-1',
      'name': 'Al-Masa Hotel',
      'city': 'Tripoli',
      'country': 'Libya',
      'address': 'Central Tripoli',
      'rating': 4.5,
      'review_count': 12,
      'price_per_night': 100,
      'image_url': 'https://example.com/cover.jpg',
      'gallery_images': [
        'https://example.com/room.jpg',
        'https://example.com/lobby.jpg',
      ],
      'amenities': [],
      'description': '',
      'stars': 0,
    });

    expect(
      hotel.photos,
      [
        'https://example.com/cover.jpg',
        'https://example.com/room.jpg',
        'https://example.com/lobby.jpg',
      ],
    );
  });

  test('partner hotel inventory fields parse from nested attributes', () {
    final hotel = HotelModel.fromJson({
      'id': 'partner-44',
      'title': 'Al-Masa Hotel',
      'city': 'Tripoli',
      'country': 'Libya',
      'price': '120.00',
      'image_url': 'https://example.com/cover.jpg',
      'active': true,
      'attributes': {
        'location_input': '32.8872, 13.1913',
        'room_types': [
          {
            'code': 'standard',
            'name': 'Standard Room',
            'price_per_night': 120,
            'rooms_available': 12,
          },
        ],
        'available_rooms': 15,
        'availability_schedule': [
          {'available': true},
        ],
        'gallery_images': ['https://example.com/room.jpg'],
      },
    });

    expect(hotel.latitude, 32.8872);
    expect(hotel.longitude, 13.1913);
    expect(hotel.pricePerNight, 120);
    expect(hotel.roomTypes.single['rooms_available'], 12);
    expect(hotel.availableRooms, 15);
    expect(hotel.availabilitySchedule.single['available'], isTrue);
    expect(hotel.galleryImages, ['https://example.com/room.jpg']);
    expect(hotel.isActive, isTrue);
  });

  test('Duffel room offers and rating provenance are retained', () {
    final hotel = HotelModel.fromJson({
      'id': 'duffel-srr-example',
      'source': 'duffel',
      'provider_search_result_id': 'srr_example',
      'rating_source': 'duffel',
      'review_score': 8.6,
      'room_types': [
        {
          'name': 'Double room',
          'rates': [
            {
              'id': 'rate-1',
              'name': 'Breakfast included',
              'total_amount': '400.00',
              'total_currency': 'GBP',
            },
          ],
        },
      ],
      'offers': [
        {
          'id': 'rate-1',
          'room_name': 'Double room',
          'name': 'Breakfast included',
          'total_amount': '400.00',
          'total_currency': 'GBP',
        },
      ],
    });

    expect(hotel.ratingSource, 'duffel');
    expect(hotel.reviewScore, 8.6);
    expect(hotel.hasComparisonPrice, isFalse);
    expect(hotel.roomTypes.single['rates'], hasLength(1));
    expect(hotel.offers.single['total_currency'], 'GBP');

    final updated = hotel.withRoomOffers(
      roomTypes: hotel.roomTypes,
      offers: hotel.offers,
      pricePerNight: 130,
      priceCurrencyCode: 'GBP',
    );
    expect(updated.providerSearchResultId, 'srr_example');
    expect(updated.offers, hasLength(1));
    expect(updated.pricePerNight, 130);
    expect(updated.priceCurrencyCode, 'GBP');
    expect(updated.hasComparisonPrice, isTrue);
  });

  test('hotel location coordinates parse from a Google Maps query URL', () {
    final hotel = HotelModel.fromJson({
      'id': 'hotel-url-coordinates',
      'city': 'Tripoli',
      'location_input': 'https://maps.google.com/?q=32.8872%2C13.1913',
    });

    expect(hotel.latitude, 32.8872);
    expect(hotel.longitude, 13.1913);
  });

  test('hotel schema and pricing breakdown match the detail view contract', () {
    final hotel = HotelModel.fromJson({
      'id': 'partner-1',
      'name': 'Grand Horizon Hotel',
      'location_name': 'City Center, Misrata',
      'google_maps_url': 'https://maps.google.com/?q=32.3754%2C15.0925',
      'place_id': 'ChIJexampleplaceid12345',
      'google_rating': 4.9,
      'google_review_count': 8240,
      'amenities': ['Gym', 'Wi-Fi', 'Restaurant', 'Spa', 'Pool'],
      'description': 'A welcoming stay in Misrata.',
      'price_per_night': 420,
      'tax_and_fees_percentage': 12,
      'available_rooms': 15,
    });

    final breakdown = hotel.pricingFor(3);

    expect(hotel.locationName, 'City Center, Misrata');
    expect(hotel.googleMapsUrl, contains('maps.google.com'));
    expect(hotel.placeId, 'ChIJexampleplaceid12345');
    expect(hotel.googleRating, 4.9);
    expect(hotel.googleReviewCount, 8240);
    expect(breakdown.subtotal, 1260);
    expect(breakdown.taxAndFees, 151.2);
    expect(breakdown.totalPrice, 1411.2);
    final multipleRoomBreakdown = hotel.pricingFor(3, rooms: 2);
    expect(multipleRoomBreakdown.subtotal, 2520);
    expect(multipleRoomBreakdown.taxAndFees, 302.4);
    expect(multipleRoomBreakdown.totalPrice, 2822.4);
    expect(hotel.availableRooms, 15);
  });

  test('Google rating fields parse numeric strings from API JSON', () {
    final rootFields = HotelModel.fromJson({
      'id': 'partner-42',
      'name': 'Al-Masa Hotel',
      'city': 'Tripoli',
      'country': 'Libya',
      'google_rating': '4.9',
      'google_review_count': '8240',
      'amenities': const <String>[],
      'description': '',
    });
    final nestedFields = HotelModel.fromJson({
      'id': 'partner-43',
      'name': 'Al-Masa Hotel',
      'city': 'Tripoli',
      'country': 'Libya',
      'attributes': '{"google_rating":"4.9","google_review_count":"8240"}',
    });

    expect(rootFields.googleRating, 4.9);
    expect(rootFields.googleReviewCount, 8240);
    expect(nestedFields.googleRating, 4.9);
    expect(nestedFields.googleReviewCount, 8240);
    expect(
        '(${nestedFields.reviewCount}) ${nestedFields.rating.toStringAsFixed(1)}',
        '(8240) 4.9');
  });

  test('Hotelbeds hotel data uses shared offers without partner ownership',
      () {
    final hotel = HotelModel.fromJson({
      'id': 'hotelbeds-123',
      'source': 'hotelbeds',
      'provider_accommodation_id': '123',
      'name': 'Example London Hotel',
      'city': 'London',
      'country': 'GB',
      'location_name': '100 Clifton Street',
      'rating': 4.4,
      'review_count': 336,
      'price_per_night': '200.00',
      'price_currency': 'GBP',
      'tax_and_fees_percentage': 0,
      'available_rooms': 3,
      'availability_known': true,
      'image_url': 'https://example.com/hotel.jpg',
      'gallery_images': ['https://example.com/hotel.jpg'],
      'amenities': ['Wi-Fi'],
      'offers': [
        {
          'room_name': 'Double Room',
          'price_per_night': 100,
          'stay_total': 200,
          'currency': 'GBP',
        },
      ],
    });

    expect(hotel.isHotelbedsOffer, isTrue);
    expect(hotel.source, 'hotelbeds');
    expect(hotel.providerAccommodationId, '123');
    expect(hotel.priceCurrencyCode, 'GBP');
    expect(hotel.pricePerNight, 200);
    expect(hotel.availableRooms, 3);
    expect(hotel.availabilityKnown, isTrue);
    expect(hotel.offers.single['stay_total'], 200);
    expect(hotel.googleRating, 4.4);
    expect(hotel.photos, ['https://example.com/hotel.jpg']);
  });

  test('malformed optional hotel data safely falls back to empty values', () {
    final hotel = HotelModel.fromJson({
      'id': 'partner-bad-attributes',
      'name': 'Safe Hotel',
      'attributes': 'not valid json',
      'gallery_images': 'not a list',
      'amenities': null,
      'price_per_night': 'NaN',
      'latitude': double.nan,
    });

    expect(hotel.name, 'Safe Hotel');
    expect(hotel.galleryImages, isEmpty);
    expect(hotel.amenities, isEmpty);
    expect(hotel.pricePerNight.isFinite, isTrue);
    expect(hotel.latitude, isNull);
  });

  test('visible mock hotels expose the unified hotel listing fields', () {
    final hotel = MockDataService.hotels(city: 'Misrata').first;

    expect(hotel.id, 'htl-1');
    expect(hotel.name, 'Grand Horizon Hotel');
    expect(hotel.locationName, 'City Center, Misrata');
    expect(hotel.googleRating, 4.9);
    expect(hotel.googleReviewCount, 8240);
    expect(hotel.hasGoogleRating, isTrue);
    expect(hotel.amenities, containsAll(['Gym', 'Wi-Fi', 'Restaurant']));
    expect(hotel.taxAndFeesPercentage, 12);
  });
}

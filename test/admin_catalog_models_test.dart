import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/models/attraction_model.dart';
import 'package:zentrip/models/travel_package_model.dart';

void main() {
  test('monument model maps admin fields onto the customer attraction schema',
      () {
    final monument = AttractionModel.fromJson({
      'id': 'monument-1',
      'title': 'Leptis Magna',
      'location': 'Khoms, Libya',
      'category_tag': 'Historical',
      'category': 'landmark',
      'rating': '4.9',
      'review_count': 3120,
      'description': 'A Roman city',
      'working_hours': '8:00 AM - 5:00 PM',
      'best_time_to_visit': 'Oct - Apr',
      'entry_fee': '5',
      'tags': ['Theatre', 'Market'],
      'image_url': 'https://example.com/leptis.jpg',
    });

    expect(monument.title, 'Leptis Magna');
    expect(monument.location, 'Khoms, Libya');
    expect(monument.categoryLabel, 'Historical');
    expect(monument.workingHours, '8:00 AM - 5:00 PM');
    expect(monument.entryFee, 5);
    expect(monument.toJson()['tags'], ['Theatre', 'Market']);
  });

  test('offer total is flight plus hotel rate multiplied by nights', () {
    final offer = TravelPackage.fromJson({
      'id': 'istanbul-dream',
      'title': 'Istanbul Dream',
      'location': 'Istanbul',
      'country': 'Turkey',
      'description': 'Explore the city',
      'image_url': '',
      'price_per_person': 1290,
      'flight_price_per_person': 420,
      'hotel_price_per_night': 95,
      'duration_nights': 7,
      'rating': 4.8,
      'review_count': 2340,
      'is_featured': 1,
      'badge': 'Featured Offer',
      'highlights': ['Grand Bazaar', 'Hagia Sophia'],
    });

    expect(offer.totalPricePerPerson, 1085);
    expect(offer.durationNights, 7);
    expect(offer.isFeatured, isTrue);
    expect(offer.badge, 'Featured Offer');
    expect(offer.toJson()['highlights'], ['Grand Bazaar', 'Hagia Sophia']);
  });

  test('offer maps its selected partner flight and airline data', () {
    final offer = TravelPackage.fromJson({
      'id': 'tripoli-escape',
      'title': 'Tripoli Escape',
      'location': 'Tripoli',
      'country': 'Libya',
      'description': 'A package stay',
      'flight_listing_id': 25,
      'flight_price_per_person': 175,
      'hotel_price_per_night': 80,
      'duration_nights': 3,
      'flight': {
        'id': 'partner-25',
        'partner_listing_id': 25,
        'airline': 'Libyan Wings',
        'flight_number': 'YL25',
        'origin_city': 'Misrata',
        'origin_code': 'MRA',
        'destination_city': 'Tripoli',
        'destination_code': 'MJI',
        'departure_time': '2035-11-20T10:00:00Z',
        'arrival_time': '2035-11-20T11:00:00Z',
        'duration_minutes': 60,
        'seats_available': 20,
        'economy_price': 175,
        'status': 'published',
        'is_active': true,
      },
    });

    expect(offer.flightListingId, 25);
    expect(offer.flight?.airline, 'Libyan Wings');
    expect(offer.flight?.flightNumber, 'YL25');
    expect(offer.flight?.originCode, 'MRA');
    expect(offer.flight?.destinationCode, 'MJI');
    expect(offer.totalPricePerPerson, 415);
    expect(offer.toJson()['flight_listing_id'], 25);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/models/admin_dashboard_model.dart';
import 'package:zentrip/models/partner_dashboard_model.dart';
import 'package:zentrip/models/travel_package_model.dart';
import 'package:zentrip/models/user_model.dart';

void main() {
  group('AdminDashboardData', () {
    test('parses dashboard summary and recent reservation data', () {
      final data = AdminDashboardData.fromJson({
        'summary': {
          'customer_count': 15,
          'new_customers_30d': 4,
          'total_user_count': 24,
          'partner_count': 6,
          'active_partner_listing_count': 19,
          'reservation_count': 21,
          'flight_count': 5,
          'service_booking_count': 11,
          'transfer_count': 5,
          'booked_value': '1240.50',
        },
        'recent_reservations': [
          {
            'id': 'booking-9',
            'type': 'hotel',
            'title': 'Cairo Hotel',
            'customer_name': 'Mina',
            'reservation_date': '2026-10-15T12:00:00',
            'amount': 250,
            'status': 'confirmed',
          },
        ],
      });

      expect(data.customerCount, 15);
      expect(data.totalUserCount, 24);
      expect(data.partnerCount, 6);
      expect(data.activePartnerListingCount, 19);
      expect(data.bookedValue, 1240.5);
      expect(data.recentReservations.single.id, 'booking-9');
      expect(data.recentReservations.single.reservationDate,
          DateTime(2026, 10, 15, 12));
    });
  });

  test('admin role is parsed without granting it to legacy users', () {
    final admin = UserModel.fromJson({
      'id': 1,
      'name': 'Admin',
      'email': 'admin@example.com',
      'role': 'admin',
    });
    final legacyCustomer = UserModel.fromJson({
      'id': 2,
      'name': 'Customer',
      'email': 'customer@example.com',
    });

    expect(admin.isAdmin, isTrue);
    expect(legacyCustomer.role, 'customer');
    expect(legacyCustomer.isAdmin, isFalse);
  });

  test('partner data carries company-scoped listing and guest details', () {
    final dashboard = PartnerDashboardData.fromJson({
      'company': {'name': 'Libyan Wings', 'service_type': 'airline'},
      'summary': {
        'listing_count': 3,
        'active_listing_count': 2,
        'reservation_count': 7,
        'customer_count': 5,
        'booked_value': '1200.50',
      },
      'recent_reservations': [
        {
          'id': 'flight-9',
          'type': 'flight',
          'title': 'Tripoli to Cairo',
          'customer_name': 'Mina',
          'customer_email': 'mina@example.com',
          'customer_phone': '123456789',
          'partner_listing_id': 44,
          'reservation_date': '2026-10-15T12:00:00',
          'amount': 250,
          'status': 'upcoming',
        },
      ],
    });

    expect(dashboard.companyName, 'Libyan Wings');
    expect(dashboard.listingCount, 3);
    expect(dashboard.bookedValue, 1200.5);
    expect(
        dashboard.recentReservations.single.customerEmail, 'mina@example.com');
    expect(dashboard.recentReservations.single.listingId, 44);
  });

  test('partner dashboard ignores missing or null-heavy database fields', () {
    final dashboard = PartnerDashboardData.fromJson({
      'company': null,
      'summary': {'listing_count': null, 'booked_value': 'NaN'},
      'recent_reservations': [
        null,
        'invalid row',
        {
          'id': null,
          'title': null,
          'customer_email': null,
          'customer_phone': null,
          'amount': null,
          'reservation_date': null,
        },
      ],
    });
    final listing = PartnerListing.fromJson({
      'id': 11,
      'type': 'flight',
      'title': null,
      'city': null,
      'country': null,
      'attributes': {
        'flight_number': null,
        'meal_plan': 'Breakfast included',
        'features': [null, 'Wi-Fi', null],
        'contact_email': 'private@example.com',
      },
    });
    final malformedListing = PartnerListing.fromJson({
      'type': 'hotel',
      'attributes': '{not-json',
    });

    expect(dashboard.companyName, 'Partner account');
    expect(dashboard.listingCount, 0);
    expect(dashboard.bookedValue, 0);
    expect(dashboard.recentReservations, hasLength(1));
    expect(dashboard.recentReservations.single.customerEmail, isEmpty);
    expect(listing.locationName, isEmpty);
    expect(
      listing.nonEmptyAttributes.keys,
      containsAll(['meal_plan', 'features', 'contact_email']),
    );
    expect(listing.nonEmptyAttributes.keys, isNot(contains('flight_number')));
    expect(malformedListing.attributes, isEmpty);
  });

  test('partner listing preserves ownership fields and JSON attributes', () {
    final listing = PartnerListing.fromJson({
      'id': 6,
      'type': 'hotel',
      'title': 'Sea View',
      'city': 'Tripoli',
      'country': 'Libya',
      'image_url': 'https://example.com/hotel.jpg',
      'price': '84.50',
      'active': true,
      'attributes':
          '{"listing_code":"HTL-000006","stars":4,"amenities":["wifi"]}',
    });

    expect(listing.id, 6);
    expect(listing.price, 84.5);
    expect(listing.listingCode, 'HTL-000006');
    expect(listing.attributes['stars'], 4);
    expect(listing.toJson()['type'], 'hotel');
  });

  test('partner travel package listing id survives model serialization', () {
    final package = TravelPackage.fromJson({
      'id': 'partner-19',
      'title': 'Coastal Escape',
      'location': 'Tripoli',
      'country': 'Libya',
      'description': 'A short getaway',
      'image_url': 'https://example.com/package.jpg',
      'flight_price_per_person': 220,
      'hotel_price_per_night': 0,
      'duration_nights': 1,
      'partner_listing_id': 19,
    });

    expect(package.partnerListingId, 19);
    expect(package.toJson()['partner_listing_id'], 19);
    expect(package.totalPricePerPerson, 220);
  });
}

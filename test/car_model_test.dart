import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/models/car_model.dart';

void main() {
  test('parses partner vehicle fields from listing attributes', () {
    final car = CarModel.fromJson({
      'id': 'partner-22',
      'partner_listing_id': 22,
      'title': 'Kia Picanto 2023',
      'price': '28.00',
      'city': 'Misrata',
      'attributes': {
        'brand': 'Kia',
        'model': 'Picanto',
        'year': 2023,
        'rating': '4.1',
        'fuel_type': 'gasoline',
        'transmission': 'manual',
        'luggage_capacity': 2,
        'seats': 4,
        'has_ac': true,
        'features': ['Compact Size', 'Easy Parking', 'Bluetooth'],
        'insurance_fee': 4,
        'service_fee': 10,
        'available_vehicles': 3,
        'latitude': 32.3754,
        'longitude': 15.0925,
      },
    });

    expect(car.id, 'partner-22');
    expect(car.modelName, 'Kia Picanto 2023');
    expect(car.rating, 4.1);
    expect(car.bags, 2);
    expect(car.seats, 4);
    expect(car.features, ['Compact Size', 'Easy Parking', 'Bluetooth']);
    expect(car.availableVehicles, 3);
    expect(car.latitude, 32.3754);
  });

  test('calculates total rental price for the selected duration', () {
    const car = CarModel(
      id: 'car-1',
      brand: 'Kia',
      model: 'Picanto',
      category: 'economy',
      year: 2023,
      pricePerDay: 28,
      seats: 4,
      transmission: 'manual',
      fuelType: 'gasoline',
      features: [],
      rating: 4.1,
      pickupLocation: 'Misrata',
      insuranceFee: 4,
      serviceFee: 10,
    );

    final breakdown = car.pricingForDays(3);
    expect(breakdown.subtotal, 84);
    expect(breakdown.numberOfDays, 3);
    expect(breakdown.totalPrice, 98);
  });
}

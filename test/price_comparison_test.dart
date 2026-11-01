import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/core/services/price_comparison.dart';
import 'package:zentrip/core/utils/money_format.dart';
import 'package:zentrip/features/flight_booking/logic/flight_controller.dart';
import 'package:zentrip/features/hotel_booking/logic/hotel_controller.dart';
import 'package:zentrip/models/exchange_rates.dart';
import 'package:zentrip/models/flight_model.dart';
import 'package:zentrip/models/hotel_model.dart';

final now = DateTime.utc(2026, 11, 1, 12);

ExchangeRates rates({DateTime? date}) => ExchangeRates(
      rates: {
        'EUR': ExchangeRate(0.5, date ?? now),
        'GBP': ExchangeRate(0.25, date ?? now),
        'LYD': ExchangeRate(5, date ?? now),
      },
      fetchedAt: now,
    );

PriceComparison comparison({Future<ExchangeRates> Function()? load}) =>
    PriceComparison(loadRates: load ?? () async => rates(), clock: () => now);

FlightModel flight(String id, double price, String currency,
        {bool total = false, double? business}) =>
    FlightModel.fromJson({
      'id': id,
      'source': total ? 'duffel' : 'partner',
      'economy_price': price,
      'business_price': business,
      'price_currency': currency,
      'price_is_total': total,
      'duration_minutes': price.toInt(),
    });

HotelModel hotel(String id, double price, String currency) =>
    HotelModel.fromJson({
      'id': id,
      'price_per_night': price,
      'price_currency': currency,
      'source': currency == 'USD' ? 'partner' : 'duffel',
    });

FlightSearchParams flightParams(
        {bool roundTrip = false, String cabin = 'economy'}) =>
    FlightSearchParams(
      originCode: 'MJI',
      originCity: 'Misrata',
      destinationCode: 'TUN',
      destinationCity: 'Tunis',
      departureDate: now,
      passengers: 2,
      seatClass: cabin,
      isRoundTrip: roundTrip,
    );

void main() {
  test('currency display retains appropriate minor units', () {
    expect(formatProviderMoney(75.25, 'EUR'), 'EUR 75.25');
    expect(formatProviderMoney(75.251, 'TND'), 'TND 75.251');
    expect(formatProviderMoney(75.251, 'LYD'), 'LYD 75.251');
    expect(formatProviderMoney(100, 'JPY'), 'JPY 100');
  });
  test('USD pivot conversion, identity and full-precision comparison',
      () async {
    final c = comparison();
    await c.refresh();
    expect(c.convert(100, 'EUR'), 200);
    c.setCurrency('GBP');
    expect(c.convert(100, 'EUR'), 50);
    expect(c.convert(100, 'GBP'), 100);
    expect(c.convert(100, 'XXX'), isNull);
    expect(c.convert(double.nan, 'GBP'), isNull);
    expect(c.convert(-1, 'GBP'), isNull);
    expect(c.compare(null, 1, descending: true), greaterThan(0));
    expect(c.compare(1, null), lessThan(0));
    expect(c.compare(100.001, 100.002), lessThan(0));
  });

  test(
      'old rates warned after four days, expired after seven, identity survives',
      () async {
    for (final days in [4, 5, 8]) {
      final c = comparison(
          load: () async => rates(date: now.subtract(Duration(days: days))));
      await c.refresh();
      expect(c.isStale(['EUR']), days > 4 && days <= 7);
      expect(c.convert(10, 'EUR'), days > 7 ? isNull : 20);
      expect(c.convert(10, 'USD'), 10);
    }
    final future = comparison(
        load: () async => rates(date: now.add(const Duration(days: 1))));
    await future.refresh();
    expect(future.convert(10, 'EUR'), isNull);
  });

  test('malformed rates rejected and wrong pivot fails explicitly', () {
    expect(
        () => ExchangeRates.fromJson({'base': 'EUR'}), throwsFormatException);
    final parsed = ExchangeRates.fromJson({
      'base': 'USD',
      'fetched_at': now.toIso8601String(),
      'rates': [
        for (final value in ['NaN', 'Infinity', '-1', '0', 'bad'])
          {'quote': 'EUR', 'rate': value, 'date': '2026-11-01'},
        {'quote': 'GBP', 'rate': '0.25', 'date': 'bad'},
        {'quote': 'LYD', 'rate': '5', 'date': '2026-11-01'},
      ],
    });
    expect(parsed.rates.keys, ['LYD']);
  });

  test(
      'refresh failure preserves dated rates, coalesces work and retry recovers',
      () async {
    final pending = Completer<ExchangeRates>();
    var calls = 0;
    var fail = false;
    final c = comparison(load: () {
      calls++;
      if (fail) throw StateError('offline');
      return calls == 1 ? pending.future : Future.value(rates());
    });
    final first = c.refresh();
    await c.refresh();
    expect(calls, 1);
    pending.complete(rates());
    await first;
    fail = true;
    await c.refresh();
    expect(c.failed, isTrue);
    expect(c.convert(10, 'EUR'), 20);
    fail = false;
    await c.refresh();
    expect(c.failed, isFalse);
    c.dispose();
  });

  test(
      'flight cheapest and total-budget use converted traveler totals and cabin',
      () async {
    final original = [
      flight('usd', 90, 'USD', business: 150),
      flight('eur', 60, 'EUR', total: true),
      flight('unknown', 1, 'XXX', total: true),
    ];
    final c = FlightController(
        comparison: comparison(), searchFlights: (_) async => original);
    await c.search(flightParams());
    expect(c.results.map((f) => f.id), ['eur', 'usd', 'unknown']);
    expect(c.comparisonPrice(original[0]), 180);
    expect(c.comparisonPrice(original[1]), 120);
    c.setMaxBudget(150);
    expect(c.results.map((f) => f.id), ['eur']);
    c.comparison.setCurrency('EUR');
    expect(c.results.map((f) => f.id), ['eur', 'usd']);
    c.setMaxBudget(null);
    await c.search(flightParams(cabin: 'business'));
    expect(c.comparisonPrice(original[0]), 150); // 300 USD -> 150 EUR
    expect(original[0].economyPrice, 90);
    expect(original[1].economyPrice, 60);
    expect(original[1].priceCurrencyCode, 'EUR');
    c.setSort(FlightSort.fastest);
    expect(c.results.first.id, 'unknown');
  });

  test('outbound-only Partner fares cannot rank against round-trip totals',
      () async {
    final partner = flight('partner', 10, 'USD');
    final duffel = flight('duffel', 80, 'EUR', total: true);
    final c = FlightController(
        comparison: comparison(),
        searchFlights: (_) async => [partner, duffel]);
    await c.search(flightParams(roundTrip: true));
    expect(c.comparisonPrice(partner), isNull);
    expect(c.results.first, duffel);
    c.setMaxBudget(200);
    expect(c.results, [duffel]);
    expect(partner.economyPrice, 10);
  });

  test('missing requested cabin is not replaced with economy price', () {
    final f = flight('partner', 10, 'USD');
    expect(f.comparisonTotal(passengers: 2, seatClass: 'first'), isNull);
    expect(f.comparisonTotal(passengers: 0, seatClass: 'economy'), isNull);
  });

  test('invalid hotel amounts do not become comparable zero prices', () {
    for (final amount in [null, 'bad', 'NaN', 'Infinity', -10]) {
      final h = HotelModel.fromJson({'price_per_night': amount});
      expect(h.comparisonNightlyPrice, isNull);
      expect(h.withDistanceMeters(100).comparisonNightlyPrice, isNull);
    }
    expect(
        HotelModel.fromJson({'price_per_night': 0}).comparisonNightlyPrice, 0);
  });

  test('hotel sort/filter use selected currency with exact budget boundaries',
      () async {
    final original = [
      hotel('budget', 49, 'EUR'), // 98 USD
      hotel('mid-start', 50, 'EUR'), // 100 USD
      hotel('mid-end', 249.999, 'USD'),
      hotel('luxury', 125, 'EUR'), // 250 USD
      hotel('unknown', 1, 'XXX'),
    ];
    final c = HotelController(
        comparison: comparison(), searchHotels: (_) async => original);
    await c.search(HotelSearchParams(
        city: 'Tunis',
        checkIn: now,
        checkOut: now.add(const Duration(days: 2))));
    c.setSort(HotelSort.priceHigh);
    expect(c.results.map((h) => h.id),
        ['luxury', 'mid-end', 'mid-start', 'budget', 'unknown']);
    c.setSort(HotelSort.priceLow);
    expect(c.results.first.id, 'budget');
    c.setFilter(HotelFilter.budget);
    expect(c.results.map((h) => h.id), ['budget']);
    c.setFilter(HotelFilter.midRange);
    expect(c.results.map((h) => h.id), ['mid-start', 'mid-end']);
    c.setFilter(HotelFilter.luxury);
    expect(c.results.map((h) => h.id), ['luxury']);
    c.comparison.setCurrency('EUR');
    expect(c.results, isEmpty);
    c.setFilter(HotelFilter.all);
    expect(c.results.length, 5);
    expect(c.unpricedCount, 1);
    expect(original[0].pricePerNight, 49);
    expect(original[0].priceCurrencyCode, 'EUR');
  });

  test('late rates reapply filters without replacing provider offers',
      () async {
    final pending = Completer<ExchangeRates>();
    final c = HotelController(
      comparison: comparison(load: () => pending.future),
      searchHotels: (_) async =>
          [hotel('eur', 20, 'EUR'), hotel('usd', 80, 'USD')],
    );
    c.setFilter(HotelFilter.budget);
    await c.search(HotelSearchParams(
        city: 'Tunis',
        checkIn: now,
        checkOut: now.add(const Duration(days: 1))));
    expect(c.results.map((h) => h.id), ['usd']);
    pending.complete(rates());
    await Future<void>.delayed(Duration.zero);
    expect(c.results.map((h) => h.id).toSet(), {'eur', 'usd'});
  });

  test('out-of-order searches do not replace current results', () async {
    final first = Completer<List<FlightModel>>();
    var calls = 0;
    final c = FlightController(
        comparison: comparison(),
        searchFlights: (_) => ++calls == 1
            ? first.future
            : Future.value([flight('latest', 10, 'USD')]));
    final earlier = c.search(flightParams());
    await c.search(flightParams());
    first.complete([flight('old', 1, 'USD')]);
    await earlier;
    expect(c.results.single.id, 'latest');
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentrip/core/services/api_service.dart';
import 'package:zentrip/core/services/user_settings_sync.dart';
import 'package:zentrip/features/favorites/logic/favorites_controller.dart';
import 'package:zentrip/features/price_alerts/logic/price_alerts_store.dart';
import 'package:zentrip/models/user_model.dart';

/// Minimal in-memory stand-in for the saved-data endpoints.
class _FakeServer implements HttpClientAdapter {
  final favorites = <Map<String, dynamic>>[];
  final alerts = <Map<String, dynamic>>[];
  Map<String, dynamic> settings = {};
  final calls = <String>[];
  int _nextAlertId = 100;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = options.data is Map
        ? Map<String, dynamic>.from(options.data as Map)
        : <String, dynamic>{};
    final path = options.uri.path.replaceFirst(RegExp(r'^.*/api'), '');
    calls.add('${options.method} $path');
    Object? reply;
    switch ('${options.method} $path') {
      case 'GET /favorites':
        reply = {'favorites': favorites};
      case 'POST /favorites':
        favorites.removeWhere((f) => f['id'] == body['id']);
        favorites.insert(0, body);
        reply = {'favorite': body};
      case 'DELETE /favorites':
        favorites.removeWhere(
            (f) => f['id'] == options.uri.queryParameters['id']);
        return ResponseBody.fromString('', 204);
      case 'GET /price-alerts':
        reply = {'price_alerts': alerts};
      case 'POST /price-alerts':
        final alert = {
          ...body,
          'id': _nextAlertId++,
          'created_at': '2035-01-01T00:00:00Z',
        };
        alerts.insert(0, alert);
        reply = {'price_alert': alert};
      case 'GET /settings':
        reply = {'settings': settings};
      case 'PUT /settings':
        settings = {...settings, ...body};
        reply = {'settings': settings};
      default:
        if (options.method == 'DELETE' && path.startsWith('/price-alerts/')) {
          final id = int.parse(path.split('/').last);
          alerts.removeWhere((a) => a['id'] == id);
          return ResponseBody.fromString('', 204);
        }
        return ResponseBody.fromString('{"message":"not found"}', 404,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType]
            });
    }
    return ResponseBody.fromString(jsonEncode(reply), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _FakeServer server;

  setUp(() {
    server = _FakeServer();
    ApiService.instance.httpClientAdapterForTesting = server;
    ApiService.instance.currentUser = const UserModel(
        id: 7, name: 'Sync user', email: 'sync@example.com', phone: '');
  });

  tearDown(() {
    ApiService.instance.currentUser = null;
    FavoritesController.instance.clear();
    PriceAlertsStore.instance.clear();
  });

  test('device favorites are uploaded once, then the server list is used',
      () async {
    const local = FavoritePlace(
        id: 'hotel:1', title: 'Old device hotel', subtitle: 'Tripoli',
        type: 'hotel');
    SharedPreferences.setMockInitialValues({
      'favorites_v2_sync@example.com': [jsonEncode(local.toJson())],
    });
    server.favorites.add({
      'id': 'attraction:2', 'title': 'Saved on phone B', 'subtitle': '',
      'type': 'attraction',
    });

    await FavoritesController.instance.load();

    final ids = FavoritesController.instance.all.map((f) => f.id).toSet();
    expect(ids, {'hotel:1', 'attraction:2'});
    expect(server.favorites.map((f) => f['id']), contains('hotel:1'));

    // Removed on another device: the next load follows the server.
    server.favorites.removeWhere((f) => f['id'] == 'hotel:1');
    await FavoritesController.instance.load();
    expect(FavoritesController.instance.all.map((f) => f.id), ['attraction:2']);
  });

  test('toggling a favorite saves and deletes it on the server', () async {
    SharedPreferences.setMockInitialValues({});
    await FavoritesController.instance.load();
    const place = FavoritePlace(
        id: 'cafe:9', title: 'Cafe', subtitle: 'Old city', type: 'cafe');

    await FavoritesController.instance.toggle(place);
    expect(server.favorites.single['id'], 'cafe:9');

    await FavoritesController.instance.toggle(place);
    expect(server.favorites, isEmpty);
  });

  test('price alerts use the server id and are removed on the server',
      () async {
    SharedPreferences.setMockInitialValues({});
    await PriceAlertsStore.instance.load();

    await PriceAlertsStore.instance.track(
      originCode: 'TIP',
      destinationCode: 'IST',
      departureDate: DateTime(2035, 12, 1),
      priceUsd: 250,
    );
    expect(server.alerts.single['departure_date'], '2035-12-01');
    expect(PriceAlertsStore.instance.all.single.id, '100');

    await PriceAlertsStore.instance.remove('100');
    expect(server.alerts, isEmpty);
    expect(server.calls, contains('DELETE /price-alerts/100'));
  });

  test('guests never call the saved-data endpoints', () async {
    ApiService.instance.currentUser = null;
    SharedPreferences.setMockInitialValues({});
    await FavoritesController.instance.load();
    await FavoritesController.instance.toggle(const FavoritePlace(
        id: 'x', title: 'X', subtitle: '', type: 'hotel'));
    await UserSettingsSync.instance.push({'locale': 'ar'});
    expect(server.calls, isEmpty);
  });

  test('settings changes are pushed and server settings are applied',
      () async {
    SharedPreferences.setMockInitialValues({});
    await UserSettingsSync.instance.push({'notif_promo': false});
    expect(server.settings['notif_promo'], false);

    server.settings = {'notif_trip': false, 'notif_general': true};
    await UserSettingsSync.instance.pullAndApply();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('notif_trip'), false);
    expect(prefs.getBool('notif_general'), true);
  });
}

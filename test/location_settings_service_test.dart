import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/core/services/location_settings_service.dart';

void main() {
  test('does not call native settings APIs on web', () async {
    var called = false;

    final result = await LocationSettingsService.openSafely(
      isWeb: true,
      open: () async {
        called = true;
        return true;
      },
    );

    expect(result, isFalse);
    expect(called, isFalse);
  });

  test('swallows unsupported native settings errors', () async {
    final result = await LocationSettingsService.openSafely(
      isWeb: false,
      open: () => throw UnsupportedError('settings unavailable'),
    );

    expect(result, isFalse);
  });
}

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

abstract final class LocationSettingsService {
  static const bool isSupported = !kIsWeb;

  static Future<bool> openLocationSettings() => openSafely(
        isWeb: kIsWeb,
        open: Geolocator.openLocationSettings,
      );

  static Future<bool> openAppSettings() => openSafely(
        isWeb: kIsWeb,
        open: Geolocator.openAppSettings,
      );

  @visibleForTesting
  static Future<bool> openSafely({
    required bool isWeb,
    required Future<bool> Function() open,
  }) async {
    if (isWeb) return false;
    try {
      return await open();
    } catch (_) {
      return false;
    }
  }
}

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

enum CurrentLocationError {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unableToDetermine,
}

class CurrentLocationException implements Exception {
  final CurrentLocationError reason;

  const CurrentLocationException(this.reason);
}

class CurrentPlace {
  final Position position;
  final String? city;
  final String? country;

  const CurrentPlace({required this.position, this.city, this.country});
}

class CurrentLocationService {
  const CurrentLocationService();

  static const _locationTimeout = Duration(seconds: 20);

  Future<Position> getPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()
          .timeout(_locationTimeout)) {
        throw const CurrentLocationException(
            CurrentLocationError.serviceDisabled);
      }

      var permission =
          await Geolocator.checkPermission().timeout(_locationTimeout);
      if (permission == LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission().timeout(_locationTimeout);
      }
      if (permission == LocationPermission.deniedForever) {
        throw const CurrentLocationException(
            CurrentLocationError.permissionDeniedForever);
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        throw const CurrentLocationException(
            CurrentLocationError.permissionDenied);
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: _locationTimeout,
      ).timeout(_locationTimeout);
    } on CurrentLocationException {
      rethrow;
    } catch (_) {
      throw const CurrentLocationException(
          CurrentLocationError.unableToDetermine);
    }
  }

  Future<CurrentPlace> getCurrentPlace() async {
    final position = await getPosition();
    try {
      final placemarks = await Geocoding()
          .placemarkFromCoordinates(position.latitude, position.longitude)
          .timeout(const Duration(seconds: 8));
      if (placemarks.isEmpty) return CurrentPlace(position: position);

      final placemark = placemarks.first;
      final city = [
        placemark.locality,
        placemark.subAdministrativeArea,
        placemark.administrativeArea,
      ]
          .whereType<String>()
          .map((value) => value.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      return CurrentPlace(
        position: position,
        city: city.isEmpty ? null : city,
        country: placemark.country?.trim().isEmpty == true
            ? null
            : placemark.country?.trim(),
      );
    } catch (_) {
      return CurrentPlace(position: position);
    }
  }
}

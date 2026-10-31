import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/api_service.dart';
import '../../../models/trip_model.dart';
import '../../../models/user_model.dart';

class ProfileController extends ChangeNotifier {
  final _api = ApiService.instance;

  UserModel? get currentUser => _api.currentUser;
  bool isLoading = false;
  String? errorMessage;

  static int countNonCancelledFlights(Iterable<TripModel> flights) => flights
      .where((flight) => flight.status.toLowerCase() != 'cancelled')
      .length;

  Future<bool> updateProfile({
    required String name,
    required String phone,
    XFile? photo,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result =
          await _api.updateProfile(name: name, phone: phone, photo: photo);
      errorMessage = result.isFailure ? result.errorMessage : null;
      return result.isSuccess;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> changePassword(
      {required String current, required String newPass}) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result =
          await _api.changePassword(current: current, newPass: newPass);
      errorMessage = result.isFailure ? result.errorMessage : null;
      return result.isSuccess;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

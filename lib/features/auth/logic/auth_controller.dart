import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/api_result.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/social_auth_service.dart';
import '../../../features/favorites/logic/favorites_controller.dart';
import '../../../features/notifications/logic/notifications_store.dart';
import '../../../features/price_alerts/logic/price_alerts_store.dart';
import '../../../core/services/user_settings_sync.dart';
import '../../../models/user_model.dart';

/// كل منطق المصادقة — الشاشات تستمع عبر ListenableBuilder ولا تتحدث مع
/// ApiService مباشرةً. استخدم دوال الـ "await" ثم افحص القيمة المُرجَعة.
class AuthController extends ChangeNotifier {
  final ApiService _api;

  AuthController({ApiService? api}) : _api = api ?? ApiService.instance;

  // ── State ────────────────────────────────────────────────────────────────
  bool isLoading = false;
  String? errorMessage;
  UserModel? currentUser;

  // ── Auth methods ─────────────────────────────────────────────────────────

  Future<bool> login({required String email, required String password}) {
    return _run(() async {
      final r = await _api.login(email: email, password: password);
      if (r.isSuccess) {
        currentUser = r.data;
        // نرجع نحمّل بيانات الحساب ده بالذات (مش حساب اللي كان مسجّل قبله).
        await FavoritesController.instance.load();
        await NotificationsStore.instance.load();
        await PriceAlertsStore.instance.load();
        await UserSettingsSync.instance.pullAndApply();
        await PushNotificationService.instance.syncTokenWithBackend();
      }
      return r;
    });
  }

  Future<bool> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    XFile? photo,
  }) {
    return _run(() async {
      final r = await _api.register(
          name: name,
          email: email,
          phone: phone,
          password: password,
          photo: photo);
      if (r.isSuccess) {
        currentUser = r.data;
        // حساب جديد يبدأ ببيانات فاضية فعليًا، مش شايل حاجة من حساب قديم.
        await FavoritesController.instance.load();
        await NotificationsStore.instance.load();
        await PriceAlertsStore.instance.load();
        await UserSettingsSync.instance.pullAndApply();
        await PushNotificationService.instance.syncTokenWithBackend();
      }
      return r;
    });
  }

  /// بيرجع true لو نجح الدخول، false لو فشل **أو** المستخدم لغى العملية
  /// بنفسه (زي ما يقفل نافذة اختيار حساب جوجل) — في الحالة التانية مفيش
  /// داعي نوري رسالة خطأ، فالشاشة بتتصرف حسب errorMessage لو null.
  Future<bool> loginWithGoogle() {
    return _run(() async {
      final idToken = await SocialAuthService.instance.signInWithGoogle();
      if (idToken == null) return ApiResult.failure('');
      final r =
          await _api.loginWithSocial(provider: 'google', idToken: idToken);
      if (r.isSuccess) {
        currentUser = r.data;
        await FavoritesController.instance.load();
        await NotificationsStore.instance.load();
        await PriceAlertsStore.instance.load();
        await UserSettingsSync.instance.pullAndApply();
        await PushNotificationService.instance.syncTokenWithBackend();
      }
      return r;
    });
  }

  Future<bool> loginWithApple() {
    return _run(() async {
      final idToken = await SocialAuthService.instance.signInWithApple();
      if (idToken == null) return ApiResult.failure('');
      final r = await _api.loginWithSocial(provider: 'apple', idToken: idToken);
      if (r.isSuccess) {
        currentUser = r.data;
        await FavoritesController.instance.load();
        await NotificationsStore.instance.load();
        await PriceAlertsStore.instance.load();
        await UserSettingsSync.instance.pullAndApply();
        await PushNotificationService.instance.syncTokenWithBackend();
      }
      return r;
    });
  }

  Future<bool> sendResetCode({required String email}) {
    return _run(() => _api.sendResetCode(email: email));
  }

  Future<bool> verifyResetCode({
    required String email,
    required String code,
  }) {
    return _run(() => _api.verifyResetCode(email: email, code: code));
  }

  Future<bool> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) {
    return _run(() => _api.resetPassword(
          email: email,
          code: code,
          newPassword: newPassword,
        ));
  }

  Future<bool> logout() {
    return _run(() async {
      await PushNotificationService.instance.detachTokenFromCurrentUser();
      final r = await _api.logout();
      if (r.isSuccess) {
        currentUser = null;
        // نمسح البيانات المحمّلة في الذاكرة فورًا، عشان لو سجّلت حساب
        // تاني في نفس الجلسة من غير ما تقفل التطبيق، ما تفضلش شايف
        // بيانات الحساب اللي قبله ولو للحظات قبل ما الشاشة تحمّل الجديد.
        FavoritesController.instance.clear();
        NotificationsStore.instance.clear();
        PriceAlertsStore.instance.clear();
      }
      return r;
    });
  }

  // ── Helper ───────────────────────────────────────────────────────────────

  Future<bool> _run<T>(Future<ApiResult<T>> Function() fn) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await fn();
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

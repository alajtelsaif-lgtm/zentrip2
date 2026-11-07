import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../features/notifications/logic/notifications_store.dart';
import 'api_service.dart';

/// استقبال الإشعارات (Push Notifications) عن طريق Firebase Cloud Messaging.
/// FCM handles device notifications only; account data remains in the
/// authenticated Zentrip API and PostgreSQL.
///
/// FCM delivery is intentionally disabled until Firebase client configuration
/// and backend Admin credentials are installed. Booking confirmations are
/// persisted in the authenticated backend inbox independently of FCM.
class PushNotificationService {
  static final PushNotificationService instance = PushNotificationService._();
  PushNotificationService._();

  static const bool isConfigured = false;

  static const String _androidChannelId = 'zentrip_default';
  static const String _androidChannelName = 'Zentrip Notifications';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  String? _fcmToken;
  bool _initialized = false;

  /// بتتنادى مرة واحدة عند بدء التطبيق (main.dart). آمنة تمامًا لو
  /// [isConfigured] لسه false — مش هتعمل حاجة خالص.
  Future<void> initialize() async {
    if (!isConfigured || _initialized) return;
    _initialized = true;
    try {
      await Firebase.initializeApp();
      await _initLocalNotifications();

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      _fcmToken = await messaging.getToken();
      if (_fcmToken != null) await _syncToken(_fcmToken!);
      messaging.onTokenRefresh.listen(_syncToken);

      // التطبيق مفتوح والإشعار وصل — نضيفه لقائمة الإشعارات جوه التطبيق
      // ونوريه كـ banner فوري (FCM لوحدها مابتعملش كده تلقائي وقت الـ foreground).
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // المستخدم دوس على إشعار وصل والتطبيق في الخلفية أو مقفول.
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    } catch (_) {
      // فشل التهيئة (زي ملفات Firebase مش مظبوطة لسه) — التطبيق يكمل
      // عادي من غير Push Notifications، مفيش أي كراش.
    }
  }

  /// بتتنادى تاني بعد نجاح تسجيل الدخول/التسجيل — عشان لو التوكن اتجاب
  /// قبل ما نعرف هوية المستخدم، يترسل تاني وهو مربوط بحسابه الصح.
  Future<void> syncTokenWithBackend() async {
    if (_fcmToken != null) await _syncToken(_fcmToken!);
  }

  Future<void> _syncToken(String token) async {
    _fcmToken = token;
    if (ApiService.instance.currentUser == null) return;
    await ApiService.instance.registerFcmToken(token);
  }

  Future<void> detachTokenFromCurrentUser() async {
    final token = _fcmToken;
    if (token != null && ApiService.instance.currentUser != null) {
      await ApiService.instance.unregisterFcmToken(token);
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _local.initialize(const InitializationSettings(
        android: androidSettings, iOS: iosSettings));
    const channel = AndroidNotificationChannel(
        _androidChannelId, _androidChannelName,
        importance: Importance.high);
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    if (title.isEmpty && body.isEmpty) return;

    await NotificationsStore.instance
        .add(kind: NotifKind.promo, title: title, subtitle: body);

    await _local.show(
      message.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
            _androidChannelId, _androidChannelName,
            importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    // لو الإشعار جاله data زي {"type": "trip_reminder", "trip_id": "..."}،
    // هنا المكان اللي تعمل فيه Navigation للشاشة المناسبة.
  }
}

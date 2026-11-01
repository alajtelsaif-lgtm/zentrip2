import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/payment_session.dart';
import '../../models/review_model.dart';
import '../../models/destination_info_model.dart';
import '../../models/booking_model.dart';
import '../../models/travel_package_model.dart';
import '../../models/mock_data_service.dart';
import '../../models/flight_model.dart';
import '../../models/flight_seat_map.dart';
import '../../models/flight_booking_model.dart';
import '../../models/hotel_model.dart';
import '../../models/car_model.dart';
import '../../models/attraction_model.dart';
import '../../models/transfer_model.dart';
import '../../models/trip_model.dart';
import '../../models/user_model.dart';
import '../../models/travel_preferences.dart';
import '../utils/hotel_geo.dart';
import '../utils/car_geo.dart';
import 'api_result.dart';
import '../../models/map_search_result.dart';
import '../../models/admin_dashboard_model.dart';
import '../../models/partner_dashboard_model.dart';
import '../../models/legacy_attraction_review_model.dart';

/// طبقة الشبكة المركزية — كل التواصل مع الـ PHP Laravel API يمر من هنا.
/// الـ Controllers لا تُنشئ Dio مباشرةً أبداً، بل تستدعي ApiService.instance.
///
/// ── وضع المحاكاة (Mock Mode) ──────────────────────────────────────────────
/// [useMockMode] لما يكون true، كل دوال المصادقة (login/register/forgot
/// password/verify/reset/logout/profile) بترجع استجابات وهمية ناجحة بدل ما
/// تكلم باك اند حقيقي — بمحاكاة تأخير شبكة واقعي، عشان تقدر تختبر كل شاشات
/// الـ UI (loading states, transitions, error handling) من غير باك اند شغال.
///
/// كود التحقق الوهمي المقبول هو [mockVerificationCode] — أي كود تاني هيفشل
/// عمداً عشان تقدر تختبر مسار الخطأ وعداد المحاولات في شاشة verify code.
///
/// عند جاهزية الـ Backend:
///  1. خلي [useMockMode] = false.
///  2. غيّر قيمة [baseUrl] للعنوان الحقيقي.
///  3. تأكد من أن مسارات الـ endpoints مطابقة لما في Laravel routes/api.php.
class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  static final ValueNotifier<int> flightTripsRevision = ValueNotifier(0);
  static final ValueNotifier<int> bookingsRevision = ValueNotifier(0);

  static const String _configuredBaseUrl =
      String.fromEnvironment('ZENTRIP_API_URL');
  static String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;

    // Android emulators need 10.0.2.2 to reach the host machine. Physical
    // devices should provide a LAN IP via --dart-define=ZENTRIP_API_URL or by
    // setting the environment before running the app.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080/api';
    }
    if (kIsWeb) return '/api';
    return 'http://127.0.0.1:8080/api';
  }

  static const String _tokenKey = 'auth_token';

  // ── Mock Mode ───────────────────────────────────────────────────────────
  static const bool useMockMode = false;
  static const String mockVerificationCode = '123456';
  static const Duration _mockDelay = Duration(milliseconds: 700);

  late final Dio _dio;
  UserModel? currentUser;

  /// Callback يُنادى تلقائياً عند 401 من أي endpoint.
  SessionExpiredCallback? onSessionExpired;

  bool _initialized = false;

  Future<ApiResult<List<MapSearchResult>>> searchGoogleMaps({
    required String query,
    required double latitude,
    required double longitude,
    required String category,
    int limit = 10,
  }) async {
    return _request(() async {
      final response = await _dio.get(
        '/maps/search',
        queryParameters: {
          'query': query,
          'lat': latitude,
          'lng': longitude,
          'category': category,
          'limit': limit,
        },
      );

      final items = response.data['results'] as List? ?? [];

      return items
          .map((item) => MapSearchResult.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  void init() {
    if (_initialized) return;
    _initialized = true;

    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _getToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (e, handler) {
          if (e.response?.statusCode == 401) {
            _clearToken();
            onSessionExpired?.call();
          }
          handler.next(e);
        },
      ),
    );
  }

  // ── Auth ─────────────────────────────────────────────────────────────────

  Future<ApiResult<UserModel>> login({
    required String email,
    required String password,
  }) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        final user = _mockUser(email);
        await _saveToken('mock-token-${user.id}');
        await _saveUserLocally(user);
        currentUser = user;
        return user;
      });
    }
    return _request(() async {
      final res = await _dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      final user = UserModel.fromJson(res.data['user'] as Map<String, dynamic>);
      await _saveToken(res.data['token'] as String);
      await _saveUserLocally(user);
      currentUser = user;
      return user;
    });
  }

  /// دخول عن طريق Google/Apple — الباك اند بيتحقق من الـ idToken فعليًا
  /// مع Google/Apple (ما تتحققش أبدًا من التطبيق نفسه، ده غير آمن).
  Future<ApiResult<UserModel>> loginWithSocial({
    required String provider,
    required String idToken,
  }) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        final user = _mockUser('$provider-user@zentrip.app');
        await _saveToken('mock-token-${user.id}');
        await _saveUserLocally(user);
        currentUser = user;
        return user;
      });
    }
    return _request(() async {
      final res = await _dio.post(
        '/auth/social-login',
        data: {'provider': provider, 'id_token': idToken},
      );
      final user = UserModel.fromJson(res.data['user'] as Map<String, dynamic>);
      await _saveToken(res.data['token'] as String);
      await _saveUserLocally(user);
      currentUser = user;
      return user;
    });
  }

  Future<MultipartFile> _profilePhotoPart(XFile photo) async {
    const maxBytes = 5 * 1024 * 1024;
    final extension = photo.name.contains('.')
        ? photo.name.split('.').last.toLowerCase()
        : '';
    var mimeType = photo.mimeType?.split(';').first.trim().toLowerCase();

    if (mimeType == null ||
        mimeType.isEmpty ||
        mimeType == 'application/octet-stream') {
      mimeType = switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => '',
      };
    }
    if (mimeType == 'image/jpg') mimeType = 'image/jpeg';
    if (!const {'image/jpeg', 'image/png', 'image/webp'}.contains(mimeType)) {
      throw const FormatException('Choose a JPEG, PNG, or WebP profile photo.');
    }

    final length = await photo.length();
    if (length == 0 || length > maxBytes) {
      throw const FormatException('Profile photos must be 5 MB or smaller.');
    }
    final bytes = await photo.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Profile photos must be 5 MB or smaller.');
    }

    final extensionForType =
        mimeType == 'image/jpeg' ? 'jpg' : mimeType.substring('image/'.length);
    return MultipartFile.fromBytes(
      bytes,
      filename: 'profile.$extensionForType',
      contentType: DioMediaType.parse(mimeType),
    );
  }

  Future<ApiResult<UserModel>> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    XFile? photo,
  }) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        final user = UserModel(
          id: DateTime.now().millisecondsSinceEpoch,
          name: name,
          email: email,
          phone: phone,
        );
        await _saveToken('mock-token-${user.id}');
        await _saveUserLocally(user);
        currentUser = user;
        return user;
      });
    }
    return _request(() async {
      final formData = FormData.fromMap({
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'password_confirmation': password,
        if (photo != null) 'photo': await _profilePhotoPart(photo),
      });
      final res = await _dio.post('/auth/register', data: formData);
      final user = UserModel.fromJson(res.data['user'] as Map<String, dynamic>);
      await _saveToken(res.data['token'] as String);
      await _saveUserLocally(user);
      currentUser = user;
      return user;
    });
  }

  Future<ApiResult<void>> sendResetCode({required String email}) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
      });
    }
    return _request(() async {
      await _dio.post('/auth/forgot-password', data: {'email': email});
    });
  }

  Future<ApiResult<void>> verifyResetCode({
    required String email,
    required String code,
  }) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        if (code != mockVerificationCode) {
          throw Exception('Invalid verification code');
        }
      });
    }
    return _request(() async {
      await _dio.post(
        '/auth/verify-code',
        data: {'email': email, 'code': code},
      );
    });
  }

  Future<ApiResult<void>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
      });
    }
    return _request(() async {
      await _dio.post(
        '/auth/reset-password',
        data: {
          'email': email,
          'code': code,
          'password': newPassword,
          'password_confirmation': newPassword,
        },
      );
    });
  }

  Future<ApiResult<void>> logout() async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        await _clearToken();
        await _clearLocalUser();
        currentUser = null;
      });
    }
    return _request(() async {
      try {
        await _dio.post('/auth/logout');
      } finally {
        try {
          await _clearToken();
        } finally {
          try {
            await _clearLocalUser();
          } finally {
            currentUser = null;
          }
        }
      }
    });
  }

  Future<bool> restoreSession() async {
    final token = await _getToken();
    if (token == null) return false;
    if (useMockMode) {
      await Future.delayed(_mockDelay);
      // نرجّع نفس اليوزر اللي كان مسجّل دخول فعليًا (مش يوزر وهمي ثابت)،
      // وإلا كل إعادة فتح للتطبيق كانت هتحط الكل على حساب "demo" واحد
      // بغض النظر عن مين سجّل دخول فعليًا آخر مرة.
      currentUser ??= await _loadLocalUser();
      return currentUser != null;
    }
    try {
      final res = await _dio.get('/auth/me');
      currentUser = UserModel.fromJson(
        res.data['user'] as Map<String, dynamic>,
      );
      return true;
    } catch (_) {
      await _clearToken();
      return false;
    }
  }

  Future<ApiResult<UserModel>> updateProfile({
    required String name,
    required String phone,
    XFile? photo,
  }) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        final base = currentUser ??
            await _loadLocalUser() ??
            _mockUser('demo@zentrip.app');
        final user = base.copyWith(
          name: name,
          phone: phone,
          photoUrl: photo?.path,
        );
        await _saveUserLocally(user);
        currentUser = user;
        return user;
      });
    }
    return _request(() async {
      final formData = FormData.fromMap({
        'name': name,
        'phone': phone,
        '_method': 'PUT',
        if (photo != null) 'photo': await _profilePhotoPart(photo),
      });
      final res = await _dio.post('/profile', data: formData);
      final user = UserModel.fromJson(res.data['user'] as Map<String, dynamic>);
      currentUser = user;
      return user;
    });
  }

  Future<ApiResult<TravelPreferences>> getTravelPreferences() {
    return _request(() async {
      final response = await _dio.get('/preferences/travel');
      final body = response.data as Map<String, dynamic>;
      final preferences = body['preferences'] ?? body;
      return TravelPreferences.fromJson(preferences as Map<String, dynamic>);
    });
  }

  Future<ApiResult<TravelPreferences>> saveTravelPreferences(
      TravelPreferences preferences) {
    return _request(() async {
      final response = await _dio.put(
        '/preferences/travel',
        data: preferences.toJson(),
      );
      final body = response.data as Map<String, dynamic>;
      final saved = body['preferences'] ?? body;
      return TravelPreferences.fromJson(saved as Map<String, dynamic>);
    });
  }

  Future<ApiResult<void>> changePassword({
    required String current,
    required String newPass,
  }) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
      });
    }
    return _request(() async {
      await _dio.put(
        '/profile/password',
        data: {
          'current_password': current,
          'password': newPass,
          'password_confirmation': newPass,
        },
      );
    });
  }

  // ── معلومات الوجهة (طقس + تأشيرة) ────────────────────────────────────────
  // الطقس محتاج مصدر حي حقيقي وقت التفعيل (OpenWeatherMap مثلاً، فيه Free
  // Tier سخي). معلومات التأشيرة عادة بيانات شبه ثابتة (مش API حي) — حتى
  // شركات السفر الكبيرة بتستخدم قاعدة بيانات مُنسّقة يدويًا وبتحدّثها من
  // وقت للتاني، مش نداء API لحظي.

  Future<ApiResult<WeatherInfo>> getDestinationWeather(String city) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        return WeatherInfo(
          tempCelsius: 24 + (city.hashCode % 10),
          condition: 'sunny',
          cityName: city,
        );
      });
    }
    return _request(() async {
      final res = await _dio.get(
        '/destinations/weather',
        queryParameters: {'city': city},
      );
      return WeatherInfo.fromJson(res.data as Map<String, dynamic>);
    });
  }

  Future<ApiResult<VisaInfo>> getVisaInfo(String country) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        return const VisaInfo(
          requirement: 'e_visa',
          notes:
              'Visa information will be verified with the destination\'s embassy before booking.',
        );
      });
    }
    return _request(() async {
      final res = await _dio.get(
        '/destinations/visa-info',
        queryParameters: {'country': country},
      );
      return VisaInfo.fromJson(res.data as Map<String, dynamic>);
    });
  }

  // ── التقييمات (Reviews) ───────────────────────────────────────────────
  // ملحوظة على وضع المحاكاة: التقييمات هنا بتتخزن محليًا على جهازك بس
  // (مش هتظهر لمستخدمين تانيين إلا بعد ربط الباك اند الحقيقي)، عشان كده
  // مش مربوطة بحساب معيّن — بتتشارك بين كل الحسابات على نفس الجهاز، بالظبط
  // زي ما هيحصل فعليًا لما الباك اند يشتغل (تقييمات مشتركة للجميع).
  static const _reviewsKey = 'shared_reviews_v1';

  Future<ApiResult<ReviewModel>> submitReview({
    required String itemId,
    required String itemType,
    required double rating,
    required String comment,
  }) async {
    final userName = currentUser?.name ?? 'Zentrip User';
    final review = ReviewModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      itemId: itemId,
      itemType: itemType,
      userName: userName,
      rating: rating,
      comment: comment,
      createdAt: DateTime.now(),
    );
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        final all = await _loadLocalReviews();
        all.insert(0, review);
        await _saveLocalReviews(all);
        return review;
      });
    }
    return _request(() async {
      final res = await _dio.post('/reviews', data: review.toJson());
      return ReviewModel.fromJson(res.data['review'] as Map<String, dynamic>);
    });
  }

  Future<ApiResult<List<ReviewModel>>> getReviews({
    required String itemId,
  }) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        final all = await _loadLocalReviews();
        return all.where((r) => r.itemId == itemId).toList();
      });
    }
    return _request(() async {
      final res = await _dio.get(
        '/reviews',
        queryParameters: {'item_id': itemId},
      );
      return (res.data['reviews'] as List)
          .map((r) => ReviewModel.fromJson(r as Map<String, dynamic>))
          .toList();
    });
  }

  Future<List<ReviewModel>> _loadLocalReviews() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_reviewsKey) ?? [];
    return raw
        .map((e) => ReviewModel.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveLocalReviews(List<ReviewModel> reviews) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _reviewsKey,
      reviews.map((r) => jsonEncode(r.toJson())).toList(),
    );
  }

  // ── الدفع (Hosted Checkout — أنسب نمط لبوابات MENA زي HyperPay/PayTabs) ──
  // الباك اند هو اللي بيتكلم مع بوابة الدفع الفعلية ويرجّع رابط صفحة دفع
  // مستضافة (Checkout URL)؛ التطبيق بيفتحها في WebView بس، مايكلمش بوابة
  // الدفع مباشرة خالص — ده بيحمي أي بيانات حساسة من التسرّب في التطبيق.

  Future<ApiResult<PaymentSession>> createPaymentCheckout({
    required double amountUsd,
    required String description,
    required String referenceId,
  }) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        return PaymentSession(
          sessionId: 'mock-$referenceId',
          checkoutUrl: 'mock://checkout',
        );
      });
    }
    return _request(() async {
      final res = await _dio.post(
        '/payments/checkout',
        data: {
          'amount': amountUsd,
          'currency': 'USD',
          'description': description,
          'reference_id': referenceId,
        },
      );
      return PaymentSession.fromJson(res.data as Map<String, dynamic>);
    });
  }

  /// بيتأكد من نجاح الدفع فعليًا من عند السيرفر (مش بس من إعادة توجيه
  /// الـ WebView، اللي ممكن يتلاعب بيها) قبل ما نأكد الحجز.
  Future<ApiResult<bool>> verifyPayment(String sessionId) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        return true;
      });
    }
    return _request(() async {
      final res = await _dio.get('/payments/verify/$sessionId');
      final rawPaid = res.data['paid'];
      if (rawPaid is bool) return rawPaid;
      if (rawPaid is String) {
        final normalized = rawPaid.trim().toLowerCase();
        return normalized == 'true' || normalized == '1' || normalized == 'yes';
      }
      return false;
    });
  }

  // ── Push Notifications (FCM Token) ───────────────────────────────────────

  Future<ApiResult<void>> registerFcmToken(String token) async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
      });
    }
    return _request(() async {
      await _dio.post(
        '/users/fcm-token',
        data: {
          'token': token,
          'platform': kIsWeb
              ? 'web'
              : defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'android',
        },
      );
    });
  }

  // ── AI Chatbot (Python Service) ──────────────────────────────────────────

  Future<ApiResult<String>> sendChatMessage({
    required String message,
    required String sessionId,
    required String language,
    required String requestId,
    bool locationRequested = false,
    Map<String, Object?>? currentLocation,
    CancelToken? cancelToken,
    void Function(String delta)? onChunk,
  }) async {
    return _request(() async {
      final res = await _dio.post<ResponseBody>(
        '/ai/chat',
        data: {
          'message': message,
          'session_id': sessionId,
          'language': language,
          'request_id': requestId,
          if (locationRequested) 'location_requested': true,
          if (currentLocation != null) 'current_location': currentLocation,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream, application/json'},
          receiveTimeout: const Duration(seconds: 150),
          sendTimeout: const Duration(seconds: 20),
        ),
        cancelToken: cancelToken,
      );
      final body = res.data;
      if (body == null) {
        throw const FormatException('Zen returned an empty response stream');
      }

      final reply = StringBuffer();
      var event = '';
      final data = StringBuffer();
      var completed = false;
      String? streamError;

      void dispatchEvent() {
        if (data.isEmpty) return;
        final payload = jsonDecode(data.toString());
        if (payload is Map<String, dynamic>) {
          if (event == 'token' && payload['text'] is String) {
            final delta = payload['text'] as String;
            reply.write(delta);
            onChunk?.call(delta);
          } else if (event == 'error' && payload['message'] is String) {
            streamError = payload['message'] as String;
          } else if (event == 'done') {
            completed = true;
          }
        }
        event = '';
        data.clear();
      }

      await for (final line in body.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isEmpty) {
          dispatchEvent();
        } else if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          if (data.isNotEmpty) data.write('\n');
          data.write(line.substring(5).trimLeft());
        }
      }
      dispatchEvent();

      if (streamError != null) {
        throw Exception(streamError);
      }
      if (!completed) {
        throw const FormatException(
            'Zen ended the response before it was complete');
      }
      return reply.toString();
    });
  }

  Future<ApiResult<void>> cancelChatMessage({
    required String sessionId,
    required String requestId,
  }) async {
    return _request(() async {
      await _dio.post(
        '/ai/chat/cancel',
        data: {'session_id': sessionId, 'request_id': requestId},
      );
    });
  }

  // ── Offers / Travel Packages ─────────────────────────────────────────────
  // دي نقطة الربط مع لوحة تحكم الأدمن (Dashboard): أي عرض يتضاف/يتعدّل من
  // جوه الداشبورد هيوصل هنا تلقائيًا لما useMockMode = false ويتحدد
  // الـ endpoint الحقيقي (GET /offers من نفس الـ Laravel API). التطبيق مش
  // محتاج يتغيّر خالص وقتها — بس السطر ده.

  Future<ApiResult<List<TravelPackage>>> getOffers() async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        return MockDataService.packages();
      });
    }
    final partnerPackages = (await _loadPartnerInventory('package'))
        .map(TravelPackage.fromJson)
        .toList();
    return _request(() async {
      final res = await _dio.get('/offers');
      final offers = (res.data['offers'] as List)
          .map((o) => TravelPackage.fromJson(o as Map<String, dynamic>))
          .toList();
      return [...partnerPackages, ...offers];
    });
  }

  Future<ApiResult<AdminDashboardData>> getAdminDashboard() {
    return _request(() async {
      final response = await _dio.get('/admin/dashboard');
      return AdminDashboardData.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<ApiResult<AdminAttractionPopularity>> getAdminAttractionPopularity() {
    return _request(() async {
      final response = await _dio.get('/admin/attractions/popularity');
      return AdminAttractionPopularity.fromJson(
          response.data as Map<String, dynamic>);
    });
  }

  Future<ApiResult<List<AdminReservation>>> getAdminReservations() {
    return _request(() async {
      final response = await _dio.get('/admin/reservations');
      return (response.data['reservations'] as List)
          .map(
              (item) => AdminReservation.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  Future<ApiResult<List<AdminCustomer>>> getAdminCustomers() {
    return _request(() async {
      final response = await _dio.get('/admin/customers');
      return (response.data['customers'] as List)
          .map((item) => AdminCustomer.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  Future<ApiResult<List<AdminPartner>>> getAdminPartners() {
    return _request(() async {
      final response = await _dio.get('/admin/partners');
      return (response.data['partners'] as List)
          .map((item) => AdminPartner.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  Future<ApiResult<List<LegacyAttractionPartner>>>
      getAdminLegacyAttractionPartners() {
    return _request(() async {
      final response = await _dio.get('/admin/partners/legacy-attractions');
      return (response.data['partners'] as List)
          .map((item) => LegacyAttractionPartner.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList();
    });
  }

  Future<ApiResult<void>> reviewAndRetireLegacyAttractionPartner({
    required int id,
    required List<Map<String, dynamic>> listingDecisions,
  }) {
    return _request(() async {
      await _dio.post(
        '/admin/partners/$id/attraction-review',
        data: {
          'approved': true,
          'listings': listingDecisions,
        },
      );
    });
  }

  Future<ApiResult<void>> addAdminPartner({
    required String name,
    required String email,
    required String serviceType,
  }) {
    return _request(() async {
      await _dio.post('/admin/partners', data: {
        'name': name,
        'email': email,
        'service_type': serviceType,
      });
    });
  }

  Future<ApiResult<void>> disableAdminPartner(int id) {
    return _request(() async {
      await _dio.delete('/admin/partners/$id');
    });
  }

  Future<ApiResult<void>> activateAdminPartner(int id) {
    return _request(() async {
      await _dio.post('/admin/partners/$id/activate');
    });
  }

  Future<ApiResult<List<TravelPackage>>> getAdminOffers() {
    return _request(() async {
      final response = await _dio.get('/admin/offers');
      return (response.data['offers'] as List)
          .map((item) => TravelPackage.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  Future<ApiResult<void>> saveAdminOffer(
    TravelPackage offer, {
    String? id,
  }) {
    return _request(() async {
      if (id == null || id.isEmpty) {
        await _dio.post('/admin/offers', data: offer.toJson());
      } else {
        await _dio.put('/admin/offers/$id', data: offer.toJson());
      }
    });
  }

  Future<ApiResult<void>> deleteAdminOffer(String id) {
    return _request(() async {
      await _dio.delete('/admin/offers/$id');
    });
  }

  Future<ApiResult<List<AttractionModel>>> getAdminMonuments() {
    return _request(() async {
      final response = await _dio.get('/admin/monuments');
      return (response.data['monuments'] as List)
          .map((item) => AttractionModel.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  Future<ApiResult<void>> saveAdminMonument(
    AttractionModel monument, {
    String? id,
  }) {
    return _request(() async {
      if (id == null || id.isEmpty) {
        await _dio.post('/admin/monuments', data: monument.toJson());
      } else {
        await _dio.put('/admin/monuments/$id', data: monument.toJson());
      }
    });
  }

  Future<ApiResult<void>> deleteAdminMonument(String id) {
    return _request(() async {
      await _dio.delete('/admin/monuments/$id');
    });
  }

  Future<ApiResult<PartnerDashboardData>> getPartnerDashboard() {
    return _request(() async {
      final response = await _dio.get('/partner/dashboard');
      return PartnerDashboardData.fromJson(
          response.data as Map<String, dynamic>);
    });
  }

  Future<ApiResult<List<PartnerReservation>>> getPartnerReservations() {
    return _request(() async {
      final response = await _dio.get('/partner/reservations');
      return (response.data['reservations'] as List)
          .map((item) =>
              PartnerReservation.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  Future<ApiResult<List<AdminCustomer>>> getPartnerCustomers() {
    return _request(() async {
      final response = await _dio.get('/partner/customers');
      return (response.data['customers'] as List)
          .map((item) => AdminCustomer.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  Future<ApiResult<List<PartnerListing>>> getPartnerListings() {
    return _request(() async {
      final response = await _dio.get('/partner/listings');
      return (response.data['listings'] as List)
          .map((item) => PartnerListing.fromJson(item as Map<String, dynamic>))
          .toList();
    });
  }

  Future<ApiResult<PartnerListing>> savePartnerListing(PartnerListing listing) {
    return _request(() async {
      final data = listing.toJson();
      final response = listing.id == null
          ? await _dio.post('/partner/listings', data: data)
          : await _dio.put('/partner/listings/${listing.id}', data: data);
      return PartnerListing.fromJson(
          response.data['listing'] as Map<String, dynamic>);
    });
  }

  Future<ApiResult<String>> uploadPartnerHotelImage({
    required Uint8List bytes,
    required String filename,
  }) {
    return _request(() async {
      final response = await _dio.post(
        '/partner/hotel-images',
        data: FormData.fromMap({
          'image': MultipartFile.fromBytes(bytes, filename: filename),
        }),
      );
      final imageUrl = response.data['image_url'] as String;
      return Uri.parse(baseUrl).resolve(imageUrl).toString();
    });
  }

  Future<ApiResult<void>> setPartnerListingActive(
      PartnerListing listing, bool active) {
    return _request(() async {
      await _dio.put('/partner/listings/${listing.id}', data: {
        ...listing.toJson(),
        'active': active,
      });
    });
  }

  Future<List<Map<String, dynamic>>> _loadPartnerInventory(
    String type, {
    String? city,
  }) async {
    try {
      final response = await _dio.get(
        '/inventory/$type',
        queryParameters: {
          if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
        },
      );
      return (response.data['items'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } on DioException catch (error) {
      debugPrint('Partner $type inventory unavailable: ${error.message}');
      return [];
    }
  }

  // ── Search: Flights / Hotels / Cars / Attractions / Transfers ───────────
  // كل الطلبات دي بتروح لباك اند Zentrip نفسه (نفس baseUrl فوق) — الباك
  // اند هو اللي بيكلم Amadeus/Booking.com بمفاتيحه الخاصة (مخزّنة في
  // .env عنده)، ويرجّعلنا بيانات بنفس شكل الموديلات هنا بالظبط. يعني
  // مفتاح API حقيقي **مايتحطش في التطبيق خالص** — ده مبدأ أمان أساسي.

  Future<List<AirportOption>> searchAirports(String query) async {
    final response = await _dio.get(
      '/airports/search',
      queryParameters: {'query': query.trim()},
    );
    final airports = response.data['airports'] as List;
    return airports
        .map((airport) =>
            AirportOption.fromJson(Map<String, dynamic>.from(airport as Map)))
        .toList();
  }

  Future<List<FlightModel>> searchFlights({
    required String originCode,
    required String destinationCode,
    String? originCity,
    String? destinationCity,
    required DateTime departureDate,
    DateTime? returnDate,
    bool isRoundTrip = false,
    int adults = 1,
    String seatClass = 'economy',
  }) async {
    if (useMockMode) {
      await Future.delayed(_mockDelay);
      return MockDataService.flights(
        origin: originCode,
        destination: destinationCode,
        originCity: originCity,
        destinationCity: destinationCity,
        departureDate: departureDate,
      );
    }
    final res = await _dio.get(
      '/flights/search',
      queryParameters: {
        'origin': originCode,
        'destination': destinationCode,
        'departure_date': _formatDate(departureDate),
        if (returnDate != null) 'return_date': _formatDate(returnDate),
        'trip_type': isRoundTrip ? 'round_trip' : 'one_way',
        'adults': adults,
        'seat_class': seatClass,
      },
    );
    return (res.data['flights'] as List)
        .map((flight) =>
            FlightModel.fromJson(Map<String, dynamic>.from(flight as Map)))
        .toList();
  }

  Future<ApiResult<FlightSeatMap>> getFlightSeatMap(String flightId) {
    return _request(() async {
      final response = await _dio.get('/flights/$flightId/seats');
      return FlightSeatMap.fromJson(
          Map<String, dynamic>.from(response.data as Map));
    });
  }

  Future<ApiResult<Set<String>>> getOccupiedFlightSeats(
    String flightId,
  ) {
    return _request(() async {
      final response = await _dio.get('/flights/$flightId/seats');
      final seats = response.data['occupied_seats'];
      if (seats is! List) {
        throw const FormatException('Invalid flight seat response');
      }
      return seats.map((seat) => seat.toString()).toSet();
    });
  }

  Future<ApiResult<Set<String>>> reserveFlightSeats({
    required String flightId,
    required List<String> seats,
  }) {
    return _request(() async {
      final response = await _dio.post(
        '/flights/$flightId/seats/reserve',
        data: {'seats': seats},
      );
      final occupiedSeats = response.data['occupied_seats'];
      if (occupiedSeats is! List) {
        throw const FormatException('Invalid flight seat reservation response');
      }
      return occupiedSeats.map((seat) => seat.toString()).toSet();
    });
  }

  Future<ApiResult<void>> releaseFlightSeatReservation(String flightId) {
    return _request(() async {
      await _dio.delete('/flights/$flightId/seats/reserve');
    });
  }

  Future<ApiResult<FlightBookingConfirmation>> confirmFlightBooking({
    required String flightId,
    required List<String> seats,
    required String seatClass,
    DateTime? returnDate,
    List<String> extras = const [],
  }) async {
    final result = await _request(() async {
      final response = await _dio.post(
        '/bookings/confirm',
        data: {
          'flight_id': flightId,
          'seats': seats,
          'seat_class': seatClass,
          'extras': extras,
          if (returnDate != null)
            'return_date': returnDate.toUtc().toIso8601String(),
        },
      );
      return FlightBookingConfirmation.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });
    if (result.isSuccess) flightTripsRevision.value++;
    return result;
  }

  Future<ApiResult<TransferModel>> createTransferBooking(
    TransferModel transfer, {
    required int passengers,
    required String referenceId,
  }) async {
    return _request(() async {
      final res = await _dio.post(
        '/transfers',
        data: {
          'provider_name': transfer.providerName,
          'vehicle_type': transfer.vehicleType,
          'pickup_location': transfer.pickupLocation,
          'dropoff_location': transfer.dropoffLocation,
          'pickup_time': transfer.pickupTime.toIso8601String(),
          'duration_minutes': transfer.durationMinutes,
          'price': transfer.priceUSD,
          'passengers': passengers,
          'reference_id': referenceId,
          'status': 'confirmed',
          'partner_listing_id': transfer.partnerListingId,
        },
      );

      return TransferModel.fromJson(
        res.data['transfer'] as Map<String, dynamic>,
      );
    });
  }

  Future<ApiResult<bool>> checkTransferAvailability({
    required DateTime pickupTime,
    required int durationMinutes,
  }) async {
    return _request(() async {
      final response = await _dio.get(
        '/transfers/availability',
        queryParameters: {
          'pickup_time': pickupTime.toIso8601String(),
          'duration_minutes': durationMinutes,
        },
      );
      return response.data['available'] == true;
    });
  }

  Future<List<HotelModel>> searchHotels({
    required String city,
    DateTime? checkIn,
    DateTime? checkOut,
    int rooms = 1,
    int guests = 2,
  }) async {
    if (useMockMode) {
      await Future.delayed(_mockDelay);
      return MockDataService.hotels(city: city);
    }
    try {
      final res = await _dio.get(
        '/hotels/search',
        queryParameters: {
          'city': city,
          if (checkIn != null) 'check_in': _formatDate(checkIn),
          if (checkOut != null) 'check_out': _formatDate(checkOut),
          'rooms': rooms,
          'guests': guests,
        },
      );
      final hotels = (res.data['hotels'] as List)
          .map((h) => HotelModel.fromJson(h as Map<String, dynamic>))
          .toList();
      return [...hotels, ...MockDataService.hotels(city: city)];
    } catch (_) {
      final partnerHotels = (await _loadPartnerInventory('hotel', city: city))
          .map(HotelModel.fromJson)
          .toList();
      return [...partnerHotels, ...MockDataService.hotels(city: city)];
    }
  }

  Future<List<String>> searchHotelLocations(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    List<String> matchingSuggestions(Iterable<HotelModel> hotels) => hotels
        .expand((hotel) => [hotel.city, hotel.address, hotel.name])
        .where(
            (value) => value.toLowerCase().contains(normalized.toLowerCase()))
        .toSet()
        .take(12)
        .toList();

    if (useMockMode) {
      return matchingSuggestions(MockDataService.hotels());
    }
    try {
      final response = await _dio.get(
        '/hotels/locations',
        queryParameters: {'query': normalized},
      );
      final remote = (response.data['suggestions'] as List? ?? const [])
          .map((value) => value.toString())
          .toList();
      return {...remote, ...matchingSuggestions(MockDataService.hotels())}
          .take(12)
          .toList();
    } catch (_) {
      final partnerHotels = (await _loadPartnerInventory('hotel'))
          .map(HotelModel.fromJson)
          .toList();
      return {
        ...matchingSuggestions(partnerHotels),
        ...matchingSuggestions(MockDataService.hotels()),
      }.take(12).toList();
    }
  }

  Future<List<HotelModel>> nearbyHotels({
    required double lat,
    required double lng,
    double radiusMeters = 50000,
  }) async {
    if (useMockMode) {
      await Future.delayed(_mockDelay);
      return hotelsWithinRadius(
        hotels: MockDataService.hotels(city: 'Tripoli'),
        latitude: lat,
        longitude: lng,
        radiusMeters: radiusMeters,
      );
    }
    try {
      final res = await _dio.get(
        '/hotels/nearby',
        queryParameters: {
          'lat': lat,
          'lon': lng,
          'lng': lng,
          'radius': radiusMeters,
        },
      );
      final hotels = (res.data['hotels'] as List)
          .map((h) => HotelModel.fromJson(h as Map<String, dynamic>))
          .toList();
      return hotelsWithinRadius(
        hotels: [...hotels, ...MockDataService.hotels(city: 'Tripoli')],
        latitude: lat,
        longitude: lng,
        radiusMeters: radiusMeters,
      );
    } on DioException catch (error) {
      debugPrint('Nearby hotel API unavailable, using local inventory: '
          '${error.message}');
      return hotelsWithinRadius(
        hotels: [
          ...(await _loadPartnerInventory('hotel')).map(HotelModel.fromJson),
          ...MockDataService.hotels(city: 'Tripoli'),
        ],
        latitude: lat,
        longitude: lng,
        radiusMeters: radiusMeters,
      );
    }
  }

  Future<List<CarModel>> searchCars({
    required String city,
    DateTime? pickupDate,
    DateTime? returnDate,
    String? carType,
  }) async {
    if (useMockMode) {
      await Future.delayed(_mockDelay);
      var results = MockDataService.cars(city: city);
      if (carType != null && carType != 'all') {
        results = results.where((c) => c.type == carType).toList();
      }

      return results;
    }
    final partnerCars = (await _loadPartnerInventory('car', city: city))
        .map(CarModel.fromJson)
        .where((car) =>
            car.availableVehicles > 0 &&
            (carType == null || carType == 'all' || car.type == carType))
        .toList();
    try {
      final res = await _dio.get(
        '/cars/search',
        queryParameters: {
          'city': city,
          if (pickupDate != null) 'pickup_date': _formatDate(pickupDate),
          if (returnDate != null) 'return_date': _formatDate(returnDate),
          if (carType != null) 'car_type': carType,
        },
      );
      final cars = (res.data['cars'] as List)
          .map((c) => CarModel.fromJson(c as Map<String, dynamic>))
          .where((car) => car.availableVehicles > 0)
          .toList();
      return [...partnerCars, ...cars];
    } catch (_) {
      var results = MockDataService.cars(city: city);
      if (carType != null && carType != 'all') {
        results = results.where((c) => c.type == carType).toList();
      }
      return [...partnerCars, ...results];
    }
  }

  Future<List<String>> searchCarLocations(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    final localMatches = MockDataService.cars()
        .map((car) => car.pickupLocation)
        .where(
          (location) =>
              location.toLowerCase().contains(normalized.toLowerCase()),
        )
        .toSet();
    if (useMockMode) return localMatches.take(12).toList();
    try {
      final response = await _dio.get(
        '/cars/locations',
        queryParameters: {'query': normalized},
      );
      final remote = (response.data['suggestions'] as List? ?? const [])
          .map((value) => value.toString());
      return {...remote, ...localMatches}.take(12).toList();
    } on DioException catch (error) {
      debugPrint('Car location suggestions unavailable: ${error.message}');
      final hotelLocations = await searchHotelLocations(normalized);
      return {...hotelLocations, ...localMatches}.take(12).toList();
    }
  }

  Future<List<CarModel>> nearbyCars({
    required double lat,
    required double lng,
    double radiusMeters = 50000,
    String? carType,
  }) async {
    List<CarModel> filterType(Iterable<CarModel> cars) => cars
        .where((car) =>
            car.availableVehicles > 0 &&
            (carType == null || carType == 'all' || car.type == carType))
        .toList();
    if (useMockMode) {
      await Future.delayed(_mockDelay);
      return carsWithinRadius(
        cars: filterType(MockDataService.cars(city: 'Tripoli')),
        latitude: lat,
        longitude: lng,
        radiusMeters: radiusMeters,
      );
    }
    try {
      final response = await _dio.get(
        '/cars/nearby',
        queryParameters: {
          'lat': lat,
          'lng': lng,
          'radius': radiusMeters,
          if (carType != null) 'car_type': carType,
        },
      );
      final cars = (response.data['cars'] as List)
          .map((item) => CarModel.fromJson(item as Map<String, dynamic>));
      return carsWithinRadius(
        cars: cars,
        latitude: lat,
        longitude: lng,
        radiusMeters: radiusMeters,
      );
    } on DioException catch (error) {
      debugPrint('Nearby car API unavailable: ${error.message}');
      final partnerCars =
          (await _loadPartnerInventory('car')).map(CarModel.fromJson);
      return carsWithinRadius(
        cars: filterType([
          ...partnerCars,
          ...MockDataService.cars(city: 'Tripoli'),
        ]),
        latitude: lat,
        longitude: lng,
        radiusMeters: radiusMeters,
      );
    }
  }

  Future<List<TransferModel>> searchTransfers({
    required String from,
    required String to,
    DateTime? date,
    int passengers = 1,
  }) async {
    if (useMockMode) {
      await Future.delayed(_mockDelay);
      final results = MockDataService.transfers();
      results.sort((a, b) => a.priceUSD.compareTo(b.priceUSD));
      return results;
    }
    final partnerTransfers =
        (await _loadPartnerInventory('transfer', city: from))
            .map(TransferModel.fromJson)
            .where((transfer) =>
                transfer.pickupLocation.trim().toLowerCase() ==
                    from.trim().toLowerCase() &&
                transfer.dropoffLocation.trim().toLowerCase() ==
                    to.trim().toLowerCase() &&
                transfer.maxPassengers >= passengers &&
                (date == null ||
                    (transfer.pickupTime.year == date.year &&
                        transfer.pickupTime.month == date.month &&
                        transfer.pickupTime.day == date.day)))
            .toList();
    try {
      final res = await _dio.get(
        '/transfers/search',
        queryParameters: {
          'from': from,
          'to': to,
          if (date != null) 'date': _formatDate(date),
          'passengers': passengers,
        },
      );
      final results = (res.data['transfers'] as List)
          .map((t) => TransferModel.fromJson(t as Map<String, dynamic>))
          .toList();
      final allResults = [...partnerTransfers, ...results];
      allResults.sort((a, b) => a.priceUSD.compareTo(b.priceUSD));
      return allResults;
    } catch (_) {
      final results = MockDataService.transfers();
      final allResults = [...partnerTransfers, ...results];
      allResults.sort((a, b) => a.priceUSD.compareTo(b.priceUSD));
      return allResults;
    }
  }

  /// أماكن/معالم — بيشمل مطاعم ومقاهي كفئات (category) عن طريق الباك اند.
  Future<List<AttractionModel>> searchAttractions({
    required String city,
    String? category,
    String? country,
    String? language,
  }) async {
    if (useMockMode) {
      await Future.delayed(_mockDelay);
      final all = MockDataService.attractions();
      return category == null
          ? all
          : all.where((a) => a.category == category).toList();
    }
    try {
      final res = await _dio.get(
        '/attractions/search',
        queryParameters: {
          'city': city,
          if (category != null) 'category': category,
          if (country != null && country.isNotEmpty) 'country': country,
          if (language != null && language.isNotEmpty) 'lang': language,
        },
      );
      final attractions = (res.data['attractions'] as List)
          .map((a) => AttractionModel.fromJson(a as Map<String, dynamic>))
          .toList();
      return attractions;
    } catch (_) {
      rethrow;
    }
  }

  /// Records one anonymous place visit per device and UTC day.
  Future<void> recordAttractionVisit(String attractionId) async {
    if (useMockMode) return;
    final visitorId = await _dailyAttractionVisitorId();
    await _dio.post(
      '/attractions/${Uri.encodeComponent(attractionId)}/visits',
      data: {'visitor_id': visitorId},
    );
  }

  Future<String> _dailyAttractionVisitorId() async {
    final preferences = await SharedPreferences.getInstance();
    final now = DateTime.now().toUtc();
    final date = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    const dateKey = 'attraction_visitor_token_date';
    const tokenKey = 'attraction_visitor_token';
    if (preferences.getString(dateKey) == date) {
      final existing = preferences.getString(tokenKey);
      if (existing != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(existing)) {
        return existing;
      }
    }

    final random = Random.secure();
    final token = List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await preferences.setString(dateKey, date);
    await preferences.setString(tokenKey, token);
    return token;
  }

  Future<List<AttractionModel>> nearbyAttractions({
    required double lat,
    required double lng,
    double radiusMeters = 5000,
    String? category,
  }) async {
    if (useMockMode) {
      await Future.delayed(_mockDelay);
      final all = MockDataService.attractions();
      if (category != null) {
        return all.where((a) => a.category == category).toList();
      }
      return all
          .where((a) => a.category != 'restaurant' && a.category != 'cafe')
          .toList();
    }
    try {
      final res = await _dio.get(
        '/attractions/nearby',
        queryParameters: {
          'lat': lat,
          'lng': lng,
          'radius': radiusMeters,
          if (category != null) 'category': category,
        },
      );
      final attractions = (res.data['attractions'] as List)
          .map((a) => AttractionModel.fromJson(a as Map<String, dynamic>))
          .toList();
      return attractions;
    } catch (_) {
      final all = MockDataService.attractions();
      return category != null
          ? all.where((a) => a.category == category).toList()
          : all
              .where((a) => a.category != 'restaurant' && a.category != 'cafe')
              .toList();
    }
  }

  Future<List<AttractionModel>> nearbyRestaurants({
    required double lat,
    required double lng,
    double radiusMeters = 3000,
  }) =>
      nearbyAttractions(
        lat: lat,
        lng: lng,
        radiusMeters: radiusMeters,
        category: 'restaurant',
      );

  Future<List<AttractionModel>> nearbyCafes({
    required double lat,
    required double lng,
    double radiusMeters = 3000,
  }) =>
      nearbyAttractions(
        lat: lat,
        lng: lng,
        radiusMeters: radiusMeters,
        category: 'cafe',
      );

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Bookings (الرحلات في TripModel، والباقي في BookingModel) ────────────
  // في وضع المحاكاة بتتخزن محليًا (SharedPreferences) عشان تفضل موجودة حتى
  // بعد ما تقفل التطبيق. لما الباك اند يشتغل، هترجع تتخزن على السيرفر فعليًا
  // من غير أي تغيير في الشاشات اللي بتنادي الدوال دي.

  // مربوطين بإيميل الحساب الحالي — عشان رحلات/حجوزات حساب متتخلطش بحساب تاني
  // على نفس الجهاز.
  String get _flightTripsKey =>
      'local_flight_trips_${currentUser?.email ?? 'guest'}';
  String get _bookingsKey => 'local_bookings_${currentUser?.email ?? 'guest'}';

  Future<ApiResult<TripModel>> createFlightTrip(TripModel trip) async {
    if (useMockMode) {
      final result = await _request(() async {
        await Future.delayed(_mockDelay);
        final all = await _loadLocalFlightTrips();
        all.insert(0, trip);
        await _saveLocalFlightTrips(all);
        return trip;
      });
      if (result.isSuccess) flightTripsRevision.value++;
      return result;
    }
    final result = await _request(() async {
      final res = await _dio.post('/trips', data: trip.toJson());
      return TripModel.fromJson(res.data['trip'] as Map<String, dynamic>);
    });
    if (result.isSuccess) flightTripsRevision.value++;
    return result;
  }

  Future<ApiResult<bool>> checkFlightAvailability({
    required DateTime departureDate,
    required DateTime arrivalDate,
    DateTime? returnDate,
  }) async {
    return _request(() async {
      final res = await _dio.get(
        '/trips/availability',
        queryParameters: {
          'departure_date': departureDate.toUtc().toIso8601String(),
          'arrival_date': arrivalDate.toUtc().toIso8601String(),
          if (returnDate != null)
            'return_date': returnDate.toUtc().toIso8601String(),
        },
      );
      return res.data['available'] == true;
    });
  }

  Future<ApiResult<List<TripModel>>> getMyFlightTrips() async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        return _loadLocalFlightTrips();
      });
    }
    try {
      final res = await _dio.get('/trips');
      final trips = (res.data['trips'] as List)
          .map((t) => TripModel.fromJson(t as Map<String, dynamic>))
          .toList();
      await _saveLocalFlightTrips(
        trips,
      ); // تحديث النسخة المحفوظة محليًا كـ Cache
      return ApiResult.success(trips);
    } catch (e) {
      // مفيش نت أو السيرفر مش متجاوب — نرجّع آخر نسخة محفوظة بدل شاشة فاضية.
      final cached = await _loadLocalFlightTrips();
      if (cached.isNotEmpty) return ApiResult.success(cached);
      return ApiResult.failure(e.toString());
    }
  }

  /// إلغاء رحلة. الرحلة بتتحذف نهائيًا من قائمة الحجوزات — مش بس بتتحول
  /// لحالة "ملغاة" — عشان "الرحلة القادمة" ما تفضلش شايفة حجز اتلغى.
  Future<ApiResult<Map<String, dynamic>>> cancelFlightTrip(
      TripModel trip) async {
    if (useMockMode) {
      final result = await _request(() async {
        await Future.delayed(_mockDelay);
        final all = await _loadLocalFlightTrips();
        final index = all.indexWhere((t) => t.id == trip.id);
        if (index >= 0) {
          all[index] = all[index].copyWith(
            status: 'cancelled',
            refundStatus: 'pending_airline_review',
            refundMethod: 'original_payment_method',
          );
        }
        await _saveLocalFlightTrips(all);
        return <String, dynamic>{
          'status': 'cancelled',
          'refund_status': 'pending_airline_review',
          'refund_method': 'original_payment_method',
        };
      });
      if (result.isSuccess) flightTripsRevision.value++;
      return result;
    }
    final result = await _request(() async {
      final response = await _dio.delete('/trips/${trip.id}');
      return Map<String, dynamic>.from(response.data as Map);
    });
    if (result.isSuccess) flightTripsRevision.value++;
    return result;
  }

  Future<ApiResult<BookingModel>> createBooking(BookingModel booking) async {
    if (useMockMode) {
      final result = await _request(() async {
        await Future.delayed(_mockDelay);
        final all = await _loadLocalBookings();
        all.insert(0, booking);
        await _saveLocalBookings(all);
        return booking;
      });
      if (result.isSuccess) bookingsRevision.value++;
      return result;
    }
    final result = await _request(() async {
      final res = await _dio.post('/bookings', data: booking.toJson());
      return BookingModel.fromJson(res.data['booking'] as Map<String, dynamic>);
    });
    if (result.isSuccess) bookingsRevision.value++;
    return result;
  }

  Future<ApiResult<void>> cancelBooking(BookingModel booking) async {
    if (useMockMode) {
      final result = await _request(() async {
        await Future.delayed(_mockDelay);
        final all = await _loadLocalBookings();
        final index = all.indexWhere((item) => item.id == booking.id);
        if (index < 0) {
          throw StateError('The booking could not be found.');
        }
        final existing = all[index];
        all[index] = BookingModel(
          id: existing.id,
          type: existing.type,
          title: existing.title,
          subtitle: existing.subtitle,
          date: existing.date,
          endDate: existing.endDate,
          price: existing.price,
          refCode: existing.refCode,
          status: 'cancelled',
          imageUrl: existing.imageUrl,
          partnerListingId: existing.partnerListingId,
          rooms: existing.rooms,
        );
        await _saveLocalBookings(all);
      });
      if (result.isSuccess) bookingsRevision.value++;
      return result;
    }

    final result = await _request(() async {
      await _dio.delete('/bookings/${Uri.encodeComponent(booking.id)}');
    });
    if (result.isSuccess) bookingsRevision.value++;
    return result;
  }

  Future<ApiResult<bool>> checkBookingAvailability({
    required BookingType type,
    required String title,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    return _request(() async {
      final response = await _dio.get(
        '/bookings/availability',
        queryParameters: {
          'type': type.name,
          'title': title,
          'start_date': startDate.toUtc().toIso8601String(),
          'end_date': endDate.toUtc().toIso8601String(),
        },
      );
      return response.data['available'] == true;
    });
  }

  Future<ApiResult<List<BookingModel>>> getMyBookings() async {
    if (useMockMode) {
      return _request(() async {
        await Future.delayed(_mockDelay);
        return _loadLocalBookings();
      });
    }
    try {
      final res = await _dio.get('/bookings');
      final bookings = (res.data['bookings'] as List)
          .map((b) => BookingModel.fromJson(b as Map<String, dynamic>))
          .toList();
      await _saveLocalBookings(bookings);
      return ApiResult.success(bookings);
    } catch (e) {
      final cached = await _loadLocalBookings();
      if (cached.isNotEmpty) return ApiResult.success(cached);
      return ApiResult.failure(e.toString());
    }
  }

  Future<List<TripModel>> _loadLocalFlightTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_flightTripsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => TripModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveLocalFlightTrips(List<TripModel> trips) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _flightTripsKey,
      jsonEncode(trips.map((t) => t.toJson()).toList()),
    );
  }

  Future<List<BookingModel>> _loadLocalBookings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_bookingsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => BookingModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveLocalBookings(List<BookingModel> bookings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _bookingsKey,
      jsonEncode(bookings.map((b) => b.toJson()).toList()),
    );
  }

  // ── Mock helpers ────────────────────────────────────────────────────────

  UserModel _mockUser(String email) {
    final namePart = email.contains('@') ? email.split('@').first : email;
    final displayName = namePart.isEmpty
        ? 'Zentrip User'
        : namePart[0].toUpperCase() + namePart.substring(1);
    return UserModel(
      id: email.hashCode,
      name: displayName,
      email: email,
      phone: '+201000000000',
    );
  }

  // ── Token helpers ────────────────────────────────────────────────────────

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // ── User persistence (لوضع Mock فقط) ──────────────────────────────────
  // بيانات المستخدم نفسه (مش التوكن) — عشان restoreSession يرجّع نفس
  // الحساب اللي كان مسجّل دخول فعليًا بدل ما يخترع يوزر ثابت (demo).
  static const _localUserKey = 'local_current_user';

  Future<void> _saveUserLocally(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localUserKey, jsonEncode(user.toJson()));
  }

  Future<UserModel?> _loadLocalUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localUserKey);
    if (raw == null) return null;
    return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> _clearLocalUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localUserKey);
  }

  // ── Generic wrapper ──────────────────────────────────────────────────────

  Future<ApiResult<T>> _request<T>(Future<T> Function() fn) async {
    try {
      final result = await fn();
      return ApiResult.success(result);
    } on DioException catch (e) {
      final responseData = e.response?.data;
      var responseMessage = _extractResponseMessage(responseData);
      if (responseData is ResponseBody && responseMessage == null) {
        final body = await responseData.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();
        try {
          responseMessage = _extractResponseMessage(jsonDecode(body));
        } on FormatException {
          responseMessage = null;
        }
      }
      final msg = responseMessage ?? _dioErrorMessage(e);
      return ApiResult.failure(msg);
    } catch (e) {
      return ApiResult.failure(e.toString());
    }
  }

  String? _extractResponseMessage(Object? data) {
    if (data is! Map) return null;

    final errors = data['errors'];
    if (errors is Map) {
      for (final error in errors.values) {
        if (error is String && error.trim().isNotEmpty) return error;
        if (error is List) {
          for (final message in error) {
            if (message is String && message.trim().isNotEmpty) return message;
          }
        }
      }
    }

    for (final key in ['message', 'detail', 'error']) {
      final message = data[key];
      if (message is String && message.trim().isNotEmpty) return message;
    }
    return null;
  }

  String _dioErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The connection to the server timed out';
      case DioExceptionType.connectionError:
        return "Can't reach the Zentrip server at $baseUrl. Start the backend "
            'or check the API URL and device network settings.';
      default:
        return 'Something went wrong, please try again';
    }
  }
}

// Typedef لـ onSessionExpired callback (اسم مختلف عن VoidCallback بتاع Flutter
// عشان مايحصلش تعارض في الملفات اللي بتعمل import للاتنين مع بعض).
typedef SessionExpiredCallback = void Function();

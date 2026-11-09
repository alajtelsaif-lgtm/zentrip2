import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/api_service.dart';

// ── Models ───────────────────────────────────────────────────────────────────

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isItinerary;
  final Map<String, dynamic>? itineraryData;
  final bool isSavedItinerary;

  const ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isItinerary = false,
    this.itineraryData,
    this.isSavedItinerary = false,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'is_user': isUser,
        'timestamp': timestamp.toIso8601String(),
        'is_itinerary': isItinerary,
        'itinerary_data': itineraryData,
        'is_saved_itinerary': isSavedItinerary,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'] as String,
        isUser: json['is_user'] as bool,
        timestamp: DateTime.parse(json['timestamp'] as String),
        isItinerary: json['is_itinerary'] as bool? ?? false,
        itineraryData: json['itinerary_data'] as Map<String, dynamic>?,
        isSavedItinerary: json['is_saved_itinerary'] as bool? ?? false,
      );
}

class ChatSession {
  final String id;
  final String title;
  final DateTime savedAt;
  final List<ChatMessage> messages;

  const ChatSession({
    required this.id,
    required this.title,
    required this.savedAt,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'saved_at': savedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        title: json['title'] as String,
        savedAt: DateTime.parse(json['saved_at'] as String),
        messages: (json['messages'] as List)
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

// ── Controller ────────────────────────────────────────────────────────────────

/// Chat state and local transcript persistence for Zen AI.
class ChatbotController extends ChangeNotifier {
  static final RegExp _itineraryIntent = RegExp(
    r'\b(?:itinerary|travel plan|trip plan|plan (?:a |my |our )?trip)\b|برنامج|خطة سفر|جدول الرحلة|مسار الرحلة',
    caseSensitive: false,
  );

  static final RegExp _locationIntent = RegExp(
    r'\b(?:where am i|my location|near me|nearby|around me|closest|nearest)\b|موقعي|مكاني|أين أنا|بالقرب مني|قريب مني|قريبة مني|أماكن قريبة|الأماكن القريبة|حولِي',
    caseSensitive: false,
  );

  /// مفتاح مربوط بإيميل الحساب الحالي — عشان محادثات حساب متتخلطش بحساب تاني.
  static String get _historyKey =>
      'zen_chat_history_${ApiService.instance.currentUser?.email ?? 'guest'}';

  final List<ChatMessage> messages = [];
  bool isLoading = false;
  String? errorMessage;
  String _sessionId = DateTime.now().microsecondsSinceEpoch.toString();
  int _requestGeneration = 0;
  CancelToken? _activeCancelToken;
  String? _activeRequestId;
  ChatMessage? _pendingUserMessage;
  ChatMessage? _streamingAssistantMessage;

  bool get hasStreamedReply => _streamingAssistantMessage != null;

  // ── Localized strings supplied by the UI layer ──────────────────────────
  bool _isArabic = true;
  String _welcomeText = '';
  String _connectionErrorText = '';

  ChatbotController() {
    _addWelcome();
  }

  /// Called from the UI layer to inject locale-aware strings.
  /// Refreshes the welcome message in place when it's the only message shown.
  void configure({
    required bool isArabic,
    required String welcomeText,
    required String connectionErrorText,
  }) {
    _isArabic = isArabic;
    _welcomeText = welcomeText;
    _connectionErrorText = connectionErrorText;
    // Swap the placeholder welcome in place. No notifyListeners here: this is
    // invoked during build, and the ongoing build already renders this state.
    if (messages.length == 1 &&
        !messages.first.isUser &&
        messages.first.text != welcomeText) {
      messages[0] = ChatMessage(
          text: welcomeText,
          isUser: false,
          timestamp: messages.first.timestamp);
    }
  }

  void _addWelcome() {
    messages.add(ChatMessage(
      text: _welcomeText.isNotEmpty
          ? _welcomeText
          : 'أهلاً! أنا زن، مساعدك الذكي للسفر 🌍\nأخبرني بوجهتك المفضلة وسأساعدك في التخطيط لرحلة مثالية. يمكنك أيضاً طرح أسئلة عن الميزانية، أفضل وقت للسفر، أو طلب برنامج سفر كامل ✨',
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  static Map<String, dynamic>? parseItineraryResponse(
    String response, {
    String? requestedDestination,
  }) {
    final dayHeading = RegExp(
      r'^\s*(?:#{1,6}\s*)?(?:\*{1,2}\s*)?(?:day|اليوم)\s*([0-9٠-٩]+(?:\s*[-–—]\s*[0-9٠-٩]+)?)\s*(?:\|\s*|[：:–—-]\s*)?(.*?)(?:\*{1,2})?\s*$',
      caseSensitive: false,
    );
    final bullet = RegExp(r'^\s*(?:[-*•●▪]\s*|\d+[.)]\s*)(.+?)\s*$');
    final budgetPattern = RegExp(
      r'(?:estimated (?:cost|budget)|التكلفة التقديرية|الميزانية التقديرية|ميزانية تقديرية)\s*[:：]?\s*(.+)$',
      caseSensitive: false,
    );
    final days = <Map<String, dynamic>>[];
    Map<String, dynamic>? currentDay;
    String? budget;

    for (final rawLine in response.split('\n')) {
      final line = rawLine.replaceAll(RegExp(r'[*_`]'), '').trim();
      if (line.isEmpty) continue;

      final dayMatch = dayHeading.firstMatch(rawLine.trim());
      if (dayMatch != null) {
        final number = dayMatch.group(1)!.replaceAll(RegExp(r'\s+'), '');
        final title = dayMatch.group(2)?.trim() ?? '';
        final dayLabel = RegExp(r'اليوم', caseSensitive: false)
                .hasMatch(rawLine)
            ? 'اليوم'
            : 'Day';
        currentDay = <String, dynamic>{
          'title': title.isEmpty ? '$dayLabel $number' : '$dayLabel $number | $title',
          'activities': <String>[],
        };
        days.add(currentDay);
        continue;
      }

      budget ??= budgetPattern.firstMatch(line)?.group(1)?.trim();
      final activity = bullet.firstMatch(rawLine)?.group(1)?.trim();
      if (currentDay != null && activity != null && activity.isNotEmpty) {
        (currentDay['activities'] as List<String>).add(activity);
      }
    }

    if (days.isEmpty) return null;

    final destination = _extractRequestedDestination(requestedDestination ?? '');
    return <String, dynamic>{
      if (destination != null) 'destination': destination,
      'days': days,
      if (budget != null && budget.isNotEmpty) 'estimated_budget': budget,
    };
  }

  static String? _extractRequestedDestination(String text) {
    if (text.trim().isEmpty) return null;
    final match = RegExp(
      r'\b(?:to|for)\s+([^.!?,\n]+)|(?:إلى|الى|عن)\s*([^،.!؟?\n]+)',
      caseSensitive: false,
    ).firstMatch(text);
    var destination = (match?.group(1) ?? match?.group(2) ?? '').trim();
    destination = destination.replaceFirst(
      RegExp(
        r'\s+(?:(?:for|over|lasting)\b|لمدة|للمدة).*$',
        caseSensitive: false,
      ),
      '',
    );
    return destination.isEmpty ? null : destination;
  }

  Future<void> sendMessage(String text) async {
    final messageText = text.trim();
    if (messageText.isEmpty || isLoading) return;

    final generation = ++_requestGeneration;
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    final cancelToken = CancelToken();
    final userMessage =
        ChatMessage(text: messageText, isUser: true, timestamp: DateTime.now());
    _activeCancelToken = cancelToken;
    _activeRequestId = requestId;
    _pendingUserMessage = userMessage;
    _streamingAssistantMessage = null;
    messages.add(userMessage);
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final String reply;
      if (ApiService.useMockMode) {
        reply = await _mockAIResponse(text);
      } else {
        final wantsLocation = _locationIntent.hasMatch(messageText);
        final currentLocation =
            wantsLocation ? await _getCurrentLocationIfAllowed() : null;
        final result = await ApiService.instance.sendChatMessage(
          message: messageText,
          sessionId: _sessionId,
          language: _isArabic ? 'ar' : 'en',
          requestId: requestId,
          locationRequested: wantsLocation,
          currentLocation: currentLocation,
          cancelToken: cancelToken,
          onChunk: (delta) {
            if (generation != _requestGeneration) return;
            final previous = _streamingAssistantMessage;
            final streamedMessage = ChatMessage(
              text: '${previous?.text ?? ''}$delta',
              isUser: false,
              timestamp: previous?.timestamp ?? DateTime.now(),
            );
            if (previous == null) {
              messages.add(streamedMessage);
            } else {
              final index = messages.indexOf(previous);
              if (index >= 0) messages[index] = streamedMessage;
            }
            _streamingAssistantMessage = streamedMessage;
            notifyListeners();
          },
        );
        if (generation != _requestGeneration) return;
        if (result.isFailure || result.data == null) {
          errorMessage = result.errorMessage ?? _connectionErrorText;
          return;
        }
        reply = result.data!;
      }

      if (generation != _requestGeneration) return;

      final itineraryData = _itineraryIntent.hasMatch(messageText)
          ? parseItineraryResponse(
              reply,
              requestedDestination: messageText,
            )
          : null;
      final streamedMessage = _streamingAssistantMessage;
      final completedMessage = ChatMessage(
        text: reply,
        isUser: false,
        timestamp: streamedMessage?.timestamp ?? DateTime.now(),
        isItinerary: itineraryData != null,
        itineraryData: itineraryData,
      );
      if (streamedMessage == null) {
        messages.add(completedMessage);
      } else {
        final index = messages.indexOf(streamedMessage);
        if (index >= 0) {
          messages[index] = completedMessage;
          _streamingAssistantMessage = completedMessage;
        }
      }
      await _autoSave();
    } catch (e) {
      if (generation == _requestGeneration && !cancelToken.isCancelled) {
        errorMessage = _connectionErrorText.isNotEmpty
            ? _connectionErrorText
            : 'تعذّر الاتصال بالمساعد الذكي';
      }
    } finally {
      if (generation == _requestGeneration) {
        isLoading = false;
        _activeCancelToken = null;
        _activeRequestId = null;
        _pendingUserMessage = null;
        _streamingAssistantMessage = null;
        notifyListeners();
      }
    }
  }

  Future<Map<String, Object?>?> _getCurrentLocationIfAllowed() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 4),
      );
      final location = <String, Object?>{
        'latitude': position.latitude,
        'longitude': position.longitude,
      };
      try {
        final placemarks = await Geocoding()
            .placemarkFromCoordinates(position.latitude, position.longitude)
            .timeout(const Duration(seconds: 5));
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          final placeFields = <String, String?>{
            'locality': placemark.locality,
            'sub_locality': placemark.subLocality,
            'administrative_area': placemark.administrativeArea,
            'country': placemark.country,
            'country_code': placemark.isoCountryCode,
          };
          for (final entry in placeFields.entries) {
            final value = entry.value?.trim();
            if (value != null && value.isNotEmpty) {
              location[entry.key] = value;
            }
          }
        }
      } catch (_) {
        // Keep coordinates if platform reverse geocoding is unavailable.
      }
      return location;
    } catch (_) {
      return null;
    }
  }

  void cancelResponse() {
    if (!isLoading) return;

    final sessionId = _sessionId;
    final requestId = _activeRequestId;
    _requestGeneration++;
    _activeCancelToken?.cancel('Cancelled by user');
    _activeCancelToken = null;
    _activeRequestId = null;
    isLoading = false;
    errorMessage = null;
    final streamedMessage = _streamingAssistantMessage;
    if (streamedMessage != null) messages.remove(streamedMessage);
    _streamingAssistantMessage = null;
    final pendingMessage = _pendingUserMessage;
    if (pendingMessage != null) messages.remove(pendingMessage);
    _pendingUserMessage = null;
    notifyListeners();

    if (requestId != null && !ApiService.useMockMode) {
      unawaited(ApiService.instance.cancelChatMessage(
        sessionId: sessionId,
        requestId: requestId,
      ));
    }
  }

  Future<void> requestItinerarySuggestion(String destination) async {
    await sendMessage(_isArabic
        ? 'أريد برنامج سفر كامل إلى $destination لمدة 7 أيام'
        : 'I want a full 7-day travel itinerary for $destination');
  }

  Future<void> saveItinerary(ChatMessage message) async {
    final index = messages.indexOf(message);
    if (index < 0 || !message.isItinerary || message.itineraryData == null) {
      throw StateError('This message does not contain a saveable itinerary.');
    }
    if (message.isSavedItinerary) return;

    messages[index] = ChatMessage(
      text: message.text,
      isUser: false,
      timestamp: message.timestamp,
      isItinerary: true,
      itineraryData: message.itineraryData,
      isSavedItinerary: true,
    );
    await _autoSave();
    notifyListeners();
  }

  void clearChat() {
    cancelResponse();
    _sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    messages.clear();
    _addWelcome();
    notifyListeners();
  }

  void loadSession(ChatSession session) {
    cancelResponse();
    _sessionId = session.id;
    messages
      ..clear()
      ..addAll(session.messages);
    notifyListeners();
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _autoSave() async {
    if (!messages.any((m) => m.isUser)) return;
    final first =
        messages.firstWhere((m) => m.isUser, orElse: () => messages.first);
    final session = ChatSession(
      id: _sessionId,
      title: first.text.length > 42
          ? '${first.text.substring(0, 42)}...'
          : first.text,
      savedAt: DateTime.now(),
      messages: List.of(messages),
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyKey) ?? [];
    final sessions = raw
        .map((e) => ChatSession.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
    sessions.removeWhere((s) => s.id == _sessionId);
    sessions.insert(0, session);
    await prefs.setStringList(_historyKey,
        sessions.take(20).map((s) => jsonEncode(s.toJson())).toList());
  }

  static Future<List<ChatSession>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyKey) ?? [];
    return raw
        .map((e) => ChatSession.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> deleteSession(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_historyKey) ?? [];
    final sessions = raw
        .map((e) => ChatSession.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
    sessions.removeWhere((s) => s.id == id);
    await prefs.setStringList(
        _historyKey, sessions.map((s) => jsonEncode(s.toJson())).toList());
  }

  // ── Mock AI (احذف هذا عند ربط Python service) ────────────────────────────

  Future<String> _mockAIResponse(String input) async {
    await Future.delayed(const Duration(milliseconds: 1200));
    final lower = input.toLowerCase();
    if (lower.contains('إسطنبول') || lower.contains('istanbul')) {
      return _isArabic
          ? '''🗺️ **برنامج إسطنبول — 7 أيام**

**اليوم 1-2 | الجانب الأوروبي**
• آيا صوفيا والمسجد الأزرق
• قصر توبقابي
• جامعة إسطنبول والبازار الكبير

**اليوم 3 | مضيق البوسفور**
• جولة بحرية عبر المضيق
• قصر دولمة بهجة

**اليوم 4-5 | الجانب الآسيوي**
• حي كاديكوي وسوق الحي
• برج العذراء والمنارة الضوئية

**اليوم 6-7 | التسوق والترفيه**
• شارع الاستقلال وتقسيم
• تجربة حمام تركي تقليدي

💰 **التكلفة التقديرية:** من \$900 للشخص'''
          : '''🗺️ **Istanbul Itinerary — 7 Days**

**Day 1-2 | European Side**
• Hagia Sophia & the Blue Mosque
• Topkapi Palace
• Istanbul University & the Grand Bazaar

**Day 3 | The Bosphorus**
• Cruise along the strait
• Dolmabahçe Palace

**Day 4-5 | Asian Side**
• Kadıköy district & local market
• Maiden's Tower & the lighthouse

**Day 6-7 | Shopping & Leisure**
• Istiklal Avenue & Taksim
• A traditional Turkish bath experience

💰 **Estimated cost:** from \$900 per person''';
    }
    if (lower.contains('ميزان') ||
        lower.contains('تكلف') ||
        lower.contains('سعر') ||
        lower.contains('budget') ||
        lower.contains('cost') ||
        lower.contains('price')) {
      return _isArabic
          ? 'تتراوح تكاليف السفر بشكل عام بين:\n\n🟢 اقتصادي: \$500-800/شخص/أسبوع\n🔵 متوسط: \$1200-2000/شخص/أسبوع\n🟡 فاخر: \$3000+/شخص/أسبوع\n\nأخبرني بوجهتك وميزانيتك وسأقترح لك أفضل الخيارات!'
          : 'Travel costs generally fall into these ranges:\n\n🟢 Budget: \$500-800/person/week\n🔵 Mid-range: \$1200-2000/person/week\n🟡 Luxury: \$3000+/person/week\n\nTell me your destination and budget, and I\'ll suggest the best options for you!';
    }
    if (lower.contains('بالي') || lower.contains('bali')) {
      return _isArabic
          ? '🌴 بالي وجهة رائعة!\n\nأفضل وقت للزيارة: أبريل-أكتوبر\nمتوسط التكلفة: \$1200-1800/أسبوع\n\nالأماكن الأبرز:\n• معابد أوبود\n• شاطئ سيمينياك\n• منازل أوبود الريفية\n• جبل أغونج (لمحبي الطبيعة)\n\nهل تريد برنامجاً تفصيلياً؟ 🗺️'
          : '🌴 Bali is a wonderful choice!\n\nBest time to visit: April-October\nAverage cost: \$1200-1800/week\n\nTop highlights:\n• Ubud temples\n• Seminyak beach\n• Ubud countryside villas\n• Mount Agung (for nature lovers)\n\nWould you like a detailed itinerary? 🗺️';
    }
    return _isArabic
        ? 'شكراً على سؤالك! 😊\n\nلمساعدتك بشكل أفضل، أخبرني:\n• ما هي وجهتك المفضلة؟\n• كم مدة الرحلة؟\n• ما هو ميزانيتك التقريبية؟\n\nوسأعدّ لك برنامجاً سفر مثالياً! ✈️'
        : 'Thanks for your question! 😊\n\nTo help you better, tell me:\n• What\'s your favorite destination?\n• How long is the trip?\n• What\'s your approximate budget?\n\nAnd I\'ll craft the perfect travel itinerary for you! ✈️';
  }
}

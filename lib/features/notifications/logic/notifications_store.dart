import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/api_service.dart';
import '../../../models/travel_package_model.dart';
import '../../../models/trip_model.dart';

enum NotifKind { booking, cancel, chat, promo, reminder }

class NotificationItem {
  final String id;
  final NotifKind kind;
  final String title;
  final String subtitle;
  final String? titleAr;
  final String? subtitleAr;
  final DateTime createdAt;
  final bool isRead;
  final int? serverId;
  final String? targetType;
  final int? targetId;
  final String? bookingRef;

  const NotificationItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    this.isRead = false,
    this.titleAr,
    this.subtitleAr,
    this.serverId,
    this.targetType,
    this.targetId,
    this.bookingRef,
  });

  String localizedTitle(String languageCode) =>
      languageCode == 'ar' ? titleAr ?? title : title;

  String localizedSubtitle(String languageCode) =>
      languageCode == 'ar' ? subtitleAr ?? subtitle : subtitle;

  NotificationItem copyWith({bool? isRead}) => NotificationItem(
        id: id,
        kind: kind,
        title: title,
        subtitle: subtitle,
        titleAr: titleAr,
        subtitleAr: subtitleAr,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        serverId: serverId,
        targetType: targetType,
        targetId: targetId,
        bookingRef: bookingRef,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'subtitle': subtitle,
        'created_at': createdAt.toIso8601String(),
        'is_read': isRead,
        if (bookingRef != null) 'booking_ref': bookingRef,
      };

  factory NotificationItem.fromJson(Map<String, dynamic> j) {
    final id = j['id']?.toString() ?? '';
    final kindName = j['kind']?.toString();
    return NotificationItem(
      id: id,
      kind: NotifKind.values.firstWhere(
        (kind) => kind.name == kindName,
        orElse: () => NotifKind.booking,
      ),
      title: j['title']?.toString() ?? '',
      subtitle: j['subtitle']?.toString() ?? '',
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isRead: j['is_read'] == true,
      bookingRef: j['booking_ref']?.toString(),
    );
  }

  factory NotificationItem.fromServerJson(Map<String, dynamic> json) {
    final id = _notificationInteger(json['id']);
    final kindName = json['kind']?.toString();
    return NotificationItem(
      id: 'server-$id',
      serverId: id,
      kind: NotifKind.values.firstWhere(
        (kind) => kind.name == kindName,
        orElse: () => NotifKind.booking,
      ),
      title: json['title_en']?.toString() ?? '',
      titleAr: json['title_ar']?.toString(),
      subtitle: json['body_en']?.toString() ?? '',
      subtitleAr: json['body_ar']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isRead: json['is_read'] == true,
      targetType: json['target_type']?.toString(),
      targetId: _notificationInteger(json['target_id']),
      bookingRef: json['booking_ref']?.toString(),
    );
  }

  static int? _notificationInteger(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

/// إشعارات حقيقية بتتولّد من أحداث فعلية في التطبيق (حجز ناجح، إلغاء
/// رحلة..إلخ) — مش بيانات وهمية ثابتة. متخزنة محليًا ومربوطة بحساب
/// المستخدم الحالي، بنفس أسلوب المفضلة بالظبط.
class NotificationsStore extends ChangeNotifier {
  static final NotificationsStore instance = NotificationsStore._();
  NotificationsStore._();

  static const int _maxStored = 30;
  final List<NotificationItem> _items = [];

  List<NotificationItem> get all => List.unmodifiable(_items);
  bool get hasUnread => _items.any((n) => !n.isRead);
  int get unreadCount => _items.where((notification) => !notification.isRead).length;

  String get _key => 'notifications_${ApiService.instance.currentUser?.email ?? 'guest'}';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final keyAtLoad = _key;
    final raw = prefs.getStringList(_key) ?? [];
    _items
      ..clear()
      ..addAll(raw.map((entry) {
        try {
          return NotificationItem.fromJson(
              jsonDecode(entry) as Map<String, dynamic>);
        } catch (error) {
          debugPrint('Ignoring invalid saved notification: $error');
          return null;
        }
      }).whereType<NotificationItem>());
    _sortNewestFirst();
    notifyListeners();

    if (ApiService.instance.currentUser == null) return;
    final result = await ApiService.instance.getNotifications();
    if (!result.isSuccess || result.data == null || _key != keyAtLoad) return;
    final localItems =
        _items.where((notification) => notification.serverId == null).toList();
    final serverBookingRefs = result.data!
        .map((row) => row['booking_ref']?.toString())
        .whereType<String>()
        .where((reference) => reference.isNotEmpty)
        .toSet();
    localItems.removeWhere((notification) =>
        notification.bookingRef != null &&
        serverBookingRefs.contains(notification.bookingRef));
    _items
      ..clear()
      ..addAll(result.data!.map(NotificationItem.fromServerJson))
      ..addAll(localItems);
    _sortNewestFirst();
    notifyListeners();
    await _persist();
  }

  /// بتتنادى عند تسجيل الخروج — عشان الإشعارات متفضلش في الذاكرة لحساب قديم.
  void clear() {
    _items.clear();
    notifyListeners();
  }

  Future<void> add({
    required NotifKind kind,
    required String title,
    required String subtitle,
    String? dedupeId,
    String? bookingRef,
  }) async {
    if (dedupeId != null && _items.any((n) => n.id == dedupeId)) return; // إشعار زي ده اتبعت قبل كده
    _items.insert(0, NotificationItem(
      id: dedupeId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      kind: kind,
      title: title,
      subtitle: subtitle,
      createdAt: DateTime.now(),
      bookingRef: bookingRef,
    ));
    if (_items.length > _maxStored) _items.removeRange(_maxStored, _items.length);
    notifyListeners();
    await _persist();
  }

  Future<void> refreshAfterBooking({
    required String title,
    required String subtitle,
    required String bookingRef,
  }) async {
    final normalizedReference = bookingRef.trim();
    await load();
    if (_items.any((notification) =>
        notification.serverId != null &&
        notification.bookingRef == normalizedReference)) {
      return;
    }
    await add(
      kind: NotifKind.booking,
      title: title,
      subtitle: subtitle,
      bookingRef: normalizedReference,
      dedupeId: 'local-booking-$normalizedReference',
    );
  }

  /// بتقارن العروض الحالية بآخر عروض شافها المستخدم، وتولّد إشعار بس
  /// للعروض الجديدة فعلاً. أول مرة يفتح فيها المستخدم التطبيق، كل العروض
  /// بتتسجّل كـ "متشافة" من غير ما تغرقه بإشعارات لعروض كانت موجودة أصلاً.
  Future<void> notifyNewOffers(List<TravelPackage> offers, {required String promoTitle}) async {
    final seenKey = '${_key}_seen_offers';
    final prefs = await SharedPreferences.getInstance();
    final seen = (prefs.getStringList(seenKey) ?? []).toSet();
    final isFirstRun = seen.isEmpty;
    var changed = false;
    for (final o in offers) {
      if (seen.add(o.id)) {
        changed = true;
        if (!isFirstRun) {
          await add(kind: NotifKind.promo, title: promoTitle, subtitle: o.title, dedupeId: 'offer_${o.id}');
        }
      }
    }
    if (changed) await prefs.setStringList(seenKey, seen.toList());
  }

  /// بيدوّر على رحلات قريب ميعادها (خلال 3 أيام) ويولّد تذكير — مرة واحدة
  /// بس لكل رحلة (مش هيكرر التذكير كل ما تفتح التطبيق).
  Future<void> checkTripReminders(List<TripModel> trips, {required String reminderTitle}) async {
    final now = DateTime.now();
    for (final t in trips) {
      if (t.status != 'upcoming') continue;
      final daysUntil = t.departureDate.difference(now).inDays;
      if (daysUntil < 0 || daysUntil > 3) continue;
      await add(
        kind: NotifKind.reminder,
        title: reminderTitle,
        subtitle: '${t.originCode} → ${t.destinationCode}',
        dedupeId: 'reminder_${t.id}',
      );
    }
  }

  Future<void> markRead(String id) async {
    final index = _items.indexWhere((notification) => notification.id == id);
    if (index < 0 || _items[index].isRead) return;
    final notification = _items[index];
    if (notification.serverId != null) {
      final result = await ApiService.instance
          .markNotificationRead(notification.serverId!);
      if (!result.isSuccess) return;
    }
    _items[index] = notification.copyWith(isRead: true);
    notifyListeners();
    await _persist();
  }

  Future<void> markAllRead() async {
    if (!hasUnread) return;
    final unreadServerItems =
        _items.where((item) => !item.isRead && item.serverId != null);
    var serverMarked = unreadServerItems.isEmpty;
    if (!serverMarked && ApiService.instance.currentUser != null) {
      serverMarked =
          (await ApiService.instance.markAllNotificationsRead()).isSuccess;
    }
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].serverId == null || serverMarked) {
        _items[i] = _items[i].copyWith(isRead: true);
      }
    }
    notifyListeners();
    await _persist();
  }

  void _sortNewestFirst() {
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final localItems =
        _items.where((notification) => notification.serverId == null);
    await prefs.setStringList(
      _key,
      localItems.map((notification) => jsonEncode(notification.toJson())).toList(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zentrip/core/services/api_service.dart';
import 'package:zentrip/features/notifications/logic/notifications_store.dart';
import 'package:zentrip/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiService.instance.currentUser = null;
    NotificationsStore.instance.clear();
    await NotificationsStore.instance.load();
  });

  tearDown(() {
    NotificationsStore.instance.clear();
  });

  test('server notification preserves translated text and booking target', () {
    final notification = NotificationItem.fromServerJson({
      'id': 17,
      'kind': 'booking',
      'title_en': 'Flight booking confirmed',
      'title_ar': 'تم تأكيد حجز الرحلة',
      'body_en': 'Your flight is confirmed.',
      'body_ar': 'تم تأكيد رحلتك.',
      'created_at': '2026-11-07T10:00:00Z',
      'is_read': false,
      'target_type': 'trip',
      'target_id': 42,
      'booking_ref': 'ZT-1234',
    });

    expect(notification.serverId, 17);
    expect(notification.localizedTitle('ar'), 'تم تأكيد حجز الرحلة');
    expect(notification.localizedSubtitle('en'), 'Your flight is confirmed.');
    expect(notification.targetType, 'trip');
    expect(notification.targetId, 42);
    expect(notification.bookingRef, 'ZT-1234');
  });

  test('successful booking still creates an inbox alert while offline', () async {
    await NotificationsStore.instance.refreshAfterBooking(
      title: 'Booking confirmed',
      subtitle: 'Stay at City Hotel is confirmed.',
      bookingRef: 'ZT-OFFLINE-1',
    );

    expect(NotificationsStore.instance.all, hasLength(1));
    expect(NotificationsStore.instance.all.single.bookingRef, 'ZT-OFFLINE-1');
    expect(NotificationsStore.instance.all.single.serverId, isNull);
  });

  testWidgets('notification center displays booking and marks local alerts read',
      (tester) async {
    await NotificationsStore.instance.add(
      kind: NotifKind.booking,
      title: 'Booking confirmed',
      subtitle: 'Hotel stay confirmed.',
    );

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: NotificationsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(find.text('Hotel stay confirmed.'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);

    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();

    expect(NotificationsStore.instance.hasUnread, isFalse);
    expect(find.text('Mark all read'), findsNothing);
  });
}

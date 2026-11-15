import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/features/auth/presentation/screens/login_screen.dart';

void main() {
  for (final size in const [
    Size(360, 640),
    Size(402, 874),
    Size(1280, 900),
  ]) {
    testWidgets('login header and sheet align on ${size.height}px screen',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 12);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewPadding);

      await tester.pumpWidget(const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LoginScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      final sheetRect = tester.getRect(find.byType(SingleChildScrollView));
      final signRect =
          tester.getRect(find.byIcon(Icons.directions_bus_rounded));
      final poleRect =
          tester.getRect(find.byKey(const ValueKey('bus-stop-sign-pole')));
      expect(sheetRect.top, lessThan(size.height * 0.30));
      expect(signRect.top, greaterThanOrEqualTo(32));
      expect(signRect.bottom, lessThan(sheetRect.top));
      expect(poleRect.height, 34);
      expect(poleRect.top, greaterThan(signRect.bottom));
      expect(poleRect.bottom, closeTo(sheetRect.top, 0.01));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

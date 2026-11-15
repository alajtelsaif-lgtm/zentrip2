import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/features/auth/presentation/screens/register_screen.dart';

void main() {
  testWidgets('phone input filters digits and applies country length limits',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RegisterScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    final phoneField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Enter your phone number',
    );
    await tester.ensureVisible(phoneField);
    await tester.pump();

    await tester.enterText(phoneField, '01abc234567890');
    expect(tester.widget<TextField>(phoneField).controller!.text, '012345678');
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('+218'));
    await tester.tap(find.text('+218'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Egypt'));
    await tester.tap(find.text('Egypt'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(phoneField, '012345678901');
    expect(tester.widget<TextField>(phoneField).controller!.text.length, 10);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

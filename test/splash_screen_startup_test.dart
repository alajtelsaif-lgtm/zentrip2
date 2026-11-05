import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentrip/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:zentrip/features/splash/presentation/screen/splash_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      OnboardingScreen.seenKey: true,
    });
  });

  testWidgets('splash navigates to sign-in after its delay without a session',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SplashScreen(),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(
          body: Text(settings.name ?? 'missing route'),
        ),
      ),
    ));

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('/auth'), findsOneWidget);
  });

  testWidgets('onboarding Skip navigates to sign-in', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const OnboardingScreen(),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(
          body: Text(settings.name ?? 'missing route'),
        ),
      ),
    ));

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('/auth'), findsOneWidget);
  });
}

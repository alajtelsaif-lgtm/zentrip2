import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:zentrip/features/auth/presentation/screens/login_screen.dart';
import 'package:zentrip/features/auth/presentation/screens/register_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';

Widget _arabic(Widget home) => MaterialApp(
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  testWidgets('login screen is shown in Arabic', (tester) async {
    await tester.pumpWidget(_arabic(const LoginScreen()));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('تسجيل الدخول'), findsWidgets);
    expect(find.text('Login'), findsNothing);
  });

  testWidgets('register screen is shown in Arabic', (tester) async {
    await tester.pumpWidget(_arabic(const RegisterScreen()));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('إنشاء حساب'), findsWidgets);
    expect(find.text('Create Account'), findsNothing);
  });

  testWidgets('forgot password screen is shown in Arabic', (tester) async {
    await tester.pumpWidget(_arabic(const ForgotPasswordScreen()));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('إرسال رمز إعادة التعيين'), findsOneWidget);
  });
}

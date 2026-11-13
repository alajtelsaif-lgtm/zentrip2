import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/core/services/api_service.dart';
import 'package:zentrip/features/auth/logic/auth_controller.dart';
import 'package:zentrip/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:zentrip/features/auth/presentation/screens/reset_password_screen.dart';
import 'package:zentrip/l10n/app_localizations.dart';
import 'package:zentrip/routes/app_routes.dart';

void main() {
  test('demo reset mode is limited to Replit preview hosts', () {
    expect(
        ApiService.isDemoPasswordResetHost('project.spock.replit.dev'), isTrue);
    expect(ApiService.isDemoPasswordResetHost('localhost'), isTrue);
    expect(ApiService.isDemoPasswordResetHost('project.replit.app'), isFalse);
    expect(
        ApiService.isDemoPasswordResetHost('replit.dev.example.com'), isFalse);
  });

  testWidgets(
      'sending a reset code opens reset page and successful reset returns to login',
      (tester) async {
    _setViewport(tester);
    final auth = _FakeAuthController();
    addTearDown(auth.dispose);
    await tester.pumpWidget(_app(auth));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
        find.byType(TextField).first, 'traveler@example.com');
    await tester.tap(find.text('Send Reset Code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(auth.sentEmail, 'traveler@example.com');
    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    expect(find.text('traveler@example.com'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.enterText(find.byType(TextField).at(1), 'travel-pass-42');
    await tester.enterText(find.byType(TextField).at(2), 'travel-pass-42');
    await tester.ensureVisible(find.text('Reset Password'));
    await tester.tap(find.text('Reset Password'));
    await tester.pump();

    expect(auth.resetEmail, 'traveler@example.com');
    expect(auth.resetCode, '123456');
    expect(auth.resetPasswordValue, 'travel-pass-42');
    expect(
      find.text('Password changed successfully'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Login destination'), findsOneWidget);
    expect(find.text('Back to Login'), findsNothing);
  });

  testWidgets('reset page validates empty, short, and mismatched passwords',
      (tester) async {
    _setViewport(tester);
    final auth = _FakeAuthController();
    addTearDown(auth.dispose);
    await tester.pumpWidget(_app(auth));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
        find.byType(TextField).first, 'traveler@example.com');
    await tester.tap(find.text('Send Reset Code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.ensureVisible(find.text('Reset Password'));
    await tester.tap(find.text('Reset Password'));
    await tester.pump();
    expect(find.text('Enter the valid 6-digit reset code'), findsOneWidget);
    expect(auth.resetPasswordValue, isNull);

    await tester.enterText(find.byType(TextField).at(0), '123456');
    await tester.ensureVisible(find.text('Reset Password'));
    await tester.tap(find.text('Reset Password'));
    await tester.pump();
    expect(find.text('Enter and confirm your new password'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'short');
    await tester.enterText(find.byType(TextField).at(2), 'short');
    await tester.ensureVisible(find.text('Reset Password'));
    await tester.tap(find.text('Reset Password'));
    await tester.pump();
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(auth.resetPasswordValue, isNull);

    await tester.enterText(find.byType(TextField).at(1), 'travel-pass-42');
    await tester.enterText(find.byType(TextField).at(2), 'another-pass-42');
    await tester.ensureVisible(find.text('Reset Password'));
    await tester.tap(find.text('Reset Password'));
    await tester.pump();
    expect(find.text("Passwords don't match"), findsOneWidget);
    expect(auth.resetPasswordValue, isNull);
  });

  testWidgets('reset request failure stays on forgot-password screen',
      (tester) async {
    _setViewport(tester);
    final auth = _FakeAuthController()
      ..sendSuccess = false
      ..errorMessage = 'Password recovery email is not configured.';
    addTearDown(auth.dispose);
    await tester.pumpWidget(_app(auth));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(
        find.byType(TextField).first, 'traveler@example.com');
    await tester.tap(find.text('Send Reset Code'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Forgot Your Password?'), findsOneWidget);
    expect(find.text('Verify Your'), findsNothing);
    expect(find.text('Password recovery email is not configured.'),
        findsOneWidget);
  });
}

Widget _app(_FakeAuthController auth) {
  return MaterialApp(
    home: ForgotPasswordScreen(authController: auth),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    onGenerateRoute: (settings) {
      switch (settings.name) {
        case AppRoutes.resetPassword:
          return PageRouteBuilder<void>(
            settings: settings,
            transitionDuration: Duration.zero,
            pageBuilder: (_, __, ___) => ResetPasswordScreen(
              email: settings.arguments! as String,
              authController: auth,
            ),
          );
        case AppRoutes.auth:
          return PageRouteBuilder<void>(
            settings: settings,
            transitionDuration: Duration.zero,
            pageBuilder: (_, __, ___) => const Scaffold(
              body: Center(child: Text('Login destination')),
            ),
          );
      }
      return null;
    },
  );
}

void _setViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _FakeAuthController extends AuthController {
  bool sendSuccess = true;
  bool verifySuccess = true;
  bool resetSuccess = true;
  String? sentEmail;
  String? resetEmail;
  String? resetCode;
  String? resetPasswordValue;

  @override
  Future<bool> sendResetCode({required String email}) async {
    sentEmail = email;
    return sendSuccess;
  }

  @override
  Future<bool> verifyResetCode({
    required String email,
    required String code,
  }) async {
    return verifySuccess;
  }

  @override
  Future<bool> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    resetEmail = email;
    resetCode = code;
    if (resetSuccess) resetPasswordValue = newPassword;
    return resetSuccess;
  }
}

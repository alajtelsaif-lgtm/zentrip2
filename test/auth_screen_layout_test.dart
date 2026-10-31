import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentrip/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:zentrip/features/auth/presentation/screens/login_screen.dart';
import 'package:zentrip/features/auth/presentation/screens/register_screen.dart';
import 'package:zentrip/features/auth/presentation/screens/verfiy_screen.dart.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('forgot password sheet fills the bottom and scrolls to actions',
      (tester) async {
    _setViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(home: ForgotPasswordScreen()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final scrollRect = tester.getRect(find.byType(SingleChildScrollView));
    expect(scrollRect.bottom, closeTo(tester.view.physicalSize.height, 1));
    final titleRect = tester.getRect(find.text('Forgot Your Password?'));
    expect(titleRect.center.dy, greaterThan(scrollRect.top + 60));
    expect(titleRect.center.dy, lessThan(scrollRect.bottom - 200));
    await tester.ensureVisible(find.text('Send Reset Code'));
    await tester.pump();
    expect(find.text('Send Reset Code'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('registration sheet fills the bottom and scrolls to actions',
      (tester) async {
    _setViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(home: RegisterScreen()),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final scrollRect = tester.getRect(find.byType(SingleChildScrollView));
    expect(scrollRect.bottom, closeTo(tester.view.physicalSize.height, 1));
    await tester.ensureVisible(find.text('Create Account'));
    await tester.pump();
    expect(find.text('Create Account'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('OTP sheet fits compact screens and scrolls to verification',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: VerifyScreen(email: 'traveler@example.com'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Verify Code'));
    await tester.pump();
    expect(find.text('Verify Code'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('login sheet fits compact screens and clears the keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    final createAccountText = find.byWidgetPredicate(
      (widget) => widget is Text && widget.textSpan != null,
    );
    expect(createAccountText, findsOneWidget);
    await tester.ensureVisible(createAccountText);
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    final scrollRect = tester.getRect(find.byType(SingleChildScrollView));
    expect(scrollRect.bottom, lessThanOrEqualTo(391));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _setViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

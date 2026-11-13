import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../features/favorites/logic/favorites_controller.dart';
import '../../../../features/notifications/logic/notifications_store.dart';
import '../../../../features/price_alerts/logic/price_alerts_store.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routes/app_routes.dart';
import '../../../onboarding/presentation/screens/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (kIsWeb) {
      final requestedRoute = Uri.base.fragment;
      if (const {
        AppRoutes.auth,
        AppRoutes.register,
        AppRoutes.forgotPassword,
        AppRoutes.verifyCode,
        AppRoutes.resetPassword,
      }.contains(requestedRoute)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, requestedRoute);
        });
        return;
      }
    }

    // مدة عرض شاشة الـ Splash قبل الانتقال التلقائي.
    const splashDuration = kIsWeb ? Duration.zero : Duration(seconds: 4);
    final results = await Future.wait<Object>([
      Future.delayed(splashDuration, () => true),
      _restoreSessionSafely(),
      _readOnboardingSafely(),
    ]);

    if (!mounted) return;
    final hasSession = results[1] as bool;
    final hasSeenOnboarding = results[2] as bool;

    if (hasSession) {
      // في main() حمّلنا المفضلة قبل ما نعرف مين المستخدم (كانت لسه
      // 'guest'). دلوقتي عرفنا هويته بعد استعادة الجلسة، فنعيد التحميل
      // ببيانات حسابه هو بالذات.
      await _loadUserScopedStoresSafely();
      if (!mounted) return;
      final user = ApiService.instance.currentUser;
      final destination = user?.isAdmin == true
          ? AppRoutes.adminDashboard
          : user?.isPartner == true
              ? AppRoutes.partnerDashboard
              : AppRoutes.home;
      Navigator.pushReplacementNamed(context, destination);
    } else if (!hasSeenOnboarding) {
      Navigator.pushReplacementNamed(context, AppRoutes.onboarding);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.auth);
    }
  }

  Future<bool> _restoreSessionSafely() async {
    try {
      return await ApiService.instance
          .restoreSession()
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
    } catch (error) {
      debugPrint('Session restoration was skipped: $error');
      return false;
    }
  }

  Future<bool> _readOnboardingSafely() async {
    try {
      return await SharedPreferences.getInstance()
          .then((prefs) => prefs.getBool(OnboardingScreen.seenKey) ?? false)
          .timeout(const Duration(seconds: 4), onTimeout: () => false);
    } catch (error) {
      debugPrint('Onboarding state was unavailable: $error');
      return false;
    }
  }

  Future<void> _loadUserScopedStoresSafely() async {
    await Future.wait([
      _runOptionalLoad('favorites', FavoritesController.instance.load),
      _runOptionalLoad('notifications', NotificationsStore.instance.load),
      _runOptionalLoad('price alerts', PriceAlertsStore.instance.load),
    ]);
  }

  Future<void> _runOptionalLoad(
    String service,
    Future<void> Function() load,
  ) async {
    try {
      await load().timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('Loading $service was skipped during startup: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFF),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _OrbitalGlobe(),
              const SizedBox(height: 42),
              Text(
                'Zentrip',
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ).animate().fade(duration: 600.ms).slideY(begin: 0.12, end: 0),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  AppLocalizations.of(context).welcomeTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    letterSpacing: 0.2,
                  ),
                ),
              ).animate().fade(delay: 180.ms, duration: 600.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbitalGlobe extends StatefulWidget {
  const _OrbitalGlobe();

  @override
  State<_OrbitalGlobe> createState() => _OrbitalGlobeState();
}

class _OrbitalGlobeState extends State<_OrbitalGlobe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbitController;

  @override
  void initState() {
    super.initState();
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _orbitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 224.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(size, size),
            painter: _OrbitPainter(_orbitController),
          ),
          Image.asset(
            'assets/images/Earth.png',
            width: 124,
            height: 124,
            fit: BoxFit.contain,
          ),
          AnimatedBuilder(
            animation: _orbitController,
            builder: (context, child) => Transform.rotate(
              angle: _orbitController.value * 2 * math.pi,
              child: child,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Transform.rotate(
                  angle: math.pi / 2,
                  child: const Icon(
                    Icons.flight_rounded,
                    size: 29,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final Animation<double> orbitAnimation;

  _OrbitPainter(this.orbitAnimation) : super(repaint: orbitAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final orbitRect = Rect.fromCircle(center: center, radius: size.width * .38);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dashLength = 4.0;
    const gapLength = 5.0;
    final circumference = 2 * math.pi * orbitRect.width / 2;
    final dashCount = (circumference / (dashLength + gapLength)).floor();
    final planeAngle = orbitAnimation.value * 2 * math.pi - math.pi / 2;
    for (var i = 0; i < dashCount; i++) {
      final start = i * (dashLength + gapLength) / (orbitRect.width / 2);
      final sweep = dashLength / (orbitRect.width / 2);
      final dashCenter = start + sweep / 2;
      final angleFromPlane = math
          .atan2(math.sin(dashCenter - planeAngle),
              math.cos(dashCenter - planeAngle))
          .abs();
      final fade = (angleFromPlane / .42).clamp(0.0, 1.0);
      final smoothFade = fade * fade * (3 - 2 * fade);
      paint.color = AppColors.primary.withValues(alpha: .58 * smoothFade);
      canvas.drawArc(orbitRect, start, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.orbitAnimation != orbitAnimation;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../routes/app_routes.dart';
import '../../logic/auth_controller.dart';

// ───────────────────────── Colors ─────────────────────────
class AppColors {
  static const navy = Color(0xFF1F2A9A);
  static const navyDark = Color(0xFF16206E);
  static const fieldBg = Color(0xFFF3F5FB);
  static const hint = Color(0xFF9AA3B5);
  static const text = Color(0xFF111827);
  static const skyTop = Color(0xFF7FB6E8);
  static const skyBottom = Color(0xFFD6EAF8);
}

// ───────────────────────── Screen ─────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _planeCtrl;
  final _auth = AuthController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _remember = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _planeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _planeCtrl.dispose();
    _auth.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    FocusScope.of(context).unfocus();
    final email = _emailCtrl.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _showMessage('Enter a valid email address');
      return;
    }
    if (_passCtrl.text.isEmpty) {
      _showMessage('Enter your password');
      return;
    }

    setState(() => _loading = true);
    final success = await _auth.login(email: email, password: _passCtrl.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      _continueToApp();
    } else {
      final error = _auth.errorMessage;
      if (error != null && error.isNotEmpty) _showMessage(error);
    }
  }

  Future<void> _socialLogin({required bool withApple}) async {
    if (_loading) return;
    setState(() => _loading = true);
    final success = withApple
        ? await _auth.loginWithApple()
        : await _auth.loginWithGoogle();
    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      _continueToApp();
    } else {
      final error = _auth.errorMessage;
      if (error != null && error.isNotEmpty) _showMessage(error);
    }
  }

  void _continueToApp() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.splash,
      (route) => false,
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final safeTop = MediaQuery.of(context).viewPadding.top;
          final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
          final availableHeight = (constraints.maxHeight - keyboardHeight)
              .clamp(0.0, double.infinity);
          final heroHeight =
              (availableHeight * (keyboardHeight > 0 ? 0.16 : 0.28))
                  .clamp(72.0, keyboardHeight > 0 ? 120.0 : 240.0)
                  .toDouble();
          return Stack(
            fit: StackFit.expand,
            children: [
              // ── Sky + illustration ──
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: heroHeight + 40,
                child: Stack(
                  children: [
                    const Positioned.fill(child: _SkyBackground()),
                    Positioned(
                      top: safeTop + 8,
                      right: (constraints.maxWidth * 0.07)
                          .clamp(16.0, 28.0)
                          .toDouble(),
                      height: math.max(44.0, heroHeight - safeTop - 8),
                      child: const _BusStopSign(),
                    ),
                    // ── الطائرة المتحركة ──
                    Positioned.fill(
                      child: _AnimatedPlane(
                        controller: _planeCtrl,
                        top:
                            math.min(heroHeight * 0.42, availableHeight * 0.16),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Bottom sheet ──
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboardHeight,
                top: heroHeight,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 24,
                        offset: Offset(0, -6),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        24,
                        10,
                        24,
                        16,
                      ),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: _buildForm(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        // handle
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFE3E6EE),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Login to Access Your',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            height: 1.2,
          ),
        ),
        Text(
          'Travel Tickets',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 22),

        _InputField(
          controller: _emailCtrl,
          hint: 'Enter your email',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _InputField(
          controller: _passCtrl,
          hint: 'Enter your password',
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          suffix: IconButton(
            splashRadius: 20,
            icon: Icon(
              _obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
              color: AppColors.hint,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        const SizedBox(height: 10),

        // Remember me / Forgot password
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: _remember,
                    activeColor: AppColors.navy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                    onChanged: (v) => setState(() => _remember = v ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Remember me',
                  style:
                      GoogleFonts.poppins(fontSize: 12, color: AppColors.hint),
                ),
              ],
            ),
            GestureDetector(
              onTap: _loading
                  ? null
                  : () =>
                      Navigator.of(context).pushNamed(AppRoutes.forgotPassword),
              child: Text(
                'Forgot password?',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        _PressableButton(
          label: 'Login',
          loading: _loading,
          onTap: _submitLogin,
        ),
        const SizedBox(height: 16),

        // Divider
        Row(
          children: [
            const Expanded(child: Divider(color: Color(0xFFE9ECF3))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Or sign up with',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.hint,
                ),
              ),
            ),
            const Expanded(child: Divider(color: Color(0xFFE9ECF3))),
          ],
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: _SocialButton(
                label: 'Google',
                icon: const _GoogleG(),
                onTap: () => _socialLogin(withApple: false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SocialButton(
                label: 'Apple',
                icon: const Icon(Icons.apple, size: 22, color: Colors.black),
                onTap: () => _socialLogin(withApple: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _loading
              ? null
              : () => Navigator.of(context).pushNamed(AppRoutes.register),
          child: Text.rich(
            TextSpan(
              text: "Don't have an account? ",
              style: GoogleFonts.poppins(fontSize: 12, color: AppColors.text),
              children: [
                TextSpan(
                  text: 'Create an account',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Animated plane ─────────────────────────
class _AnimatedPlane extends StatelessWidget {
  final Animation<double> controller;
  final double top;
  const _AnimatedPlane({required this.controller, required this.top});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = controller.value; // 0 → 1
          const planeSize = 26.0;
          const trailLen = 90.0;

          // يمين ← يسار أو يسار ← يمين: هنا من اليسار لليمين
          final x = -trailLen + (c.maxWidth + trailLen * 2) * t;
          // حركة موجية خفيفة (طفو)
          final y = top + math.sin(t * math.pi * 4) * 6;
          // ميل الطائرة حسب اتجاه الحركة
          final tilt = math.cos(t * math.pi * 4) * 0.12;

          // تلاشي عند الدخول والخروج
          double opacity = 1;
          if (t < 0.08) opacity = t / 0.08;
          if (t > 0.92) opacity = (1 - t) / 0.08;

          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Stack(
              children: [
                // الأثر (Trail)
                Positioned(
                  left: x - trailLen,
                  top: y + planeSize / 2 - 1,
                  child: Container(
                    width: trailLen,
                    height: 2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                  ),
                ),
                // الطائرة
                Positioned(
                  left: x,
                  top: y,
                  child: Transform.rotate(
                    angle: math.pi / 2 + tilt,
                    child: const Icon(
                      Icons.flight,
                      size: planeSize,
                      color: AppColors.navy,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}

// ───────────────────────── Sky / mountains fallback ─────────────────────────
class _SkyBackground extends StatelessWidget {
  const _SkyBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.skyTop, AppColors.skyBottom],
        ),
      ),
      child: CustomPaint(painter: _MountainPainter(), size: Size.infinite),
    );
  }
}

class _MountainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    Path mountain(double x0, double peakX, double peakY, double x1) => Path()
      ..moveTo(x0, h)
      ..lineTo(peakX, peakY)
      ..lineTo(x1, h)
      ..close();

    canvas.drawPath(
      mountain(-w * 0.1, w * 0.28, h * 0.30, w * 0.75),
      Paint()..color = const Color(0xFF8E9BE0),
    );
    canvas.drawPath(
      mountain(w * 0.35, w * 0.72, h * 0.42, w * 1.15),
      Paint()..color = const Color(0xFF6F82D6),
    );
    // قمم ثلجية
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.28 - 28, h * 0.30 + 40)
        ..lineTo(w * 0.28, h * 0.30)
        ..lineTo(w * 0.28 + 28, h * 0.30 + 40)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );

    // سحب
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.9);
    void drawCloud(double cx, double cy, double s) {
      canvas.drawCircle(Offset(cx, cy), 14 * s, cloud);
      canvas.drawCircle(Offset(cx + 16 * s, cy + 4 * s), 12 * s, cloud);
      canvas.drawCircle(Offset(cx - 16 * s, cy + 5 * s), 11 * s, cloud);
    }

    drawCloud(w * 0.12, h * 0.42, 1.2);
    drawCloud(w * 0.90, h * 0.30, 1.0);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _BusStopSign extends StatelessWidget {
  const _BusStopSign();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final poleHeight = math.min(54.0, math.max(0.0, constraints.maxHeight - 44));
      return Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF5A623),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF7A4A12), width: 2),
            ),
            child: const Icon(Icons.directions_bus_rounded,
                color: Colors.white, size: 24),
          ),
          Container(
            key: const ValueKey('bus-stop-sign-pole'),
            width: 3,
            height: poleHeight,
            color: const Color(0xFF9AA3B5),
          ),
        ],
      );
    });
  }
}

// ───────────────────────── Components ─────────────────────────
class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.text),
      cursorColor: AppColors.navy,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(fontSize: 13, color: AppColors.hint),
        prefixIcon: Icon(icon, size: 20, color: AppColors.hint),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.fieldBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.navy, width: 1.4),
        ),
      ),
    );
  }
}

class _PressableButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool loading;
  const _PressableButton({
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        if (!widget.loading) widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: 52,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: widget.loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text(
                  widget.label,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  const _SocialButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE9ECF3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const SweepGradient(
        colors: [
          Color(0xFFEA4335),
          Color(0xFFFBBC05),
          Color(0xFF34A853),
          Color(0xFF4285F4),
          Color(0xFFEA4335),
        ],
      ).createShader(r),
      child: Text(
        'G',
        style: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

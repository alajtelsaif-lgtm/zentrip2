import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ───────────────────────── Colors ─────────────────────────
class AppColors {
  static const navy = Color(0xFF1F2A9A);
  static const fieldBg = Color(0xFFF3F5FB);
  static const hint = Color(0xFF9AA3B5);
  static const text = Color(0xFF111827);
  static const line = Color(0xFFE9ECF3);
  static const error = Color(0xFFE5484D);
  static const skyTop = Color(0xFF7FB6E8);
  static const skyBottom = Color(0xFFD6EAF8);
}

// ───────────────────────── Scaffold (hero + plane + sheet) ─────────────────────────
class AuthScaffold extends StatefulWidget {
  /// نسبة ارتفاع الصورة العلوية من الشاشة (0.46 للدخول، 0.30 للتسجيل)
  final double heroFraction;
  final Widget child;
  final IconData signIcon;
  final bool showBack;

  const AuthScaffold({
    super.key,
    required this.child,
    this.heroFraction = 0.40,
    this.signIcon = Icons.directions_bus_rounded,
    this.showBack = true,
  });

  @override
  State<AuthScaffold> createState() => _AuthScaffoldState();
}

class _AuthScaffoldState extends State<AuthScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _planeCtrl;

  @override
  void initState() {
    super.initState();
    _planeCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 9))
          ..repeat();
  }

  @override
  void dispose() {
    _planeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final usableHeight = (mq.size.height - mq.viewInsets.bottom)
        .clamp(0.0, double.infinity)
        .toDouble();
    final heroHeight = usableHeight * widget.heroFraction;
    final topPad = mq.padding.top;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Hero ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: heroHeight + 40,
              child: Stack(
                children: [
                  const Positioned.fill(child: _SkyBackground()),
                  if (heroHeight >= topPad + 92)
                    Positioned(
                      bottom: 40,
                      right: 28,
                      child: _SignPost(icon: widget.signIcon),
                    ),
                  Positioned.fill(
                    child: _AnimatedPlane(
                      controller: _planeCtrl,
                      top: topPad + 62,
                    ),
                  ),
                ],
              ),
            ),

            // ── Back button ──
            if (widget.showBack && Navigator.of(context).canPop())
              Positioned(
                top: topPad + 8,
                left: 16,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.85),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          size: 18, color: AppColors.text),
                    ),
                  ),
                ),
              ),

            // ── Sheet ──
            Positioned(
              left: 0,
              right: 0,
              bottom: mq.viewInsets.bottom,
              top: heroHeight,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 24,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bottomPadding =
                        (mq.viewInsets.bottom == 0 ? mq.padding.bottom : 0.0) +
                            16.0;
                    const contentTopPadding = 44.0;
                    final contentHeight = (constraints.maxHeight -
                            contentTopPadding -
                            bottomPadding)
                        .clamp(0.0, double.infinity)
                        .toDouble();
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              24,
                              contentTopPadding,
                              24,
                              bottomPadding,
                            ),
                            child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(minHeight: contentHeight),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [widget.child],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              key: const Key('auth-sheet-handle'),
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3E6EE),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Plane ─────────────────────────
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
          final t = controller.value;
          const planeSize = 26.0;
          const trailLen = 90.0;

          final x = -trailLen + (c.maxWidth + trailLen * 2) * t;
          final y = top + math.sin(t * math.pi * 4) * 10;
          final tilt = math.cos(t * math.pi * 4) * 0.12;

          double opacity = 1;
          if (t < 0.08) opacity = t / 0.08;
          if (t > 0.92) opacity = (1 - t) / 0.08;

          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Stack(
              children: [
                Positioned(
                  left: x - trailLen,
                  top: y + planeSize / 2 - 1,
                  child: Container(
                    width: trailLen,
                    height: 2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.85),
                      ]),
                    ),
                  ),
                ),
                Positioned(
                  left: x,
                  top: y,
                  child: Transform.rotate(
                    angle: math.pi / 2 + tilt,
                    child: const Icon(Icons.flight,
                        size: planeSize, color: AppColors.navy),
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

// ───────────────────────── Hero pieces ─────────────────────────
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

    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.9);
    void drawCloud(double cx, double cy, double s) {
      canvas.drawCircle(Offset(cx, cy), 14 * s, cloud);
      canvas.drawCircle(Offset(cx + 16 * s, cy + 4 * s), 12 * s, cloud);
      canvas.drawCircle(Offset(cx - 16 * s, cy + 5 * s), 11 * s, cloud);
    }

    drawCloud(w * 0.12, h * 0.24, 1.05);
    drawCloud(w * 0.90, h * 0.16, 0.9);

    canvas.drawPath(mountain(-w * 0.1, w * 0.28, h * 0.30, w * 0.75),
        Paint()..color = const Color(0xFF8E9BE0));
    canvas.drawPath(mountain(w * 0.35, w * 0.72, h * 0.42, w * 1.15),
        Paint()..color = const Color(0xFF6F82D6));
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.28 - 28, h * 0.30 + 40)
        ..lineTo(w * 0.28, h * 0.30)
        ..lineTo(w * 0.28 + 28, h * 0.30 + 40)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _SignPost extends StatelessWidget {
  final IconData icon;
  const _SignPost({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFFF5A623),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF7A4A12), width: 3),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        Container(
          key: const ValueKey('bus-stop-sign-pole'),
          width: 4,
          height: 34,
          color: const Color(0xFF9AA3B5),
        ),
      ],
    );
  }
}

// ───────────────────────── Text ─────────────────────────
class AuthTitle extends StatelessWidget {
  final String line1;
  final String line2;
  final String? subtitle;
  const AuthTitle(
      {super.key, required this.line1, required this.line2, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          line1,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            height: 1.2,
          ),
        ),
        Text(
          line2,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.navy,
            height: 1.3,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: AppColors.hint,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

// ───────────────────────── Input ─────────────────────────
class AuthInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  const AuthInput({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.errorText,
    this.onChanged,
  });

  OutlineInputBorder _border(Color c, [double w = 0]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
      );

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.text),
      cursorColor: AppColors.navy,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(fontSize: 13, color: AppColors.hint),
        errorText: errorText,
        errorStyle: GoogleFonts.poppins(fontSize: 11, color: AppColors.error),
        prefixIcon: Icon(icon, size: 20, color: AppColors.hint),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.fieldBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: _border(Colors.transparent),
        enabledBorder: _border(Colors.transparent),
        focusedBorder: _border(AppColors.navy, 1.4),
        errorBorder: _border(AppColors.error, 1.2),
        focusedErrorBorder: _border(AppColors.error, 1.4),
      ),
    );
  }
}

// ───────────────────────── Buttons ─────────────────────────
class AuthButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const AuthButton(
      {super.key,
      required this.label,
      required this.onTap,
      this.loading = false});

  @override
  State<AuthButton> createState() => _AuthButtonState();
}

class _AuthButtonState extends State<AuthButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        if (!widget.loading) widget.onTap?.call();
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
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: widget.loading
                ? const SizedBox(
                    key: ValueKey('l'),
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : Text(
                    widget.label,
                    key: const ValueKey('t'),
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  const SocialButton(
      {super.key,
      required this.label,
      required this.icon,
      required this.onTap});

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
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 8),
              Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text)),
            ],
          ),
        ),
      ),
    );
  }
}

class GoogleG extends StatelessWidget {
  const GoogleG({super.key});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const SweepGradient(colors: [
        Color(0xFFEA4335),
        Color(0xFFFBBC05),
        Color(0xFF34A853),
        Color(0xFF4285F4),
        Color(0xFFEA4335),
      ]).createShader(r),
      child: Text('G',
          style: GoogleFonts.poppins(
              fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}

class OrDivider extends StatelessWidget {
  final String text;
  const OrDivider({super.key, this.text = 'Or sign up with'});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(text,
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.hint)),
        ),
        const Expanded(child: Divider(color: AppColors.line)),
      ],
    );
  }
}

/// سطر "نص عادي + رابط ملوّن" مثل: Don't have an account? Create an account
class AuthFooterLink extends StatelessWidget {
  final String text;
  final String link;
  final VoidCallback onTap;
  const AuthFooterLink(
      {super.key, required this.text, required this.link, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text.rich(
          TextSpan(
            text: '$text ',
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.text),
            children: [
              TextSpan(
                text: link,
                style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/api_service.dart';
import '../../../../routes/app_routes.dart';
import '../../logic/auth_controller.dart';
import 'auth_shared.dart' show AuthScaffold;

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

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _remember = true;
  bool _loading = false;

  @override
  void dispose() {
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
    return AuthScaffold(
      heroFraction: 0.28,
      showBack: false,
      child: _buildForm(),
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        Text(
          'Login to',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            height: 1.2,
          ),
        ),
        Text(
          'Travel Around the Globe',
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
        if (ApiService.socialAuthConfigured) ...[
          const SizedBox(height: 16),
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
        ],

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

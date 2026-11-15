import '../../../../l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../routes/app_routes.dart';
import '../../logic/auth_controller.dart';
import 'auth_shared.dart';

class VerifyScreen extends StatefulWidget {
  final String email;
  final AuthController? authController;

  const VerifyScreen({super.key, required this.email, this.authController});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  late final AuthController _auth;
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;
  bool _loading = false;
  bool _verified = false;
  bool _resetDone = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  Timer? _timer;
  Timer? _redirectTimer;
  int _cooldown = 0;

  @override
  void initState() {
    super.initState();
    _auth = widget.authController ?? AuthController();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _redirectTimer?.cancel();
    if (widget.authController == null) _auth.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    final code = _codeCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = AppLocalizations.of(context).enterSixDigitCode);
      return;
    }

    setState(() {
      _error = null;
      _loading = true;
    });
    final success =
        await _auth.verifyResetCode(email: widget.email, code: code);
    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      setState(() => _verified = true);
    } else {
      _showError(_auth.errorMessage);
    }
  }

  Future<void> _resetPassword() async {
    FocusScope.of(context).unfocus();
    if (_passwordCtrl.text.isEmpty || _confirmCtrl.text.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).enterAndConfirmPassword);
      return;
    }
    if (_passwordCtrl.text.length < 8) {
      setState(() => _error = AppLocalizations.of(context).passwordMinLength);
      return;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = AppLocalizations.of(context).passwordsDontMatch);
      return;
    }

    setState(() {
      _error = null;
      _loading = true;
    });
    final success = await _auth.resetPassword(
      email: widget.email,
      code: _codeCtrl.text.trim(),
      newPassword: _passwordCtrl.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      setState(() => _resetDone = true);
      _redirectTimer?.cancel();
      _redirectTimer = Timer(const Duration(seconds: 2), _goToLogin);
    } else {
      _showError(_auth.errorMessage);
    }
  }

  void _goToLogin() {
    if (!mounted) return;
    _redirectTimer?.cancel();
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.auth,
      (route) => false,
    );
  }

  Future<void> _resendCode() async {
    if (_loading || _cooldown > 0) return;
    setState(() => _loading = true);
    final success = await _auth.sendResetCode(email: widget.email);
    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      _startCooldown();
    } else {
      _showError(_auth.errorMessage);
    }
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _cooldown = 0);
      } else if (mounted) {
        setState(() => _cooldown--);
      }
    });
  }

  void _showError(String? message) {
    if (message == null || message.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      heroFraction: 0.40,
      signIcon: Icons.verified_user_rounded,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOut,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: _resetDone
            ? _buildSuccess()
            : _verified
                ? _buildResetForm()
                : _buildVerifyForm(),
      ),
    );
  }

  Widget _buildVerifyForm() {
    return Column(
      key: const ValueKey('verify'),
      children: [
        AuthTitle(
          line1: AppLocalizations.of(context).verifyTitleLine1,
          line2: AppLocalizations.of(context).verifyTitleLine2,
          subtitle: AppLocalizations.of(context).verifySubtitle,
        ),
        const SizedBox(height: 8),
        Text(
          widget.email,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 24),
        AuthInput(
          controller: _codeCtrl,
          hint: AppLocalizations.of(context).verificationCodeHint,
          icon: Icons.pin_outlined,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          errorText: _error,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 20),
        AuthButton(
          label: AppLocalizations.of(context).verifyCodeButton,
          loading: _loading,
          onTap: _loading ? null : _verify,
        ),
        const SizedBox(height: 18),
        AuthFooterLink(
          text: AppLocalizations.of(context).didntReceiveCode,
          link: _cooldown > 0 ? AppLocalizations.of(context).resendInSeconds(_cooldown) : AppLocalizations.of(context).resendCodeLink,
          onTap: _resendCode,
        ),
      ],
    );
  }

  Widget _buildResetForm() {
    return Column(
      key: const ValueKey('reset'),
      children: [
        AuthTitle(
          line1: AppLocalizations.of(context).newPasswordTitleLine1,
          line2: AppLocalizations.of(context).newPasswordTitleLine2,
          subtitle: AppLocalizations.of(context).newPasswordSubtitle,
        ),
        const SizedBox(height: 24),
        AuthInput(
          controller: _passwordCtrl,
          hint: AppLocalizations.of(context).newPasswordHint,
          icon: Icons.lock_outline_rounded,
          obscure: _obscurePassword,
          textInputAction: TextInputAction.next,
          errorText: _error,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          suffix: _eye(
            _obscurePassword,
            () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 12),
        AuthInput(
          controller: _confirmCtrl,
          hint: AppLocalizations.of(context).confirmNewPasswordHint,
          icon: Icons.verified_user_outlined,
          obscure: _obscureConfirm,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          suffix: _eye(
            _obscureConfirm,
            () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ),
        const SizedBox(height: 20),
        AuthButton(
          label: AppLocalizations.of(context).resetPasswordAction,
          loading: _loading,
          onTap: _loading ? null : _resetPassword,
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      key: const ValueKey('success'),
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (_, value, child) =>
              Transform.scale(scale: value, child: child),
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.navy.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_outlined,
              size: 40,
              color: AppColors.navy,
            ),
          ),
        ),
        const SizedBox(height: 18),
        AuthTitle(line1: AppLocalizations.of(context).passwordResetTitleLine1, line2: AppLocalizations.of(context).passwordResetTitleLine2),
        const SizedBox(height: 10),
        Text(
          AppLocalizations.of(context).passwordUpdatedSuccess,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12.5,
            color: AppColors.hint,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 26),
        AuthButton(
          label: AppLocalizations.of(context).backToLoginButton,
          onTap: _goToLogin,
        ),
      ],
    );
  }

  Widget _eye(bool obscured, VoidCallback onTap) => IconButton(
        splashRadius: 20,
        icon: Icon(
          obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20,
          color: AppColors.hint,
        ),
        onPressed: onTap,
      );
}

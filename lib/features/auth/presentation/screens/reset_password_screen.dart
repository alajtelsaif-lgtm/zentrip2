import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/api_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routes/app_routes.dart';
import '../../logic/auth_controller.dart';
import 'auth_shared.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String email;
  final AuthController? authController;

  const ResetPasswordScreen({
    super.key,
    required this.email,
    this.authController,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final AuthController _auth;
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;
  bool _loading = false;
  bool _resetDone = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  Timer? _redirectTimer;

  bool get _isDemo => ApiService.instance.isDemoPasswordResetEnabled;

  @override
  void initState() {
    super.initState();
    _auth = widget.authController ?? AuthController();
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    if (widget.authController == null) _auth.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    FocusScope.of(context).unfocus();
    final l10n = AppLocalizations.of(context);
    if (!RegExp(r'^\d{6}$').hasMatch(_codeCtrl.text.trim())) {
      setState(() => _error = l10n.resetCodeInvalid);
      return;
    }
    if (_passwordCtrl.text.isEmpty || _confirmCtrl.text.isEmpty) {
      setState(() => _error = l10n.resetPasswordFieldsRequired);
      return;
    }
    if (_passwordCtrl.text.length < 8) {
      setState(() => _error = l10n.resetPasswordMinLength);
      return;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = l10n.resetPasswordMismatch);
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
    if (!success) {
      final message = _auth.errorMessage;
      if (message != null && message.isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }

    setState(() => _resetDone = true);
    _redirectTimer = Timer(const Duration(seconds: 2), _goToLogin);
  }

  void _goToLogin() {
    if (!mounted) return;
    _redirectTimer?.cancel();
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.auth,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthScaffold(
      heroFraction: 0.40,
      signIcon: Icons.lock_reset_rounded,
      child: _resetDone ? _buildSuccess(l10n) : _buildForm(l10n),
    );
  }

  Widget _buildForm(AppLocalizations l10n) {
    return Column(
      children: [
        AuthTitle(
          line1: l10n.resetPasswordTitleLine1,
          line2: l10n.resetPasswordTitleLine2,
          subtitle: l10n.resetPasswordSubtitle,
        ),
        const SizedBox(height: 8),
        Text(
          widget.email,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w600,
              ),
        ),
        if (_isDemo) ...[
          const SizedBox(height: 12),
          Text(
            l10n.demoPasswordResetNotice,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
        const SizedBox(height: 20),
        AuthInput(
          controller: _codeCtrl,
          hint: l10n.resetCodeInputHint,
          icon: Icons.pin_outlined,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 12),
        AuthInput(
          controller: _passwordCtrl,
          hint: l10n.newPasswordLabel,
          icon: Icons.lock_outline_rounded,
          obscure: _obscurePassword,
          textInputAction: TextInputAction.next,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          suffix: _visibilityButton(
            _obscurePassword,
            () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 12),
        AuthInput(
          controller: _confirmCtrl,
          hint: l10n.confirmPasswordLabel,
          icon: Icons.verified_user_outlined,
          obscure: _obscureConfirm,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          suffix: _visibilityButton(
            _obscureConfirm,
            () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              _error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.error),
            ),
          ),
        ],
        const SizedBox(height: 20),
        AuthButton(
          label: l10n.resetPasswordButton,
          loading: _loading,
          onTap: _loading ? null : _resetPassword,
        ),
      ],
    );
  }

  Widget _buildSuccess(AppLocalizations l10n) {
    return Column(
      children: [
        Container(
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
        const SizedBox(height: 18),
        AuthTitle(
          line1: l10n.passwordResetSuccessTitle,
          line2: '',
          subtitle: _isDemo
              ? l10n.demoPasswordResetComplete
              : l10n.passwordResetSuccess,
        ),
        const SizedBox(height: 20),
        AuthButton(
          label: l10n.backToLogin,
          loading: false,
          onTap: _goToLogin,
        ),
      ],
    );
  }

  Widget _visibilityButton(bool obscured, VoidCallback onTap) {
    return IconButton(
      tooltip: obscured
          ? AppLocalizations.of(context).showPassword
          : AppLocalizations.of(context).hidePassword,
      onPressed: onTap,
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
    );
  }
}

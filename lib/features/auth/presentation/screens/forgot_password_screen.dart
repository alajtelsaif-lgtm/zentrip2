import '../../../../l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../../../routes/app_routes.dart';
import '../../logic/auth_controller.dart';
import 'auth_shared.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final AuthController? authController;

  const ForgotPasswordScreen({super.key, this.authController});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final AuthController _auth;
  final _emailCtrl = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _auth = widget.authController ?? AuthController();
  }

  @override
  void dispose() {
    if (widget.authController == null) _auth.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String v) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  Future<void> _send() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    if (!_validEmail(_emailCtrl.text)) {
      setState(() => _error = AppLocalizations.of(context).authInvalidEmail);
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });

    final success = await _auth.sendResetCode(email: _emailCtrl.text.trim());

    if (!mounted) return;
    if (!success) {
      setState(() => _loading = false);
      final message = _auth.errorMessage;
      if (message != null && message.isNotEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }

    await Navigator.of(context).pushNamed(
      AppRoutes.resetPassword,
      arguments: _emailCtrl.text.trim(),
    );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      heroFraction: 0.40,
      signIcon: Icons.lock_reset_rounded,
      child: _buildForm(),
    );
  }

  Widget _buildForm() {
    return Column(
      children: [
        AuthTitle(
          line1: AppLocalizations.of(context).forgotTitleLine1,
          line2: AppLocalizations.of(context).forgotTitleLine2,
          subtitle:
              AppLocalizations.of(context).forgotSubtitle,
        ),
        const SizedBox(height: 24),
        AuthInput(
          controller: _emailCtrl,
          hint: AppLocalizations.of(context).authEmailHint,
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          errorText: _error,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 20),
        AuthButton(label: AppLocalizations.of(context).sendResetCode, loading: _loading, onTap: _send),
        const SizedBox(height: 18),
        AuthFooterLink(
          text: AppLocalizations.of(context).rememberedIt,
          link: AppLocalizations.of(context).backToLoginLower,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

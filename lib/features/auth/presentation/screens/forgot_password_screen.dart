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
      setState(() => _error = 'Enter a valid email address');
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
        const AuthTitle(
          line1: 'Forgot Your Password?',
          line2: "We'll Get You Back On Track",
          subtitle:
              "Enter the email linked to your account and we'll send you a code to reset your password.",
        ),
        const SizedBox(height: 24),
        AuthInput(
          controller: _emailCtrl,
          hint: 'Enter your email',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          errorText: _error,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 20),
        AuthButton(label: 'Send Reset Code', loading: _loading, onTap: _send),
        const SizedBox(height: 18),
        AuthFooterLink(
          text: 'Remembered it?',
          link: 'Back to login',
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

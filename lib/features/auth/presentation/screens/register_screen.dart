import '../../../../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/api_service.dart';
import '../../../../routes/app_routes.dart';
import '../../logic/auth_controller.dart';
import '../models/country_phone_option.dart';
import 'auth_shared.dart';
import '../widgets/photo_picker_avatar.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _auth = AuthController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  XFile? _photo;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _agree = false;
  bool _loading = false;
  CountryPhoneOption _phoneCountry = CountryPhoneOption.supported.first;

  String? _nameErr, _emailErr, _phoneErr, _passErr, _confirmErr, _termsErr;

  @override
  void dispose() {
    _auth.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // 0..4
  int get _strength {
    final p = _passCtrl.text;
    int s = 0;
    if (p.length >= 8) s++;
    if (RegExp(r'[A-Z]').hasMatch(p)) s++;
    if (RegExp(r'[0-9]').hasMatch(p)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
    return s;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final emailOk =
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_emailCtrl.text.trim());
    final phoneDigits = _phoneCtrl.text;

    setState(() {
      _nameErr =
          _nameCtrl.text.trim().length < 2 ? AppLocalizations.of(context).fullNameHint : null;
      _emailErr = emailOk ? null : AppLocalizations.of(context).authInvalidEmail;
      _phoneErr = _phoneCountry.accepts(phoneDigits)
          ? null
          : _phoneCountry.minNationalDigits == _phoneCountry.maxNationalDigits
              ? AppLocalizations.of(context).phoneExactDigits(_phoneCountry.maxNationalDigits, _phoneCountry.name)
              : AppLocalizations.of(context).phoneDigitRange(_phoneCountry.minNationalDigits, _phoneCountry.maxNationalDigits, _phoneCountry.name);
      _passErr = _passCtrl.text.length < 8 ? AppLocalizations.of(context).passwordMinLength : null;
      _confirmErr =
          _confirmCtrl.text != _passCtrl.text ? AppLocalizations.of(context).passwordsDontMatch : null;
      _termsErr = _agree ? null : AppLocalizations.of(context).acceptTermsError;
    });

    if ([_nameErr, _emailErr, _phoneErr, _passErr, _confirmErr, _termsErr]
        .any((e) => e != null)) {
      return;
    }

    setState(() => _loading = true);
    final success = await _auth.register(
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: '+${_phoneCountry.dialCode}${phoneDigits.trim()}',
      password: _passCtrl.text,
      photo: _photo,
    );

    if (!mounted) return;
    setState(() => _loading = false);
    if (success) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.splash,
        (route) => false,
      );
      return;
    }

    final message = _auth.errorMessage;
    if (message != null && message.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
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
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.splash,
        (route) => false,
      );
      return;
    }

    final message = _auth.errorMessage;
    if (message != null && message.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _selectPhoneCountry() async {
    final country = await showModalBottomSheet<CountryPhoneOption>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: ListView.builder(
            itemCount: CountryPhoneOption.supported.length,
            itemBuilder: (context, index) {
              final option = CountryPhoneOption.supported[index];
              return ListTile(
                leading:
                    Text(option.flag, style: const TextStyle(fontSize: 24)),
                title: Text(option.name),
                trailing: Text('+${option.dialCode}'),
                onTap: () => Navigator.pop(context, option),
              );
            },
          ),
        ),
      ),
    );
    if (country == null || !mounted) return;

    final digitCount = _phoneCtrl.text.length > country.maxNationalDigits
        ? country.maxNationalDigits
        : _phoneCtrl.text.length;
    final digits = _phoneCtrl.text.substring(0, digitCount);
    setState(() {
      _phoneCountry = country;
      _phoneCtrl.value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
      _phoneErr = null;
    });
  }

  Widget _phoneNumberInput() {
    return TextField(
      controller: _phoneCtrl,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(_phoneCountry.maxNationalDigits),
      ],
      onChanged: (_) => setState(() => _phoneErr = null),
      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.text),
      cursorColor: AppColors.navy,
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).phoneHint,
        hintStyle: GoogleFonts.poppins(fontSize: 13, color: AppColors.hint),
        errorText: _phoneErr,
        errorStyle: GoogleFonts.poppins(fontSize: 11, color: AppColors.error),
        prefixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 14),
            const Icon(Icons.phone_outlined, size: 20, color: AppColors.hint),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _selectPhoneCountry,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_phoneCountry.flag,
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 4),
                    Text(
                      '+${_phoneCountry.dialCode}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down,
                        size: 18, color: AppColors.hint),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(width: 1, height: 26, color: AppColors.line),
            const SizedBox(width: 8),
          ],
        ),
        prefixIconConstraints: const BoxConstraints(minHeight: 52),
        filled: true,
        fillColor: AppColors.fieldBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.navy, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error, width: 1.4),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      heroFraction: 0.30,
      signIcon: Icons.confirmation_number_rounded,
      child: Column(
        children: [
          PhotoPickerAvatar(
            initialFile: _photo,
            size: 72,
            onChanged: (photo) => setState(() => _photo = photo),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).addProfilePhotoOptional,
            style: GoogleFonts.poppins(fontSize: 11, color: AppColors.hint),
          ),
          const SizedBox(height: 12),
          AuthTitle(
            line1: AppLocalizations.of(context).registerTitleLine1,
            line2: AppLocalizations.of(context).registerTitleLine2,
          ),
          const SizedBox(height: 20),

          AuthInput(
            controller: _nameCtrl,
            hint: AppLocalizations.of(context).fullNameHint,
            icon: Icons.person_outline_rounded,
            textInputAction: TextInputAction.next,
            errorText: _nameErr,
            onChanged: (_) => setState(() => _nameErr = null),
          ),
          const SizedBox(height: 12),
          AuthInput(
            controller: _emailCtrl,
            hint: AppLocalizations.of(context).authEmailHint,
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            errorText: _emailErr,
            onChanged: (_) => setState(() => _emailErr = null),
          ),
          const SizedBox(height: 12),
          _phoneNumberInput(),
          const SizedBox(height: 12),
          AuthInput(
            controller: _passCtrl,
            hint: AppLocalizations.of(context).createPasswordHint,
            icon: Icons.lock_outline_rounded,
            obscure: _obscurePass,
            textInputAction: TextInputAction.next,
            errorText: _passErr,
            onChanged: (_) => setState(() => _passErr = null),
            suffix: _eye(_obscurePass,
                () => setState(() => _obscurePass = !_obscurePass)),
          ),
          _StrengthBar(score: _strength, visible: _passCtrl.text.isNotEmpty),
          const SizedBox(height: 12),
          AuthInput(
            controller: _confirmCtrl,
            hint: AppLocalizations.of(context).confirmPasswordHint,
            icon: Icons.verified_user_outlined,
            obscure: _obscureConfirm,
            textInputAction: TextInputAction.done,
            errorText: _confirmErr,
            onChanged: (_) => setState(() => _confirmErr = null),
            suffix: _eye(_obscureConfirm,
                () => setState(() => _obscureConfirm = !_obscureConfirm)),
          ),
          const SizedBox(height: 12),

          // ── الشروط ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: _agree,
                  activeColor: AppColors.navy,
                  side: BorderSide(
                    color: _termsErr != null
                        ? AppColors.error
                        : const Color(0xFFB8BFCE),
                    width: 1.4,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5)),
                  onChanged: (v) => setState(() {
                    _agree = v ?? false;
                    _termsErr = null;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text.rich(
                    TextSpan(
                      text: AppLocalizations.of(context).agreeToThe,
                      style: GoogleFonts.poppins(
                          fontSize: 11.5, color: AppColors.hint),
                      children: [
                        TextSpan(
                          text: AppLocalizations.of(context).termsOfService,
                          style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.navy),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: AppLocalizations.of(context).privacyPolicy,
                          style: GoogleFonts.poppins(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.navy),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_termsErr != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, left: 30),
                child: Text(_termsErr!,
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.error)),
              ),
            ),
          const SizedBox(height: 18),

          AuthButton(
              label: AppLocalizations.of(context).createAccountButton, loading: _loading, onTap: _submit),
          if (ApiService.socialAuthConfigured) ...[
            const SizedBox(height: 16),
            const OrDivider(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SocialButton(
                    label: 'Google',
                    icon: const GoogleG(),
                    onTap: () => _socialLogin(withApple: false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SocialButton(
                    label: 'Apple',
                    icon:
                        const Icon(Icons.apple, size: 22, color: Colors.black),
                    onTap: () => _socialLogin(withApple: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          AuthFooterLink(
            text: AppLocalizations.of(context).alreadyHaveAccount,
            link: AppLocalizations.of(context).loginButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
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

// ───────────────────────── Password strength ─────────────────────────
class _StrengthBar extends StatelessWidget {
  final int score; // 0..4
  final bool visible;
  const _StrengthBar({required this.score, required this.visible});

  @override
  Widget build(BuildContext context) {
    const labels = ['Too weak', 'Weak', 'Fair', 'Good', 'Strong'];
    const colors = [
      Color(0xFFE5484D),
      Color(0xFFE5484D),
      Color(0xFFF5A623),
      Color(0xFF3DB26E),
      Color(0xFF1F9D55),
    ];
    final color = colors[score];

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: visible
          ? Padding(
              padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: List.generate(4, (i) {
                        return Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            height: 4,
                            margin: EdgeInsets.only(right: i == 3 ? 0 : 5),
                            decoration: BoxDecoration(
                              color:
                                  i < score ? color : const Color(0xFFE3E6EE),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    labels[score],
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: color),
                  ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

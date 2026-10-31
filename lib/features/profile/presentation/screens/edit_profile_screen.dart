import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/services/api_service.dart';
import '../../../../models/user_model.dart';
import '../../../../core/utils/validators.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../global_widgets/phone_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/presentation/widgets/auth_text_field.dart';
import '../../../auth/presentation/widgets/photo_picker_avatar.dart';
import '../../../auth/presentation/widgets/primary_button.dart';
import '../../logic/profile_controller.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ctrl = ProfileController();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  XFile? _photo;

  UserModel? get user => ApiService.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: user?.name ?? '');
    _phoneCtrl = TextEditingController(text: user?.phone ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await _ctrl.updateProfile(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        photo: _photo);
    if (!mounted) return;
    if (ok) {
      AppSnackbar.success(
          context, AppLocalizations.of(context).profileUpdatedSuccess);
      Navigator.pop(context);
    } else {
      AppSnackbar.error(context,
          _ctrl.errorMessage ?? AppLocalizations.of(context).genericError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.editProfileTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Center(
                  child: PhotoPickerAvatar(
                      onChanged: (f) => setState(() => _photo = f))),
              const SizedBox(height: 28),
              AuthTextField(
                  controller: _nameCtrl,
                  label: l10n.nameLabel,
                  icon: Icons.person_outline,
                  validator: Validators.requiredValidator(l10n.nameLabel,
                      minLength: 2)),
              const SizedBox(height: 14),
              PhoneField(
                  controller: _phoneCtrl,
                  label: l10n.phoneLabel,
                  validator: Validators.phoneValidator(
                      l10n.phoneLabel, l10n.genericError)),
              const SizedBox(height: 28),
              ListenableBuilder(
                listenable: _ctrl,
                builder: (_, __) => PrimaryButton(
                    label: l10n.saveChanges,
                    isLoading: _ctrl.isLoading,
                    onPressed: _save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

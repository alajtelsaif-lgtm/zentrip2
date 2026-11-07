import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../global_widgets/locale_controller.dart';
import '../../../../l10n/app_localizations.dart';

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final langs = [
      (const Locale('ar'), '🇱🇾', l10n.arabic, 'العربية'),
      (const Locale('en'), '🇺🇸', l10n.english, 'English'),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.language)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListenableBuilder(
          listenable: LocaleController.instance,
          builder: (_, __) {
            final current = LocaleController.instance.locale;
            return Column(
              children: langs.map((opt) {
                final (locale, flag, label, nativeLabel) = opt;
                final isSelected = current.languageCode == locale.languageCode;
                return GestureDetector(
                  onTap: () => LocaleController.instance.setLocale(locale),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primarySurface : (isDark ? AppColors.darkSurface : AppColors.surface),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isSelected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.border), width: isSelected ? 2 : 1),
                    ),
                    child: Row(
                      children: [
                        Text(flag, style: const TextStyle(fontSize: 32)),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, fontSize: 15)),
                            Text(nativeLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ],
                        ),
                        const Spacer(),
                        if (isSelected) const Icon(Icons.check_circle_rounded, color: AppColors.primary),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

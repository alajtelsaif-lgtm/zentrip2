import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../l10n/app_localizations.dart';

class CurrencyScreen extends StatelessWidget {
  const CurrencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.currencyTitle)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListenableBuilder(
          listenable: CurrencyService.instance,
          builder: (_, __) {
            final current = CurrencyService.instance.selected;
            final isArabic =
                Localizations.localeOf(context).languageCode == 'ar';
            return ListView(
              children: CurrencyService.supported.map((c) {
                final isSelected = c.code == current.code;
                return GestureDetector(
                  onTap: () => CurrencyService.instance.setCurrency(c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primarySurface
                          : (isDark
                              ? AppColors.darkSurface
                              : AppColors.surface),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : (isDark
                                  ? AppColors.darkBorder
                                  : AppColors.border),
                          width: isSelected ? 2 : 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(
                            c.code == 'LYD' && !isArabic ? 'LYD' : c.symbol,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.code,
                                style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: 15)),
                            Text(
                              isArabic ? c.nameAr : c.nameEn,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            if (c.code == 'LYD')
                              Text(
                                AppLocalizations.of(context).lydFixedRate,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                        const Spacer(),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded,
                              color: AppColors.primary),
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

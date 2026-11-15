import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/services/price_comparison.dart';
import '../core/utils/money_format.dart';
import '../l10n/app_localizations.dart';

/// Compact selector reuses the established theme and only changes the
/// displayed/recorded booking currency, not the provider's original quote.
class FlightCurrencySelector extends StatelessWidget {
  final PriceComparison comparison;
  final ValueChanged<String>? onChanged;

  const FlightCurrencySelector({
    super.key,
    required this.comparison,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            AppLocalizations.of(context).compareIn,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: DropdownButton<String>(
              value: comparison.currency,
              isDense: true,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(10),
              items: PriceComparison.supportedCurrencies
                  .map((code) => DropdownMenuItem(
                        value: code,
                        child: Text(
                          currencySelectionLabel(
                            code,
                            locale:
                                Localizations.localeOf(context).languageCode,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (code) {
                if (code == null) return;
                comparison.setCurrency(code);
                onChanged?.call(code);
              },
            ),
          ),
        ],
      );
}

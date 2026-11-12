import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/services/price_comparison.dart';
import '../l10n/app_localizations.dart';

/// Currency and reference-rate controls shared by the flight and hotel results.
class PriceComparisonControls extends StatelessWidget {
  final PriceComparison comparison;
  final Iterable<String> sourceCurrencies;
  final int unpricedCount;
  final bool showBudget;
  final double? budget;
  final ValueChanged<double?>? onBudgetChanged;
  final ValueChanged<String>? onCurrencyChanged;

  const PriceComparisonControls({
    super.key,
    required this.comparison,
    required this.sourceCurrencies,
    required this.unpricedCount,
    this.showBudget = false,
    this.budget,
    this.onBudgetChanged,
    this.onCurrencyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final date = comparison.oldestDate(sourceCurrencies);
    final stale = comparison.isStale(sourceCurrencies);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.compareIn,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(
                width: 112,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(comparison.currency),
                  initialValue: comparison.currency,
                  isDense: true,
                  decoration: InputDecoration(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: comparison.currencies
                      .map((currency) => DropdownMenuItem(
                            value: currency,
                            child: Text(currency),
                          ))
                      .toList(),
                  onChanged: comparison.isLoading
                      ? null
                      : (value) {
                          if (value != null) {
                            comparison.setCurrency(value);
                            onCurrencyChanged?.call(value);
                          }
                        },
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    comparison.isLoading ? null : () => comparison.refresh(),
                icon: comparison.isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 17),
                label: Text(
                    comparison.failed ? l10n.retryRates : l10n.refreshRates),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              if (showBudget && onBudgetChanged != null)
                SizedBox(
                  width: 168,
                  child: TextFormField(
                    key: ValueKey('budget-${budget ?? ''}'),
                    initialValue: budget?.toStringAsFixed(2) ?? '',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final parsed = double.tryParse(value.trim());
                      return parsed != null && parsed.isFinite && parsed >= 0
                          ? null
                          : l10n.invalidComparisonBudget;
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l10n.flightMaxBudget,
                      prefixText: '${comparison.currency} ',
                      suffixIcon: budget == null
                          ? null
                          : IconButton(
                              tooltip: l10n.clearBudget,
                              onPressed: () => onBudgetChanged!(null),
                              icon: const Icon(Icons.close_rounded, size: 17),
                            ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 9),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onFieldSubmitted: (value) {
                      if (value.trim().isEmpty) {
                        onBudgetChanged!(null);
                        return;
                      }
                      final parsed = double.tryParse(value.trim());
                      if (parsed != null && parsed.isFinite && parsed >= 0) {
                        onBudgetChanged!(parsed);
                      }
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            date == null
                ? l10n.frankfurterRatesUnavailable
                : l10n.frankfurterRatesDate(
                    MaterialLocalizations.of(context).formatMediumDate(date),
                  ),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (comparison.failed || stale) ...[
            const SizedBox(height: 5),
            Text(
              comparison.failed ? l10n.rateRefreshFailed : l10n.ratesMayBeStale,
              style: const TextStyle(
                color: AppColors.accentOrange,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (unpricedCount > 0) ...[
            const SizedBox(height: 5),
            Text(
              l10n.unpricedOffers(unpricedCount),
              style: const TextStyle(
                color: AppColors.accentOrange,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 5),
          Text(
            l10n.priceEstimateDisclaimer,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            l10n.referenceRatePolicy,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

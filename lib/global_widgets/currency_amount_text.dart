import 'package:flutter/material.dart';

import '../core/services/currency_service.dart';
import '../core/utils/money_format.dart';

/// Displays a USD-base or provider-currency amount in the user's selected
/// currency. Original amounts remain unchanged in the booking/provider models.
class CurrencyAmountText extends StatelessWidget {
  final double amount;
  final String sourceCurrencyCode;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? decimalDigits;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool softWrap;

  const CurrencyAmountText({
    super.key,
    required this.amount,
    this.sourceCurrencyCode = 'USD',
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.textAlign,
    this.decimalDigits,
    this.maxLines,
    this.overflow,
    this.softWrap = true,
  });

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final service = CurrencyService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final code = service.selected.code;
        final converted = service.convertFrom(amount, sourceCurrencyCode);
        final display = converted == null
            ? formatProviderMoney(
                amount,
                sourceCurrencyCode,
                locale: locale,
              )
            : formatCurrencyAmount(
                converted,
                code,
                locale: locale,
                decimalDigits: decimalDigits,
              );
        return Text(
          '$prefix$display$suffix',
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap,
        );
      },
    );
  }
}

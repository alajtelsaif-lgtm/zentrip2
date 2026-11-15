import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money_format.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_model.dart';
import 'flight_primary_button.dart';

/// Shared blue-gradient title bar and four-step progress indicator.
class FlightBookingFlowHeader extends StatelessWidget {
  final String title;
  final int activeStep;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  const FlightBookingFlowHeader({
    super.key,
    required this.title,
    required this.activeStep,
    this.onBack,
    this.onSkip,
  }) : assert(activeStep >= 0 && activeStep <= 3);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final copy = CheckoutLabels(l10n);
    final labels = [copy.fare, l10n.passengers, copy.seats, copy.pay];
    return Column(
      children: [
        Container(
          height: 70,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          child: Row(
            children: [
              if (onBack != null)
                IconButton(
                  tooltip: l10n.goBack,
                  onPressed: onBack,
                  icon:
                      const Icon(Icons.arrow_back_rounded, color: Colors.white),
                )
              else
                const SizedBox(width: 48),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                child: onSkip == null
                    ? null
                    : TextButton(
                        onPressed: onSkip,
                        child: Text(
                          copy.skip,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
          child: Row(
            children: List.generate(labels.length, (index) {
              final complete = index < activeStep;
              final active = index == activeStep;
              return Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    end: index == labels.length - 1 ? 0 : 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 3,
                        decoration: BoxDecoration(
                          color: complete || active
                              ? AppColors.primary
                              : AppColors.border,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          if (complete)
                            const Icon(Icons.check_circle_rounded,
                                size: 12, color: AppColors.primary)
                          else if (active)
                            const Icon(Icons.circle,
                                size: 11, color: AppColors.primary)
                          else
                            const SizedBox(width: 11),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              labels[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active || complete
                                    ? AppColors.textPrimary
                                    : AppColors.textHint,
                                fontSize: 10,
                                fontWeight: active || complete
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

/// Bilingual presentation copy shared by checkout steps.
class CheckoutLabels {
  final AppLocalizations l10n;
  const CheckoutLabels(this.l10n);

  bool get _ar => l10n.localeName.startsWith('ar');
  String get chooseFare => _ar ? 'اختر الدرجة' : 'Choose Fare';
  String get chooseSeats => _ar ? 'اختر المقاعد' : 'Choose Seats';
  String get continueLabel => _ar ? 'متابعة' : 'Continue';
  String get fare => _ar ? 'الدرجة' : 'Fare';
  String get seats => _ar ? 'المقاعد' : 'Seats';
  String get pay => _ar ? 'الدفع' : 'Pay';
  String get skip => _ar ? 'تخطي' : 'Skip';
  String get chooseYourFare =>
      _ar ? 'اختر الدرجة المناسبة' : 'Choose your fare';
  String get fareSubheading =>
      _ar ? 'اختر السعر الذي يناسب رحلتك' : 'Select a fare for your trip';
  String get farePrice => _ar ? 'سعر التذكرة' : 'Fare price';
  String get availableSeats => _ar ? 'المقاعد المتاحة' : 'Available seats';
  String get available => _ar ? 'متاح' : 'Available';
  String get extraLegroom => _ar ? 'مساحة إضافية للأرجل' : 'Extra legroom';
  String get yourSeat => _ar ? 'مقعدك' : 'Your seat';
  String get taken => _ar ? 'محجوز' : 'Taken';
  String get deck => _ar ? 'المقصورة' : 'DECK';
  String seatSemanticLabel(
    String seatId, {
    required bool selected,
    required bool occupied,
    required bool premium,
  }) {
    final status = _ar
        ? selected
            ? 'مقعدك'
            : occupied
                ? 'محجوز'
                : premium
                    ? 'مساحة إضافية للأرجل، متاح'
                    : 'متاح'
        : selected
            ? 'your seat'
            : occupied
                ? 'taken'
                : premium
                    ? 'extra legroom, available'
                    : 'available';
    return _ar ? 'المقعد $seatId، $status' : 'Seat $seatId, $status';
  }

  String chooseSeatsOrSkip(int count) => _ar
      ? 'اختر $count من المقاعد أو تخطَّ اختيار المقاعد.'
      : 'Choose $count seat${count == 1 ? '' : 's'}, or skip seat selection.';
  String get economy => _ar ? 'الاقتصادية' : 'Economy';
  String get business => _ar ? 'رجال الأعمال' : 'Business';
  String get firstClass => _ar ? 'الدرجة الأولى' : 'First';
  String get noFareData =>
      _ar ? 'لا توجد بيانات أسعار متاحة.' : 'Fare details are not available.';
  String get whosFlying => _ar ? 'من المسافر؟' : 'Who’s flying?';
  String get passportPrompt => _ar
      ? 'أدخل بياناتك تماماً كما تظهر في جواز السفر'
      : 'Enter your details exactly as they appear on your passport';
  String get dateOfBirth => _ar ? 'تاريخ الميلاد' : 'Date of birth';
  String get nationality => _ar ? 'الجنسية' : 'Nationality';
  String get passportNumber => _ar ? 'رقم جواز السفر' : 'Passport number';
  String get passportExpiry => _ar ? 'تاريخ انتهاء الجواز' : 'Passport expiry';
  String get passportPrivacy => _ar
      ? 'تُرسل بيانات جواز السفر إلى شركة الطيران وإجراءات الحدود فقط.'
      : 'Passport details are shared with the airline and border control only.';
  String get noPassengerData => _ar
      ? 'لا توجد بيانات مسافرين.'
      : 'Passenger details have not been provided.';
  String get reviewPay => _ar ? 'مراجعة ودفع' : 'Review & Pay';
  String get priceDetails => _ar ? 'تفاصيل السعر' : 'Price details';
  String get simulatedPayment =>
      _ar ? 'الدفع التجريبي الآمن' : 'Secure simulated payment';
  String get promoCode => _ar ? 'رمز ترويجي' : 'Add promo code';
  String get acceptTermsBelow =>
      _ar ? 'اقبل الشروط أدناه' : 'Accept the terms below';
  String get direct => _ar ? 'مباشرة' : 'Direct';
  String get traveller => _ar ? 'مسافر' : 'Traveler';
  String travellerType(int index) => '$traveller ${index + 1}';
  String fareForClass(String seatClass) => switch (seatClass.toLowerCase()) {
        'business' => business,
        'first' => firstClass,
        _ => economy,
      };
  String travellerPrice(int count) => _ar
      ? '$count مسافر · السعر الإجمالي'
      : '$count traveler${count == 1 ? '' : 's'} · total';
  String stops(int count) =>
      _ar ? 'توقف $count' : '$count stop${count == 1 ? '' : 's'}';
  String payAmount(String amount) => _ar ? 'ادفع $amount' : 'Pay $amount';
  String fareRules(String fare) => _ar
      ? 'أوافق على شروط درجة $fare وسياسة النقل الجوي.'
      : 'I accept the $fare fare rules and conditions of carriage.';
  String securePayment(String currency) => _ar
      ? 'دفع مشفّر تجريبياً · $currency'
      : 'Secure simulated payment · charged in $currency';
  String get nameLabel => l10n.nameLabel;
}

class CheckoutScaffold extends StatelessWidget {
  final Widget header;
  final Widget child;
  final Widget footer;
  const CheckoutScaffold({
    super.key,
    required this.header,
    required this.child,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              header,
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: child,
                  ),
                ),
              ),
              footer,
            ],
          ),
        ),
      );
}

class CheckoutFooter extends StatefulWidget {
  final String total;
  final String caption;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final Future<void> Function()? onAsyncPressed;
  final bool loading;
  const CheckoutFooter({
    super.key,
    required this.total,
    required this.caption,
    required this.buttonLabel,
    required this.onPressed,
    this.onAsyncPressed,
    this.loading = false,
  });

  @override
  State<CheckoutFooter> createState() => _CheckoutFooterState();
}

class _CheckoutFooterState extends State<CheckoutFooter> {
  bool _busy = false;

  Future<void> _invokeAsync() async {
    final callback = widget.onAsyncPressed;
    if (callback == null || _busy || widget.loading) return;
    setState(() => _busy = true);
    try {
      await callback();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 688),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.total,
                          style: const TextStyle(
                              fontSize: 19,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800)),
                      Text(widget.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.textHint, fontSize: 9)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: FlightPrimaryButton(
                    label: widget.buttonLabel,
                    loading: widget.loading || _busy,
                    onPressed: _busy
                        ? null
                        : widget.onAsyncPressed == null
                            ? widget.onPressed
                            : _invokeAsync,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class CheckoutPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const CheckoutPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.025),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
}

class CheckoutIconTile extends StatelessWidget {
  final IconData icon;
  const CheckoutIconTile({super.key, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: AppColors.primary, size: 16),
      );
}

class CheckoutDataRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasis;
  const CheckoutDataRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                    color: emphasis
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontSize: emphasis ? 14 : 11,
                    fontWeight: emphasis ? FontWeight.w800 : FontWeight.w500,
                  )),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: emphasis ? AppColors.primary : AppColors.textPrimary,
                    fontSize: emphasis ? 17 : 11,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ],
        ),
      );
}

class CheckoutEmptyPanel extends StatelessWidget {
  final String message;
  const CheckoutEmptyPanel({super.key, required this.message});
  @override
  Widget build(BuildContext context) => CheckoutPanel(
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 18, color: AppColors.textHint),
            const SizedBox(width: 9),
            Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ),
          ],
        ),
      );
}

class CheckoutRouteCaption extends StatelessWidget {
  final FlightModel flight;
  final bool compact;
  const CheckoutRouteCaption({
    super.key,
    required this.flight,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              '${flight.originCode}  →  ${flight.destinationCode}',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: compact ? 11 : 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${flight.duration} · ${checkoutShortDate(flight.departureTime)}',
            style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 10,
                fontWeight: FontWeight.w500),
          ),
        ],
      );
}

class CheckoutTwoColumnValues extends StatelessWidget {
  final String firstLabel;
  final String firstValue;
  final String secondLabel;
  final String secondValue;
  const CheckoutTwoColumnValues({
    super.key,
    required this.firstLabel,
    required this.firstValue,
    required this.secondLabel,
    required this.secondValue,
  });
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
              child: CheckoutValueLine(label: firstLabel, value: firstValue)),
          const SizedBox(width: 10),
          Expanded(
              child: CheckoutValueLine(label: secondLabel, value: secondValue)),
        ],
      );
}

class CheckoutValueLine extends StatelessWidget {
  final String label;
  final String value;
  const CheckoutValueLine(
      {super.key, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.textHint, fontSize: 10)),
          const SizedBox(height: 3),
          Text(
            value.isEmpty ? '—' : value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 11),
          ),
        ],
      );
}

InputDecoration checkoutInputDecoration(String label, IconData icon) =>
    InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 17),
      filled: true,
      fillColor: AppColors.surfaceSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );

String checkoutMoney(
  String currency,
  double value, {
  String locale = 'en',
}) =>
    formatCurrencyAmount(value, currency, locale: locale);

String checkoutClock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String checkoutShortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';

String checkoutMaskPassport(String value) {
  if (value.isEmpty) return '';
  final visible = value.length > 4 ? value.substring(value.length - 4) : value;
  return '${'•' * (value.length - visible.length)}$visible';
}

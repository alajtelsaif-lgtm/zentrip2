import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/constants/app_colors.dart';
import '../core/services/api_service.dart';
import '../l10n/app_localizations.dart';
import '../models/payment_session.dart';

/// بتفتح صفحة دفع (Hosted Checkout) وترجع true/false حسب نجاح الدفع من
/// عدمه. استخدمها هكذا:
/// ```dart
/// final paid = await PaymentCheckoutScreen.start(context, amountUsd: 120, description: 'حجز فندق', referenceId: bookingRef);
/// if (paid) { ... }
/// ```
class PaymentCheckoutScreen extends StatefulWidget {
  final PaymentSession session;
  const PaymentCheckoutScreen({super.key, required this.session});

  /// بيبدأ عملية دفع كاملة: يطلب رابط الدفع من الباك اند، يفتح الشاشة،
  /// ويتحقق من نجاح الدفع فعليًا مع السيرفر قبل ما يرجّع true.
  static Future<bool> start(
    BuildContext context, {
    required double amountUsd,
    String currencyCode = 'USD',
    required String description,
    required String referenceId,
  }) async {
    final sessionResult = await ApiService.instance.createPaymentCheckout(
      amountUsd: amountUsd,
      currencyCode: currencyCode,
      description: description,
      referenceId: referenceId,
    );
    if (sessionResult.data == null || !context.mounted) return false;

    final completedInCheckout = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => PaymentCheckoutScreen(session: sessionResult.data!)),
    );
    if (completedInCheckout != true || !context.mounted) return false;

    final verifyResult =
        await ApiService.instance.verifyPayment(sessionResult.data!.sessionId);
    if (verifyResult.isFailure) return false;
    return verifyResult.data == true;
  }

  @override
  State<PaymentCheckoutScreen> createState() => _PaymentCheckoutScreenState();
}

class _PaymentCheckoutScreenState extends State<PaymentCheckoutScreen> {
  late final WebViewController _webController;
  bool _isMock = false;
  bool _mockLoading = false;

  @override
  void initState() {
    super.initState();
    _isMock = widget.session.checkoutUrl.startsWith('mock://');
    if (!_isMock) {
      _webController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
            NavigationDelegate(onNavigationRequest: _onNavigation))
        ..loadRequest(Uri.parse(widget.session.checkoutUrl));
    }
  }

  NavigationDecision _onNavigation(NavigationRequest request) {
    // الباك اند لازم يوجّه المتصفح لروابط زي دي بعد الدفع، حسب ما بيتفق
    // عليه مع بوابة الدفع (HyperPay/PayTabs بترجع لـ return_url محدد).
    if (request.url.contains('/payments/success')) {
      Navigator.pop(context, true);
      return NavigationDecision.prevent;
    }
    if (request.url.contains('/payments/cancel')) {
      Navigator.pop(context, false);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _mockPay(bool success) async {
    if (_mockLoading) return;
    setState(() => _mockLoading = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    Navigator.pop(context, success);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_isMock) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.paymentTitle)),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.credit_card_rounded,
                      size: 56, color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(l10n.mockPaymentNotice,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _mockLoading ? null : () => _mockPay(true),
                      child: Text(l10n.simulateSuccessfulPayment),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _mockLoading ? null : () => _mockPay(false),
                      child: Text(l10n.simulateFailedPayment),
                    ),
                  ),
                ],
              ),
            ),
            if (_mockLoading)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.paymentTitle)),
      body: WebViewWidget(controller: _webController),
    );
  }
}

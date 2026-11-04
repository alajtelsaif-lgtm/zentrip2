import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/constants/app_colors.dart';
import '../l10n/app_localizations.dart';

/// عرض التذكرة كـ QR Code — يقدر موظف الاستقبال/المطار يمسحه بدل ما
/// يدوّر على كود الحجز يدويًا. شغالة تمامًا Offline (مفيش نداء API هنا).
class TicketQrScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final String refCode;
  final List<String> details;
  const TicketQrScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.refCode,
    this.details = const [],
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.yourTicket)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: QrImageView(data: refCode, size: 220, backgroundColor: Colors.white),
              ),
              const SizedBox(height: 24),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center),
              for (final detail in details)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              const SizedBox(height: 12),
              Text(refCode, style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/constants/app_colors.dart';
import '../global_widgets/app_shell.dart';
import '../l10n/app_localizations.dart';
import '../routes/app_routes.dart';

class BookingConfirmationScreen extends StatelessWidget {
  final String serviceName;
  final String primaryText;
  final String secondaryText;
  final String reference;
  final String dateLabel;
  final String priceLabel;
  final IconData serviceIcon;
  final String? routeStart;
  final String? routeEnd;

  const BookingConfirmationScreen({
    super.key,
    required this.serviceName,
    required this.primaryText,
    required this.secondaryText,
    required this.reference,
    required this.dateLabel,
    required this.priceLabel,
    required this.serviceIcon,
    this.routeStart,
    this.routeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasRoute = routeStart != null && routeEnd != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: IconButton(
                      tooltip: l10n.done,
                      onPressed: () => _returnHome(context),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF8B9BFF), size: 42),
                  const SizedBox(height: 12),
                  Text(
                    l10n.notifBookingConfirmedTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    primaryText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFB6C0E0),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _TicketCard(
                    serviceName: serviceName,
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                    reference: reference,
                    dateLabel: dateLabel,
                    priceLabel: priceLabel,
                    serviceIcon: serviceIcon,
                    hasRoute: hasRoute,
                    routeStart: routeStart,
                    routeEnd: routeEnd,
                    referenceLabel: l10n.bookingRef,
                    confirmedLabel: l10n.notifBookingConfirmedTitle,
                    dateFieldLabel: l10n.homeTravelDateLabel,
                    totalFieldLabel: l10n.flightTotal,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => _returnHome(context),
                    icon: const Icon(Icons.home_rounded),
                    label: Text(l10n.done),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryLight,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _returnHome(BuildContext context) {
    AppShellTabController.goToTab(3);
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (_) => false);
  }
}

class _TicketCard extends StatelessWidget {
  final String serviceName;
  final String primaryText;
  final String secondaryText;
  final String reference;
  final String dateLabel;
  final String priceLabel;
  final IconData serviceIcon;
  final bool hasRoute;
  final String? routeStart;
  final String? routeEnd;
  final String referenceLabel;
  final String confirmedLabel;
  final String dateFieldLabel;
  final String totalFieldLabel;

  const _TicketCard({
    required this.serviceName,
    required this.primaryText,
    required this.secondaryText,
    required this.reference,
    required this.dateLabel,
    required this.priceLabel,
    required this.serviceIcon,
    required this.hasRoute,
    required this.routeStart,
    required this.routeEnd,
    required this.referenceLabel,
    required this.confirmedLabel,
    required this.dateFieldLabel,
    required this.totalFieldLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(serviceIcon, color: AppColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        serviceName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primarySurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        confirmedLabel.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (hasRoute)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _RoutePoint(code: routeStart!, city: primaryText),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            children: [
                              Icon(Icons.flight_rounded,
                                  color: AppColors.primary, size: 19),
                              SizedBox(height: 5),
                              Divider(height: 1, color: AppColors.border),
                            ],
                          ),
                        ),
                      ),
                      _RoutePoint(
                          code: routeEnd!, city: secondaryText, alignEnd: true),
                    ],
                  )
                else ...[
                  Text(
                    primaryText,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    secondaryText,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _TicketInfo(
                        label: dateFieldLabel.toUpperCase(),
                        value: dateLabel,
                      ),
                    ),
                    Expanded(
                      child: _TicketInfo(
                        label: totalFieldLabel.toUpperCase(),
                        value: priceLabel,
                        alignEnd: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _TicketNotchedDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: _TicketInfo(
                        label: referenceLabel.toUpperCase(),
                        value: reference,
                      ),
                    ),
                    QrImageView(
                      data: reference,
                      size: 72,
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePoint extends StatelessWidget {
  final String code;
  final String city;
  final bool alignEnd;

  const _RoutePoint({
    required this.code,
    required this.city,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          code,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 88,
          child: Text(
            city,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }
}

class _TicketInfo extends StatelessWidget {
  final String label;
  final String value;
  final bool alignEnd;

  const _TicketInfo({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _TicketNotchedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFF0B1020),
              borderRadius: BorderRadius.horizontal(
                right: Radius.circular(12),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  (constraints.maxWidth / 12).floor(),
                  (_) => Container(
                    width: 5,
                    height: 1,
                    color: AppColors.border,
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFF0B1020),
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

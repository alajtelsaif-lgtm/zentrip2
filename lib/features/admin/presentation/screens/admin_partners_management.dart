import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/admin_dashboard_model.dart';
import '../../../../models/legacy_attraction_review_model.dart';
import 'admin_legacy_attraction_review_dialog.dart';

class AdminPartnersManagement extends StatefulWidget {
  const AdminPartnersManagement({super.key});

  @override
  State<AdminPartnersManagement> createState() =>
      AdminPartnersManagementState();
}

class AdminPartnersManagementState extends State<AdminPartnersManagement> {
  List<AdminPartner> _partners = const [];
  List<LegacyAttractionPartner> _legacyAttractions = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _legacyError;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ApiService.instance.getAdminPartners();
    final legacyResult =
        await ApiService.instance.getAdminLegacyAttractionPartners();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.isSuccess && result.data != null) {
        _partners = result.data!;
      } else {
        _error = result.errorMessage;
      }
      if (legacyResult.isSuccess && legacyResult.data != null) {
        _legacyAttractions = legacyResult.data!;
        _legacyError = null;
      } else {
        _legacyError = legacyResult.errorMessage;
      }
    });
  }

  Future<void> _addPartner() async {
    final l10n = AppLocalizations.of(context);
    final details = await showDialog<_PartnerFormValue>(
      context: context,
      builder: (_) => _AddPartnerDialog(l10n: l10n),
    );
    if (details == null || !mounted) return;
    setState(() => _saving = true);
    final result = await ApiService.instance.addAdminPartner(
      name: details.name,
      email: details.email,
      serviceType: details.serviceType,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.isFailure) {
      AppSnackbar.error(context, result.errorMessage ?? l10n.genericError);
      return;
    }
    AppSnackbar.success(context, l10n.adminPartnerAdded);
    await reload();
  }

  Future<void> _disablePartner(AdminPartner partner) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminDisablePartner),
        content: Text(l10n.adminDisablePartnerConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.adminDisablePartner),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final result = await ApiService.instance.disableAdminPartner(partner.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.isFailure) {
      AppSnackbar.error(context, result.errorMessage ?? l10n.genericError);
      return;
    }
    AppSnackbar.success(context, l10n.adminPartnerDisabled);
    await reload();
  }

  Future<void> _activatePartner(AdminPartner partner) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final result = await ApiService.instance.activateAdminPartner(partner.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.isFailure) {
      AppSnackbar.error(context, result.errorMessage ?? l10n.genericError);
      return;
    }
    AppSnackbar.success(context, l10n.adminPartnerRestored);
    await reload();
  }

  Future<void> _reviewAttraction(LegacyAttractionPartner partner) async {
    final l10n = AppLocalizations.of(context);
    final placesResult = await ApiService.instance.getAdminMonuments();
    if (!mounted) return;
    if (placesResult.isFailure || placesResult.data == null) {
      AppSnackbar.error(context, placesResult.errorMessage ?? l10n.genericError);
      return;
    }
    final decisions = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => AdminLegacyAttractionReviewDialog(
        partner: partner,
        places: placesResult.data!,
      ),
    );
    if (decisions == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.adminLegacyAttractionConfirmTitle),
        content: Text(l10n.adminLegacyAttractionConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.adminLegacyAttractionApproveRetire),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final result =
        await ApiService.instance.reviewAndRetireLegacyAttractionPartner(
      id: partner.id,
      listingDecisions: decisions,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.isFailure) {
      AppSnackbar.error(context, result.errorMessage ?? l10n.genericError);
      return;
    }
    AppSnackbar.success(context, l10n.adminLegacyAttractionReviewSaved);
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading && _partners.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null && _partners.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: reload,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.adminRefresh),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: _saving || _loading ? null : _addPartner,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded),
              label: Text(l10n.adminAddPartner),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.adminLegacyAttractionReviewTitle,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (_legacyError != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline_rounded),
                title: Text(_legacyError!),
                trailing: IconButton(
                  onPressed: reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
            ),
          if (_legacyAttractions.isEmpty && _legacyError == null)
            _PartnerEmptyState(text: l10n.adminNoPartners),
          for (final partner in _legacyAttractions)
            _LegacyAttractionCard(
              partner: partner,
              saving: _saving,
              onReview: partner.isReviewed || _saving
                  ? null
                  : () => _reviewAttraction(partner),
            ),
          const SizedBox(height: 20),
          Text(
            l10n.adminPartners,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (_partners
                  .where((p) => p.serviceType.toLowerCase() != 'attraction')
                  .isEmpty &&
              _legacyAttractions.isEmpty)
            _PartnerEmptyState(text: l10n.adminNoPartners),
          for (final partner
              in _partners.where(
                  (p) => p.serviceType.toLowerCase() != 'attraction'))
            _PartnerCard(
              partner: partner,
              serviceLabel: _serviceLabel(partner.serviceType, l10n),
              statusActionLabel: partner.isActive
                  ? l10n.adminDisablePartner
                  : l10n.adminRestorePartner,
              onStatusAction: _saving || _loading
                  ? null
                  : () => partner.isActive
                      ? _disablePartner(partner)
                      : _activatePartner(partner),
            ),
        ],
      ),
    );
  }

  String _serviceLabel(String type, AppLocalizations l10n) => switch (type) {
        'airline' => l10n.adminServiceAirline,
        'hotel' => l10n.adminServiceHotel,
        'car' => l10n.adminServiceCar,
        'attraction' => l10n.adminServiceAttraction,
        'transfer' => l10n.adminServiceTransfer,
        'travel' => l10n.adminServiceTravel,
        _ => type,
      };
}

class _LegacyAttractionCard extends StatelessWidget {
  final LegacyAttractionPartner partner;
  final bool saving;
  final VoidCallback? onReview;

  const _LegacyAttractionCard({
    required this.partner,
    required this.saving,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final statusColor =
        partner.isActive ? AppColors.accentGreen : AppColors.textSecondary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.primarySurface,
                  child: Icon(Icons.attractions_rounded,
                      color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    partner.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(
                  label: Text(partner.isActive
                      ? l10n.adminPartnerStatusActive
                      : l10n.adminPartnerStatusInactive),
                  labelStyle: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (partner.accounts.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                partner.accounts.join(', '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PartnerStat(
                  label: l10n.adminPartnerAccounts,
                  value: partner.accounts.length,
                ),
                _PartnerStat(
                  label: l10n.adminPartnerListings,
                  value: partner.listings.length,
                ),
              ],
            ),
            if (partner.listings.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(l10n.adminLegacyAttractionNoListings),
              )
            else ...[
              const SizedBox(height: 8),
              for (final listing in partner.listings)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    '• ${listing.title.isEmpty ? '#${listing.id}' : listing.title}'
                    ' — ${listing.type}'
                    '${listing.city.isEmpty ? '' : ', ${listing.city}'}'
                    '${listing.country.isEmpty ? '' : ', ${listing.country}'}'
                    ' — ${listing.active ? l10n.adminPartnerStatusActive : l10n.adminPartnerStatusInactive}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            const Divider(height: 24),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: partner.isReviewed
                  ? Text(
                      l10n.adminLegacyAttractionAccountReviewedBy(
                        partner.reviewedByName?.isNotEmpty == true
                            ? partner.reviewedByName!
                            : l10n.adminDashboard,
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : FilledButton.icon(
                      onPressed: saving ? null : onReview,
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.fact_check_outlined),
                      label: Text(l10n.adminLegacyAttractionReviewAction),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartnerCard extends StatelessWidget {
  final AdminPartner partner;
  final String serviceLabel;
  final String statusActionLabel;
  final VoidCallback? onStatusAction;

  const _PartnerCard({
    required this.partner,
    required this.serviceLabel,
    required this.statusActionLabel,
    required this.onStatusAction,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final statusColor =
        partner.isActive ? AppColors.accentGreen : AppColors.textSecondary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primarySurface,
                  child: Icon(
                    _serviceIcon(partner.serviceType),
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        partner.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        serviceLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    partner.isActive
                        ? l10n.adminPartnerStatusActive
                        : l10n.adminPartnerStatusInactive,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (partner.contactEmails.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(
                partner.contactEmails,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PartnerStat(
                  label: l10n.adminPartnerAccounts,
                  value: partner.accountCount,
                ),
                _PartnerStat(
                  label: l10n.adminPartnerListings,
                  value: partner.listingCount,
                ),
              ],
            ),
            const Divider(height: 24),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: onStatusAction,
                icon: Icon(partner.isActive
                    ? Icons.person_off_outlined
                    : Icons.person_add_alt_1_outlined),
                label: Text(statusActionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _serviceIcon(String type) => switch (type) {
        'airline' => Icons.flight_rounded,
        'hotel' => Icons.hotel_rounded,
        'car' => Icons.directions_car_rounded,
        'attraction' => Icons.attractions_rounded,
        'transfer' => Icons.local_taxi_rounded,
        _ => Icons.luggage_rounded,
      };
}

class _PartnerStat extends StatelessWidget {
  final String label;
  final int value;

  const _PartnerStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Chip(
        avatar: const Icon(Icons.insights_outlined, size: 16),
        label: Text('$label: $value'),
        visualDensity: VisualDensity.compact,
      );
}

class _PartnerEmptyState extends StatelessWidget {
  final String text;

  const _PartnerEmptyState({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 72),
        child: Column(
          children: [
            const Icon(
              Icons.business_outlined,
              size: 44,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      );
}

class _PartnerFormValue {
  final String name;
  final String email;
  final String serviceType;

  const _PartnerFormValue(this.name, this.email, this.serviceType);
}

class _AddPartnerDialog extends StatefulWidget {
  final AppLocalizations l10n;

  const _AddPartnerDialog({required this.l10n});

  @override
  State<_AddPartnerDialog> createState() => _AddPartnerDialogState();
}

class _AddPartnerDialogState extends State<_AddPartnerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  String _serviceType = 'airline';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final services = <String, String>{
      'airline': l10n.adminServiceAirline,
      'hotel': l10n.adminServiceHotel,
      'car': l10n.adminServiceCar,
      'transfer': l10n.adminServiceTransfer,
      'travel': l10n.adminServiceTravel,
    };
    return AlertDialog(
      title: Text(l10n.adminAddPartner),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.adminPartnerExistingAccountHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 255,
                  decoration: InputDecoration(
                    labelText: l10n.adminPartnerName,
                    prefixIcon: const Icon(Icons.business_outlined),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? l10n.adminRequiredField
                      : null,
                ),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: l10n.adminPartnerEmail,
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(email)) {
                      return l10n.adminInvalidEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _serviceType,
                  decoration: InputDecoration(
                    labelText: l10n.adminPartnerService,
                    prefixIcon: const Icon(Icons.category_outlined),
                  ),
                  items: services.entries
                      .map((entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _serviceType = value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _PartnerFormValue(
                _name.text.trim(),
                _email.text.trim(),
                _serviceType,
              ),
            );
          },
          child: Text(l10n.adminAddPartner),
        ),
      ],
    );
  }
}

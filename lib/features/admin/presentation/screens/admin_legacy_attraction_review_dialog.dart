import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/attraction_model.dart';
import '../../../../models/legacy_attraction_review_model.dart';

class AdminLegacyAttractionReviewDialog extends StatefulWidget {
  final LegacyAttractionPartner partner;
  final List<AttractionModel> places;

  const AdminLegacyAttractionReviewDialog({
    super.key,
    required this.partner,
    required this.places,
  });

  @override
  State<AdminLegacyAttractionReviewDialog> createState() =>
      _AdminLegacyAttractionReviewDialogState();
}

class _AdminLegacyAttractionReviewDialogState
    extends State<AdminLegacyAttractionReviewDialog> {
  final Map<int, String> _choices = {};

  List<Map<String, dynamic>> get _decisions => widget.partner.listings
      .where((listing) => listing.canMapToPlace)
      .map((listing) {
        final choice = _choices[listing.id] ?? 'omit';
        if (choice.startsWith('existing:')) {
          return <String, dynamic>{
            'listing_id': listing.id,
            'action': 'existing',
            'monument_id': choice.substring('existing:'.length),
          };
        }
        return <String, dynamic>{
          'listing_id': listing.id,
          'action': choice,
        };
      }).toList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final attractionListings =
        widget.partner.listings.where((listing) => listing.canMapToPlace);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 760,
        height: MediaQuery.sizeOf(context).height * .86,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${l10n.adminLegacyAttractionReviewTitle}: ${widget.partner.name}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Text(
                l10n.adminLegacyAttractionReviewDescription,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.partner.listings.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l10n.adminLegacyAttractionNoListings),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (widget.partner.accounts.isNotEmpty) ...[
                          Text(
                            '${l10n.adminPartnerAccounts}: ${widget.partner.accounts.join(', ')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                        ],
                        for (final listing in widget.partner.listings)
                          Card(
                            color: isDark
                                ? AppColors.darkSurfaceSecondary
                                : AppColors.surfaceSecondary,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    listing.title.isEmpty
                                        ? '${l10n.adminPartnerListings} #${listing.id}'
                                        : listing.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      listing.type,
                                      [listing.city, listing.country]
                                          .where((part) => part.isNotEmpty)
                                          .join(', '),
                                      listing.active
                                          ? l10n.adminPartnerStatusActive
                                          : l10n.adminPartnerStatusInactive,
                                    ].where((part) => part.isNotEmpty).join(' • '),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  if (listing.description.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      listing.description,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  if (listing.canMapToPlace)
                                    DropdownButtonFormField<String>(
                                      initialValue:
                                          _choices[listing.id] ?? 'omit',
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: l10n
                                            .adminLegacyAttractionReviewPlace,
                                        border: const OutlineInputBorder(),
                                      ),
                                      items: [
                                        DropdownMenuItem(
                                          value: 'omit',
                                          child: Text(
                                              l10n.adminLegacyAttractionOmit),
                                        ),
                                        DropdownMenuItem(
                                          value: 'create',
                                          child: Text(l10n
                                              .adminLegacyAttractionCreatePlace),
                                        ),
                                        for (final place in widget.places)
                                          DropdownMenuItem(
                                            value: 'existing:${place.id}',
                                            child: Text(
                                              '${l10n.adminLegacyAttractionUseExisting}: ${place.title} (${place.location})',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(
                                              () => _choices[listing.id] = value);
                                        }
                                      },
                                    )
                                  else
                                    Text(
                                      l10n
                                          .adminLegacyAttractionNonPlaceListing,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (attractionListings.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                                l10n.adminLegacyAttractionNoListings),
                          ),
                      ],
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, _decisions),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(l10n.adminLegacyAttractionApproveRetire),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

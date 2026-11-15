import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../global_widgets/currency_amount_text.dart';
import '../../../../global_widgets/app_network_image.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/attraction_model.dart';
import '../../../../models/flight_model.dart';
import '../../../../models/travel_package_model.dart';

enum AdminCatalogKind { monuments, offers }

class AdminCatalogManagement extends StatefulWidget {
  final AdminCatalogKind kind;

  const AdminCatalogManagement({super.key, required this.kind});

  @override
  State<AdminCatalogManagement> createState() => AdminCatalogManagementState();
}

class AdminCatalogManagementState extends State<AdminCatalogManagement> {
  List<AttractionModel> _monuments = [];
  List<TravelPackage> _offers = [];
  List<FlightModel> _flights = [];
  bool _loading = true;
  String? _error;

  bool get _isOffer => widget.kind == AdminCatalogKind.offers;

  Future<void> reload() => _load();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminCatalogManagement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (_isOffer) {
      final result = await ApiService.instance.getAdminOffers();
      final flightsResult = await ApiService.instance.getAdminFlightListings();
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (result.isSuccess && result.data != null) {
          _offers = result.data!;
        } else {
          _error = result.errorMessage;
        }
        if (flightsResult.isSuccess && flightsResult.data != null) {
          _flights = flightsResult.data!;
        } else {
          _error ??= flightsResult.errorMessage;
        }
      });
    } else {
      final result = await ApiService.instance.getAdminMonuments();
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (result.isSuccess && result.data != null) {
          _monuments = result.data!;
        } else {
          _error = result.errorMessage;
        }
      });
    }
  }

  Future<void> _edit({AttractionModel? monument, TravelPackage? offer}) async {
    final l10n = AppLocalizations.of(context);
    final value = await showDialog<dynamic>(
      context: context,
      builder: (_) => _CatalogEditor(
        kind: widget.kind,
        monument: monument,
        offer: offer,
        flights: _flights,
      ),
    );
    if (value == null || !mounted) return;
    final result = _isOffer
        ? await ApiService.instance.saveAdminOffer(
            value as TravelPackage,
            id: offer?.id,
          )
        : await ApiService.instance.saveAdminMonument(
            value as AttractionModel,
            id: monument?.id,
          );
    if (!mounted) return;
    if (result.isFailure) {
      AppSnackbar.error(context, result.errorMessage ?? l10n.genericError);
      return;
    }
    AppSnackbar.success(context, l10n.adminCatalogSaved);
    await _load();
  }

  Future<void> _delete(String id) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.adminDeleteCatalogEntry),
        content: Text(l10n.adminDeleteConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.partnerCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.adminDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = _isOffer
        ? await ApiService.instance.deleteAdminOffer(id)
        : await ApiService.instance.deleteAdminMonument(id);
    if (!mounted) return;
    if (result.isFailure) {
      AppSnackbar.error(context, result.errorMessage ?? l10n.genericError);
      return;
    }
    AppSnackbar.success(context, l10n.adminCatalogDeleted);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.adminRefresh),
              ),
            ],
          ),
        ),
      );
    }

    final count = _isOffer ? _offers.length : _monuments.length;
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded),
              label:
                  Text(_isOffer ? l10n.adminAddOffer : l10n.adminAddMonument),
            ),
          ),
          const SizedBox(height: 14),
          if (count == 0)
            _CatalogEmpty(
              label: l10n.adminCatalogEmpty,
              icon: _isOffer
                  ? Icons.local_offer_outlined
                  : Icons.account_balance_outlined,
            ),
          if (_isOffer)
            for (final offer in _offers)
              _OfferCard(
                offer: offer,
                onEdit: () => _edit(offer: offer),
                onDelete: () => _delete(offer.id),
              )
          else
            for (final monument in _monuments)
              _MonumentCard(
                monument: monument,
                onEdit: () => _edit(monument: monument),
                onDelete: () => _delete(monument.id),
              ),
        ],
      ),
    );
  }
}

class _MonumentCard extends StatelessWidget {
  final AttractionModel monument;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MonumentCard({
    required this.monument,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _CatalogCard(
      title: monument.title,
      subtitle: monument.location,
      imageUrl: monument.imageUrl,
      fallbackIcon: Icons.account_balance_rounded,
      rating: monument.rating,
      reviewCount: monument.reviewCount,
      price: monument.entryFee,
      onEdit: onEdit,
      onDelete: onDelete,
      children: [
        if (monument.categoryLabel.isNotEmpty)
          _CatalogBadge(
              label: monument.categoryLabel, color: AppColors.accentPurple),
        if (monument.workingHours.isNotEmpty)
          _CatalogBadge(
              label: '${l10n.adminWorkingHours}: ${monument.workingHours}',
              color: AppColors.accentTeal),
        if (monument.bestTimeToVisit?.isNotEmpty == true)
          _CatalogBadge(
              label: '${l10n.adminBestTime}: ${monument.bestTimeToVisit}',
              color: AppColors.accentGreen),
        for (final tag in monument.tags.take(4))
          _CatalogBadge(label: tag, color: AppColors.primary),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  final TravelPackage offer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _OfferCard({
    required this.offer,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _CatalogCard(
      title: offer.title,
      subtitle: '${offer.location}, ${offer.country}',
      imageUrl: offer.imageUrl,
      fallbackIcon: offer.icon,
      rating: offer.rating,
      reviewCount: offer.reviewCount,
      price: offer.totalPricePerPerson,
      onEdit: onEdit,
      onDelete: onDelete,
      children: [
        if (offer.flight != null)
          _CatalogBadge(
            label: '${offer.flight!.airline}'
                '${offer.flight!.flightNumber.isEmpty ? '' : ' · ${offer.flight!.flightNumber}'}'
                ' · ${offer.flight!.originCode} → ${offer.flight!.destinationCode}',
            color: AppColors.primary,
          ),
        if (offer.flight == null)
          _CatalogBadge(
              label: l10n.adminOfferFlightMissing,
              color: AppColors.accentOrange),
        if (offer.badge.isNotEmpty || offer.isFeatured)
          _CatalogBadge(
              label: offer.badge.isEmpty ||
                      offer.badge.toLowerCase() == 'featured offer' ||
                      offer.badge == 'عرض مميز'
                  ? l10n.homeFeaturedOffer
                  : offer.badge,
              color: AppColors.accentOrange),
        _CatalogBadge(
            label: '${offer.durationNights} ${l10n.adminNights}',
            color: AppColors.accentTeal),
        _CatalogBadge(
            label: l10n.adminCalculatedOfferTotal,
            amount: offer.totalPricePerPerson,
            color: AppColors.accentGreen),
        for (final highlight in offer.highlights.take(4))
          _CatalogBadge(label: highlight, color: AppColors.primary),
      ],
    );
  }
}

class _CatalogCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imageUrl;
  final IconData fallbackIcon;
  final double rating;
  final int reviewCount;
  final double? price;
  final List<Widget> children;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CatalogCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.fallbackIcon,
    required this.rating,
    required this.reviewCount,
    required this.price,
    required this.children,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: isDark ? AppColors.darkSurface : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side:
            BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: AppNetworkImage(
                      url: imageUrl,
                      fallbackIcon: fallbackIcon,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              color: AppColors.accentYellow, size: 16),
                          Text(' ${rating.toStringAsFixed(1)} ($reviewCount)',
                              style: Theme.of(context).textTheme.bodySmall),
                          if (price != null) ...[
                            const Spacer(),
                            CurrencyAmountText(
                                amount: price!,
                                decimalDigits: 0,
                                style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 7, runSpacing: 7, children: children),
            ],
            const Divider(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(l10n.adminDelete),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(l10n.partnerEditListing),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogBadge extends StatelessWidget {
  final String label;
  final Color color;
  final double? amount;

  const _CatalogBadge({
    required this.label,
    required this.color,
    this.amount,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: amount == null
            ? Text(
                label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600),
              )
            : CurrencyAmountText(
                amount: amount!,
                prefix: '$label: ',
                decimalDigits: 0,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600),
              ),
      );
}

class _CatalogEmpty extends StatelessWidget {
  final String label;
  final IconData icon;

  const _CatalogEmpty({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 72),
        child: Column(
          children: [
            Icon(icon, size: 42, color: AppColors.primaryLight),
            const SizedBox(height: 12),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      );
}

class _CatalogEditor extends StatefulWidget {
  final AdminCatalogKind kind;
  final AttractionModel? monument;
  final TravelPackage? offer;
  final List<FlightModel> flights;

  const _CatalogEditor({
    required this.kind,
    this.monument,
    this.offer,
    this.flights = const [],
  });

  @override
  State<_CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<_CatalogEditor> {
  final _formKey = GlobalKey<FormState>();
  final _tagInput = TextEditingController();
  late final Map<String, TextEditingController> _fields;
  late final List<String> _tags;
  late bool _featured;
  FlightModel? _selectedFlight;

  bool get _isOffer => widget.kind == AdminCatalogKind.offers;
  dynamic get _current => _isOffer ? widget.offer : widget.monument;

  @override
  void initState() {
    super.initState();
    final monument = widget.monument;
    final offer = widget.offer;
    for (final flight in widget.flights) {
      if (flight.partnerListingId == offer?.flightListingId) {
        _selectedFlight = flight;
        break;
      }
    }
    _fields = _isOffer
        ? {
            'title': TextEditingController(text: offer?.title ?? ''),
            'location': TextEditingController(text: offer?.location ?? ''),
            'country': TextEditingController(text: offer?.country ?? ''),
            'destination_code':
                TextEditingController(text: offer?.destinationCode ?? ''),
            'description':
                TextEditingController(text: offer?.description ?? ''),
            'image_url': TextEditingController(text: offer?.imageUrl ?? ''),
            'badge': TextEditingController(text: offer?.badge ?? ''),
            'hotel_price_per_night': TextEditingController(
                text: offer == null ? '' : '${offer.hotelPricePerNight}'),
            'duration_nights':
                TextEditingController(text: '${offer?.durationNights ?? 7}'),
            'rating': TextEditingController(text: '${offer?.rating ?? 0}'),
            'review_count':
                TextEditingController(text: '${offer?.reviewCount ?? 0}'),
            'category': TextEditingController(text: offer?.category ?? 'city'),
          }
        : {
            'title': TextEditingController(text: monument?.title ?? ''),
            'location': TextEditingController(text: monument?.location ?? ''),
            'category_tag':
                TextEditingController(text: monument?.categoryLabel ?? ''),
            'description':
                TextEditingController(text: monument?.description ?? ''),
            'working_hours':
                TextEditingController(text: monument?.workingHours ?? ''),
            'best_time_to_visit':
                TextEditingController(text: monument?.bestTimeToVisit ?? ''),
            'entry_fee': TextEditingController(
                text: monument?.entryFee?.toString() ?? ''),
            'image_url': TextEditingController(text: monument?.imageUrl ?? ''),
            'rating': TextEditingController(text: '${monument?.rating ?? 0}'),
            'review_count':
                TextEditingController(text: '${monument?.reviewCount ?? 0}'),
            'category':
                TextEditingController(text: monument?.category ?? 'historical'),
          };
    _tags = List<String>.of(
        _isOffer ? offer?.highlights ?? [] : monument?.tags ?? []);
    _featured = offer?.isFeatured ?? false;
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    _tagInput.dispose();
    super.dispose();
  }

  void _addTags(String value) {
    final additions = value
        .split(',')
        .map((item) => item.trim())
        .where((item) =>
            item.isNotEmpty &&
            !_tags.any((tag) => tag.toLowerCase() == item.toLowerCase()))
        .toList();
    if (additions.isNotEmpty) setState(() => _tags.addAll(additions));
    _tagInput.clear();
  }

  String? _validateRequired(String? value) =>
      value == null || value.trim().isEmpty
          ? AppLocalizations.of(context).partnerRequiredField
          : null;

  String? _validateNumber(String? value, {bool required = true}) {
    if (!required && (value == null || value.trim().isEmpty)) return null;
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0) {
      return AppLocalizations.of(context).partnerInvalidServiceField;
    }
    return null;
  }

  Widget _field(
    String key,
    String label, {
    bool required = false,
    bool numeric = false,
    int lines = 1,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _fields[key],
        maxLines: lines,
        onChanged: (_) => setState(() {}),
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        validator: required
            ? (value) {
                final requiredError = _validateRequired(value);
                if (requiredError != null) return requiredError;
                if (!numeric) return null;
                final numberError = _validateNumber(value);
                if (numberError != null) return numberError;
                if (key == 'duration_nights') {
                  final nights = int.tryParse(value!.trim());
                  return nights == null || nights < 1 || nights > 365
                      ? AppLocalizations.of(context).partnerInvalidServiceField
                      : null;
                }
                if (key == 'review_count') {
                  return int.tryParse(value!.trim()) == null
                      ? AppLocalizations.of(context).partnerInvalidServiceField
                      : null;
                }
                if (key == 'rating' && double.parse(value!.trim()) > 5) {
                  return AppLocalizations.of(context)
                      .partnerInvalidServiceField;
                }
                return null;
              }
            : numeric
                ? (value) => _validateNumber(value, required: false)
                : null,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: isDark
              ? AppColors.darkSurfaceSecondary
              : AppColors.surfaceSecondary,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.border),
          ),
        ),
      ),
    );
  }

  double _number(String key, [double fallback = 0]) =>
      double.tryParse(_fields[key]!.text.trim()) ?? fallback;

  int _int(String key, [int fallback = 0]) =>
      int.tryParse(_fields[key]!.text.trim()) ?? fallback;

  Widget _flightPicker(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<FlightModel>(
        initialValue: _selectedFlight,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.adminLinkedFlight,
          hintText: l10n.adminSelectFlight,
          filled: true,
          fillColor: isDark
              ? AppColors.darkSurfaceSecondary
              : AppColors.surfaceSecondary,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.border),
          ),
        ),
        items: widget.flights
            .map((flight) => DropdownMenuItem(
                  value: flight,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${flight.airline} · ${flight.flightNumber} · '
                          '${flight.originCode} → ${flight.destinationCode}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      CurrencyAmountText(
                        amount: flight.economyPrice,
                        sourceCurrencyCode: flight.priceCurrencyCode,
                        decimalDigits: 0,
                      ),
                    ],
                  ),
                ))
            .toList(),
        validator: (value) => value == null ? l10n.adminSelectFlight : null,
        onChanged: widget.flights.isEmpty
            ? null
            : (flight) => setState(() => _selectedFlight = flight),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final id = (_current?.id ?? '').toString();
    if (_isOffer) {
      final category = _fields['category']!.text.trim().isEmpty
          ? 'city'
          : _fields['category']!.text.trim();
      Navigator.pop(
        context,
        TravelPackage(
          id: id,
          title: _fields['title']!.text.trim(),
          location: _fields['location']!.text.trim(),
          country: _fields['country']!.text.trim(),
          destinationCode: _fields['destination_code']!.text.trim(),
          description: _fields['description']!.text.trim(),
          imageUrl: _fields['image_url']!.text.trim(),
          pricePerPerson: (_selectedFlight?.economyPrice ?? 0) +
              _number('hotel_price_per_night') * _int('duration_nights', 7),
          flightPricePerPerson: _selectedFlight?.economyPrice ?? 0,
          hotelPricePerNight: _number('hotel_price_per_night'),
          durationNights: _int('duration_nights', 7),
          rating: _number('rating'),
          reviewCount: _int('review_count'),
          gradient: AppColors.destinationGradients[
              id.hashCode.abs() % AppColors.destinationGradients.length],
          icon: TravelPackage.iconForCategory(category),
          highlights: List.unmodifiable(_tags),
          isFeatured: _featured,
          badge: _fields['badge']!.text.trim(),
          category: category,
          flightListingId: _selectedFlight?.partnerListingId,
          flight: _selectedFlight,
        ),
      );
    } else {
      final category = _fields['category']!.text.trim().isEmpty
          ? 'historical'
          : _fields['category']!.text.trim();
      Navigator.pop(
        context,
        AttractionModel(
          id: id,
          name: _fields['title']!.text.trim(),
          city: _fields['location']!.text.trim(),
          country: '',
          description: _fields['description']!.text.trim(),
          category: category,
          categoryTag: _fields['category_tag']!.text.trim(),
          rating: _number('rating'),
          reviewCount: _int('review_count'),
          entryFee: _fields['entry_fee']!.text.trim().isEmpty
              ? null
              : _number('entry_fee'),
          imageUrl: _fields['image_url']!.text.trim(),
          latitude: 0,
          longitude: 0,
          openingHours: _fields['working_hours']!.text.trim(),
          tags: List.unmodifiable(_tags),
          bestTimeToVisit: _fields['best_time_to_visit']!.text.trim(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = _isOffer
        ? <(String, String, bool, bool, int)>[
            ('title', l10n.adminTitle, true, false, 1),
            ('location', l10n.adminLocation, true, false, 1),
            ('country', l10n.adminCountry, true, false, 1),
            ('destination_code', l10n.adminDestinationCode, false, false, 1),
            ('description', l10n.adminDescription, true, false, 4),
            ('image_url', l10n.adminImageUrl, false, false, 1),
            ('badge', l10n.adminBadge, false, false, 1),
            ('hotel_price_per_night', l10n.adminHotelPriceNight, true, true, 1),
            ('duration_nights', l10n.adminNights, true, true, 1),
            ('rating', l10n.adminRating, true, true, 1),
            ('review_count', l10n.adminReviewCount, true, true, 1),
          ]
        : <(String, String, bool, bool, int)>[
            ('title', l10n.adminTitle, true, false, 1),
            ('location', l10n.adminLocation, true, false, 1),
            ('category_tag', l10n.adminCategoryTag, true, false, 1),
            ('description', l10n.adminDescription, true, false, 4),
            ('working_hours', l10n.adminWorkingHours, false, false, 1),
            ('best_time_to_visit', l10n.adminBestTime, false, false, 1),
            ('entry_fee', l10n.adminEntryFee, false, true, 1),
            ('image_url', l10n.adminImageUrl, false, false, 1),
            ('rating', l10n.adminRating, true, true, 1),
            ('review_count', l10n.adminReviewCount, true, true, 1),
          ];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = _isOffer
        ? (_current == null ? l10n.adminAddOffer : l10n.adminEditOffer)
        : (_current == null ? l10n.adminAddMonument : l10n.adminEditMonument);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * .88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    for (final (key, label, required, numeric, lines) in labels)
                      _field(
                        key,
                        label,
                        required: required,
                        numeric: numeric,
                        lines: lines,
                      ),
                    if (_isOffer) ...[
                      _flightPicker(l10n),
                      _field('category', l10n.adminCategory),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.adminFeaturedBadge),
                        value: _featured,
                        onChanged: (value) => setState(() => _featured = value),
                      ),
                      if (_selectedFlight != null ||
                          _fields['hotel_price_per_night']!.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: CurrencyAmountText(
                            amount: (_selectedFlight?.economyPrice ?? 0) +
                                _number('hotel_price_per_night') *
                                    _int('duration_nights', 7),
                            prefix: '${l10n.adminCalculatedOfferTotal}: ',
                            decimalDigits: 0,
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                    ] else
                      _field('category', l10n.adminCategory),
                    Text(
                      _isOffer ? l10n.adminHighlights : l10n.adminTagsLandmarks,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tagInput,
                            textInputAction: TextInputAction.done,
                            onSubmitted: _addTags,
                            decoration: InputDecoration(
                              hintText: l10n.partnerAmenityInputHint,
                              filled: true,
                              fillColor: isDark
                                  ? AppColors.darkSurfaceSecondary
                                  : AppColors.surfaceSecondary,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _addTags(_tagInput.text),
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                    if (_tags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _tags
                            .map((tag) => InputChip(
                                  label: Text(tag),
                                  onDeleted: () =>
                                      setState(() => _tags.remove(tag)),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
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
                    child: Text(l10n.partnerCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l10n.partnerSave),
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

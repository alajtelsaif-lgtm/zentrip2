import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../aircraft/aircraft.dart';
import '../../../aircraft/airbus_a320.dart';
import '../../../aircraft/atr72.dart';
import '../../logic/hotel_location_parser.dart';
import '../../../../global_widgets/app_logo.dart';
import '../../../../global_widgets/app_network_image.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/admin_dashboard_model.dart';
import '../../../../models/flight_model.dart';
import '../../../../models/partner_dashboard_model.dart';
import '../../../../routes/app_routes.dart';

enum _PartnerSection { overview, listings, reservations, customers }

class _SelectedHotelImage {
  final String filename;
  final Uint8List bytes;

  const _SelectedHotelImage({
    required this.filename,
    required this.bytes,
  });
}

class PartnerDashboardScreen extends StatefulWidget {
  const PartnerDashboardScreen({super.key});

  @override
  State<PartnerDashboardScreen> createState() => _PartnerDashboardScreenState();
}

class _PartnerDashboardScreenState extends State<PartnerDashboardScreen> {
  _PartnerSection _section = _PartnerSection.overview;
  PartnerDashboardData? _dashboard;
  List<PartnerListing> _listings = [];
  List<PartnerReservation> _reservations = [];
  List<AdminCustomer> _customers = [];
  bool _loading = true;
  bool _loadingSection = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOverview();
  }

  Future<void> _loadOverview() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ApiService.instance.getPartnerDashboard();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.isSuccess && result.data != null) {
        _dashboard = result.data;
      } else {
        _error = result.errorMessage;
      }
    });
  }

  Future<void> _loadListings() async {
    final result = await ApiService.instance.getPartnerListings();
    if (!mounted) return;
    if (result.isSuccess && result.data != null) {
      setState(() => _listings = result.data!);
    } else {
      setState(() => _error = result.errorMessage);
    }
  }

  Future<void> _refreshHotelRatingEventually(int listingId) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      final result = await ApiService.instance.getPartnerListings();
      if (!mounted) return;
      if (result.isFailure || result.data == null) {
        setState(() {
          _error =
              result.errorMessage ?? AppLocalizations.of(context).genericError;
        });
        return;
      }

      final listings = result.data!;
      setState(() => _listings = listings);
      PartnerListing? listing;
      for (final item in listings) {
        if (item.id == listingId) {
          listing = item;
          break;
        }
      }
      if (listing == null ||
          listing.googleRating > 0 ||
          listing.googleReviewCount > 0) {
        return;
      }
    }
  }

  Future<void> _selectSection(_PartnerSection section) async {
    setState(() {
      _section = section;
      _error = null;
    });
    if (section == _PartnerSection.overview) return;
    if (section == _PartnerSection.listings) {
      if (_listings.isEmpty) {
        setState(() => _loadingSection = true);
        await _loadListings();
        if (mounted) setState(() => _loadingSection = false);
      }
      return;
    }
    if (section == _PartnerSection.reservations && _reservations.isNotEmpty) {
      return;
    }
    if (section == _PartnerSection.customers && _customers.isNotEmpty) return;

    setState(() => _loadingSection = true);
    if (section == _PartnerSection.reservations) {
      final result = await ApiService.instance.getPartnerReservations();
      if (!mounted) return;
      setState(() {
        _loadingSection = false;
        if (result.isSuccess && result.data != null) {
          _reservations = result.data!;
        } else {
          _error = result.errorMessage;
        }
      });
    } else {
      final result = await ApiService.instance.getPartnerCustomers();
      if (!mounted) return;
      setState(() {
        _loadingSection = false;
        if (result.isSuccess && result.data != null) {
          _customers = result.data!;
        } else {
          _error = result.errorMessage;
        }
      });
    }
  }

  Future<void> _refresh() async {
    await _loadOverview();
    if (!mounted || _error != null) return;
    switch (_section) {
      case _PartnerSection.overview:
        break;
      case _PartnerSection.listings:
        await _loadListings();
        break;
      case _PartnerSection.reservations:
        final result = await ApiService.instance.getPartnerReservations();
        if (!mounted) return;
        setState(() {
          if (result.isSuccess && result.data != null) {
            _reservations = result.data!;
          } else {
            _error = result.errorMessage;
          }
        });
        break;
      case _PartnerSection.customers:
        final result = await ApiService.instance.getPartnerCustomers();
        if (!mounted) return;
        setState(() {
          if (result.isSuccess && result.data != null) {
            _customers = result.data!;
          } else {
            _error = result.errorMessage;
          }
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ApiService.instance.currentUser;
    if (user?.isPartner != true) {
      return Scaffold(body: Center(child: Text(l10n.adminNoAccess)));
    }

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth >= 900;
      return Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkBackground
            : AppColors.background,
        bottomNavigationBar: isWide ? null : _mobileNavigation(l10n),
        body: SafeArea(
          child: Row(
            children: [
              if (isWide) _sideNavigation(l10n, user!.name),
              Expanded(
                child: Column(
                  children: [
                    _topBar(l10n, user!.name, isWide),
                    Expanded(
                      child: RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: _refresh,
                        child: _content(l10n, isWide),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _sideNavigation(AppLocalizations l10n, String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 248,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppLogo(size: 42, showBackground: true),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Zentrip',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(l10n.partnerWorkspaceLabel,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
          _navItem(l10n.partnerOverview, Icons.space_dashboard_outlined,
              _PartnerSection.overview),
          const SizedBox(height: 8),
          _navItem(l10n.partnerListings, Icons.inventory_2_outlined,
              _PartnerSection.listings),
          const SizedBox(height: 8),
          _navItem(l10n.partnerReservations, Icons.book_online_outlined,
              _PartnerSection.reservations),
          const SizedBox(height: 8),
          _navItem(l10n.partnerCustomers, Icons.people_outline_rounded,
              _PartnerSection.customers),
          const Spacer(),
          Divider(color: isDark ? AppColors.darkBorder : AppColors.divider),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            leading: const Icon(Icons.open_in_new_rounded, size: 20),
            title: Text(l10n.partnerBackToApp,
                style: const TextStyle(fontSize: 13)),
            onTap: () =>
                Navigator.pushReplacementNamed(context, AppRoutes.home),
          ),
          const SizedBox(height: 10),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primarySurface,
            child: Text(name.isEmpty ? 'Z' : name[0].toUpperCase(),
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _navItem(String label, IconData icon, _PartnerSection section) {
    final selected = _section == section;
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _selectSection(section),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: selected
                      ? AppColors.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                    color: selected ? AppColors.primary : null,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileNavigation(AppLocalizations l10n) => NavigationBar(
        selectedIndex: _section.index,
        onDestinationSelected: (index) =>
            _selectSection(_PartnerSection.values[index]),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.space_dashboard_outlined),
              label: l10n.partnerOverview),
          NavigationDestination(
              icon: const Icon(Icons.inventory_2_outlined),
              label: l10n.partnerListings),
          NavigationDestination(
              icon: const Icon(Icons.book_online_outlined),
              label: l10n.partnerReservations),
          NavigationDestination(
              icon: const Icon(Icons.people_outline_rounded),
              label: l10n.partnerCustomers),
        ],
      );

  Widget _topBar(AppLocalizations l10n, String name, bool isWide) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 32 : 18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        border: Border(
          bottom: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Row(
        children: [
          if (!isWide) ...[
            const AppLogo(size: 38, showBackground: true),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_sectionTitle(l10n),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
                if (isWide)
                  Text('${l10n.partnerWelcome}, $name',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          IconButton(
              tooltip: l10n.adminRefresh,
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded)),
          if (!isWide)
            IconButton(
                tooltip: l10n.partnerBackToApp,
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, AppRoutes.home),
                icon: const Icon(Icons.home_outlined)),
        ],
      ),
    );
  }

  String _sectionTitle(AppLocalizations l10n) => switch (_section) {
        _PartnerSection.overview => l10n.partnerOverview,
        _PartnerSection.listings => l10n.partnerListings,
        _PartnerSection.reservations => l10n.partnerReservations,
        _PartnerSection.customers => l10n.partnerCustomers,
      };

  Widget _content(AppLocalizations l10n, bool isWide) {
    if (_loading && _dashboard == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null && _dashboard == null) {
      return _errorState(l10n.partnerLoadFailed);
    }
    if (_loadingSection) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) return _errorState(l10n.partnerLoadFailed);
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(isWide ? 32 : 18, 24, isWide ? 32 : 18, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: switch (_section) {
            _PartnerSection.overview => _overview(l10n, isWide),
            _PartnerSection.listings => _listingsView(l10n, isWide),
            _PartnerSection.reservations => _reservationsView(l10n),
            _PartnerSection.customers => _customersView(l10n, isWide),
          },
        ),
      ),
    );
  }

  Widget _errorState(String message) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(AppLocalizations.of(context).adminRefresh)),
          ],
        ),
      );

  Widget _overview(AppLocalizations l10n, bool isWide) {
    final data = _dashboard;
    if (data == null) return const SizedBox.shrink();
    final columns = isWide ? 4 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${l10n.partnerSubtitle} ${data.companyName}',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, constraints) {
          final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _MetricCard(
                  width: width,
                  title: l10n.partnerListingCount,
                  value: '${data.listingCount}',
                  icon: Icons.inventory_2_outlined,
                  color: AppColors.primary),
              _MetricCard(
                  width: width,
                  title: l10n.partnerActiveListings,
                  value: '${data.activeListingCount}',
                  icon: Icons.check_circle_outline,
                  color: AppColors.accentGreen),
              _MetricCard(
                  width: width,
                  title: l10n.partnerReservationCount,
                  value: '${data.reservationCount}',
                  icon: Icons.book_online_outlined,
                  color: AppColors.accentTeal),
              _MetricCard(
                  width: width,
                  title: l10n.partnerCustomerCount,
                  value: '${data.customerCount}',
                  icon: Icons.people_outline_rounded,
                  color: AppColors.accentOrange),
              _MetricCard(
                  width: width,
                  title: l10n.partnerBookedValue,
                  value: NumberFormat.currency(
                          locale: Localizations.localeOf(context).toString(),
                          symbol: '\$',
                          decimalDigits: 0)
                      .format(data.bookedValue),
                  icon: Icons.payments_outlined,
                  color: AppColors.accentOrange),
            ],
          );
        }),
        const SizedBox(height: 24),
        _sectionHeading(l10n.partnerRecentReservations),
        const SizedBox(height: 12),
        if (data.recentReservations.isEmpty)
          _emptyCard(l10n.partnerNoReservations)
        else
          ...data.recentReservations
              .map((item) => _reservationCard(item, l10n)),
      ],
    );
  }

  Widget _listingsView(AppLocalizations l10n, bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionHeading(l10n.partnerManageListings)),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _editListing,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.partnerCreateListing),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _serviceLabel(l10n, _dashboard?.serviceType),
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        if (_listings.isEmpty)
          _emptyCard(l10n.partnerEmptyListings)
        else
          LayoutBuilder(builder: (context, constraints) {
            final columns = isWide ? 2 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: _listings
                  .map((listing) => SizedBox(
                      width: width, child: _listingCard(listing, l10n)))
                  .toList(),
            );
          }),
      ],
    );
  }

  Widget _listingCard(PartnerListing listing, AppLocalizations l10n) {
    final status =
        listing.active ? l10n.partnerStatusActive : l10n.partnerStatusPaused;
    final availableRooms = listing.availableRooms;
    final location = [listing.locationName, listing.country]
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && value.toLowerCase() != 'null')
        .join(', ');
    final dynamicDetails = _dynamicListingDetails(listing);
    final carSpecs =
        listing.type == 'car' ? _carSpecs(listing, l10n) : const <Widget>[];
    final features = _displayAttributeList(listing.attributes['features']);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (listing.type == 'hotel' &&
              listing.imageUrl.trim().isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AppNetworkImage(
                url: listing.imageUrl,
                fallbackIcon: Icons.hotel_rounded,
                height: 110,
                width: double.infinity,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: Text(listing.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                    color: listing.active
                        ? AppColors.accentGreen.withValues(alpha: .12)
                        : AppColors.accentOrange.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(status,
                    style: TextStyle(
                        color: listing.active
                            ? AppColors.accentGreen
                            : AppColors.accentOrange,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (location.isNotEmpty)
            Text(location,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (listing.listingCode != null) ...[
            const SizedBox(height: 4),
            Text(
              '${l10n.partnerGeneratedCode}: ${listing.listingCode}'
              '${listing.type == 'flight' ? ' · ${listing.attributes['flight_number'] ?? ''}' : ''}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            listing.type == 'hotel'
                ? '${l10n.hotelNightPrice} · ${NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(listing.price)}'
                : '${_serviceLabel(l10n, _serviceForListingType(listing.type))} · ${NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(listing.price)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (listing.type == 'hotel') ...[
            if (listing.locationName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${l10n.partnerHotelLocationName}: ${listing.locationName}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
            if (listing.amenities.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: listing.amenities.take(5).map((amenity) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      amenity,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                }).toList(),
              ),
            ],
            if (listing.nonEmptyAttributes.containsKey('available_rooms')) ...[
              const SizedBox(height: 8),
              Text(
                '${l10n.partnerHotelAvailableRooms}: $availableRooms',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
            if (_attributeText(listing.attributes['location_input']) !=
                null) ...[
              const SizedBox(height: 4),
              Text(
                '${l10n.partnerHotelLocation}: ${_attributeText(listing.attributes['location_input'])}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
          if (listing.type == 'car') ...[
            if (carSpecs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: carSpecs,
              ),
            ],
            if (features.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: features
                    .map((feature) => Chip(
                          avatar:
                              const Icon(Icons.check_circle_outline, size: 16),
                          label: Text(feature),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ],
            if (_attributeText(listing.attributes['available_vehicles']) !=
                null) ...[
              const SizedBox(height: 4),
              Text(
                '${l10n.partnerAvailableVehicles}: ${_attributeText(listing.attributes['available_vehicles'])}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
          if (dynamicDetails.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: dynamicDetails
                  .map((detail) => _dynamicDetailChip(detail.key, detail.value))
                  .toList(growable: false),
            ),
          ],
          if (listing.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(listing.description,
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _editListing(listing),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(l10n.partnerEditListing),
              ),
              OutlinedButton(
                onPressed: () => _setListingActive(listing, !listing.active),
                child: Text(listing.active
                    ? l10n.partnerStatusPaused
                    : l10n.partnerStatusActive),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _alreadyDisplayedAttributeKeys = <String>{
    'listing_code',
    'flight_number',
    'address',
    'location_name',
    'neighborhood',
    'district',
    'landmark',
    'location_input',
    'amenities',
    'available_rooms',
    'available_vehicles',
    'stars',
    'room_types',
    'gallery_images',
    'google_maps_url',
    'google_place_id',
    'place_id',
    'google_rating',
    'google_review_count',
    'latitude',
    'longitude',
    'tax_and_fees_percentage',
    'rating',
    'fuel_type',
    'transmission',
    'has_ac',
    'luggage_capacity',
    'seats',
    'features',
  };

  List<MapEntry<String, String>> _dynamicListingDetails(
      PartnerListing listing) {
    const privateKeyFragments = [
      'password',
      'token',
      'secret',
      'credential',
      'private',
      'internal',
      'contact',
      'email',
      'phone',
      'photo',
      'image',
      'url',
      'path',
    ];
    return listing.nonEmptyAttributes.entries
        .where((entry) {
          final key = entry.key.trim().toLowerCase();
          return key.isNotEmpty &&
              !_alreadyDisplayedAttributeKeys.contains(key) &&
              !key.endsWith('_id') &&
              !privateKeyFragments.any(key.contains);
        })
        .map((entry) {
          final label = entry.key
              .replaceAll(RegExp(r'([a-z])([A-Z])'), r'$1 $2')
              .replaceAll(RegExp(r'[_-]+'), ' ')
              .trim()
              .split(RegExp(r'\s+'))
              .where((part) => part.isNotEmpty)
              .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
              .join(' ');
          final value = _attributeText(entry.value);
          return value == null ? null : MapEntry(label, value);
        })
        .whereType<MapEntry<String, String>>()
        .take(6)
        .toList(growable: false);
  }

  Widget _dynamicDetailChip(String label, String value) => Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$label: $value',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );

  List<Widget> _carSpecs(PartnerListing listing, AppLocalizations l10n) {
    final values = listing.nonEmptyAttributes;
    final specs = <Widget>[];
    String? value(String key) => _attributeText(values[key]);

    if (value('rating') case final rating?) {
      specs.add(_listingSpecChip(Icons.star_rounded, rating));
    }
    if (value('fuel_type') case final fuelType?) {
      specs.add(_listingSpecChip(Icons.local_gas_station_rounded, fuelType));
    }
    if (value('transmission') case final transmission?) {
      specs.add(_listingSpecChip(Icons.settings_rounded, transmission));
    }
    if (values.containsKey('has_ac')) {
      final hasAc = values['has_ac'] == true ||
          values['has_ac'] == 1 ||
          '${values['has_ac']}'.toLowerCase() == 'true';
      specs.add(_listingSpecChip(
          Icons.ac_unit_rounded, hasAc ? l10n.carHasAc : l10n.carNoAc));
    }
    if (value('luggage_capacity') case final luggage?) {
      specs.add(_listingSpecChip(
          Icons.luggage_rounded, '$luggage ${l10n.partnerMaxLuggage}'));
    }
    if (value('seats') case final seats?) {
      specs.add(_listingSpecChip(
          Icons.people_rounded, '$seats ${l10n.partnerSeats}'));
    }
    return specs;
  }

  String? _attributeText(Object? value) {
    if (value == null || value is Map) return null;
    if (value is List) {
      final items = value
          .map(_attributeText)
          .whereType<String>()
          .take(3)
          .toList(growable: false);
      return items.isEmpty ? null : items.join(', ');
    }
    if (value is double && !value.isFinite) return null;
    final text =
        value is bool ? (value ? 'Yes' : 'No') : value.toString().trim();
    if (text.isEmpty ||
        text.toLowerCase() == 'null' ||
        text.toLowerCase() == 'undefined') {
      return null;
    }
    return text.length > 80 ? '${text.substring(0, 77)}…' : text;
  }

  List<String> _displayAttributeList(Object? value) => value is List
      ? value.map(_attributeText).whereType<String>().toList(growable: false)
      : const [];

  Widget _listingSpecChip(IconData icon, String label) => Chip(
        avatar: Icon(icon, size: 16),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      );

  String _serviceLabel(AppLocalizations l10n, String? serviceType) =>
      switch (serviceType) {
        'airline' => l10n.partnerTypeFlight,
        'hotel' => l10n.partnerTypeHotel,
        'car' => l10n.partnerTypeCar,
        'attraction' => l10n.partnerTypeAttraction,
        'transfer' => l10n.partnerTypeTransfer,
        'travel' => l10n.partnerTypePackage,
        _ => l10n.partnerServiceType,
      };

  String _serviceForListingType(String type) => switch (type) {
        'flight' => 'airline',
        'hotel' => 'hotel',
        'car' => 'car',
        'attraction' => 'attraction',
        'transfer' => 'transfer',
        'package' => 'travel',
        _ => '',
      };

  Future<void> _editListing([PartnerListing? existing]) async {
    final l10n = AppLocalizations.of(context);
    final user = ApiService.instance.currentUser!;
    final result = await showDialog<PartnerListing>(
      context: context,
      builder: (_) => _PartnerListingDialog(
        existing: existing,
        type: _listingType(user.partnerServiceType),
      ),
    );
    if (result == null || !mounted) return;
    final response = await ApiService.instance.savePartnerListing(result);
    if (!mounted) return;
    if (response.isFailure) {
      AppSnackbar.error(
          context, response.errorMessage ?? l10n.partnerListingSaveFailed);
      return;
    }
    AppSnackbar.success(context, l10n.partnerListingSaved);
    await _loadListings();
    if (!mounted) return;
    final savedListingId = response.data?.id;
    if (result.type == 'hotel' && savedListingId != null) {
      unawaited(_refreshHotelRatingEventually(savedListingId));
    }
    await _loadOverview();
  }

  Future<void> _setListingActive(PartnerListing listing, bool active) async {
    final l10n = AppLocalizations.of(context);
    final result =
        await ApiService.instance.setPartnerListingActive(listing, active);
    if (!mounted) return;
    if (result.isFailure) {
      AppSnackbar.error(
          context, result.errorMessage ?? l10n.partnerListingSaveFailed);
      return;
    }
    await _loadListings();
    if (!mounted) return;
    await _loadOverview();
  }

  String _listingType(String? serviceType) => switch (serviceType) {
        'airline' => 'flight',
        'hotel' => 'hotel',
        'car' => 'car',
        'attraction' => 'attraction',
        'transfer' => 'transfer',
        'travel' => 'package',
        _ => 'hotel',
      };

  Widget _reservationsView(AppLocalizations l10n) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(l10n.partnerReservations),
          const SizedBox(height: 14),
          if (_reservations.isEmpty)
            _emptyCard(l10n.partnerNoReservations)
          else
            ..._reservations.map((item) => _reservationCard(item, l10n)),
        ],
      );

  Widget _reservationCard(PartnerReservation item, AppLocalizations l10n) {
    final date = item.reservationDate == null
        ? ''
        : DateFormat.yMMMd(Localizations.localeOf(context).toString())
            .format(item.reservationDate!);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _Panel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
                backgroundColor: AppColors.primarySurface,
                child:
                    Icon(Icons.book_online_outlined, color: AppColors.primary)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${item.customerName} · $date'),
                  if (item.customerEmail.isNotEmpty ||
                      item.customerPhone.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      [item.customerEmail, item.customerPhone]
                          .where((value) => value.isNotEmpty)
                          .join(' · '),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                    NumberFormat.currency(symbol: '\$', decimalDigits: 2)
                        .format(item.amount),
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(item.status,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _customersView(AppLocalizations l10n, bool isWide) {
    if (_customers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(l10n.partnerCustomers),
          const SizedBox(height: 14),
          _emptyCard(l10n.partnerNoCustomers),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(l10n.partnerCustomerDetails),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, constraints) {
          final columns = isWide ? 2 : 1;
          final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: _customers
                .map((customer) => SizedBox(
                      width: width,
                      child: _Panel(
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.primarySurface,
                              child: Text(customer.name.isEmpty
                                  ? '?'
                                  : customer.name[0].toUpperCase()),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(customer.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800)),
                                  if (customer.email.isNotEmpty)
                                    Text(customer.email),
                                  if (customer.phone.isNotEmpty)
                                    Text(customer.phone),
                                ],
                              ),
                            ),
                            Text('${customer.reservationCount}',
                                style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          );
        }),
      ],
    );
  }

  Widget _sectionHeading(String label) => Text(label,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800));

  Widget _emptyCard(String label) => _Panel(
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ),
      );
}

class _PartnerListingDialog extends StatefulWidget {
  final PartnerListing? existing;
  final String type;

  const _PartnerListingDialog({this.existing, required this.type});

  @override
  State<_PartnerListingDialog> createState() => _PartnerListingDialogState();
}

class _PartnerListingDialogState extends State<_PartnerListingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _city;
  late final TextEditingController _country;
  late final TextEditingController _description;
  late final TextEditingController _image;
  late final TextEditingController _price;
  late final TextEditingController _hotelLocation;
  late final TextEditingController _hotelLocationName;
  late final TextEditingController _googleRating;
  late final TextEditingController _amenityInput;
  late final TextEditingController _featureInput;
  late final FocusNode _amenityFocusNode;
  late final FocusNode _featureFocusNode;
  late final List<String> _hotelAmenities;
  late final List<String> _carFeatures;
  late final List<String> _hotelGalleryUrls;
  _SelectedHotelImage? _hotelMainImage;
  final List<_SelectedHotelImage> _newHotelGalleryImages = [];
  late final Map<String, TextEditingController> _attributeFields;
  late final Map<String, bool> _booleanAttributes;
  late final TextEditingController _originCity;
  late final TextEditingController _originCode;
  late final TextEditingController _destinationCity;
  late final TextEditingController _destinationCode;
  late final TextEditingController _departureTime;
  late final TextEditingController _arrivalTime;
  String _aircraftId = airbusA320.id;
  late final TextEditingController _transferPickupTime;
  late final TextEditingController _pickupLocation;
  late final TextEditingController _dropoffLocation;
  String? _error;
  bool _saving = false;

  Aircraft get _selectedAircraft =>
      _aircraftId == atr72.id ? atr72 : airbusA320;

  @override
  void initState() {
    super.initState();
    final listing = widget.existing;
    _title = TextEditingController(text: listing?.title ?? '');
    _city = TextEditingController(text: listing?.city ?? '');
    _country = TextEditingController(text: listing?.country ?? '');
    _description = TextEditingController(text: listing?.description ?? '');
    _image = TextEditingController(
      text: widget.type == 'flight' ? '' : listing?.imageUrl ?? '',
    );
    _price =
        TextEditingController(text: listing == null ? '' : '${listing.price}');
    final attributes = {
      ..._starterAttributes(widget.type),
      ...?listing?.attributes,
    };
    if (widget.type == 'flight') {
      final aircraftId = '${attributes['aircraft_model'] ?? ''}';
      final seatLayout = '${attributes['seat_layout'] ?? ''}'.toLowerCase();
      _aircraftId = aircraftId == atr72.id ||
              (aircraftId.isEmpty && seatLayout.contains('2'))
          ? atr72.id
          : airbusA320.id;
    }
    _hotelLocationName = TextEditingController(
      text: '${attributes['location_name'] ?? listing?.locationName ?? ''}',
    );
    _googleRating = TextEditingController(
      text: listing != null && listing.googleRating > 0
          ? listing.googleRating.toStringAsFixed(1)
          : '',
    );
    _amenityInput = TextEditingController();
    _featureInput = TextEditingController();
    _amenityFocusNode = FocusNode();
    _featureFocusNode = FocusNode();
    final rawAmenities = attributes['amenities'];
    _hotelAmenities = rawAmenities is List
        ? rawAmenities.map((item) => item.toString()).toList()
        : <String>[];
    final rawFeatures = attributes['features'];
    _carFeatures = rawFeatures is List
        ? rawFeatures.map((item) => item.toString()).toList()
        : <String>[];
    final existingLatitude = attributes['latitude'];
    final existingLongitude = attributes['longitude'];
    final locationValue = attributes['google_maps_url'] ??
        attributes['location_input'] ??
        attributes['place_id'] ??
        attributes['google_place_id'] ??
        (existingLatitude != null && existingLongitude != null
            ? '$existingLatitude,$existingLongitude'
            : '');
    _hotelLocation = TextEditingController(text: '$locationValue');
    final galleryImages = attributes['gallery_images'];
    _hotelGalleryUrls = galleryImages is List
        ? galleryImages.map((image) => image.toString()).toList()
        : [];
    final originCity = '${attributes['origin_city'] ?? listing?.city ?? ''}';
    final destinationCity =
        '${attributes['destination_city'] ?? attributes['destination'] ?? _destinationFromTitle(listing?.title)}';
    _originCity = TextEditingController(text: originCity);
    _originCode = TextEditingController(
      text:
          '${attributes['origin_code'] ?? AirportOption.byCity(originCity)?.code ?? ''}',
    );
    _destinationCity = TextEditingController(text: destinationCity);
    _destinationCode = TextEditingController(
      text:
          '${attributes['destination_code'] ?? AirportOption.byCity(destinationCity)?.code ?? ''}',
    );
    _departureTime = TextEditingController(
        text: _dateTimeFieldValue(attributes['departure_time']));
    _arrivalTime = TextEditingController(
        text: _dateTimeFieldValue(attributes['arrival_time']));
    _transferPickupTime = TextEditingController(
        text: _dateTimeFieldValue(attributes['pickup_time']));
    _pickupLocation =
        TextEditingController(text: '${attributes['pickup_location'] ?? ''}');
    _dropoffLocation =
        TextEditingController(text: '${attributes['dropoff_location'] ?? ''}');
    _attributeFields = {
      for (final key in _editableAttributeKeys(widget.type))
        if (!_booleanAttributeKeys.contains(key) &&
            !(widget.type == 'hotel' && key == 'amenities') &&
            !(widget.type == 'car' && key == 'features'))
          key: TextEditingController(
            text: _attributeFieldValue(attributes[key]),
          ),
    };
    _booleanAttributes = {
      for (final key in _booleanAttributeKeys)
        if (_editableAttributeKeys(widget.type).contains(key))
          key: attributes[key] == true,
    };
  }

  @override
  void dispose() {
    _title.dispose();
    _city.dispose();
    _country.dispose();
    _description.dispose();
    _image.dispose();
    _price.dispose();
    _hotelLocation.dispose();
    _hotelLocationName.dispose();
    _googleRating.dispose();
    _amenityInput.dispose();
    _featureInput.dispose();
    _amenityFocusNode.dispose();
    _featureFocusNode.dispose();
    for (final controller in _attributeFields.values) {
      controller.dispose();
    }
    _originCity.dispose();
    _originCode.dispose();
    _destinationCity.dispose();
    _destinationCode.dispose();
    _departureTime.dispose();
    _arrivalTime.dispose();
    _transferPickupTime.dispose();
    _pickupLocation.dispose();
    _dropoffLocation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final price = double.tryParse(_price.text.trim());
    if (price == null || price < 0) {
      setState(() => _error = l10n.partnerInvalidPrice);
      return;
    }
    if (widget.type == 'hotel' &&
        (_country.text.trim().isEmpty || _country.text.trim().length > 255)) {
      setState(() => _error = l10n.partnerRequiredField);
      return;
    }
    final existingMainImage = widget.existing?.imageUrl.trim() ?? '';
    if (widget.type == 'hotel' &&
        _hotelMainImage == null &&
        existingMainImage.isEmpty) {
      setState(() => _error = l10n.partnerHotelPhotoRequired);
      return;
    }
    if (widget.type == 'flight') {
      final departure = _parseDateTimeField(_departureTime.text);
      final arrival = _parseDateTimeField(_arrivalTime.text);
      if (departure == null || arrival == null || !arrival.isAfter(departure)) {
        setState(() => _error = l10n.partnerInvalidFlightTimes);
        return;
      }
      if (_airportFromInput(_originCity.text, _originCode.text) == null ||
          _airportFromInput(_destinationCity.text, _destinationCode.text) ==
              null) {
        setState(() => _error = l10n.partnerRequiredField);
        return;
      }
    } else if (widget.type != 'transfer' && !_isRegisteredCity(_city.text)) {
      setState(() => _error = l10n.partnerRequiredField);
      return;
    }
    if (widget.type == 'transfer' &&
        (!_isRegisteredCity(_pickupLocation.text) ||
            !_isRegisteredCity(_dropoffLocation.text))) {
      setState(() => _error = l10n.partnerRequiredField);
      return;
    }
    try {
      setState(() {
        _saving = true;
        _error = null;
      });
      final decoded = <String, dynamic>{
        ...?widget.existing?.attributes,
        for (final entry in _attributeFields.entries)
          entry.key: _parseAttributeValue(entry.key, entry.value.text),
        ..._booleanAttributes,
      }..removeWhere((key, _) =>
          _generatedAttributeKeys.contains(key) ||
          _deferredFlightAttributeKeys.contains(key));
      if (widget.type == 'hotel') {
        final parsedLocation = parseHotelLocationInput(_hotelLocation.text);
        final previousLocation =
            widget.existing?.attributes['google_maps_url'] ??
                widget.existing?.attributes['location_input'] ??
                widget.existing?.attributes['place_id'] ??
                widget.existing?.attributes['google_place_id'] ??
                '';
        if (!parsedLocation.containsKey('latitude') &&
            _hotelLocation.text.trim() != '$previousLocation'.trim()) {
          decoded.remove('latitude');
          decoded.remove('longitude');
        }
        if (_hotelLocation.text.trim() != '$previousLocation'.trim() &&
            !parsedLocation.containsKey('google_place_id')) {
          decoded.remove('google_place_id');
        }
        decoded.addAll(parsedLocation);
        decoded['location_name'] = _hotelLocationName.text.trim();
        decoded['amenities'] = List<String>.unmodifiable(_hotelAmenities);
        decoded['google_maps_url'] = _hotelLocation.text.trim();
        if (parsedLocation['google_place_id'] != null) {
          decoded['place_id'] = parsedLocation['google_place_id'];
        } else if (_hotelLocation.text.trim() != '$previousLocation'.trim()) {
          decoded.remove('place_id');
        }
        if (widget.type == 'car') {
          decoded['features'] = List<String>.unmodifiable(_carFeatures);
        }
        decoded.remove('google_rating');
        decoded.remove('google_review_count');
        decoded.remove('rating');
        decoded.remove('review_count');
        decoded.remove('stars');
      }
      if (widget.type == 'flight') {
        final departure = _parseDateTimeField(_departureTime.text)!;
        final arrival = _parseDateTimeField(_arrivalTime.text)!;
        final origin = _airportFromInput(_originCity.text, _originCode.text)!;
        final destination =
            _airportFromInput(_destinationCity.text, _destinationCode.text)!;
        final aircraft = _selectedAircraft;
        final existingAircraft = widget.existing?.attributes['aircraft_model'];
        final existingLayout =
            '${widget.existing?.attributes['seat_layout'] ?? ''}'.toLowerCase();
        final previousAircraftId = existingAircraft == atr72.id ||
                (existingAircraft == null && existingLayout.contains('2'))
            ? atr72.id
            : airbusA320.id;
        final availableSeats = int.tryParse(
              '${widget.existing?.attributes['seats_available'] ?? aircraft.seatCapacity}',
            ) ??
            aircraft.seatCapacity;
        if (widget.existing != null &&
            previousAircraftId != aircraft.id &&
            availableSeats < _aircraftById(previousAircraftId).seatCapacity) {
          setState(() {
            _saving = false;
            _error = l10n.partnerAircraftChangeHasBookings;
          });
          return;
        }
        decoded.addAll({
          'origin_city': origin.city,
          'origin_code': origin.code,
          'origin_country': origin.country,
          'origin_region': origin.region,
          'destination_city': destination.city,
          'destination_code': destination.code,
          'destination_country': destination.country,
          'destination_region': destination.region,
          'departure_time': departure.toIso8601String(),
          'arrival_time': arrival.toIso8601String(),
          'aircraft_model': aircraft.id,
          'aircraft_name': aircraft.name,
          'seat_layout': aircraft.seatLayout,
          'seat_rows': aircraft.rowCount,
          'row_count': aircraft.rowCount,
          'seat_capacity': aircraft.seatCapacity,
          'seats_available':
              widget.existing == null || previousAircraftId != aircraft.id
                  ? aircraft.seatCapacity
                  : availableSeats,
        });
      } else if (widget.type == 'transfer') {
        final pickupTime = _parseDateTimeField(_transferPickupTime.text);
        if (pickupTime == null) {
          setState(() {
            _saving = false;
            _error = l10n.partnerRequiredField;
          });
          return;
        }
        decoded.addAll({
          'pickup_location': _pickupLocation.text.trim(),
          'dropoff_location': _dropoffLocation.text.trim(),
          'pickup_time': pickupTime.toIso8601String(),
        });
      }
      final listingCity = widget.type == 'flight'
          ? _originCity.text
          : widget.type == 'transfer'
              ? _pickupLocation.text
              : _city.text;
      final location = AirportOption.byCity(listingCity)!;
      decoded['location_code'] = location.code;
      decoded['location_region'] = location.region;
      var imageUrl = widget.type == 'flight' ? '' : _image.text.trim();
      if (widget.type == 'hotel') {
        final galleryUrls = [..._hotelGalleryUrls];
        if (_hotelMainImage != null) {
          final upload = await ApiService.instance.uploadPartnerHotelImage(
            bytes: _hotelMainImage!.bytes,
            filename: _hotelMainImage!.filename,
          );
          if (!mounted) return;
          if (upload.isFailure || upload.data == null) {
            setState(() {
              _saving = false;
              _error = upload.errorMessage ?? l10n.genericError;
            });
            return;
          }
          imageUrl = upload.data!;
          if (existingMainImage.isNotEmpty &&
              !galleryUrls.contains(existingMainImage)) {
            galleryUrls.insert(0, existingMainImage);
          }
        } else {
          imageUrl = existingMainImage;
        }
        for (final image in _newHotelGalleryImages) {
          final upload = await ApiService.instance.uploadPartnerHotelImage(
            bytes: image.bytes,
            filename: image.filename,
          );
          if (!mounted) return;
          if (upload.isFailure || upload.data == null) {
            setState(() {
              _saving = false;
              _error = upload.errorMessage ?? l10n.genericError;
            });
            return;
          }
          galleryUrls.add(upload.data!);
        }
        decoded['gallery_images'] = galleryUrls;
      }
      Navigator.pop(
        context,
        PartnerListing(
          id: widget.existing?.id,
          type: widget.type,
          title: _title.text.trim(),
          city: location.city,
          country:
              widget.type == 'hotel' ? _country.text.trim() : location.country,
          description: widget.type == 'flight' ? '' : _description.text.trim(),
          imageUrl: imageUrl,
          price: price,
          active: widget.existing?.active ?? true,
          attributes: decoded,
        ),
      );
    } on FormatException catch (error) {
      setState(() {
        _saving = false;
        _error = error.message.toString();
      });
    }
  }

  Widget _aircraftSelector(AppLocalizations l10n) {
    final aircraft = _selectedAircraft;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _aircraftId,
            decoration: InputDecoration(labelText: l10n.partnerAircraft),
            items: [
              for (final option in [airbusA320, atr72])
                DropdownMenuItem(
                  value: option.id,
                  child: Text(option.name),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) setState(() => _aircraftId = value);
                  },
          ),
          const SizedBox(height: 4),
          Text(
            l10n.partnerAircraftCapacity(
              aircraft.seatCapacity,
              aircraft.rowCount,
              aircraft.seatLayout,
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(520.0, screenSize.width - 32);
    final dialogHeight = math.min(720.0, screenSize.height * 0.78);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  widget.existing == null
                      ? l10n.partnerCreateListing
                      : l10n.partnerEditListing,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field(
                        _title,
                        widget.type == 'hotel'
                            ? l10n.partnerHotelName
                            : l10n.partnerListingTitle,
                        required: true,
                      ),
                      if (widget.type == 'flight') ...[
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(l10n.partnerFlightRoute,
                                style: Theme.of(context).textTheme.titleSmall),
                          ),
                        ),
                        _airportField(
                          controller: _originCity,
                          codeController: _originCode,
                          label: l10n.partnerOriginCity,
                        ),
                        _airportField(
                          controller: _destinationCity,
                          codeController: _destinationCode,
                          label: l10n.partnerDestinationCity,
                        ),
                        _dateTimeField(
                            _departureTime, l10n.partnerDepartureTime),
                        _dateTimeField(_arrivalTime, l10n.partnerArrivalTime),
                        _aircraftSelector(l10n),
                      ] else if (widget.type != 'transfer')
                        _cityField(_city, l10n.partnerCity),
                      if (widget.type == 'hotel')
                        _field(
                          _hotelLocationName,
                          l10n.partnerHotelLocationName,
                          required: true,
                        ),
                      if (widget.type == 'hotel')
                        _field(
                          _hotelLocation,
                          l10n.partnerHotelGoogleMapsUrl,
                          required: true,
                          helperText: l10n.partnerHotelLocationHint,
                          validator: (value) {
                            try {
                              parseHotelLocationInput(value ?? '');
                              return null;
                            } on FormatException {
                              return l10n.partnerHotelLocationInvalid;
                            }
                          },
                        ),
                      if (widget.type == 'hotel') ...[
                        _field(
                          _googleRating,
                          l10n.partnerHotelGoogleRating,
                          readOnly: true,
                          helperText: _googleRating.text.isEmpty
                              ? l10n.partnerHotelGoogleRatingPending
                              : l10n.partnerHotelGoogleRatingReadOnly,
                        ),
                        _hotelAmenitiesSection(l10n),
                      ],
                      if (widget.type == 'car') _carFeaturesSection(l10n),
                      if (widget.type == 'transfer') ...[
                        _cityField(_pickupLocation, l10n.transferPickupLabel),
                        _cityField(_dropoffLocation, l10n.transferDropoffLabel),
                        _dateTimeField(_transferPickupTime, l10n.transferDate),
                      ],
                      _field(
                        _country,
                        l10n.partnerCountry,
                        required: widget.type == 'hotel',
                        readOnly: widget.type != 'hotel',
                      ),
                      if (widget.type != 'flight')
                        _field(_description, l10n.partnerDescription,
                            maxLines: 3),
                      if (widget.type == 'hotel')
                        _hotelImagesSection(l10n)
                      else if (widget.type != 'flight')
                        _field(_image, l10n.partnerImageUrl,
                            keyboardType: TextInputType.url),
                      _field(
                        _price,
                        widget.type == 'flight'
                            ? l10n.partnerTicketPrice
                            : widget.type == 'hotel'
                                ? l10n.hotelNightPrice
                                : l10n.partnerPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                      ..._buildServiceFields(l10n),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(l10n.partnerCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.partnerSave),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hotelImagesSection(AppLocalizations l10n) {
    final existingMainImage = widget.existing?.imageUrl.trim() ?? '';
    final hasMainImage =
        _hotelMainImage != null || existingMainImage.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.partnerHotelMainPhoto,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 150,
              child: _hotelMainImage != null
                  ? Image.memory(
                      _hotelMainImage!.bytes,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      cacheWidth: 800,
                    )
                  : AppNetworkImage(
                      url: existingMainImage.isEmpty ? null : existingMainImage,
                      width: double.infinity,
                      height: 150,
                      fallbackIcon: Icons.hotel_rounded,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickHotelMainImage,
            icon: const Icon(Icons.image_outlined),
            label: Text(l10n.partnerChooseMainPhoto),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.partnerHotelGallery,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          if (_hotelGalleryUrls.isNotEmpty ||
              _newHotelGalleryImages.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < _hotelGalleryUrls.length; index++)
                  _hotelGalleryTile(
                    image: AppNetworkImage(
                      url: _hotelGalleryUrls[index],
                      width: 86,
                      height: 86,
                    ),
                    onRemove: _saving
                        ? null
                        : () =>
                            setState(() => _hotelGalleryUrls.removeAt(index)),
                  ),
                for (var index = 0;
                    index < _newHotelGalleryImages.length;
                    index++)
                  _hotelGalleryTile(
                    image: Image.memory(
                      _newHotelGalleryImages[index].bytes,
                      width: 86,
                      height: 86,
                      fit: BoxFit.cover,
                      cacheWidth: 172,
                    ),
                    onRemove: _saving
                        ? null
                        : () => setState(
                            () => _newHotelGalleryImages.removeAt(index)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickHotelGalleryImages,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(l10n.partnerAddHotelPhotos),
          ),
          if (!hasMainImage)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.partnerHotelPhotoRequired,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _hotelGalleryTile({
    required Widget image,
    required VoidCallback? onRemove,
  }) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 86,
          height: 86,
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              PositionedDirectional(
                top: 2,
                end: 2,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onRemove,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _pickHotelMainImage() async {
    final selectedImage = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (selectedImage != null && mounted) {
      final image = _SelectedHotelImage(
        filename: selectedImage.name,
        bytes: await selectedImage.readAsBytes(),
      );
      if (mounted) setState(() => _hotelMainImage = image);
    }
  }

  Future<void> _pickHotelGalleryImages() async {
    final selectedImages = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (selectedImages.isNotEmpty && mounted) {
      final images = await Future.wait(
        selectedImages.map(
          (image) async => _SelectedHotelImage(
            filename: image.name,
            bytes: await image.readAsBytes(),
          ),
        ),
      );
      if (mounted) setState(() => _newHotelGalleryImages.addAll(images));
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool readOnly = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? helperText,
    FormFieldValidator<String>? validator,
  }) {
    final input = TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      readOnly: readOnly,
      decoration: _listingInputDecoration(
        labelText: widget.type == 'flight' ? null : label,
        helperText: helperText,
      ),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return AppLocalizations.of(context).partnerRequiredField;
        }
        return validator?.call(value);
      },
    );
    return widget.type == 'flight'
        ? _flightLabeledField(label, input)
        : Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: input,
          );
  }

  List<Widget> _buildServiceFields(AppLocalizations l10n) {
    final keys = _editableAttributeKeys(widget.type)
        .where((key) =>
            !_hiddenAttributeKeys(widget.type).contains(key) &&
            !(widget.type == 'hotel' && key == 'amenities') &&
            !(widget.type == 'car' && key == 'features'))
        .toList();
    return [
      for (final key in keys)
        if (_booleanAttributeKeys.contains(key))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_attributeLabel(key, l10n)),
            value: _booleanAttributes[key] ?? false,
            onChanged: (value) =>
                setState(() => _booleanAttributes[key] = value),
          )
        else
          _field(
            _attributeFields[key]!,
            _attributeLabel(key, l10n),
            keyboardType: _numericAttributeKeys.contains(key)
                ? const TextInputType.numberWithOptions(decimal: true)
                : null,
            maxLines: _listAttributeKeys.contains(key) ? 2 : 1,
            required: _requiredAttributeKeys.contains(key),
            helperText: _listAttributeKeys.contains(key)
                ? l10n.partnerCommaSeparatedHint
                : null,
            validator: _numericAttributeKeys.contains(key)
                ? (value) => _validateNumericAttribute(key, value, l10n)
                : null,
          ),
    ];
  }

  Widget _carFeaturesSection(AppLocalizations l10n) {
    void addFeatures(Iterable<String> values) {
      final additions = values
          .map((value) => value.trim())
          .where((value) =>
              value.isNotEmpty &&
              !_carFeatures.any(
                  (existing) => existing.toLowerCase() == value.toLowerCase()))
          .toList();
      if (additions.isNotEmpty) {
        setState(() => _carFeatures.addAll(additions));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.carFeatures, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          TextFormField(
            controller: _featureInput,
            focusNode: _featureFocusNode,
            textInputAction: TextInputAction.done,
            decoration: _listingInputDecoration(
              hintText: l10n.partnerAmenityInputHint,
              suffixIcon: IconButton(
                tooltip: l10n.partnerAmenityAdd,
                onPressed: () {
                  addFeatures(_featureInput.text.split(','));
                  _featureInput.clear();
                  _featureFocusNode.requestFocus();
                },
                icon: const Icon(Icons.add),
              ),
            ),
            onChanged: (value) {
              if (!value.contains(',')) return;
              final parts = value.split(',');
              final pending = parts.removeLast();
              addFeatures(parts);
              _featureInput.value = TextEditingValue(
                text: pending,
                selection: TextSelection.collapsed(offset: pending.length),
              );
            },
            onFieldSubmitted: (value) {
              addFeatures(value.split(','));
              _featureInput.clear();
            },
          ),
          if (_carFeatures.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final feature in _carFeatures)
                  InputChip(
                    label: Text(feature),
                    onDeleted: _saving
                        ? null
                        : () => setState(
                              () => _carFeatures.remove(feature),
                            ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _hotelAmenitiesSection(AppLocalizations l10n) {
    void addAmenities(Iterable<String> values) {
      final additions = values
          .map((value) => value.trim())
          .where((value) =>
              value.isNotEmpty &&
              !_hotelAmenities.any(
                  (existing) => existing.toLowerCase() == value.toLowerCase()))
          .toList();
      if (additions.isNotEmpty) {
        setState(() => _hotelAmenities.addAll(additions));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.partnerAmenities,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _amenityInput,
            focusNode: _amenityFocusNode,
            textInputAction: TextInputAction.done,
            decoration: _listingInputDecoration(
              hintText: l10n.partnerAmenityInputHint,
              suffixIcon: IconButton(
                tooltip: l10n.partnerAmenityAdd,
                onPressed: () {
                  addAmenities(_amenityInput.text.split(','));
                  _amenityInput.clear();
                  _amenityFocusNode.requestFocus();
                },
                icon: const Icon(Icons.add),
              ),
            ),
            onChanged: (value) {
              if (!value.contains(',')) return;
              final parts = value.split(',');
              final pending = parts.removeLast();
              addAmenities(parts);
              _amenityInput.value = TextEditingValue(
                text: pending,
                selection: TextSelection.collapsed(offset: pending.length),
              );
            },
            onFieldSubmitted: (value) {
              addAmenities(value.split(','));
              _amenityInput.clear();
            },
          ),
          if (_hotelAmenities.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final amenity in _hotelAmenities)
                  InputChip(
                    label: Text(amenity),
                    onDeleted: _saving
                        ? null
                        : () => setState(
                              () => _hotelAmenities.remove(amenity),
                            ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _listingInputDecoration({
    String? labelText,
    String? helperText,
    String? hintText,
    Widget? suffixIcon,
  }) {
    if (widget.type != 'flight' &&
        widget.type != 'hotel' &&
        widget.type != 'car') {
      return InputDecoration(
        filled: false,
        labelText: labelText,
        helperText: helperText,
        hintText: hintText,
        helperMaxLines: 2,
        errorMaxLines: 2,
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
        border: const OutlineInputBorder(),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.border;
    return InputDecoration(
      filled: true,
      fillColor:
          isDark ? AppColors.darkSurfaceSecondary : AppColors.surfaceSecondary,
      labelText: labelText,
      helperText: helperText,
      hintText: hintText,
      helperMaxLines: 2,
      errorMaxLines: 2,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _flightLabeledField(String label, Widget field) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 14, bottom: 4),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            field,
          ],
        ),
      );

  String _attributeLabel(String key, AppLocalizations l10n) => switch (key) {
        'seats_available' => l10n.partnerSeatsAvailable,
        'seat_class' => l10n.partnerSeatClass,
        'business_price' => l10n.partnerBusinessPrice,
        'address' => l10n.partnerAddress,
        'location_name' => l10n.partnerHotelLocationName,
        'tax_and_fees_percentage' => l10n.partnerHotelTaxAndFeesPercentage,
        'district' => l10n.partnerDistrict,
        'neighborhood' => l10n.partnerNeighborhood,
        'landmark' => l10n.partnerLandmark,
        'rating' => l10n.partnerRating,
        'amenities' => l10n.partnerAmenities,
        'available_rooms' => l10n.partnerHotelAvailableRooms,
        'brand' => l10n.partnerBrand,
        'model' => l10n.partnerModel,
        'category' => l10n.partnerCategory,
        'year' => l10n.partnerYear,
        'seats' => l10n.partnerSeats,
        'transmission' => l10n.partnerTransmission,
        'fuel_type' => l10n.partnerFuelType,
        'pickup_location' => l10n.partnerAddress,
        'luggage_capacity' => l10n.partnerMaxLuggage,
        'available_vehicles' => l10n.partnerAvailableVehicles,
        'insurance_fee' => l10n.carInsurance,
        'service_fee' => l10n.carServiceFee,
        'features' => l10n.partnerFeatures,
        'has_ac' => l10n.partnerAirConditioning,
        'has_gps' => l10n.partnerGps,
        'opening_hours' => l10n.partnerOpeningHours,
        'latitude' => l10n.partnerLatitude,
        'longitude' => l10n.partnerLongitude,
        'tags' => l10n.partnerTags,
        'vehicle_type' => l10n.partnerVehicleType,
        'max_passengers' => l10n.partnerMaxPassengers,
        'max_luggage' => l10n.partnerMaxLuggage,
        'duration_minutes' => l10n.partnerDurationMinutes,
        'included_services' => l10n.partnerIncludedServices,
        'duration_nights' => l10n.partnerDurationNights,
        'highlights' => l10n.partnerHighlights,
        _ => key.replaceAll('_', ' '),
      };

  String? _validateNumericAttribute(
    String key,
    String? value,
    AppLocalizations l10n,
  ) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty && _optionalAttributeKeys.contains(key)) return null;
    final number = num.tryParse(trimmed);
    if (number == null) return l10n.partnerInvalidServiceField;
    if (key == 'rating' && (number < 0 || number > 5)) {
      return l10n.partnerInvalidServiceField;
    }
    if (key == 'latitude' && (number < -90 || number > 90)) {
      return l10n.partnerInvalidServiceField;
    }
    if (key == 'longitude' && (number < -180 || number > 180)) {
      return l10n.partnerInvalidServiceField;
    }
    if (key == 'tax_and_fees_percentage' && number > 100) {
      return l10n.partnerInvalidServiceField;
    }
    if (number < 0 ||
        (_integerAttributeKeys.contains(key) && number != number.round())) {
      return l10n.partnerInvalidServiceField;
    }
    if (const {'seats_available', 'seats', 'max_passengers'}.contains(key) &&
        number < 1) {
      return l10n.partnerInvalidServiceField;
    }
    if (const {'year', 'duration_nights', 'duration_minutes'}.contains(key) &&
        number < 1) {
      return l10n.partnerInvalidServiceField;
    }
    return null;
  }

  static String _attributeFieldValue(Object? value) {
    if (value == null) return '';
    if (value is List) return value.join(', ');
    return value.toString();
  }

  static Object? _parseAttributeValue(String key, String value) {
    final trimmed = value.trim();
    if (_listAttributeKeys.contains(key)) {
      return trimmed.isEmpty
          ? <String>[]
          : trimmed
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList();
    }
    if (_numericAttributeKeys.contains(key)) {
      if (trimmed.isEmpty && _optionalAttributeKeys.contains(key)) return null;
      final parsed = num.parse(trimmed);
      return _integerAttributeKeys.contains(key) ? parsed.toInt() : parsed;
    }
    return trimmed;
  }

  Widget _dateTimeField(
    TextEditingController controller,
    String label,
  ) {
    final field = TextFormField(
      controller: controller,
      readOnly: true,
      onTap: () => _pickDateTime(controller),
      decoration: _listingInputDecoration(
        labelText: widget.type == 'flight' ? null : label,
        suffixIcon: const Icon(Icons.calendar_month_outlined),
      ),
      validator: (value) => value == null || value.trim().isEmpty
          ? AppLocalizations.of(context).partnerRequiredField
          : null,
    );
    return widget.type == 'flight'
        ? _flightLabeledField(label, field)
        : Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: field,
          );
  }

  Widget _airportField({
    required TextEditingController controller,
    required TextEditingController codeController,
    required String label,
  }) {
    var query = '';
    final field = Autocomplete<AirportOption>(
      displayStringForOption: (airport) => airport.label,
      initialValue: TextEditingValue(
        text: controller.text.isEmpty
            ? ''
            : '${controller.text} [${codeController.text}]',
      ),
      optionsBuilder: (value) => AirportOption.supported
          .where((airport) => airport.matches(value.text)),
      onSelected: (airport) {
        controller.text = airport.city;
        codeController.text = airport.code;
        if (identical(controller, _originCity)) {
          _country.text = airport.country;
        }
        setState(() => _error = null);
      },
      fieldViewBuilder: (context, fieldController, focusNode, onSubmitted) {
        return TextFormField(
          controller: fieldController,
          focusNode: focusNode,
          onChanged: (value) {
            query = value;
            final airport = _airportFromInput(value, codeController.text);
            controller.text = airport?.city ?? value;
            if (airport == null) {
              codeController.clear();
            } else {
              codeController.text = airport.code;
            }
          },
          decoration: _listingInputDecoration(
            labelText: widget.type == 'flight' ? null : label,
          ),
          validator: (value) => _airportFromInput(
                        value ?? '',
                        codeController.text,
                      ) ==
                      null &&
                  _airportFromInput(
                        controller.text,
                        codeController.text,
                      ) ==
                      null
              ? AppLocalizations.of(context).partnerRequiredField
              : null,
        );
      },
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: options
                  .map((airport) => ListTile(
                        title: Text.rich(_highlightMatch(airport.label, query)),
                        subtitle: Text.rich(
                            _highlightMatch(airport.airportName, query)),
                        onTap: () => onSelected(airport),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
    );
    return _flightLabeledField(label, field);
  }

  Widget _cityField(TextEditingController controller, String label) {
    var query = '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Autocomplete<AirportOption>(
        displayStringForOption: (airport) => airport.city,
        initialValue: TextEditingValue(text: controller.text),
        optionsBuilder: (value) => AirportOption.supported
            .where((airport) => airport.matches(value.text)),
        onSelected: (airport) {
          controller.text = airport.city;
          if (identical(controller, _city) ||
              identical(controller, _pickupLocation)) {
            _country.text = airport.country;
          }
          setState(() => _error = null);
        },
        fieldViewBuilder: (context, fieldController, focusNode, onSubmitted) {
          return TextFormField(
            controller: fieldController,
            focusNode: focusNode,
            onChanged: (value) {
              query = value;
              controller.text = value;
              if (identical(controller, _city) ||
                  identical(controller, _pickupLocation)) {
                final location = AirportOption.byCity(value);
                if (location != null) _country.text = location.country;
              }
            },
            decoration: _listingInputDecoration(labelText: label),
            validator: (value) => value == null || !_isRegisteredCity(value)
                ? AppLocalizations.of(context).partnerRequiredField
                : null,
          );
        },
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: options
                    .map((airport) => ListTile(
                          title:
                              Text.rich(_highlightMatch(airport.label, query)),
                          subtitle: Text.rich(
                              _highlightMatch(airport.airportName, query)),
                          onTap: () => onSelected(airport),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextSpan _highlightMatch(String value, String query) {
    final normalizedQuery = query.trim();
    final start = value.toLowerCase().indexOf(normalizedQuery.toLowerCase());
    if (normalizedQuery.isEmpty || start < 0) return TextSpan(text: value);
    final end = start + normalizedQuery.length;
    return TextSpan(children: [
      TextSpan(text: value.substring(0, start)),
      TextSpan(
        text: value.substring(start, end),
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
      TextSpan(text: value.substring(end)),
    ]);
  }

  Future<void> _pickDateTime(TextEditingController controller) async {
    final current = _parseDateTimeField(controller.text) ??
        DateTime.now().add(const Duration(days: 14));
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final value =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    controller.text = DateFormat('yyyy-MM-dd HH:mm').format(value);
    setState(() => _error = null);
  }

  static String _dateTimeFieldValue(Object? value) {
    final dateTime = _parseDateTimeField('$value');
    return dateTime == null
        ? ''
        : DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
  }

  static DateTime? _parseDateTimeField(String value) =>
      DateTime.tryParse(value.trim().replaceFirst(' ', 'T'));

  static bool _isRegisteredCity(String city) =>
      AirportOption.byCity(city) != null;

  static AirportOption? _airportFromInput(String input, String code) {
    final value = input.trim();
    final match = RegExp(r'^(.*?)\s*\[([A-Za-z]{3})\]$').firstMatch(value);
    final city = match?.group(1)?.trim() ?? value;
    final displayedCode = match?.group(2)?.toUpperCase();
    final airport = displayedCode == null
        ? AirportOption.byCity(city)
        : AirportOption.byCode(displayedCode);
    if (airport == null || airport.city.toLowerCase() != city.toLowerCase()) {
      return null;
    }
    final normalizedCode = code.trim().toUpperCase();
    return normalizedCode.isEmpty || normalizedCode == airport.code
        ? airport
        : null;
  }

  static String _destinationFromTitle(String? title) {
    if (title == null) return '';
    final separator = title.toLowerCase().indexOf(' to ');
    return separator < 0 ? '' : title.substring(separator + 4).trim();
  }

  static const _generatedAttributeKeys = {
    'listing_code',
    'flight_number',
    'airline_code',
    'status',
    'is_active',
    'aircraft_model',
    'aircraft_name',
    'seat_layout',
    'seat_rows',
    'row_count',
    'seat_capacity',
    'seats_available',
  };

  static const _numericAttributeKeys = {
    'seats_available',
    'available_rooms',
    'business_price',
    'rating',
    'latitude',
    'longitude',
    'year',
    'seats',
    'max_passengers',
    'max_luggage',
    'duration_nights',
    'tax_and_fees_percentage',
    'duration_minutes',
    'luggage_capacity',
    'available_vehicles',
    'insurance_fee',
    'service_fee',
  };

  static const _integerAttributeKeys = {
    'seats_available',
    'seat_rows',
    'row_count',
    'seat_capacity',
    'available_rooms',
    'year',
    'seats',
    'max_passengers',
    'max_luggage',
    'luggage_capacity',
    'available_vehicles',
    'duration_nights',
  };

  static const _optionalAttributeKeys = {
    'business_price',
    'latitude',
    'longitude',
  };

  static const _listAttributeKeys = {
    'amenities',
    'features',
    'tags',
    'included_services',
    'highlights',
  };
  static const _booleanAttributeKeys = {'has_ac', 'has_gps'};
  static const _deferredFlightAttributeKeys = {'is_direct', 'stops'};

  static const _requiredAttributeKeys = {
    'available_rooms',
    'seats_available',
    'seat_class',
    'duration_minutes',
    'brand',
    'model',
    'category',
    'year',
    'seats',
    'transmission',
    'fuel_type',
    'vehicle_type',
    'duration_nights',
  };

  static Set<String> _editableAttributeKeys(String type) =>
      _starterAttributes(type).keys.toSet();

  static Aircraft _aircraftById(String id) =>
      id == atr72.id ? atr72 : airbusA320;

  static Set<String> _hiddenAttributeKeys(String type) => switch (type) {
        'flight' => {
            'origin_city',
            'origin_code',
            'destination_city',
            'destination_code',
            'departure_time',
            'arrival_time',
            'aircraft_model',
            'aircraft_name',
            'seat_layout',
            'seat_rows',
            'row_count',
            'seat_capacity',
            'seats_available',
          },
        'transfer' => {
            'pickup_location',
            'dropoff_location',
            'pickup_time',
          },
        _ => <String>{},
      };

  static Map<String, dynamic> _starterAttributes(String type) => switch (type) {
        'flight' => {
            'origin_city': '',
            'origin_code': '',
            'destination_city': '',
            'destination_code': '',
            'departure_time': '',
            'arrival_time': '',
            'duration_minutes': 120,
            'seat_class': 'Economy',
            'aircraft_model': airbusA320.id,
            'aircraft_name': airbusA320.name,
            'seat_layout': airbusA320.seatLayout,
            'seat_rows': airbusA320.rowCount,
            'row_count': airbusA320.rowCount,
            'seat_capacity': airbusA320.seatCapacity,
            'seats_available': airbusA320.seatCapacity,
            'business_price': null,
          },
        'hotel' => {
            'tax_and_fees_percentage': 12,
            'available_rooms': 15,
            'amenities': <String>[],
          },
        'car' => {
            'brand': '',
            'model': '',
            'category': 'economy',
            'year': DateTime.now().year,
            'pickup_location': '',
            'seats': 4,
            'luggage_capacity': 2,
            'transmission': 'automatic',
            'fuel_type': 'gasoline',
            'features': <String>[],
            'rating': 0,
            'insurance_fee': 4,
            'service_fee': 10,
            'available_vehicles': 1,
            'has_ac': true,
            'has_gps': false,
          },
        'attraction' => {
            'category': 'landmark',
            'rating': 0,
            'tags': <String>[],
            'opening_hours': '',
            'latitude': 0,
            'longitude': 0,
          },
        'transfer' => {
            'vehicle_type': 'sedan',
            'max_passengers': 4,
            'max_luggage': 2,
            'pickup_location': '',
            'dropoff_location': '',
            'pickup_time': '',
            'duration_minutes': 60,
            'included_services': <String>[],
          },
        'package' => {
            'duration_nights': 3,
            'category': 'city',
            'highlights': <String>[],
          },
        _ => <String, dynamic>{},
      };
}

class _MetricCard extends StatelessWidget {
  final double width;
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.width,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 14),
              Text(value,
                  style: const TextStyle(
                      fontSize: 25, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(title,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: child,
    );
  }
}

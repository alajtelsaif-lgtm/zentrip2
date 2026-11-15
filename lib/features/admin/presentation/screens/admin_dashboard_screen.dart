import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../global_widgets/app_logo.dart';
import '../../../../global_widgets/confirm_dialog.dart';
import '../../../../global_widgets/currency_amount_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/admin_dashboard_model.dart';
import '../../../../routes/app_routes.dart';
import 'admin_catalog_management.dart';
import 'admin_partners_management.dart';

enum _AdminSection {
  overview,
  popularity,
  partners,
  offers,
  reservations,
  customers,
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  _AdminSection _section = _AdminSection.overview;
  AdminDashboardData? _dashboard;
  AdminAttractionPopularity? _popularity;
  List<AdminReservation> _reservations = [];
  List<AdminCustomer> _customers = [];
  bool _loading = true;
  bool _loadingSection = false;
  String? _error;
  String _customerQuery = '';
  final _partnersKey = GlobalKey<AdminPartnersManagementState>();
  final _catalogKey = GlobalKey<AdminCatalogManagementState>();
  AdminCatalogKind _catalogKind = AdminCatalogKind.offers;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ApiService.instance.getAdminDashboard();
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

  Future<void> _selectSection(_AdminSection section) async {
    setState(() {
      _section = section;
      _error = null;
    });
    if (section == _AdminSection.overview ||
        section == _AdminSection.partners ||
        section == _AdminSection.offers) {
      return;
    }
    if (section == _AdminSection.popularity && _popularity != null) return;
    if (section == _AdminSection.reservations && _reservations.isNotEmpty) {
      return;
    }
    if (section == _AdminSection.customers && _customers.isNotEmpty) return;

    setState(() => _loadingSection = true);
    if (section == _AdminSection.popularity) {
      final result = await ApiService.instance.getAdminAttractionPopularity();
      if (!mounted) return;
      setState(() {
        _loadingSection = false;
        if (result.isSuccess && result.data != null) {
          _popularity = result.data;
        } else {
          _error = result.errorMessage;
        }
      });
    } else if (section == _AdminSection.reservations) {
      final result = await ApiService.instance.getAdminReservations();
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
      final result = await ApiService.instance.getAdminCustomers();
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
    await _loadDashboard();
    if (!mounted) return;
    if (_section == _AdminSection.reservations) {
      final result = await ApiService.instance.getAdminReservations();
      if (!mounted) return;
      if (result.isSuccess && result.data != null) {
        setState(() => _reservations = result.data!);
      } else {
        setState(() => _error = result.errorMessage);
      }
    } else if (_section == _AdminSection.customers) {
      final result = await ApiService.instance.getAdminCustomers();
      if (!mounted) return;
      if (result.isSuccess && result.data != null) {
        setState(() => _customers = result.data!);
      } else {
        setState(() => _error = result.errorMessage);
      }
    } else if (_section == _AdminSection.popularity) {
      final result = await ApiService.instance.getAdminAttractionPopularity();
      if (!mounted) return;
      if (result.isSuccess && result.data != null) {
        setState(() => _popularity = result.data);
      } else {
        setState(() => _error = result.errorMessage);
      }
    } else if (_section == _AdminSection.partners) {
      final state = _partnersKey.currentState;
      if (state != null) await state.reload();
    } else if (_section == _AdminSection.offers) {
      final state = _catalogKey.currentState;
      if (state != null) await state.reload();
    }
  }

  Future<void> _logout() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.logoutConfirmTitle,
      message: l10n.logoutConfirmMessage,
      confirmLabel: l10n.logout,
      isDanger: true,
    );
    if (!confirmed || !mounted) return;
    await ApiService.instance.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.auth, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = ApiService.instance.currentUser;
    if (user?.isAdmin != true) {
      return _AccessDenied(message: l10n.adminNoAccess);
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
                      child: _section == _AdminSection.partners ||
                              _section == _AdminSection.offers
                          ? _managementContent()
                          : RefreshIndicator(
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
                    const Text(
                      'Zentrip',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      l10n.adminWorkspaceLabel,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
          _navItem(
            l10n.adminOverview,
            Icons.space_dashboard_outlined,
            _AdminSection.overview,
          ),
          const SizedBox(height: 8),
          _navItem(
            l10n.adminPopularity,
            Icons.insights_outlined,
            _AdminSection.popularity,
          ),
          const SizedBox(height: 8),
          _navItem(
            l10n.adminPartners,
            Icons.business_outlined,
            _AdminSection.partners,
          ),
          const SizedBox(height: 8),
          _navItem(
            l10n.adminCatalog,
            Icons.local_offer_outlined,
            _AdminSection.offers,
          ),
          const SizedBox(height: 8),
          _navItem(
            l10n.adminReservations,
            Icons.book_online_outlined,
            _AdminSection.reservations,
          ),
          const SizedBox(height: 8),
          _navItem(
            l10n.adminCustomers,
            Icons.people_outline_rounded,
            _AdminSection.customers,
          ),
          const Spacer(),
          Divider(color: isDark ? AppColors.darkBorder : AppColors.divider),
          _AdminIdentity(name: name),
        ],
      ),
    );
  }

  Widget _navItem(String label, IconData icon, _AdminSection section) {
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
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.primary : null,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileNavigation(AppLocalizations l10n) {
    final index = _section.index;
    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (value) =>
          _selectSection(_AdminSection.values[value]),
      destinations: [
        NavigationDestination(
            icon: const Icon(Icons.space_dashboard_outlined),
            label: l10n.adminOverview),
        NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            label: l10n.adminPopularity),
        NavigationDestination(
            icon: const Icon(Icons.business_outlined),
            label: l10n.adminPartners),
        NavigationDestination(
            icon: const Icon(Icons.local_offer_outlined),
            label: l10n.adminCatalog),
        NavigationDestination(
            icon: const Icon(Icons.book_online_outlined),
            label: l10n.adminReservations),
        NavigationDestination(
            icon: const Icon(Icons.people_outline_rounded),
            label: l10n.adminCustomers),
      ],
    );
  }

  Widget _topBar(AppLocalizations l10n, String name, bool isWide) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 32 : 18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
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
                Text(
                  _sectionTitle(l10n),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
                if (isWide)
                  Text(
                    '${l10n.adminWelcome}, $name',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: l10n.adminRefresh,
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: l10n.logout,
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 4),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primarySurface,
            child: Text(
              name.isEmpty ? 'Z' : name[0].toUpperCase(),
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  String _sectionTitle(AppLocalizations l10n) => switch (_section) {
        _AdminSection.overview => l10n.adminOverview,
        _AdminSection.popularity => l10n.adminPopularity,
        _AdminSection.partners => l10n.adminPartners,
        _AdminSection.offers => l10n.adminCatalog,
        _AdminSection.reservations => l10n.adminReservations,
        _AdminSection.customers => l10n.adminCustomers,
      };

  Widget _managementContent() => LayoutBuilder(
        builder: (context, constraints) => Center(
          child: SizedBox(
            width: constraints.maxWidth > 1320 ? 1320 : constraints.maxWidth,
            height: constraints.maxHeight,
            child: _section == _AdminSection.partners
                ? AdminPartnersManagement(key: _partnersKey)
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: SegmentedButton<AdminCatalogKind>(
                            segments: [
                              ButtonSegment(
                                value: AdminCatalogKind.monuments,
                                icon: const Icon(Icons.place_outlined),
                                label: Text(
                                    AppLocalizations.of(context).adminPlaces),
                              ),
                              ButtonSegment(
                                value: AdminCatalogKind.offers,
                                icon: const Icon(Icons.local_offer_outlined),
                                label: Text(
                                    AppLocalizations.of(context).adminOffers),
                              ),
                            ],
                            selected: {_catalogKind},
                            onSelectionChanged: (selection) {
                              setState(() => _catalogKind = selection.first);
                            },
                          ),
                        ),
                      ),
                      Expanded(
                        child: AdminCatalogManagement(
                          key: _catalogKey,
                          kind: _catalogKind,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );

  Widget _content(AppLocalizations l10n, bool isWide) {
    if (_loading && _dashboard == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null && _dashboard == null) {
      return _ErrorState(
        message: _error!.contains('403') ||
                _error!.toLowerCase().contains('administrator')
            ? l10n.adminNoAccess
            : l10n.adminLoadFailed,
        onRetry: _refresh,
      );
    }
    if (_loadingSection) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null) {
      return _ErrorState(message: l10n.adminLoadFailed, onRetry: _refresh);
    }

    final horizontalPadding = isWide ? 32.0 : 18.0;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding:
          EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: switch (_section) {
            _AdminSection.overview => _overview(l10n, isWide),
            _AdminSection.popularity => _popularityView(l10n),
            _AdminSection.partners =>
              AdminPartnersManagement(key: _partnersKey),
            _AdminSection.offers => AdminCatalogManagement(
                key: _catalogKey,
                kind: _catalogKind,
              ),
            _AdminSection.reservations => _reservationsView(l10n),
            _AdminSection.customers => _customersView(l10n, isWide),
          },
        ),
      ),
    );
  }

  Widget _overview(AppLocalizations l10n, bool isWide) {
    final data = _dashboard;
    if (data == null) return const SizedBox.shrink();
    final cardColumns = isWide ? 3 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.adminSubtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, constraints) {
          final cardWidth =
              (constraints.maxWidth - (cardColumns - 1) * 14) / cardColumns;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _MetricCard(
                width: cardWidth,
                title: l10n.adminUserCount,
                value: '${data.totalUserCount}',
                icon: Icons.groups_rounded,
                color: AppColors.primary,
                footnote: l10n.adminCustomerCount,
                footnoteValue: '${data.customerCount}',
              ),
              _MetricCard(
                width: cardWidth,
                title: l10n.adminCustomerCount,
                value: '${data.customerCount}',
                icon: Icons.people_alt_outlined,
                color: AppColors.primary,
                footnote: l10n.adminNewCustomers,
                footnoteValue: '+${data.newCustomers}',
              ),
              _MetricCard(
                width: cardWidth,
                title: l10n.adminPartnerCount,
                value: '${data.partnerCount}',
                icon: Icons.business_outlined,
                color: AppColors.accentPurple,
                footnote: l10n.adminActivePartnerListings,
                footnoteValue: '${data.activePartnerListingCount}',
              ),
              _MetricCard(
                width: cardWidth,
                title: l10n.adminReservationCount,
                value: '${data.reservationCount}',
                icon: Icons.book_online_outlined,
                color: AppColors.accentTeal,
                footnote: l10n.adminFlights,
                footnoteValue: '${data.flightCount}',
              ),
              _MetricCard(
                width: cardWidth,
                title: l10n.adminServices,
                value: '${data.serviceBookingCount}',
                icon: Icons.hotel_outlined,
                color: AppColors.accentOrange,
                footnote: l10n.adminTransfers,
                footnoteValue: '${data.transferCount}',
              ),
              _MetricCard(
                width: cardWidth,
                title: l10n.adminBookedValue,
                value: '',
                amount: data.bookedValue,
                icon: Icons.payments_outlined,
                color: AppColors.accentGreen,
                footnote: l10n.adminReservationCount,
                footnoteValue: '${data.reservationCount}',
              ),
            ],
          );
        }),
        const SizedBox(height: 22),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _reservationMix(l10n, data)),
              const SizedBox(width: 18),
              Expanded(
                flex: 2,
                child: _recentReservations(l10n, data.recentReservations,
                    compact: true),
              ),
            ],
          )
        else ...[
          _reservationMix(l10n, data),
          const SizedBox(height: 18),
          _recentReservations(l10n, data.recentReservations),
        ],
      ],
    );
  }

  Widget _popularityView(AppLocalizations l10n) {
    final popularity = _popularity ??
        const AdminAttractionPopularity(
          places: [],
          countries: [],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Panel(
          title: l10n.adminCountryVisits,
          child: popularity.countries.isEmpty
              ? _EmptyText(l10n.adminNoCountryVisits)
              : Column(
                  children: popularity.countries
                      .map((item) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.public_rounded),
                            title: Text(
                              item.country == 'Unspecified country'
                                  ? l10n.adminUnspecifiedCountry
                                  : item.country,
                            ),
                            trailing: Text(
                              NumberFormat.decimalPattern(
                                      Localizations.localeOf(context)
                                          .toString())
                                  .format(item.visitCount),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ))
                      .toList(),
                ),
        ),
        const SizedBox(height: 18),
        _Panel(
          title: l10n.adminPlaceVisits,
          child: popularity.places.isEmpty
              ? _EmptyText(l10n.adminNoPlaceVisits)
              : Column(
                  children: popularity.places
                      .map((item) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.place_outlined),
                            title: Text(item.title),
                            subtitle: Text([
                              item.city,
                              item.country.isEmpty
                                  ? l10n.adminUnspecifiedCountry
                                  : item.country,
                            ].where((part) => part.isNotEmpty).join(', ')),
                            trailing: Text(
                              NumberFormat.decimalPattern(
                                      Localizations.localeOf(context)
                                          .toString())
                                  .format(item.visitCount),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _reservationMix(AppLocalizations l10n, AdminDashboardData data) {
    final total =
        data.flightCount + data.serviceBookingCount + data.transferCount;
    return _Panel(
      title: l10n.adminReservationBreakdown,
      child: Column(
        children: [
          _MixBar(
            label: l10n.adminFlights,
            count: data.flightCount,
            fraction: total == 0 ? 0 : data.flightCount / total,
            color: AppColors.primary,
          ),
          const SizedBox(height: 18),
          _MixBar(
            label: l10n.adminServices,
            count: data.serviceBookingCount,
            fraction: total == 0 ? 0 : data.serviceBookingCount / total,
            color: AppColors.accentOrange,
          ),
          const SizedBox(height: 18),
          _MixBar(
            label: l10n.adminTransfers,
            count: data.transferCount,
            fraction: total == 0 ? 0 : data.transferCount / total,
            color: AppColors.accentTeal,
          ),
        ],
      ),
    );
  }

  Widget _recentReservations(
      AppLocalizations l10n, List<AdminReservation> reservations,
      {bool compact = false}) {
    return _Panel(
      title: l10n.adminRecentReservations,
      trailing: TextButton(
        onPressed: () => _selectSection(_AdminSection.reservations),
        child: Text(l10n.viewAll),
      ),
      child: reservations.isEmpty
          ? _EmptyText(l10n.adminNoReservations)
          : Column(
              children: reservations
                  .take(compact ? 5 : 8)
                  .map((reservation) =>
                      _ReservationTile(reservation: reservation))
                  .toList(),
            ),
    );
  }

  Widget _reservationsView(AppLocalizations l10n) {
    return _Panel(
      title: l10n.adminReservations,
      child: _reservations.isEmpty
          ? _EmptyText(l10n.adminNoReservations)
          : Column(
              children: _reservations
                  .map((item) => _ReservationTile(
                        reservation: item,
                        detailed: true,
                      ))
                  .toList(),
            ),
    );
  }

  Widget _customersView(AppLocalizations l10n, bool isWide) {
    final query = _customerQuery.trim().toLowerCase();
    final customers = _customers.where((customer) {
      return customer.name.toLowerCase().contains(query) ||
          customer.email.toLowerCase().contains(query);
    }).toList();
    return _Panel(
      title: l10n.adminCustomers,
      trailing: SizedBox(
        width: isWide ? 260 : 180,
        height: 42,
        child: TextField(
          onChanged: (value) => setState(() => _customerQuery = value),
          decoration: InputDecoration(
            hintText: l10n.adminSearchCustomers,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkBorder
                    : AppColors.border,
              ),
            ),
          ),
        ),
      ),
      child: customers.isEmpty
          ? _EmptyText(l10n.adminNoCustomers)
          : Column(
              children: customers
                  .map((customer) => _CustomerTile(customer: customer))
                  .toList(),
            ),
    );
  }
}

class _AdminIdentity extends StatelessWidget {
  final String name;

  const _AdminIdentity({required this.name});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: AppColors.primarySurface,
          child: Text(
            name.isEmpty ? 'Z' : name[0].toUpperCase(),
            style: const TextStyle(
                color: AppColors.primary, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final double width;
  final String title;
  final String value;
  final double? amount;
  final IconData icon;
  final Color color;
  final String footnote;
  final String footnoteValue;

  const _MetricCard({
    required this.width,
    required this.title,
    required this.value,
    this.amount,
    required this.icon,
    required this.color,
    required this.footnote,
    required this.footnoteValue,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.025),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: amount == null
                ? Text(
                    value,
                    style: const TextStyle(
                        fontSize: 27, fontWeight: FontWeight.w800),
                  )
                : CurrencyAmountText(
                    amount: amount!,
                    decimalDigits: 0,
                    style: const TextStyle(
                        fontSize: 27, fontWeight: FontWeight.w800),
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.trending_up_rounded, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                footnoteValue,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  footnote,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Panel({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _MixBar extends StatelessWidget {
  final String label;
  final int count;
  final double fraction;
  final Color color;

  const _MixBar({
    required this.label,
    required this.count,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            Text('$count',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LinearProgressIndicator(
            value: fraction.clamp(0, 1),
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.12),
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ReservationTile extends StatelessWidget {
  final AdminReservation reservation;
  final bool detailed;

  const _ReservationTile({
    required this.reservation,
    this.detailed = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final date = reservation.reservationDate == null
        ? '—'
        : DateFormat.yMMMd(Localizations.localeOf(context).toString())
            .format(reservation.reservationDate!.toLocal());
    final normalizedStatus = reservation.status.toLowerCase();
    final statusColor = normalizedStatus.contains('cancel')
        ? AppColors.accentRed
        : normalizedStatus.contains('complete') ||
                normalizedStatus.contains('confirm') ||
                normalizedStatus.contains('upcoming')
            ? AppColors.accentGreen
            : AppColors.accentOrange;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: isDark ? AppColors.darkBorder : AppColors.divider),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _reservationIcon(reservation.type),
              size: 19,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reservation.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  detailed
                      ? '${reservation.customerName} · ${reservation.type}'
                      : reservation.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (detailed) ...[
            const SizedBox(width: 8),
            Text(date,
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CurrencyAmountText(
                  amount: reservation.amount,
                  decimalDigits: 0,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(l10n, reservation.status),
                  style: TextStyle(
                    fontSize: 9,
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _reservationIcon(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('flight')) return Icons.flight_takeoff_rounded;
    if (normalized.contains('transfer')) return Icons.local_taxi_rounded;
    if (normalized.contains('hotel')) return Icons.hotel_rounded;
    if (normalized.contains('car')) return Icons.directions_car_rounded;
    return Icons.confirmation_num_outlined;
  }

  static String _statusLabel(AppLocalizations l10n, String status) {
    switch (status.toLowerCase()) {
      case 'cancelled':
        return l10n.cancelled;
      case 'completed':
        return l10n.completed;
      case 'upcoming':
      case 'confirmed':
        return status.toLowerCase() == 'upcoming'
            ? l10n.adminUpcoming
            : l10n.adminConfirmed;
      default:
        return status;
    }
  }
}

class _CustomerTile extends StatelessWidget {
  final AdminCustomer customer;

  const _CustomerTile({required this.customer});

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final joined = customer.joinedAt == null
        ? '—'
        : DateFormat.yMMMd(locale).format(customer.joinedAt!.toLocal());
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkBorder
                : AppColors.divider,
          ),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: AppColors.primarySurface,
            child: Text(
              customer.name.isEmpty ? '?' : customer.name[0].toUpperCase(),
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(customer.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(joined,
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('${customer.reservationCount}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  final String text;

  const _EmptyText(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined,
                  color: AppColors.accentOrange, size: 42),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(AppLocalizations.of(context).adminRefresh),
              ),
            ],
          ),
        ),
      );
}

class _AccessDenied extends StatelessWidget {
  final String message;

  const _AccessDenied({required this.message});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      color: AppColors.accentOrange, size: 48),
                  const SizedBox(height: 14),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pushReplacementNamed(context, AppRoutes.home),
                    child: Text(AppLocalizations.of(context).adminBackToApp),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

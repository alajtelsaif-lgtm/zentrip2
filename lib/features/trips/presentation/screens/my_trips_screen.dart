import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routes/app_routes.dart';
import '../../logic/trips_controller.dart';
import 'trip_details_screen.dart';
import 'trip_item_card.dart';
import 'itinerary_screen.dart';

class MyTripsScreen extends StatefulWidget {
  final TripsController? controller;

  const MyTripsScreen({super.key, this.controller});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  late final TripsController _ctrl;
  bool _loadErrorShown = false;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TripsController();
    _ctrl.addListener(_onTripsChanged);
    _ctrl.loadTrips();
  }

  void _onTripsChanged() {
    if (_ctrl.loadError == null) {
      _loadErrorShown = false;
      return;
    }
    if (_loadErrorShown) return;
    _loadErrorShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).bookingLoadError),
        ),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTripsChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.myTrips,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  Row(children: [
                    IconButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ItineraryScreen())),
                      icon: const Icon(Icons.route_rounded),
                      tooltip: l10n.itineraryTitle,
                    ),
                    ElevatedButton.icon(
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.searchFlights),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label:
                          Text(l10n.book, style: const TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(80, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 14)),
                    ),
                  ]),
                ],
              ),
            ),
            // ── Tabs ───────────────────────────────────────────────────
            ListenableBuilder(
              listenable: _ctrl,
              builder: (_, __) =>
                  _TabBar(ctrl: _ctrl, l10n: l10n, isDark: isDark),
            ),
            ListenableBuilder(
              listenable: _ctrl,
              builder: (_, __) => _FilterBar(ctrl: _ctrl, l10n: l10n),
            ),
            // ── Content ────────────────────────────────────────────────
            Expanded(
              child: ListenableBuilder(
                listenable: _ctrl,
                builder: (_, __) {
                  if (_ctrl.isLoading) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary));
                  }
                  final items = _ctrl.visibleItems;
                  if (items.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _ctrl.loadTrips,
                      color: AppColors.primary,
                      child: LayoutBuilder(
                        builder: (_, c) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: c.maxHeight,
                            child: _EmptyTrips(
                                l10n: l10n,
                                tab: _ctrl.selectedTab,
                                filtered:
                                    _ctrl.selectedFilter != TripFilter.all),
                          ),
                        ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _ctrl.loadTrips,
                    color: AppColors.primary,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        return TripItemCard(
                          item: item,
                          isDark: isDark,
                          l10n: l10n,
                          onTap: () async {
                            final flight = item.flight;
                            if (flight == null) {
                              await showBookingDetailsSheet(context, item);
                              return;
                            }
                            final cancelled = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        TripDetailsScreen(trip: flight)));
                            if (!mounted) return;
                            if (cancelled == true) _ctrl.loadTrips();
                          },
                        )
                            .animate(
                                delay: Duration(milliseconds: 60 * (i % 8)))
                            .fade()
                            .slideY(begin: 0.05, end: 0);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final TripsController ctrl;
  final AppLocalizations l10n;
  final bool isDark;
  const _TabBar({required this.ctrl, required this.l10n, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceSecondary
            : AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: TripTab.values.map((tab) {
          final isSelected = ctrl.selectedTab == tab;
          final count = ctrl.countFor(tab);
          return Expanded(
            child: GestureDetector(
              onTap: () => ctrl.setTab(tab),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? AppColors.darkSurface : AppColors.surface)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8)
                        ]
                      : [],
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    count > 0 ? '${tab.label(l10n)} ($count)' : tab.label(l10n),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final TripsController ctrl;
  final AppLocalizations l10n;
  const _FilterBar({required this.ctrl, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final filters = [
      (TripFilter.all, l10n.tripsFilterAll, Icons.apps_rounded),
      (TripFilter.flights, l10n.tripsFilterFlights, Icons.flight_rounded),
      (TripFilter.hotels, l10n.tripsFilterHotels, Icons.hotel_rounded),
      (TripFilter.cars, l10n.tripsFilterCars, Icons.directions_car_rounded),
      (TripFilter.tours, l10n.tripsFilterTours, Icons.local_activity_rounded),
      (TripFilter.transfers, l10n.tripsFilterTransfers, Icons.local_taxi_rounded),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (filter, label, icon) = filters[i];
          final selected = ctrl.selectedFilter == filter;
          return ChoiceChip(
            avatar: Icon(icon,
                size: 15,
                color: selected ? Colors.white : AppColors.textSecondary),
            label: Text(label),
            selected: selected,
            showCheckmark: false,
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              fontSize: 12,
              color: selected ? Colors.white : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
            onSelected: (_) => ctrl.setFilter(filter),
          );
        },
      ),
    );
  }
}

class _EmptyTrips extends StatelessWidget {
  final AppLocalizations l10n;
  final TripTab tab;
  final bool filtered;
  const _EmptyTrips(
      {required this.l10n, required this.tab, this.filtered = false});

  @override
  Widget build(BuildContext context) {
    final (Widget illustration, String title, String subtitle) = filtered
        ? (
            const Icon(Icons.filter_alt_off_rounded,
                size: 72, color: AppColors.textHint),
            l10n.tripsNoFilterResults,
            '',
          )
        : switch (tab) {
            TripTab.active => (
                const Icon(Icons.hourglass_empty_rounded,
                    size: 72, color: AppColors.textHint),
                l10n.emptyActiveTitle,
                l10n.emptyActiveSubtitle,
              ),
            TripTab.completed => (
                CustomPaint(
                    size: const Size(220, 200), painter: _PastTripsPainter()),
                l10n.emptyPastTitle,
                l10n.emptyPastSubtitle,
              ),
            TripTab.cancelled => (
                CustomPaint(
                    size: const Size(220, 220),
                    painter: _CancelledTripsPainter()),
                l10n.emptyCancelledTitle,
                l10n.emptyCancelledSubtitle,
              ),
            TripTab.upcoming => (
                const Icon(Icons.card_travel_rounded,
                    size: 72, color: AppColors.textHint),
                l10n.noUpcomingTrips,
                l10n.noUpcomingTripsSubtitle,
              ),
          };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            illustration.animate().fade(duration: 400.ms).scale(
                begin: const Offset(0.92, 0.92), end: const Offset(1, 1)),
            const SizedBox(height: 32),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ).animate(delay: 100.ms).fade().slideY(begin: 0.1, end: 0),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.6),
              ).animate(delay: 200.ms).fade(),
            ],
            if (tab == TripTab.upcoming && !filtered) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.searchFlights),
                icon: const Icon(Icons.flight_takeoff_rounded),
                label: Text(l10n.tripsBookFirstTrip),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// رسمة "الرحلات السابقة" — صورة بولارويد مائلة لخريطة زرقاء مثبتة بدبابيس برتقالية.
class _PastTripsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.12);

    // إطار الصورة (كريمي)
    final frame = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 190, height: 150),
        const Radius.circular(6));
    canvas.drawShadow(
        Path()..addRRect(frame), Colors.black.withValues(alpha: 0.3), 8, false);
    canvas.drawRRect(frame, Paint()..color = const Color(0xFFFDF3E3));

    // الخريطة الزرقاء
    final map = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 172, height: 132),
        const Radius.circular(4));
    canvas.drawRRect(map, Paint()..color = const Color(0xFF1A56C4));

    // يابسة فاتحة (بقع عضوية)
    final land = Paint()..color = const Color(0xFF9CC3F5);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(-55, -35), width: 55, height: 38),
        land);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(20, -15), width: 65, height: 42),
        land);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(-30, 38), width: 48, height: 30),
        land);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(58, 40), width: 42, height: 28),
        land);

    // زاوية مطوية أعلى اليمين
    final fold = Path()
      ..moveTo(95, -75)
      ..lineTo(65, -75)
      ..lineTo(95, -45)
      ..close();
    canvas.drawPath(fold, Paint()..color = const Color(0xFFF3E2C7));

    // دبابيس برتقالية/صفراء
    void pin(Offset p, Color color) {
      canvas.drawLine(
          p,
          p + const Offset(4, 10),
          Paint()
            ..color = const Color(0xFF8A6D3B)
            ..strokeWidth = 1.6);
      canvas.drawCircle(p, 6.5, Paint()..color = color);
      canvas.drawCircle(p - const Offset(2, 2), 2,
          Paint()..color = Colors.white.withValues(alpha: 0.45));
    }

    pin(const Offset(-50, -40), const Color(0xFFF5A623));
    pin(const Offset(28, -22), const Color(0xFFF06E1D));
    pin(const Offset(-38, 30), const Color(0xFFF06E1D));
    pin(const Offset(50, 28), const Color(0xFFF5A623));

    canvas.restore();

    // خربشات صفراء زخرفية حول الصورة
    final doodle = Paint()
      ..color = const Color(0xFFF5C142)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        Rect.fromCircle(center: Offset(18, size.height - 18), radius: 14),
        3.4,
        2.4,
        false,
        doodle);
    canvas.drawArc(
        Rect.fromCircle(center: Offset(size.width - 16, 26), radius: 10),
        0.4,
        2.2,
        false,
        doodle);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// رسمة "الرحلات الملغاة" — خريطة مطوية بسهم عودة ودبوس موقع برتقالي.
class _CancelledTripsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2 - 10, size.height / 2);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(0.06);

    // أجزاء الخريطة المطوية (3 طيّات بدرجات زرقاء متفاوتة)
    const w = 150.0, h = 160.0;
    const seg = w / 3;
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawShadow(
        Path()
          ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8))),
        Colors.black.withValues(alpha: 0.25),
        10,
        false);

    final folds = [
      const Color(0xFF1A56C4),
      const Color(0xFF2E6BDB),
      const Color(0xFF1A56C4)
    ];
    for (var i = 0; i < 3; i++) {
      final r = Rect.fromLTWH(
          rect.left + seg * i, rect.top + (i == 1 ? -8 : 0), seg, h);
      canvas.drawRect(r, Paint()..color = folds[i]);
    }

    // يابسة فاتحة
    final land = Paint()..color = const Color(0xFF9CC3F5);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(-48, -45), width: 44, height: 34),
        land);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(5, 8), width: 52, height: 40),
        land);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(48, -30), width: 36, height: 30),
        land);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(-30, 55), width: 40, height: 26),
        land);

    // مسار منقّط
    final dot = Paint()..color = const Color(0xFF0B2B66);
    for (var t = 0.0; t <= 1.0; t += 0.09) {
      final p = Offset(-55 + 100 * t, 60 - 130 * t + 60 * t * t);
      canvas.drawCircle(p, 1.8, dot);
    }

    // سهم كريمي منحنٍ (تغيير الوجهة)
    final arrow = Path()
      ..moveTo(-18, 52)
      ..quadraticBezierTo(-30, -8, 18, -34)
      ..lineTo(12, -52)
      ..lineTo(46, -44)
      ..lineTo(34, -12)
      ..lineTo(28, -26)
      ..quadraticBezierTo(-8, -4, 2, 48)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFFFDF3E3));
    canvas.drawPath(
        arrow,
        Paint()
          ..color = const Color(0xFFE8D5B5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);

    canvas.restore();

    // دبوس موقع برتقالي كبير خارج الخريطة
    final pinCenter = Offset(size.width - 38, 62);
    final pin = Path()
      ..addOval(Rect.fromCircle(center: pinCenter, radius: 20))
      ..moveTo(pinCenter.dx - 12, pinCenter.dy + 16)
      ..quadraticBezierTo(
          pinCenter.dx, pinCenter.dy + 44, pinCenter.dx + 12, pinCenter.dy + 16)
      ..close();
    canvas.drawPath(pin, Paint()..color = const Color(0xFFF06E1D));
    canvas.drawCircle(pinCenter, 7.5, Paint()..color = const Color(0xFFB74A0A));

    // خيط زخرفي متعرج أسفل الدبوس
    final squiggle = Paint()
      ..color = const Color(0xFFF06E1D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final sq = Path()..moveTo(size.width - 30, 118);
    sq.cubicTo(
        size.width - 12, 128, size.width - 44, 140, size.width - 26, 150);
    canvas.drawPath(sq, squiggle);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

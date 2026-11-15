import '../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../models/trip_model.dart';
import '../core/utils/date_time_utils.dart';

class BoardingPassCard extends StatelessWidget {
  final TripModel trip;
  final VoidCallback? onTap;

  const BoardingPassCard({super.key, required this.trip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trip.originCode,
                          style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1)),
                      Text(trip.originCity,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.7))),
                    ],
                  ),
                  Column(
                    children: [
                      const Icon(Icons.flight, color: Colors.white, size: 22),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          trip.isDirect ? AppLocalizations.of(context).boardingDirect : AppLocalizations.of(context).boardingOneStop,
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(trip.destinationCode,
                          style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1)),
                      Text(trip.destinationCity,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.7))),
                    ],
                  ),
                ],
              ),
            ),
            // ── Dashed Divider ───────────────────────────────────────────
            _DashedDivider(),
            // ── Footer ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _InfoChip(
                      label: AppLocalizations.of(context).boardingDate,
                      value: DateTimeUtils.formatShortDate(trip.departureDate,
                          locale: 'en')),
                  _InfoChip(label: AppLocalizations.of(context).boardingFlight, value: trip.flightNumber),
                  _InfoChip(label: AppLocalizations.of(context).boardingClass, value: trip.seatClass ?? 'Economy'),
                  if (trip.bookingRef != null)
                    _InfoChip(
                        label: AppLocalizations.of(context).boardingRef, value: trip.bookingRef!.split('-').last),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (_, constraints) {
            final dashCount = (constraints.maxWidth / 12).floor();
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(
                  dashCount,
                  (_) => Container(
                        width: 6,
                        height: 1.5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      )),
            );
          }),
        ),
        Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(10),
              bottomLeft: Radius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

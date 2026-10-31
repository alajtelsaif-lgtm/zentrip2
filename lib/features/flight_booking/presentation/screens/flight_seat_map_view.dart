import 'dart:math' as math;
import 'package:flutter/material.dart';

const _seatNavy = Color(0xFF1E1B4B);
const _seatInk = Color(0xFF20263A);
const _seatMuted = Color(0xFF8991A2);
const _available = Color(0xFFE8ECF5);
const _taken = Color(0xFFE9EBF0);

/// Cabin rows are the actual aircraft row numbers supplied by the seat API.
/// Rows advance horizontally, with the aisle running between the two groups.
class FlightSeatMapView extends StatelessWidget {
  final List<int> rows;
  final List<String> seatLetters;
  final Set<int> extraLegroomRows;
  final Set<String> occupiedSeats;
  final Set<String> selectedSeats;
  final bool enabled;
  final ValueChanged<String> onSeatTap;

  const FlightSeatMapView({
    super.key,
    required this.rows,
    required this.seatLetters,
    required this.extraLegroomRows,
    required this.occupiedSeats,
    required this.selectedSeats,
    required this.enabled,
    required this.onSeatTap,
  });

  @override
  Widget build(BuildContext context) {
    final split = seatLetters.length ~/ 2;
    final upper = seatLetters.take(split).toList();
    final lower = seatLetters.skip(split).toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(86),
          right: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: _seatNavy.withValues(alpha: .035),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 19, 10, 18),
        child: LayoutBuilder(builder: (context, constraints) {
          final columnWidth = math.max(
            52.0, (constraints.maxWidth - 70) / math.max(1, rows.length),
          );
          return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 70,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var index = 0; index < upper.length; index++)
                      const SizedBox(height: 44),
                    const SizedBox(height: 3),
                    const SizedBox(
                      height: 24,
                      child: Center(
                        child: Text('DECK',
                            style: TextStyle(
                                color: _seatMuted,
                                fontSize: 10,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w900)),
                      ),
                    ),
                    for (var index = 0; index < lower.length; index++)
                      const SizedBox(height: 44),
                  ],
                ),
              ),
              for (final row in rows)
                SizedBox(
                  width: columnWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final letter in upper)
                        _SeatTile(
                          seatId: '$row$letter',
                          letter: letter,
                          premium: extraLegroomRows.contains(row),
                          occupied: occupiedSeats.contains('$row$letter'),
                          selected: selectedSeats.contains('$row$letter'),
                          enabled: enabled,
                          onTap: onSeatTap,
                        ),
                      const SizedBox(height: 3),
                      SizedBox(
                        height: 24,
                        child: Center(
                          child: Text('$row',
                              style: const TextStyle(
                                  color: _seatMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                      for (final letter in lower)
                        _SeatTile(
                          seatId: '$row$letter',
                          letter: letter,
                          premium: extraLegroomRows.contains(row),
                          occupied: occupiedSeats.contains('$row$letter'),
                          selected: selectedSeats.contains('$row$letter'),
                          enabled: enabled,
                          onTap: onSeatTap,
                        ),
                    ],
                  ),
                ),
            ],
          ),
          );
        }),
      ),
    );
  }
}

class _SeatTile extends StatelessWidget {
  final String seatId;
  final String letter;
  final bool premium;
  final bool occupied;
  final bool selected;
  final bool enabled;
  final ValueChanged<String> onTap;

  const _SeatTile({
    required this.seatId,
    required this.letter,
    required this.premium,
    required this.occupied,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canSelect = enabled && (!occupied || selected);
    final fill = selected
        ? _seatNavy
        : occupied
            ? _taken
            : premium
                ? Colors.white
                : _available;
    final edge = selected
        ? _seatNavy
        : premium && !occupied
            ? _seatNavy
            : Colors.transparent;
    final foreground = selected
        ? Colors.white
        : occupied
            ? const Color(0xFFC6CBD4)
            : _seatInk;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        key: ValueKey('seat-$seatId'),
        button: true,
        enabled: canSelect,
        selected: selected,
        label: 'Seat $seatId, ${selected ? 'your seat' : occupied ? 'taken' : premium ? 'extra legroom, available' : 'available'}',
        child: SizedBox(
          width: 42,
          height: 40,
          child: Material(
            color: fill,
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              onTap: canSelect ? () => onTap(seatId) : null,
              borderRadius: BorderRadius.circular(11),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: edge, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  occupied && !selected ? '' : letter,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

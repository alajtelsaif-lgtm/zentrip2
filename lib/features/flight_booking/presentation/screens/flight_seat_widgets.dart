import 'package:flutter/material.dart';

import '../../../../models/flight_model.dart';
import '../../../../models/flight_seat_map.dart';

const _navy = Color(0xFF1E1B4B);
const _ink = Color(0xFF172033);
const _muted = Color(0xFF81899B);
const _line = Color(0xFFE7EAF1);

class FlightSelectionHeader extends StatelessWidget {
  final FlightModel flight;

  const FlightSelectionHeader({super.key, required this.flight});

  @override
  Widget build(BuildContext context) {
    final date = MaterialLocalizations.of(context).formatMediumDate(
      flight.departureTime,
    );
    final time = TimeOfDay.fromDateTime(flight.departureTime).format(context);
    final aircraft = flight.aircraftName.trim().isEmpty
        ? 'Aircraft details'
        : flight.aircraftName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$date, $time · ${flight.flightNumber}',
          style: const TextStyle(
              color: _muted, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '${flight.originCode}–${flight.destinationCode}',
            maxLines: 1,
            style: const TextStyle(
              color: _navy,
              fontSize: 39,
              height: 1,
              letterSpacing: -1.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(aircraft,
            style: const TextStyle(
                color: _muted, fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class FlightFareCard extends StatelessWidget {
  final FlightSeatFare fare;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final String currencyCode;
  final bool showAvailability;

  const FlightFareCard({
    super.key,
    required this.fare,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.currencyCode = 'USD',
    this.showAvailability = true,
  });

  String get _currencyPrefix => currencyCode == 'USD' ? '\$' : '$currencyCode ';

  String get _price => fare.price == fare.price.truncateToDouble()
      ? fare.price.toStringAsFixed(0)
      : fare.price.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : _ink;
    final availability = showAvailability
        ? ', ${fare.availableSeats} seats${fare.sharedInventory ? ', shared inventory' : ''}'
        : '';
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: '${fare.label}, $_currencyPrefix$_price$availability',
      child: Material(
        color: selected ? _navy : Colors.white,
        borderRadius: BorderRadius.circular(22),
        elevation: selected ? 3 : 0,
        shadowColor: _navy.withValues(alpha: .16),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(17, 15, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fare.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('$_currencyPrefix$_price',
                      style: TextStyle(
                          color: foreground,
                          fontSize: 28,
                          height: 1,
                          letterSpacing: -.8,
                          fontWeight: FontWeight.w900)),
                ),
                if (showAvailability) ...[
                  const SizedBox(height: 5),
                  Text(
                    '${fare.availableSeats} seats',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: selected ? Colors.white70 : _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  if (fare.sharedInventory)
                    Text(
                      'Shared inventory',
                      style: TextStyle(
                          color: selected ? Colors.white70 : _muted,
                          fontSize: 10),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FlightCabinSelector extends StatelessWidget {
  final FlightSeatCabin cabin;
  final List<FlightSeatCabin> cabins;
  final String selectedCabinId;
  final bool enabled;
  final ValueChanged<FlightSeatCabin> onCabinSelected;

  const FlightCabinSelector({
    super.key,
    required this.cabin,
    required this.cabins,
    required this.selectedCabinId,
    required this.enabled,
    required this.onCabinSelected,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final maxPillWidth =
              (constraints.maxWidth * .58).clamp(124.0, 248.0).toDouble();
          final pillViewportWidth =
              (cabins.length * 54.0 - 8).clamp(0.0, maxPillWidth).toDouble();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cabin.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      '${cabin.availableSeats}/${cabin.totalSeats} available',
                      style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: pillViewportWidth,
                height: 48,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var index = 0; index < cabins.length; index++) ...[
                        if (index > 0) const SizedBox(width: 8),
                        _CabinPill(
                          number: '${index + 1}',
                          selected: cabins[index].id == selectedCabinId,
                          enabled: enabled,
                          onTap: () => onCabinSelected(cabins[index]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
}

class _CabinPill extends StatelessWidget {
  final String number;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _CabinPill({
    required this.number,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: enabled,
        selected: selected,
        label: 'Cabin $number',
        child: Material(
          color: selected ? _navy : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Center(
                child: Text(number,
                    style: TextStyle(
                        color: selected ? Colors.white : _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
      );
}

class FlightSeatLegend extends StatelessWidget {
  const FlightSeatLegend({super.key});

  @override
  Widget build(BuildContext context) => const Wrap(
        alignment: WrapAlignment.center,
        spacing: 15,
        runSpacing: 9,
        children: [
          _LegendItem(color: Color(0xFFE8ECF5), label: 'Available'),
          _LegendItem(
              color: Colors.white, border: _navy, label: 'Extra legroom'),
          _LegendItem(color: _navy, label: 'Your seat'),
          _LegendItem(color: Color(0xFFE9EBF0), label: 'Taken'),
        ],
      );
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final Color? border;
  final String label;

  const _LegendItem({required this.color, this.border, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                  color: border ?? color, width: border == null ? 0 : 1.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: _muted, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      );
}

class FlightExtrasPanel extends StatelessWidget {
  final Map<String, double> extras;
  final Set<String> selectedExtras;
  final bool enabled;
  final void Function(String key, bool selected) onChanged;

  const FlightExtrasPanel({
    super.key,
    required this.extras,
    required this.selectedExtras,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (extras.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: _line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        iconColor: _navy,
        title: const Text('Optional extras',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w800)),
        subtitle: const Text('Add only what you need',
            style: TextStyle(color: _muted, fontSize: 12)),
        children: [
          for (final entry in extras.entries)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: _navy,
              value: selectedExtras.contains(entry.key),
              title: Text(_extraLabel(entry.key),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('\$${entry.value.toStringAsFixed(2)}'),
              onChanged: enabled
                  ? (value) => onChanged(entry.key, value == true)
                  : null,
            ),
        ],
      ),
    );
  }

  String _extraLabel(String key) => key
      .split(RegExp(r'[_-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

class FlightPriceBreakdown extends StatelessWidget {
  final FlightSeatMap map;
  final FlightSeatFare fare;
  final int passengerCount;
  final Set<String> selectedSeats;
  final Set<String> selectedExtras;
  final double totalPrice;

  const FlightPriceBreakdown({
    super.key,
    required this.map,
    required this.fare,
    required this.passengerCount,
    required this.selectedSeats,
    required this.selectedExtras,
    required this.totalPrice,
  });

  @override
  Widget build(BuildContext context) {
    final base = fare.price * passengerCount;
    final premiumCount = selectedSeats.where((seat) {
      final row = int.tryParse(seat.substring(0, seat.length - 1));
      return row != null && map.extraLegroomRows.contains(row);
    }).length;
    final premium = premiumCount * map.extraLegroomFee;
    final extra = selectedExtras.fold<double>(
      0,
      (sum, key) => sum + (map.extras[key] ?? 0),
    );
    final taxes = (base + premium + extra) * map.taxRate;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          _priceRow('${fare.label} fare × $passengerCount', base),
          if (premium > 0) _priceRow('Extra-legroom seats', premium),
          if (extra > 0) _priceRow('Optional extras', extra),
          _priceRow('Taxes and fees', taxes + map.bookingFee),
          const Divider(height: 22),
          Row(
            children: [
              const Expanded(
                child: Text('Estimated total',
                    style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
              ),
              Text('\$${totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: _navy, fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
          const SizedBox(height: 5),
          Text('${selectedSeats.length} of $passengerCount seats selected',
              style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _priceRow(String title, double amount) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(color: _muted, fontSize: 13)),
            ),
            Text('\$${amount.toStringAsFixed(2)}',
                style:
                    const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class FlightSeatMapSkeleton extends StatelessWidget {
  const FlightSeatMapSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Container(
        height: 235,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Center(
          child: SizedBox(
            width: 210,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SkeletonLine(width: 140, height: 13),
                SizedBox(height: 23),
                _SkeletonLine(width: 190, height: 92),
              ],
            ),
          ),
        ),
      );
}

class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  const _SkeletonLine({required this.width, required this.height});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFE9ECF3),
          borderRadius: BorderRadius.circular(10),
        ),
      );
}

class FlightSeatErrorPanel extends StatelessWidget {
  final String message;
  final bool retrying;
  final VoidCallback? onRetry;

  const FlightSeatErrorPanel({
    super.key,
    required this.message,
    required this.retrying,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _line),
        ),
        child: Column(
          children: [
            const Icon(Icons.event_seat_outlined, color: _muted, size: 27),
            const SizedBox(height: 9),
            Text(message,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: _ink, fontWeight: FontWeight.w600)),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: retrying ? null : onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      );
}

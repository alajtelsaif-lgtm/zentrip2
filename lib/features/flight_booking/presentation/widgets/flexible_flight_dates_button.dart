import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../logic/flexible_flight_selection.dart';

class FlexibleFlightDatesButton extends StatelessWidget {
  final FlexibleFlightSelection? selection;
  final ValueChanged<FlexibleFlightSelection?> onChanged;
  final bool compact;

  const FlexibleFlightDatesButton({
    super.key,
    required this.selection,
    required this.onChanged,
    this.compact = false,
  });

  Future<void> _openSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<FlexibleFlightSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _FlexibleFlightDatesSheet(initialSelection: selection),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final months = selection?.departureMonths
            .map((month) => MaterialLocalizations.of(context)
                .formatMonthYear(DateTime(month.year, month.month, 1)))
            .toList() ??
        const <String>[];
    final label = selection == null
        ? l10n.flightFlexibleButton
        : '${months.join(', ')} · ${selection!.tripDurationDays} ${l10n.flightDays}';

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () => _openSheet(context),
        icon: const Icon(Icons.date_range_rounded, size: 18),
        label: Text(
          compact ? l10n.flightFlexibleButton : label,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: 8,
          ),
        ),
      ),
    );
  }
}

class _FlexibleFlightDatesSheet extends StatefulWidget {
  final FlexibleFlightSelection? initialSelection;

  const _FlexibleFlightDatesSheet({this.initialSelection});

  @override
  State<_FlexibleFlightDatesSheet> createState() =>
      _FlexibleFlightDatesSheetState();
}

class _FlexibleFlightDatesSheetState extends State<_FlexibleFlightDatesSheet> {
  late final List<DateTime> _availableMonths;
  late final Set<DateTime> _selectedMonths;
  late int _tripDurationDays;
  late final TextEditingController _customDaysController;
  bool _otherSelected = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _availableMonths = List.generate(
      3,
      (index) => DateTime(now.year, now.month + index, 1),
      growable: false,
    );
    final validInitial = widget.initialSelection?.departureMonths
            .where((month) => _availableMonths.any(
                  (available) =>
                      available.year == month.year &&
                      available.month == month.month,
                ))
            .map((month) => DateTime(month.year, month.month, 1))
            .toSet() ??
        <DateTime>{};
    _selectedMonths =
        validInitial.isEmpty ? {_availableMonths.first} : validInitial;
    _tripDurationDays = widget.initialSelection?.tripDurationDays ?? 7;
    _otherSelected = widget.initialSelection?.isCustomDuration == true ||
        !_presetDurations.contains(_tripDurationDays);
    _customDaysController = TextEditingController(
      text: _otherSelected ? '$_tripDurationDays' : '10',
    );
  }

  static const _presetDurations = {2, 7, 30};

  @override
  void dispose() {
    _customDaysController.dispose();
    super.dispose();
  }

  void _toggleMonth(DateTime month) {
    setState(() {
      if (_selectedMonths.contains(month)) {
        if (_selectedMonths.length > 1) _selectedMonths.remove(month);
      } else if (_selectedMonths.length < 3) {
        _selectedMonths.add(month);
      }
    });
  }

  void _selectDuration(int days) {
    setState(() {
      _tripDurationDays = days;
      _otherSelected = false;
    });
  }

  void _selectOther() {
    setState(() {
      _otherSelected = true;
      final parsed = int.tryParse(_customDaysController.text);
      _tripDurationDays = parsed == null ? 10 : parsed.clamp(1, 60).toInt();
    });
  }

  bool get _customDurationIsValid {
    final parsed = int.tryParse(_customDaysController.text);
    return parsed != null && parsed >= 1 && parsed <= 60;
  }

  void _submit() {
    if (_otherSelected && !_customDurationIsValid) return;
    if (_otherSelected) {
      _tripDurationDays = int.parse(_customDaysController.text);
    }
    final selection = FlexibleFlightSelection(
      departureMonths: _selectedMonths.toList()..sort((a, b) => a.compareTo(b)),
      tripDurationDays: _tripDurationDays,
      weekendsOnly: !_otherSelected && _tripDurationDays == 2,
      isCustomDuration: _otherSelected,
    );
    if (!selection.isValid) return;
    Navigator.of(context).pop(selection);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localizations = MaterialLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                l10n.flightSelectDates,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                l10n.flightTripLength,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DurationChoice(
                    label: l10n.flightWeekend,
                    selected: !_otherSelected && _tripDurationDays == 2,
                    onTap: () => _selectDuration(2),
                  ),
                  _DurationChoice(
                    label: l10n.flightWeek,
                    selected: !_otherSelected && _tripDurationDays == 7,
                    onTap: () => _selectDuration(7),
                  ),
                  _DurationChoice(
                    label: l10n.flightMonth,
                    selected: !_otherSelected && _tripDurationDays == 30,
                    onTap: () => _selectDuration(30),
                  ),
                  _DurationChoice(
                    label: l10n.flightOther,
                    selected: _otherSelected,
                    onTap: _selectOther,
                  ),
                ],
              ),
            ),
            if (!_otherSelected && _tripDurationDays == 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(
                  l10n.flightWeekendHint,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (_otherSelected)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: TextField(
                  controller: _customDaysController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.flightDuration,
                    suffixText: l10n.flightDays,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    setState(() {
                      if (parsed != null) {
                        _tripDurationDays = parsed.clamp(1, 60).toInt();
                      }
                    });
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
              child: Text(
                l10n.flightWhenToGo,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                l10n.flightSelectUpToMonths,
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            SizedBox(
              height: 128,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: _availableMonths.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final month = _availableMonths[index];
                  final selected = _selectedMonths.contains(month);
                  return SizedBox(
                    width: 112,
                    child: Material(
                      color: selected
                          ? (isDark
                              ? AppColors.primary.withValues(alpha: 0.2)
                              : AppColors.primary.withValues(alpha: 0.08))
                          : (isDark
                              ? AppColors.darkSurface
                              : Theme.of(context).colorScheme.surface),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _toggleMonth(month),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? AppColors.primary
                                  : (isDark
                                      ? AppColors.darkBorder
                                      : AppColors.border),
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.calendar_month_rounded,
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                localizations.formatMonthYear(month),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: selected ? AppColors.primary : null,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: FilledButton(
                onPressed: _selectedMonths.isEmpty ||
                        (_otherSelected && !_customDurationIsValid)
                    ? null
                    : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.primary,
                ),
                child: Text(l10n.flightSelectDates),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DurationChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primary.withValues(alpha: 0.1),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
        labelStyle: TextStyle(
          color: selected ? AppColors.primary : null,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      );
}

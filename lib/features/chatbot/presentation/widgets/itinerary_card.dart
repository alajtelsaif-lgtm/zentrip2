import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../global_widgets/app_snackbar.dart';
import '../../../../l10n/app_localizations.dart';

/// بطاقة البرنامج السياحي المُنشأ بواسطة زن AI.
class ItineraryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isSaved;
  final VoidCallback onSave;

  const ItineraryCard({
    super.key,
    required this.data,
    required this.isSaved,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final destination = data['destination'] as String? ?? l10n.chatItineraryDefaultDestination;
    final days = data['days'] as List? ?? [];
    final budget = data['estimated_budget'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: AppColors.skyGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.map_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.chatItineraryTitle(destination),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                      if (budget != null)
                        Text(l10n.chatItineraryBudget(budget),
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Divider ─────────────────────────────────────────────────────
          Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
          // ── Days ────────────────────────────────────────────────────────
          if (days.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.chatItineraryReady,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
            )
          else
            ...days.asMap().entries.map((e) {
              final day = e.value as Map<String, dynamic>;
              return _DayRow(day: day, index: e.key);
            }),
          const SizedBox(height: 8),
          // ── Save button ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: OutlinedButton.icon(
              onPressed: isSaved ? null : onSave,
              icon: Icon(
                isSaved ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                color: Colors.white,
                size: 16,
              ),
              label: Text(
                isSaved ? l10n.chatItinerarySavedSuccess : l10n.chatItinerarySave,
                style: const TextStyle(color: Colors.white),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                minimumSize: const Size(double.infinity, 42),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  final Map<String, dynamic> day;
  final int index;
  const _DayRow({required this.day, required this.index});

  @override
  Widget build(BuildContext context) {
    final title = day['title'] as String? ?? AppLocalizations.of(context).chatItineraryDayFallback(index + 1);
    final activities = day['activities'] as List? ?? [];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 6),
          ...activities.map((a) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Container(width: 5, height: 5, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(a.toString(), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12))),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

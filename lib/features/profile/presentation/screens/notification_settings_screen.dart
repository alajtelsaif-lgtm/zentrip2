import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/user_settings_sync.dart';
import '../../../../l10n/app_localizations.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool tripReminders = true;
  bool promotions = true;
  bool zenMessages = true;
  bool generalUpdates = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      tripReminders = prefs.getBool('notif_trip') ?? true;
      promotions = prefs.getBool('notif_promo') ?? true;
      zenMessages = prefs.getBool('notif_zen') ?? true;
      generalUpdates = prefs.getBool('notif_general') ?? false;
    });
  }

  Future<void> _save(String key, bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
    await UserSettingsSync.instance.push({key: val});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final items = [
      (
        Icons.flight_rounded,
        AppColors.primary,
        l10n.tripReminders,
        l10n.tripRemindersDesc,
        tripReminders,
        'notif_trip',
        (v) => setState(() => tripReminders = v)
      ),
      (
        Icons.local_offer_rounded,
        AppColors.accentOrange,
        l10n.promotions,
        l10n.promotionsDesc,
        promotions,
        'notif_promo',
        (v) => setState(() => promotions = v)
      ),
      (
        Icons.auto_awesome_rounded,
        AppColors.accentPurple,
        l10n.zenMessages,
        l10n.zenMessagesDesc,
        zenMessages,
        'notif_zen',
        (v) => setState(() => zenMessages = v)
      ),
      (
        Icons.info_outline_rounded,
        AppColors.accentTeal,
        l10n.generalUpdates,
        l10n.generalUpdatesDesc,
        generalUpdates,
        'notif_general',
        (v) => setState(() => generalUpdates = v)
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationSettingsTitle)),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final (icon, color, title, subtitle, value, key, onChanged) =
              items[i];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(subtitle,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Switch(
                  value: value,
                  activeThumbColor: color,
                  onChanged: (v) {
                    onChanged(v);
                    _save(key, v);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

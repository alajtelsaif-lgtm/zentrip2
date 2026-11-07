import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../features/notifications/logic/notifications_store.dart';
import '../../../../global_widgets/app_shell.dart';
import '../../../../l10n/app_localizations.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationsStore _store = NotificationsStore.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_store.load());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationsTitle),
        actions: [
          AnimatedBuilder(
            animation: _store,
            builder: (context, _) {
              if (!_store.hasUnread) return const SizedBox.shrink();
              return TextButton(
                onPressed: _store.markAllRead,
                child: Text(l10n.notifMarkAllRead),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          final unread =
              _store.all.where((notification) => !notification.isRead).toList();
          final earlier =
              _store.all.where((notification) => notification.isRead).toList();
          if (unread.isEmpty && earlier.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 46,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.notifEmptyTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.notifEmptyHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }

          final rows = <_NotificationRow>[];
          if (unread.isNotEmpty) {
            rows.add(_NotificationRow.section(l10n.notifNewSection));
            rows.addAll(unread.map(_NotificationRow.notification));
          }
          if (earlier.isNotEmpty) {
            rows.add(_NotificationRow.section(l10n.notifEarlierSection));
            rows.addAll(earlier.map(_NotificationRow.notification));
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              if (row.sectionTitle != null) {
                return Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(4, 14, 4, 8),
                  child: Text(
                    row.sectionTitle!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                );
              }
              return _NotificationCard(
                notification: row.notification!,
                onTap: () => _openNotification(row.notification!),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openNotification(NotificationItem notification) async {
    await _store.markRead(notification.id);
    if (!mounted) return;
    if (notification.targetType == 'trip' ||
        notification.targetType == 'booking') {
      Navigator.of(context).pop();
      AppShellTabController.goToTab(3);
    }
  }
}

class _NotificationRow {
  final String? sectionTitle;
  final NotificationItem? notification;

  const _NotificationRow.section(this.sectionTitle) : notification = null;
  const _NotificationRow.notification(this.notification) : sectionTitle = null;
}

class _NotificationCard extends StatelessWidget {
  final NotificationItem notification;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = _iconColor(notification.kind);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: notification.isRead
            ? (isDark ? AppColors.darkSurface : AppColors.surface)
            : (isDark ? AppColors.darkSurfaceSecondary : AppColors.primarySurface),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(_iconFor(notification.kind),
                      color: iconColor, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.localizedTitle(locale.languageCode),
                        style: TextStyle(
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textPrimary,
                          fontWeight: notification.isRead
                              ? FontWeight.w600
                              : FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.localizedSubtitle(locale.languageCode),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _timeLabel(context, notification.createdAt, l10n),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                if (!notification.isRead) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.circle,
                    size: 9,
                    color: AppColors.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(NotifKind kind) => switch (kind) {
        NotifKind.booking => Icons.confirmation_num_outlined,
        NotifKind.cancel => Icons.event_busy_outlined,
        NotifKind.chat => Icons.auto_awesome_outlined,
        NotifKind.promo => Icons.local_offer_outlined,
        NotifKind.reminder => Icons.schedule_rounded,
      };

  static Color _iconColor(NotifKind kind) => switch (kind) {
        NotifKind.booking => AppColors.primary,
        NotifKind.cancel => AppColors.accentRed,
        NotifKind.chat => AppColors.accentPurple,
        NotifKind.promo => AppColors.accentOrange,
        NotifKind.reminder => AppColors.accentTeal,
      };

  static String _timeLabel(
    BuildContext context,
    DateTime createdAt,
    AppLocalizations l10n,
  ) {
    final elapsed = DateTime.now().difference(createdAt.toLocal());
    if (elapsed.inMinutes < 1) return l10n.notifTimeAgoNow;
    if (elapsed.inHours < 1) return l10n.notifTimeAgoMinutes(elapsed.inMinutes);
    if (elapsed.inHours < 24) return l10n.notifTimeAgoHours(elapsed.inHours);
    if (elapsed.inDays < 7) return l10n.notifTimeAgoDays(elapsed.inDays);
    return MaterialLocalizations.of(context).formatMediumDate(createdAt.toLocal());
  }
}

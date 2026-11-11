import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/sheet_frame.dart';
import '../models/app_content.dart';
import '../providers/notification_providers.dart';

/// The bell: opens the notification list and shows how many notifications are
/// unread on this device. Used by the phone header, the website header and the
/// old home header, so the app and the website behave the same.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final unread = ref.watch(unreadNotificationCountProvider);
    return Semantics(
      button: true,
      label: unread > 0
          ? l10n.notificationsBellUnread(unread)
          : l10n.homeNotificationsLabel,
      excludeSemantics: true,
      child: IconButton(
        tooltip: l10n.homeNotificationsLabel,
        onPressed: () => showNotifications(context, ref),
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 9 ? '9+' : '$unread'),
          backgroundColor: context.palette.accent,
          child: const Icon(Icons.notifications_none_rounded, size: 24),
        ),
      ),
    );
  }
}

/// Opens the list (a sheet on phones, a dialog on wide screens) and marks
/// everything in it as seen. Which items were new when it was opened is kept for
/// the "새 알림" markers, so they do not vanish while you read them.
Future<void> showNotifications(BuildContext context, WidgetRef ref) {
  final seenAtOpen = ref.read(notificationsSeenProvider);
  final wide = MediaQuery.sizeOf(context).width >= Breakpoints.desktop;
  // The badge clears now; the list still marks what was new.
  Future<void>(
    () => ref.read(notificationsSeenProvider.notifier).markAllSeen(),
  );
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
          child: NotificationsPanel(seenAtOpen: seenAtOpen),
        ),
      ),
    );
  }
  return showAppSheet<void>(
    context,
    initialSize: 0.7,
    builder: (_, controller) =>
        NotificationsPanel(seenAtOpen: seenAtOpen, controller: controller),
  );
}

class NotificationsPanel extends ConsumerWidget {
  const NotificationsPanel({super.key, this.seenAtOpen, this.controller});

  /// The "last seen" moment from before this list was opened.
  final int? seenAtOpen;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final items = ref.watch(notificationItemsProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.notificationsTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.commonClose,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: items.isEmpty
              ? _Empty(controller: controller)
              : ListView.separated(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: p.border),
                  itemBuilder: (_, i) => NotificationTile(
                    item: items[i],
                    isNew: isUnreadNotification(items[i], seenAtOpen),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({this.controller});

  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 24),
        Icon(Icons.notifications_none_rounded, size: 48, color: p.textMuted),
        const SizedBox(height: 12),
        Text(
          l10n.notificationsEmpty,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.notificationsEmptyHint,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: p.textSecondary),
        ),
      ],
    );
  }
}

class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.item, this.isNew = false});

  final AppContent item;
  final bool isNew;

  Future<void> _open() async {
    final uri = Uri.tryParse(item.linkUrl ?? '');
    if (uri == null || uri.scheme != 'https') return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final time = item.time;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isNew) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: p.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n.notificationsNew,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: p.rustText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (time != null)
                Text(
                  notificationTimeLabel(
                    l10n,
                    time,
                    DateTime.now(),
                    Localizations.localeOf(context),
                  ),
                  style: TextStyle(fontSize: 12, color: p.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (item.body != null) ...[
            const SizedBox(height: 4),
            Text(
              item.body!,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: p.textSecondary,
              ),
            ),
          ],
          if (item.linkUrl != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _open,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(l10n.notificationsOpenLink),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "방금", "5분 전", "3시간 전", "2일 전", then the date (with the year only if
/// it is not this year).
String notificationTimeLabel(
  AppLocalizations l10n,
  DateTime time,
  DateTime now,
  Locale locale,
) {
  final diff = now.difference(time);
  if (diff.inSeconds < 60) return l10n.notificationsJustNow;
  if (diff.inMinutes < 60) return l10n.notificationsMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.notificationsHoursAgo(diff.inHours);
  if (diff.inDays < 7) return l10n.notificationsDaysAgo(diff.inDays);
  final tag = locale.toString();
  final local = time.toLocal();
  return (local.year == now.year ? DateFormat.MMMd(tag) : DateFormat.yMMMd(tag))
      .format(local);
}

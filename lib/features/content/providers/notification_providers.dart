import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../university/providers/university_providers.dart';
import '../models/app_content.dart';
import 'app_content_providers.dart';

/// Where this device remembers when the notification list was last opened.
const notificationsSeenPrefsKey = 'notifications_seen_ms';

/// What the bell lists: the notifications an admin published (bell only) and the
/// announcements (which also show as Home cards), for the selected campus and
/// every campus, newest first. Banners and featured restaurants are not
/// notifications. Server-side, row-level security only returns items that are on
/// and inside their dates, so everything here is meant to be shown.
final notificationItemsProvider = Provider<List<AppContent>>((ref) {
  final items = [
    for (final c in ref.watch(campusContentProvider))
      if (c.kind == AppContentKind.notification ||
          c.kind == AppContentKind.announcement)
        c,
  ];
  items.sort((a, b) {
    final ta = a.time?.millisecondsSinceEpoch ?? 0;
    final tb = b.time?.millisecondsSinceEpoch ?? 0;
    if (ta != tb) return tb.compareTo(ta); // newest first
    return a.sortOrder.compareTo(b.sortOrder);
  });
  return items;
});

/// The moment (ms since epoch) the list was last opened on this device, or null
/// if it never was. Stored locally: an unread badge is a convenience of this
/// device, not account data.
final notificationsSeenProvider = NotifierProvider<NotificationsSeen, int?>(
  NotificationsSeen.new,
);

class NotificationsSeen extends Notifier<int?> {
  @override
  int? build() =>
      ref.read(sharedPreferencesProvider).getInt(notificationsSeenPrefsKey);

  /// Everything listed right now counts as seen.
  Future<void> markAllSeen() async {
    final items = ref.read(notificationItemsProvider);
    var at = DateTime.now().millisecondsSinceEpoch;
    for (final c in items) {
      at = math.max(at, c.time?.millisecondsSinceEpoch ?? 0);
    }
    state = at;
    await ref
        .read(sharedPreferencesProvider)
        .setInt(notificationsSeenPrefsKey, at);
  }
}

/// True when [c] is newer than the last time the list was opened. An item with
/// no time is new until the list has been opened once.
bool isUnreadNotification(AppContent c, int? seenMs) {
  if (seenMs == null) return true;
  final t = c.time?.millisecondsSinceEpoch;
  return t != null && t > seenMs;
}

/// How many listed notifications are unread. Real: it is 0 when there are none,
/// and drops to 0 the moment the list is opened.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final seen = ref.watch(notificationsSeenProvider);
  return ref
      .watch(notificationItemsProvider)
      .where((c) => isUnreadNotification(c, seen))
      .length;
});

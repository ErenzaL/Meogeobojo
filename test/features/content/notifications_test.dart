import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/widgets/responsive.dart';
import 'package:meogeobojo/core/widgets/web_footer.dart';
import 'package:meogeobojo/features/content/models/app_content.dart';
import 'package:meogeobojo/features/content/providers/app_content_providers.dart';
import 'package:meogeobojo/features/content/providers/notification_providers.dart';
import 'package:meogeobojo/features/content/widgets/notification_bell.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/l10n/app_localizations_en.dart';
import 'package:meogeobojo/l10n/app_localizations_ko.dart';
import 'package:meogeobojo/l10n/app_localizations_zh.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

final _now = DateTime.now();
DateTime ago({int minutes = 0, int hours = 0, int days = 0}) =>
    _now.subtract(Duration(minutes: minutes, hours: hours, days: days));

AppContent n(
  String id, {
  AppContentKind kind = AppContentKind.notification,
  DateTime? time,
  String? body,
  String? link,
  String? universityId,
  int order = 0,
}) => AppContent(
  id: id,
  kind: kind,
  title: '제목 $id',
  body: body,
  linkUrl: link,
  universityId: universityId,
  sortOrder: order,
  time: time,
);

Future<Harness> open(
  WidgetTester tester, {
  List<AppContent> items = const [],
  Map<String, Object> storage = const {'app_language': 'ko'},
  Size size = const Size(390, 844),
  bool web = false,
}) async {
  final h = await buildHarness(
    storage: storage,
    content: FakeAppContentRepository(items),
    auth: FakeAuthGateway(user: fakeUser()),
    profiles: FakeProfileRepository(onboardingCompleted: true, nickname: '민수'),
    extraOverrides: [
      if (web) webFullWidthProvider.overrideWithValue(true),
      if (web) webFooterEnabledProvider.overrideWithValue(true),
    ],
  );
  await pumpApp(tester, h, home: const AppShell(), size: size);
  await tester.pumpAndSettle();
  return h;
}

Finder get bell => find.byIcon(Icons.notifications_none_rounded).first;

/// Text inside the open notification list (an announcement is ALSO a Home card, by design).
Finder inPanel(String text) => find.descendant(
  of: find.byType(NotificationsPanel),
  matching: find.text(text),
);

void main() {
  group('parsing', () {
    test('the bell-only kind is known; its time is the start time, else when it was last published', () {
      final a = AppContent.fromJson({
        'id': 'a',
        'kind': 'notification',
        'title': '개강 안내',
        'starts_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-10-01T00:00:00Z',
      })!;
      expect(a.kind, AppContentKind.notification);
      expect(a.time, DateTime.utc(2026, 9, 1));
      final b = AppContent.fromJson({
        'id': 'b',
        'kind': 'notification',
        'title': 'x',
        'updated_at': '2026-10-01T00:00:00Z',
      })!;
      expect(b.time, DateTime.utc(2026, 10, 1));
      expect(
        AppContent.fromJson({'id': 'c', 'kind': 'notification', 'title': 'x'})!
            .time,
        isNull,
      );
      expect(
        AppContent.fromJson({
          'id': 'd',
          'kind': 'notification',
          'title': 'x',
          'starts_at': 'not a date',
        })!.time,
        isNull,
      );
    });
  });

  group('what the bell lists', () {
    testWidgets(
      'notifications and announcements, newest first; banners and featured restaurants are not notifications',
      (tester) async {
        final h = await open(
          tester,
          items: [
            n('old', time: ago(days: 3)),
            n('new', time: ago(minutes: 5)),
            n('notice', kind: AppContentKind.announcement, time: ago(hours: 2)),
            n('banner', kind: AppContentKind.banner, time: ago(minutes: 1)),
            AppContent(
              id: 'f',
              kind: AppContentKind.featured,
              title: 'f',
              kakaoPlaceId: '1',
              time: ago(minutes: 1),
            ),
          ],
        );
        final ids = h.container
            .read(notificationItemsProvider)
            .map((c) => c.id)
            .toList();
        expect(ids, ['new', 'notice', 'old']);
      },
    );

    testWidgets('only the selected campus and the ones for every campus', (
      tester,
    ) async {
      final h = await open(
        tester,
        items: [
          n('everyone', time: ago(hours: 1)),
          n(
            'other-campus',
            universityId: 'not-this-campus',
            time: ago(hours: 2),
          ),
        ],
      );
      expect(h.container.read(notificationItemsProvider).map((c) => c.id), [
        'everyone',
      ]);
    });

    testWidgets('equal times fall back to the admin-chosen order', (
      tester,
    ) async {
      final t = ago(hours: 1);
      final h = await open(
        tester,
        items: [
          n('b', time: t, order: 2),
          n('a', time: t, order: 1),
        ],
      );
      expect(h.container.read(notificationItemsProvider).map((c) => c.id), [
        'a',
        'b',
      ]);
    });

    testWidgets(
      'bell-only notifications are NOT Home cards; announcements and banners still are',
      (tester) async {
        final h = await open(
          tester,
          items: [
            n('bellonly', time: ago(hours: 1)),
            n('notice', kind: AppContentKind.announcement, time: ago(hours: 1)),
            n('banner', kind: AppContentKind.banner, time: ago(hours: 1)),
          ],
        );
        expect(h.container.read(homeNoticesProvider).map((c) => c.id), [
          'notice',
          'banner',
        ]);
        expect(find.text('제목 bellonly'), findsNothing);
        expect(find.text('제목 notice'), findsOneWidget);
      },
    );
  });

  group('unread', () {
    test('an item is unread if it is newer than the last time the list was opened; with no history everything is', () {
      final item = n('x', time: DateTime.fromMillisecondsSinceEpoch(1000));
      expect(isUnreadNotification(item, null), isTrue);
      expect(isUnreadNotification(item, 500), isTrue);
      expect(isUnreadNotification(item, 1000), isFalse);
      expect(isUnreadNotification(item, 2000), isFalse);
      expect(
        isUnreadNotification(n('notime'), 2000),
        isFalse,
      ); // no time: not "new" once the list was opened
      expect(isUnreadNotification(n('notime'), null), isTrue);
    });

    testWidgets(
      'the count is real: 0 with nothing, and only newer items after the last visit',
      (tester) async {
        final h = await open(tester);
        expect(h.container.read(unreadNotificationCountProvider), 0);

        final seen = ago(hours: 5).millisecondsSinceEpoch;
        final h2 = await open(
          tester,
          storage: {'app_language': 'ko', notificationsSeenPrefsKey: seen},
          items: [
            n('read', time: ago(days: 1)),
            n('unread1', time: ago(hours: 1)),
            n('unread2', time: ago(minutes: 10)),
          ],
        );
        expect(h2.container.read(unreadNotificationCountProvider), 2);
      },
    );

    testWidgets(
      'marking the list as seen persists on this device and clears the count',
      (tester) async {
        final h = await open(
          tester,
          items: [
            n('a', time: ago(hours: 1)),
            n('b', time: ago(hours: 2)),
          ],
        );
        expect(h.container.read(unreadNotificationCountProvider), 2);
        await h.container
            .read(notificationsSeenProvider.notifier)
            .markAllSeen();
        expect(h.container.read(unreadNotificationCountProvider), 0);
        expect(h.sp.getInt(notificationsSeenPrefsKey), isNotNull);
      },
    );
  });

  group('the bell on a phone', () {
    testWidgets(
      'no badge when there is nothing; the list says so and there is no "coming soon" snackbar',
      (tester) async {
        await open(tester);
        expect(find.byType(Badge), findsOneWidget);
        expect(
          tester.widget<Badge>(find.byType(Badge)).isLabelVisible,
          isFalse,
        );
        await tester.tap(bell);
        await tester.pumpAndSettle();
        expect(find.text('알림'), findsWidgets); // the title
        expect(find.text('새 알림이 없어요'), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets(
      'the badge shows the unread count; opening the list shows the items, marks new ones, and clears the badge',
      (tester) async {
        await open(
          tester,
          items: [
            n(
              'a',
              time: ago(minutes: 5),
              body: '개강을 맞아 학식이 바뀌었어요.',
              link: 'https://example.org/notice',
            ),
            n('b', time: ago(days: 2)),
            n('c', kind: AppContentKind.announcement, time: ago(hours: 3)),
          ],
        );
        final badge = tester.widget<Badge>(find.byType(Badge));
        expect(badge.isLabelVisible, isTrue);
        expect((badge.label! as Text).data, '3');
        expect(find.bySemanticsLabel('알림, 안 읽은 알림 3개'), findsOneWidget);

        await tester.tap(bell);
        await tester.pumpAndSettle();
        // newest first
        final titles = ['제목 a', '제목 c', '제목 b'];
        final ys = [for (final t in titles) tester.getTopLeft(inPanel(t)).dy];
        expect(ys, [...ys]..sort());
        expect(find.text('개강을 맞아 학식이 바뀌었어요.'), findsOneWidget);
        expect(find.text('5분 전'), findsOneWidget);
        expect(find.text('3시간 전'), findsOneWidget);
        expect(find.text('2일 전'), findsOneWidget);
        expect(find.text('새 알림'), findsNWidgets(3)); // all were new
        expect(find.text('자세히 보기'), findsOneWidget); // only the one with a link

        // close and look at the bell again: nothing unread any more
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Badge>(find.byType(Badge)).isLabelVisible,
          isFalse,
        );

        // opening again: the same items, none marked new
        await tester.tap(bell);
        await tester.pumpAndSettle();
        expect(find.text('제목 a'), findsOneWidget);
        expect(find.text('새 알림'), findsNothing);
      },
    );

    testWidgets('a notification published later raises the badge again', (
      tester,
    ) async {
      final h = await open(tester, items: [n('a', time: ago(hours: 1))]);
      await h.container.read(notificationsSeenProvider.notifier).markAllSeen();
      await tester.pump();
      expect(h.container.read(unreadNotificationCountProvider), 0);
      final repo = h.container.read(
        appContentRepositoryProvider,
      ) as FakeAppContentRepository;
      repo.items = [
        n('a', time: ago(hours: 1)),
        n('fresh', time: DateTime.now().add(const Duration(minutes: 1))),
      ];
      h.container.invalidate(appContentProvider);
      await tester.pumpAndSettle();
      expect(h.container.read(unreadNotificationCountProvider), 1);
    });

    testWidgets('a long badge count shows 9+', (tester) async {
      await open(
        tester,
        items: [
          for (var i = 0; i < 12; i++) n('x$i', time: ago(minutes: i + 1)),
        ],
      );
      expect(
        (tester.widget<Badge>(find.byType(Badge)).label! as Text).data,
        '9+',
      );
    });
  });

  group('the bell on the website', () {
    testWidgets(
      'the desktop header has the bell too, and it opens the list as a dialog',
      (tester) async {
        await open(
          tester,
          web: true,
          size: const Size(1280, 800),
          items: [n('a', time: ago(hours: 1), body: '웹에서도 보여요')],
        );
        expect(bell, findsOneWidget);
        expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
        await tester.tap(bell);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('제목 a'), findsOneWidget);
        expect(find.text('웹에서도 보여요'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(
          tester.widget<Badge>(find.byType(Badge)).isLabelVisible,
          isFalse,
        );
      },
    );

    testWidgets(
      'on a tablet width (below the desktop breakpoint) the phone layout and its bell are used',
      (tester) async {
        await open(
          tester,
          size: const Size(768, 1024),
          items: [n('a', time: ago(hours: 1))],
        );
        await tester.tap(bell);
        await tester.pumpAndSettle();
        expect(find.text('제목 a'), findsOneWidget);
      },
    );
  });

  group('wording', () {
    test('relative times and labels in Korean, English and Chinese', () {
      final ko = AppLocalizationsKo();
      final en = AppLocalizationsEn();
      final zh = AppLocalizationsZh();
      String label(dynamic l, Duration d, [String lang = 'ko']) =>
          notificationTimeLabel(l, _now.subtract(d), _now, Locale(lang));
      expect(label(ko, const Duration(seconds: 10)), '방금');
      expect(label(ko, const Duration(minutes: 7)), '7분 전');
      expect(label(en, const Duration(hours: 5), 'en'), '5 h ago');
      expect(label(zh, const Duration(days: 3), 'zh'), '3 天前');
      expect(en.notificationsBellUnread(2), 'Notifications, 2 unread');
      expect(zh.notificationsTitle, '通知');
    });

    test('older than a week shows the date; with the year only if it is not this year', () {
      final ko = AppLocalizationsKo();
      final recent = DateTime(_now.year, 1, 2);
      final older = DateTime(_now.year - 1, 5, 6);
      final a = notificationTimeLabel(
        ko,
        recent,
        DateTime(_now.year, 6, 1),
        const Locale('ko'),
      );
      final b = notificationTimeLabel(
        ko,
        older,
        DateTime(_now.year, 6, 1),
        const Locale('ko'),
      );
      expect(a, contains('1월'));
      expect(a, isNot(contains('${_now.year}')));
      expect(b, contains('${_now.year - 1}'));
    });

    testWidgets('English UI: title and empty state', (tester) async {
      await open(tester, storage: const {'app_language': 'en'});
      await tester.tap(bell);
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsWidgets);
      expect(find.text('No new notifications'), findsOneWidget);
    });
  });

  testWidgets(
    'the panel can be built on its own and lists nothing for nobody',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      expect(find.byType(NotificationsPanel), findsNothing);
    },
  );
}

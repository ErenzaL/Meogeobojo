import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/widgets/web_footer.dart';
import 'package:meogeobojo/features/content/models/app_content.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

const _tabs = {
  'home': ShellTabs.home,
  'community': ShellTabs.community,
  'missions': ShellTabs.missions,
  'profile': ShellTabs.profile,
};

Future<void> open(
  WidgetTester tester, {
  required int tab,
  bool footer = true,
  Size size = const Size(1440, 900),
  String lang = 'ko',
  List<AppContent> notices = const [],
}) async {
  final h = await buildHarness(
    storage: {'app_language': lang},
    content: FakeAppContentRepository(notices),
    extraOverrides: [webFooterEnabledProvider.overrideWithValue(footer)],
  );
  await pumpApp(tester, h, home: const AppShell(), size: size);
  h.container.read(shellTabProvider.notifier).select(tab);
  await tester.pumpAndSettle();
}

Future<void> toFooter(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('web-footer')),
    600,
    // the page's own (vertical) scroll view, not the header's sideways tab strip
    scrollable: find
        .descendant(
          of: find.byType(AppShell),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axis == Axis.vertical,
          ),
        )
        .hitTestable()
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the website footer', () {
    for (final e in _tabs.entries) {
      testWidgets('${e.key}: shown once at the end of the page on the web', (
        tester,
      ) async {
        await open(tester, tab: e.value);
        await toFooter(tester);
        expect(find.byKey(const ValueKey('web-footer')), findsOneWidget);
        expect(find.text('먹어보조 소개'), findsOneWidget);
        expect(find.text('공지사항'), findsOneWidget);
        expect(find.text('문의 및 제안'), findsOneWidget);
        expect(find.text('서비스 정보'), findsOneWidget);
        expect(find.textContaining('© '), findsOneWidget);
      });

      testWidgets('${e.key}: never in the native apps', (tester) async {
        await open(tester, tab: e.value, footer: false);
        expect(find.byKey(const ValueKey('web-footer')), findsNothing);
      });
    }

    testWidgets(
      'a short page: the footer sits at the very bottom of the window, not under the content',
      (tester) async {
        // 1440 x 2400: 밥수다 (an empty feed) is much shorter than the window
        await open(
          tester,
          tab: ShellTabs.community,
          size: const Size(1440, 2400),
        );
        final box = tester.getRect(find.byKey(const ValueKey('web-footer')));
        expect(box.bottom, closeTo(2400, 1));
        final feed = tester.getBottomLeft(find.text('학교 근처 이야기'));
        expect(
          box.top,
          greaterThan(feed.dy + 200),
        ); // a real gap between the content and the footer
      },
    );

    testWidgets(
      'a long page: the footer follows the content (reached by scrolling)',
      (tester) async {
        await open(tester, tab: ShellTabs.home, size: const Size(1440, 700));
        expect(find.byKey(const ValueKey('web-footer')), findsNothing);
        await toFooter(tester);
        expect(find.byKey(const ValueKey('web-footer')), findsOneWidget);
      },
    );

    testWidgets(
      'lists only real published announcements; none means an honest line',
      (tester) async {
        await open(tester, tab: ShellTabs.community);
        await toFooter(tester);
        expect(find.text('등록된 공지가 없어요.'), findsOneWidget);

        await open(
          tester,
          tab: ShellTabs.community,
          notices: const [
            AppContent(
              id: 'a',
              kind: AppContentKind.announcement,
              title: '점검 안내',
            ),
            AppContent(
              id: 'b',
              kind: AppContentKind.banner,
              title: '배너는 공지가 아니에요',
            ),
          ],
        );
        await toFooter(tester);
        expect(find.text('점검 안내'), findsOneWidget);
        expect(find.text('배너는 공지가 아니에요'), findsNothing);
        expect(find.text('등록된 공지가 없어요.'), findsNothing);
      },
    );

    testWidgets(
      'no contact channel configured: it says so, there is no invented address or dead button',
      (tester) async {
        await open(tester, tab: ShellTabs.profile);
        await toFooter(tester);
        expect(
          find.byKey(const ValueKey('footer-contact-not-ready')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('footer-feedback')), findsNothing);
        expect(find.textContaining('@'), findsNothing);
      },
    );

    testWidgets(
      'the legal links are the existing honest ones (not published = says so)',
      (tester) async {
        await open(tester, tab: ShellTabs.home);
        await toFooter(tester);
        expect(find.text('이용약관'), findsOneWidget);
        expect(find.text('개인정보처리방침'), findsOneWidget);
      },
    );

    testWidgets('the about link opens the service introduction', (
      tester,
    ) async {
      await open(tester, tab: ShellTabs.community);
      await toFooter(tester);
      await tester.tap(find.byKey(const ValueKey('footer-about')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    for (final size in const [
      Size(390, 844),
      Size(768, 1024),
      Size(1024, 768),
      Size(1440, 900),
      Size(1920, 1080),
    ]) {
      for (final lang in const ['ko', 'en', 'zh-Hans']) {
        testWidgets('no overflow: $lang ${size.width.toInt()}px, large text', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = 1.4;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await open(tester, tab: ShellTabs.community, size: size, lang: lang);
          await toFooter(tester);
          expect(tester.takeException(), isNull);
          // the four columns are in a row on desktop and stacked below that
          final about = tester.getTopLeft(
            find.byIcon(Icons.restaurant_menu_rounded),
          );
          final notices = tester.getTopLeft(
            find.byIcon(Icons.campaign_outlined),
          );
          if (size.width >= 1024) {
            expect(notices.dy, about.dy);
            expect(notices.dx, greaterThan(about.dx));
          } else if (size.width < 600) {
            expect(notices.dy, greaterThan(about.dy));
          }
        });
      }
    }
  });
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/l10n/l10n.dart';
import 'package:meogeobojo/core/theme/app_palette.dart';
import 'package:meogeobojo/core/theme/app_theme.dart';
import 'package:meogeobojo/features/community/screens/community_screen.dart';
import 'package:meogeobojo/features/home/screens/home_screen.dart';
import 'package:meogeobojo/features/home/widgets/cafeteria_card.dart';
import 'package:meogeobojo/features/map/screens/map_screen.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/navigation/widgets/floating_nav_bar.dart';
import 'package:meogeobojo/features/profile/screens/profile_screen.dart';
import 'package:meogeobojo/features/missions/screens/mission_screen.dart';

import '../../support/harness.dart';

double _lin(int c) {
  final s = c / 255;
  return s <= 0.03928
      ? s / 12.92
      : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color c) =>
    0.2126 * _lin((c.r * 255).round()) +
    0.7152 * _lin((c.g * 255).round()) +
    0.0722 * _lin((c.b * 255).round());

double contrast(Color a, Color b) {
  final hi = math.max(_luminance(a), _luminance(b));
  final lo = math.min(_luminance(a), _luminance(b));
  return (hi + 0.05) / (lo + 0.05);
}

/// Opaque colour of [fg] (with alpha) laid over [bg].
Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

void setSafeArea(WidgetTester tester, {double bottom = 0, double top = 47}) {
  final fv = FakeViewPadding(top: top * 3, bottom: bottom * 3);
  tester.view.padding = fv;
  tester.view.viewPadding = fv;
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
}

Rect navRect(WidgetTester tester) =>
    tester.getRect(find.byType(FloatingNavBar));

Future<Harness> openShell(
  WidgetTester tester, {
  String lang = 'ko',
  Size size = const Size(390, 844),
  double safeBottom = 34,
}) async {
  final h = await buildHarness(storage: {'app_language': lang});
  setSafeArea(tester, bottom: safeBottom);
  await pumpApp(tester, h, home: const AppShell(), size: size);
  return h;
}

void main() {
  group('flat bottom bar geometry (V5)', () {
    testWidgets('full width, flush with the bottom edge, hairline on top', (
      tester,
    ) async {
      await openShell(tester);
      final r = navRect(tester);
      expect(r.left, 0);
      expect(r.right, 390);
      expect(r.bottom, 844, reason: 'the bar runs to the screen edge');
      final bar = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(FloatingNavBar),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);
      expect(bar.borderRadius, isNull, reason: 'square, not a capsule');
      expect(bar.boxShadow, isNull, reason: 'no shadow');
      expect(bar.color, AppPalette.light.navSurface);
      expect((bar.border as Border).top.color, AppPalette.light.navBorder);
      expect(
        find.descendant(
          of: find.byType(FloatingNavBar),
          matching: find.byType(BackdropFilter),
        ),
        findsNothing,
        reason: 'no blur',
      );
    });

    for (final (inset, label) in [
      (34.0, 'iOS home indicator'),
      (24.0, 'Android gesture bar'),
      (0.0, 'no inset'),
    ]) {
      testWidgets('64px of tabs above the device inset: $label', (
        tester,
      ) async {
        await openShell(tester, safeBottom: inset);
        final r = navRect(tester);
        expect(r.height, closeTo(64 + inset, 0.5));
        expect(r.bottom, 844);
        // Icons and labels stay above the inset.
        final label0 = tester.getRect(
          find.descendant(
            of: find.byType(FloatingNavBar),
            matching: find.text('홈'),
          ),
        );
        expect(label0.bottom, lessThanOrEqualTo(844 - inset));
      });
    }

    testWidgets('small screens: no overflow at 320x568, even at 1.6x text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openShell(tester, size: const Size(320, 568), safeBottom: 0);
      expect(tester.takeException(), isNull);
      expect(navRect(tester).right, 320);
    });
  });

  group('five tabs', () {
    testWidgets('destinations are unchanged', (tester) async {
      final h = await openShell(tester);
      Future<void> go(String label, Type screen) async {
        await tester.tap(
          find.descendant(
            of: find.byType(FloatingNavBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(screen), findsOneWidget, reason: label);
      }

      expect(find.byType(HomeScreen), findsOneWidget);
      await go('밥수다', CommunityScreen);
      expect(h.container.read(shellTabProvider), ShellTabs.community);
      await go('지도', MapScreen);
      expect(h.container.read(shellTabProvider), ShellTabs.map);
      await go('미션', MissionScreen);
      expect(h.container.read(shellTabProvider), ShellTabs.missions);
      await go('MY', ProfileScreen);
      expect(h.container.read(shellTabProvider), ShellTabs.profile);
      await go('홈', HomeScreen);
      expect(h.container.read(shellTabProvider), ShellTabs.home);
    });

    testWidgets('tapping the ICON or the LABEL selects the tab', (
      tester,
    ) async {
      final h = await openShell(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(FloatingNavBar),
          matching: find.byIcon(Icons.forum_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.container.read(shellTabProvider), ShellTabs.community);
      await tester.tap(
        find.descendant(
          of: find.byType(FloatingNavBar),
          matching: find.text('미션'),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.container.read(shellTabProvider), ShellTabs.missions);
    });

    testWidgets('screens are not recreated on tap; state of each tab is kept', (
      tester,
    ) async {
      await openShell(tester);
      final homeElement = tester.element(find.byType(HomeScreen));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      final scrollBefore = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      expect(scrollBefore, greaterThan(0));

      for (final label in ['밥수다', '미션', 'MY', '홈']) {
        await tester.tap(
          find.descendant(
            of: find.byType(FloatingNavBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(
        tester.element(find.byType(HomeScreen)),
        same(homeElement),
        reason: 'same element: not rebuilt from scratch',
      );
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        scrollBefore,
        reason: 'Home scroll position preserved',
      );
    });

    testWidgets('exactly one navigation bar, and no legacy bar', (
      tester,
    ) async {
      await openShell(tester);
      expect(find.byType(FloatingNavBar), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      for (final s in tester.widgetList<Scaffold>(find.byType(Scaffold))) {
        expect(
          s.bottomNavigationBar,
          isNull,
          reason: 'no Scaffold-attached bottom bar',
        );
      }
    });

    testWidgets('five equally wide tabs', (tester) async {
      await openShell(tester);
      final widths = [
        for (final l in ['홈', '밥수다', '지도', '미션', 'MY'])
          tester
              .getRect(
                find
                    .ancestor(of: find.text(l), matching: find.byType(InkWell))
                    .first,
              )
              .width,
      ];
      for (final w in widths) {
        expect(w, closeTo(widths.first, 0.5));
      }
      expect(
        widths.first,
        greaterThanOrEqualTo(48),
        reason: 'comfortable touch target width',
      );
    });
  });

  group('content is never hidden behind the bar', () {
    testWidgets('Home scrolls fully above the bar', (tester) async {
      await openShell(tester);
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final end = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(end.extentAfter, 0, reason: 'scrolled to the very end');
      final last = tester.getRect(find.byType(CafeteriaCard));
      expect(
        last.bottom,
        lessThanOrEqualTo(navRect(tester).top),
        reason: 'last section sits above the capsule',
      );
    });

    testWidgets('tab screens receive the bar footprint as bottom padding', (
      tester,
    ) async {
      await openShell(tester);
      final context = tester.element(find.byType(HomeScreen));
      final padding = MediaQuery.paddingOf(context).bottom;
      final r = navRect(tester);
      expect(
        padding,
        greaterThanOrEqualTo(844 - r.top),
        reason: 'covers the whole capsule + margin',
      );
    });
  });

  group('keyboard, sheets and dialogs', () {
    testWidgets(
      'the bar steps aside while the keyboard is open and ignores taps',
      (tester) async {
        final h = await openShell(tester);
        tester.view.viewInsets = FakeViewPadding(bottom: 300 * 3);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<AnimatedOpacity>(
                find
                    .ancestor(
                      of: find.byType(FloatingNavBar),
                      matching: find.byType(AnimatedOpacity),
                    )
                    .first,
              )
              .opacity,
          0,
        );
        await tester.tap(find.text('MY'), warnIfMissed: false);
        await tester.pump();
        expect(h.container.read(shellTabProvider), ShellTabs.home);

        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<AnimatedOpacity>(
                find
                    .ancestor(
                      of: find.byType(FloatingNavBar),
                      matching: find.byType(AnimatedOpacity),
                    )
                    .first,
              )
              .opacity,
          1,
        );
      },
    );

    testWidgets(
      'a bottom sheet / dialog is drawn above the bar and blocks it',
      (tester) async {
        final h = await openShell(tester);
        await tester.tap(find.text('정문 기준')); // 출발 위치 sheet
        await tester.pumpAndSettle();
        expect(find.text('어디서 출발하나요?'), findsOneWidget);
        // The bar is part of the shell route underneath the modal route.
        await tester.tapAt(navRect(tester).center + const Offset(120, 0));
        await tester.pump();
        expect(
          h.container.read(shellTabProvider),
          ShellTabs.home,
          reason: 'taps under a modal never reach the bar',
        );
      },
    );
  });

  group('labels in all languages', () {
    for (final (lang, labels) in [
      ('ko', ['홈', '밥수다', '지도', '미션', 'MY']),
      ('en', ['Home', 'Food Talk', 'Map', 'Missions', 'My']),
      ('zh-Hans', ['首页', '美食交流', '地图', '任务', '我的']),
    ]) {
      testWidgets('$lang labels fit, one implementation', (tester) async {
        await openShell(
          tester,
          lang: lang,
          size: const Size(320, 568),
          safeBottom: 0,
        );
        for (final l in labels) {
          expect(
            find.descendant(
              of: find.byType(FloatingNavBar),
              matching: find.text(l),
            ),
            findsOneWidget,
            reason: l,
          );
        }
        expect(tester.takeException(), isNull);
        expect(find.byType(FloatingNavBar), findsOneWidget);
      });
    }
  });

  group('accessibility', () {
    testWidgets(
      'semantics: button + label + selected state, tab bar container',
      (tester) async {
        final handle = tester.ensureSemantics();
        final h = await openShell(tester);
        expect(
          tester.getSemantics(find.bySemanticsLabel('홈').first),
          isSemantics(
            label: '홈',
            isButton: true,
            isSelected: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('지도').first),
          isSemantics(
            label: '지도',
            isButton: true,
            isSelected: false,
            hasTapAction: true,
          ),
        );
        await tester.tap(
          find.descendant(
            of: find.byType(FloatingNavBar),
            matching: find.text('MY'),
          ),
        );
        await tester.pumpAndSettle();
        expect(h.container.read(shellTabProvider), ShellTabs.profile);
        expect(
          tester.getSemantics(find.bySemanticsLabel('MY').first),
          isSemantics(label: 'MY', isSelected: true),
        );
        handle.dispose();
      },
    );

    testWidgets('reduced motion disables the transition', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await openShell(tester);
      final c = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(FloatingNavBar),
          matching: find.byType(AnimatedContainer),
        ),
      );
      for (final a in c) {
        expect(a.duration, Duration.zero);
      }
    });

    testWidgets('normal motion: a smooth 180-250 ms transition', (
      tester,
    ) async {
      await openShell(tester);
      final c = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(FloatingNavBar),
          matching: find.byType(AnimatedContainer),
        ),
      );
      for (final a in c) {
        expect(a.duration.inMilliseconds, inInclusiveRange(180, 250));
      }
    });

    testWidgets('the active tab is a filled icon with a bold label (V5)', (
      tester,
    ) async {
      await openShell(tester);
      FontWeight? weightOf(String label) => tester
          .widget<AnimatedDefaultTextStyle>(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byType(AnimatedDefaultTextStyle),
                )
                .first,
          )
          .style
          .fontWeight;
      IconData iconIn(String label) => tester
          .widget<Icon>(
            find.descendant(
              of: find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(InkWell),
                  )
                  .first,
              matching: find.byType(Icon),
            ),
          )
          .icon!;

      expect(weightOf('홈'), FontWeight.w700);
      expect(weightOf('MY'), FontWeight.w500);
      expect(iconIn('홈'), Icons.home_rounded);
      expect(iconIn('MY'), Icons.person_outline_rounded);
      await tester.tap(find.text('MY'));
      await tester.pumpAndSettle();
      expect(weightOf('MY'), FontWeight.w700);
      expect(iconIn('MY'), Icons.person_rounded);
      expect(weightOf('홈'), FontWeight.w500);
    });
  });

  group('light and dark appearance', () {
    Future<void> pumpBar(WidgetTester tester, Brightness b) async {
      setSafeArea(tester, bottom: 34);
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: b == Brightness.dark ? buildDarkTheme() : buildLightTheme(),
          locale: const Locale('ko'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: FloatingNavBar(
                    index: 2,
                    onTap: (_) {},
                    metrics: const FloatingNavMetrics(
                      height: 98,
                      bottomMargin: 0,
                      sideMargin: 0,
                      contentGap: 0,
                      safeBottom: 34,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Color? textColor(WidgetTester tester, String label) =>
        DefaultTextStyle.of(tester.element(find.text(label))).style.color;

    for (final (name, b, p) in [
      ('light', Brightness.light, AppPalette.light),
      ('dark', Brightness.dark, AppPalette.dark),
    ]) {
      testWidgets('$name: V5 surface, idle and selected colours', (
        tester,
      ) async {
        await pumpBar(tester, b);
        final surface = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(FloatingNavBar),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((d) => d.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.border != null);
        expect(surface.color, p.navSurface);
        expect((surface.border as Border).top.color, p.navBorder);
        expect(textColor(tester, '홈'), p.navIdle);
        expect(textColor(tester, '밥수다'), p.navSelectedFg);
      });

      test('$name: idle and selected labels reach WCAG AA on the bar', () {
        expect(contrast(p.navIdle, p.navSurface), greaterThanOrEqualTo(4.5));
        expect(
          contrast(p.navSelectedFg, p.navSurface),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });
}

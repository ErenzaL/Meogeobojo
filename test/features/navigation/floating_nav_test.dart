import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/l10n/l10n.dart';
import 'package:meogeobojo/core/theme/app_palette.dart';
import 'package:meogeobojo/core/theme/app_theme.dart';
import 'package:meogeobojo/features/community/screens/community_screen.dart';
import 'package:meogeobojo/features/home/screens/home_screen.dart';
import 'package:meogeobojo/features/home/widgets/menu_section.dart';
import 'package:meogeobojo/features/map/screens/map_screen.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/navigation/widgets/floating_nav_bar.dart';
import 'package:meogeobojo/features/profile/screens/profile_screen.dart';
import 'package:meogeobojo/features/records/screens/records_screen.dart';

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
  group('floating capsule geometry', () {
    testWidgets(
      'floats: clear of the left, right and bottom edges, fully rounded',
      (tester) async {
        await openShell(tester);
        final r = navRect(tester);
        expect(r.left, 16, reason: 'side margin');
        expect(r.right, 390 - 16);
        expect(
          844 - r.bottom,
          greaterThanOrEqualTo(12),
          reason: 'floats above the bottom edge',
        );
        expect(r.height, inInclusiveRange(58, 72), reason: 'compact');

        final clip = tester.widget<ClipRRect>(
          find
              .descendant(
                of: find.byType(FloatingNavBar),
                matching: find.byType(ClipRRect),
              )
              .first,
        );
        final radius = (clip.borderRadius as BorderRadius).topLeft.x;
        expect(
          radius,
          greaterThanOrEqualTo(r.height / 2),
          reason: 'capsule / pill shape',
        );
      },
    );

    testWidgets(
      'has a border, a soft shadow and a restrained blur limited to the bar',
      (tester) async {
        await openShell(tester);
        final deco = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(FloatingNavBar),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((d) => d.decoration)
            .whereType<BoxDecoration>()
            .toList();
        expect(
          deco.any((d) => d.border != null),
          isTrue,
          reason: 'subtle border',
        );
        expect(
          deco.any((d) => (d.boxShadow ?? const []).isNotEmpty),
          isTrue,
          reason: 'shadow',
        );

        final blur = find.descendant(
          of: find.byType(FloatingNavBar),
          matching: find.byType(BackdropFilter),
        );
        expect(blur, findsOneWidget);
        final b = tester.getRect(blur);
        expect(
          b.width,
          lessThan(390),
          reason: 'blur is confined to the capsule, not full-screen',
        );
        expect(b.height, lessThan(80));
        // Surface stays ~93% opaque: legible even where nothing can be blurred.
        final surface = deco
            .firstWhere((d) => d.color != null && d.border != null)
            .color!;
        expect(surface.a, inInclusiveRange(0.88, 0.96));
      },
    );

    testWidgets(
      'safe area: above the iOS home indicator, Android gesture bar and with no inset',
      (tester) async {
        for (final (safe, label) in [
          (34.0, 'iPhone home indicator'),
          (24.0, 'Android gesture bar'),
          (0.0, 'no inset'),
        ]) {
          final h = await buildHarness();
          setSafeArea(tester, bottom: safe);
          await pumpApp(tester, h, home: const AppShell());
          final r = navRect(tester);
          final gap = 844 - r.bottom;
          expect(
            gap,
            greaterThanOrEqualTo(12),
            reason: '$label: visible spacing',
          );
          if (safe > 0) {
            // the indicator / gesture pill lives in the bottom ~13 px of the inset
            expect(
              gap,
              greaterThan(14),
              reason: '$label: never on the indicator',
            );
          }
          expect(tester.takeException(), isNull, reason: label);
        }
      },
    );

    testWidgets('small screens: no overflow at 320x568, even at 1.6x text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openShell(tester, size: const Size(320, 568), safeBottom: 0);
      expect(tester.takeException(), isNull);
      final r = navRect(tester);
      expect(r.left, 16);
      expect(r.right, 304);
      expect(
        r.height,
        lessThanOrEqualTo(70),
        reason: 'bar stays compact (labels stop scaling at 1.3x)',
      );
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
      await go('기록', RecordsScreen);
      expect(h.container.read(shellTabProvider), ShellTabs.records);
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
          matching: find.byIcon(Icons.groups_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.container.read(shellTabProvider), ShellTabs.community);
      await tester.tap(
        find.descendant(
          of: find.byType(FloatingNavBar),
          matching: find.text('기록'),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.container.read(shellTabProvider), ShellTabs.records);
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

      for (final label in ['밥수다', '기록', 'MY', '홈']) {
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
        for (final l in ['홈', '밥수다', '지도', '기록', 'MY'])
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
      final last = tester.getRect(find.byType(MenuSection));
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
        await tester.tap(find.text('순천향대학교').first); // university sheet
        await tester.pumpAndSettle();
        expect(find.text('학교 선택'), findsOneWidget);
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
      ('ko', ['홈', '밥수다', '지도', '기록', 'MY']),
      ('en', ['Home', 'Food Talk', 'Map', 'Records', 'My']),
      ('zh-Hans', ['首页', '美食交流', '地图', '记录', '我的']),
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

    testWidgets('the selected tab animates its background', (tester) async {
      await openShell(tester);
      Color? bgOf(String label) {
        final box = tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        return (box.decoration as BoxDecoration?)?.color;
      }

      expect(bgOf('홈'), AppPalette.light.navSelectedBg);
      expect(bgOf('MY'), Colors.transparent);
      await tester.tap(find.text('MY'));
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump(const Duration(milliseconds: 200));
      expect(bgOf('MY'), AppPalette.light.navSelectedBg);
      expect(bgOf('홈'), Colors.transparent);
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
                  left: 16,
                  right: 16,
                  bottom: 32,
                  child: FloatingNavBar(
                    index: 2,
                    onTap: (_) {},
                    metrics: const FloatingNavMetrics(
                      height: 62,
                      bottomMargin: 32,
                      sideMargin: 16,
                      contentGap: 12,
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

    Color? bg(WidgetTester tester, String label) =>
        (tester
                    .widget<AnimatedContainer>(
                      find
                          .ancestor(
                            of: find.text(label),
                            matching: find.byType(AnimatedContainer),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration?)
            ?.color;

    Color? textColor(WidgetTester tester, String label) =>
        tester.widget<Text>(find.text(label)).style?.color ??
        DefaultTextStyle.of(tester.element(find.text(label))).style.color;

    testWidgets(
      'light: white translucent surface, charcoal idle, peach + deep-orange selected',
      (tester) async {
        await pumpBar(tester, Brightness.light);
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
        expect(surface.color, AppPalette.light.navSurface);
        expect(
          (surface.border as Border).top.color,
          AppPalette.light.navBorder,
        );
        expect(bg(tester, '지도'), AppPalette.light.navSelectedBg);
        expect(bg(tester, '홈'), Colors.transparent);
        expect(textColor(tester, '홈'), AppPalette.light.navIdle);
      },
    );

    testWidgets(
      'dark: #292929 elevated translucent surface, light-gray idle, muted warm selected',
      (tester) async {
        await pumpBar(tester, Brightness.dark);
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
        expect(surface.color, AppPalette.dark.navSurface);
        expect(AppPalette.dark.navSurface.toARGB32() & 0xFFFFFF, 0x292929);
        expect((surface.border as Border).top.color, AppPalette.dark.navBorder);
        expect(bg(tester, '지도'), AppPalette.dark.navSelectedBg);
        expect(textColor(tester, '홈'), AppPalette.dark.navIdle);
      },
    );

    test(
      'contrast: every text/icon colour reaches WCAG AA (4.5:1) on its surface',
      () {
        // light: bar over white and over the ivory page background
        for (final page in [Colors.white, AppPalette.light.background]) {
          final surface = over(AppPalette.light.navSurface, page);
          expect(
            contrast(AppPalette.light.navIdle, surface),
            greaterThanOrEqualTo(4.5),
            reason: 'idle on $page',
          );
          final selectedBg = AppPalette.light.navSelectedBg;
          expect(
            contrast(AppPalette.light.navSelectedFg, selectedBg),
            greaterThanOrEqualTo(4.5),
            reason: 'selected label',
          );
        }
        // dark: bar over near-black and over mid-gray content
        for (final page in [const Color(0xFF121212), const Color(0xFF3A3A3A)]) {
          final surface = over(AppPalette.dark.navSurface, page);
          expect(
            contrast(AppPalette.dark.navIdle, surface),
            greaterThanOrEqualTo(4.5),
            reason: 'idle on $page',
          );
          expect(
            contrast(
              AppPalette.dark.navSelectedFg,
              AppPalette.dark.navSelectedBg,
            ),
            greaterThanOrEqualTo(4.5),
            reason: 'selected label',
          );
          expect(
            contrast(AppPalette.dark.navIdle, AppPalette.dark.navSelectedBg),
            greaterThanOrEqualTo(4.5),
            reason: 'idle on pill',
          );
        }
      },
    );
  });
}

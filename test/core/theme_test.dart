import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/app.dart';
import 'package:meogeobojo/core/l10n/app_language.dart';
import 'package:meogeobojo/core/l10n/language_controller.dart';
import 'package:meogeobojo/core/theme/app_palette.dart';
import 'package:meogeobojo/core/theme/app_theme.dart';
import 'package:meogeobojo/core/theme/theme_controller.dart';
import 'package:meogeobojo/features/auth/providers/auth_providers.dart';
import 'package:meogeobojo/features/auth/screens/login_screen.dart';
import 'package:meogeobojo/features/campus_meals/models/campus_meal_models.dart';
import 'package:meogeobojo/features/campus_meals/providers/campus_meal_providers.dart';
import 'package:meogeobojo/features/campus_meals/screens/campus_meal_screen.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/restaurants/screens/restaurant_category_screen.dart';
import 'package:meogeobojo/features/restaurants/widgets/restaurant_list_tile.dart';
import 'package:meogeobojo/features/settings/screens/appearance_screen.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

// ---------------------------------------------------------------- contrast
double _lin(num c) {
  final s = c / 255;
  return s <= 0.03928
      ? s / 12.92
      : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double luminance(Color c) =>
    0.2126 * _lin(c.r * 255) +
    0.7152 * _lin(c.g * 255) +
    0.0722 * _lin(c.b * 255);

double contrast(Color a, Color b) {
  final hi = math.max(luminance(a), luminance(b));
  final lo = math.min(luminance(a), luminance(b));
  return (hi + 0.05) / (lo + 0.05);
}

// ------------------------------------------------------------ pixel probing
/// Colour of the rendered pixel at [logical] (top-left origin), taken from the
/// real paint, so it proves what the user actually sees.
Future<Color> pixelAt(WidgetTester tester, Offset logical) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final color = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = image.width;
    final i = (logical.dy.round() * w + logical.dx.round()) * 4;
    final b = data!.buffer.asUint8List();
    image.dispose();
    return Color.fromARGB(b[i + 3], b[i], b[i + 1], b[i + 2]);
  });
  return color!;
}

/// The page background: far-left gutter, where no card or section reaches.
Future<Set<int>> gutterColors(WidgetTester tester, {double x = 4}) async {
  final out = <int>{};
  for (final y in [150.0, 330.0, 480.0, 600.0]) {
    out.add((await pixelAt(tester, Offset(x, y))).toARGB32());
  }
  return out;
}

Future<void> pumpThemed(
  WidgetTester tester,
  Harness h, {
  required Widget home,
  Size size = const Size(390, 844),
}) async {
  await pumpApp(tester, h, home: home, size: size);
}

void main() {
  group('palette tokens', () {
    test('Light: V5 warm-neutral page, white cards, ink text, one accent', () {
      const p = AppPalette.light;
      expect(p.background, const Color(0xFFF6F5F3));
      expect(p.card, const Color(0xFFFFFFFF));
      expect(p.surfaceAlt, const Color(0xFFEFEDE9));
      expect(p.textPrimary, const Color(0xFF1C1A17));
      expect(p.textSecondary, const Color(0xFF57524B));
      expect(p.textMuted, const Color(0xFF6F6962));
      expect(p.accent, const Color(0xFFC2410C));
      expect(p.accentStrong, const Color(0xFF9A3412));
      expect(p.accentSoft, const Color(0xFFFBEEE7));
      expect(p.statusOpen, const Color(0xFF15803D));
      expect(p.statusWarn, const Color(0xFFB45309));
      expect(p.error, const Color(0xFFC62828));
      // Borders are the prototype's opacity-based lines, not solid greys.
      // .09 and .17 alpha of the ink colour, as 8-bit alpha values.
      expect(p.border.toARGB32(), 0x171C1A17);
      expect(p.borderStrong.toARGB32(), 0x2B1C1A17);
    });

    test(
      'Dark: V5 charcoal page, cards, raised surfaces and softened accent',
      () {
        const p = AppPalette.dark;
        expect(p.background, const Color(0xFF151413));
        expect(p.card, const Color(0xFF1C1B19));
        expect(p.surfaceAlt, const Color(0xFF272522));
        expect(p.textPrimary, const Color(0xFFEFEBE4));
        expect(p.textSecondary, const Color(0xFFB3ADA4));
        expect(p.textMuted, const Color(0xFF938D84));
        expect(p.accent, const Color(0xFFEE7A45));
        expect(p.accentStrong, const Color(0xFFF4A177));
        expect(p.statusOpen, const Color(0xFF5FC28A));
        expect(p.border.toARGB32(), 0x17EFEBE4);
      },
    );

    test('orange identity survives in both modes (accent + soft fill)', () {
      for (final p in [AppPalette.light, AppPalette.dark]) {
        expect(HSVColor.fromColor(p.accent).hue, inInclusiveRange(15, 35));
        expect(HSVColor.fromColor(p.accentSoft).hue, inInclusiveRange(15, 45));
      }
    });

    for (final (name, p) in [
      ('light', AppPalette.light),
      ('dark', AppPalette.dark),
    ]) {
      test(
        '$name: every text colour reaches WCAG AA (4.5:1) on the surfaces it is used on',
        () {
          // Translucent fills are judged on what they look like over a card.
          final soft = Color.alphaBlend(p.accentSoft, p.card);
          for (final (fg, bg, label) in [
            (p.textPrimary, p.background, 'text on page'),
            (p.textPrimary, p.card, 'text on card'),
            (p.textPrimary, p.surfaceAlt, 'text on raised'),
            (p.textPrimary, soft, 'text on accent tint'),
            (p.textSecondary, p.background, 'secondary on page'),
            (p.textSecondary, p.card, 'secondary on card'),
            (p.textSecondary, p.surfaceAlt, 'secondary on raised'),
            (p.textMuted, p.background, 'muted on page'),
            (p.textMuted, p.card, 'muted on card'),
            (p.accentStrong, p.background, 'accent text on page'),
            (p.accentStrong, p.card, 'accent text on card'),
            (p.accentStrong, soft, 'accent text on accent tint'),
            (p.onRust, p.rust, 'button label on accent'),
            (p.chipSelectedFg, p.chipSelectedBg, 'selected chip'),
            (p.navIdle, p.navSurface, 'nav idle'),
            (p.navSelectedFg, p.navSurface, 'nav selected'),
            (p.statusOpen, p.card, 'status green'),
            (p.error, p.background, 'error text'),
          ]) {
            expect(
              contrast(fg, bg),
              greaterThanOrEqualTo(4.5),
              reason: '$name: $label',
            );
          }
        },
      );
    }

    test(
      'both themes register the palette and Dark has a dark colour scheme',
      () {
        final l = buildLightTheme();
        final d = buildDarkTheme();
        expect(l.extension<AppPalette>(), AppPalette.light);
        expect(d.extension<AppPalette>(), AppPalette.dark);
        expect(l.scaffoldBackgroundColor, AppPalette.light.background);
        expect(d.scaffoldBackgroundColor, AppPalette.dark.background);
        expect(l.appBarTheme.backgroundColor, AppPalette.light.background);
        expect(d.appBarTheme.backgroundColor, AppPalette.dark.background);
        expect(d.colorScheme.brightness, Brightness.dark);
        expect(d.dialogTheme.backgroundColor, AppPalette.dark.card);
        expect(d.bottomSheetTheme.backgroundColor, AppPalette.dark.card);
        // V5 typeface.
        expect(l.textTheme.bodyMedium?.fontFamily, 'Pretendard');
      },
    );

    test('lerp blends smoothly for the theme transition', () {
      final mid = AppPalette.light.lerp(AppPalette.dark, 0.5);
      expect(mid.background, isNot(AppPalette.light.background));
      expect(mid.background, isNot(AppPalette.dark.background));
      expect(
        AppPalette.light.lerp(AppPalette.dark, 1).background,
        AppPalette.dark.background,
      );
    });
  });

  group('no hard-coded cream / ivory backgrounds remain', () {
    final forbidden = RegExp(
      r'FFF9F2|FFF8F0|FFF7EE|FFF5E9|FFF0DC|FFE7C8|orange\.shade50|brown\.shade50',
      caseSensitive: false,
    );

    test('source scan', () {
      final offenders = <String>[];
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.contains('/l10n/')) continue;
        final text = f.readAsStringSync();
        if (forbidden.hasMatch(text)) offenders.add(f.path);
      }
      expect(offenders, isEmpty, reason: 'cream constants found in $offenders');
    });

    test('raw colour literals live only in the palette, brand and fixed-brand files', () {
      final literal = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)');
      const allowed = {
        'lib/core/theme/app_palette.dart',
        'lib/core/theme/app_colors.dart',
        'lib/features/auth/widgets/kakao_login_button.dart', // Kakao's mandated yellow
        'lib/main.dart', // the existing splash background
      };
      final offenders = <String>[];
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart') || f.path.contains('/l10n/')) continue;
        if (allowed.contains(f.path)) continue;
        if (literal.hasMatch(f.readAsStringSync())) offenders.add(f.path);
      }
      expect(offenders, isEmpty, reason: 'hard-coded colours in $offenders');
    });
  });

  group('ThemeMode controller and persistence', () {
    Future<ProviderContainer> container(Map<String, Object> storage) async {
      SharedPreferences.setMockInitialValues(storage);
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('defaults to System when nothing is stored', () async {
      expect((await container({})).read(themeModeProvider), ThemeMode.system);
    });

    test('restores a stored Light / Dark / System choice; junk falls back to System', () async {
      expect(
        (await container({themeModePrefsKey: 'light'})).read(themeModeProvider),
        ThemeMode.light,
      );
      expect(
        (await container({themeModePrefsKey: 'dark'})).read(themeModeProvider),
        ThemeMode.dark,
      );
      expect(
        (await container({themeModePrefsKey: 'system'}))
            .read(themeModeProvider),
        ThemeMode.system,
      );
      expect(
        (await container({themeModePrefsKey: 'neon'})).read(themeModeProvider),
        ThemeMode.system,
      );
    });

    test(
      'select applies immediately and persists locally (no network)',
      () async {
        final c = await container({});
        final f = c.read(themeModeProvider.notifier).select(ThemeMode.dark);
        expect(c.read(themeModeProvider), ThemeMode.dark, reason: 'immediate');
        await f;
        expect(
          c.read(sharedPreferencesProvider).getString(themeModePrefsKey),
          'dark',
        );
        await c.read(themeModeProvider.notifier).select(ThemeMode.system);
        expect(
          c.read(sharedPreferencesProvider).getString(themeModePrefsKey),
          'system',
        );
      },
    );

    test(
      'a restart (fresh container, same storage) restores the choice',
      () async {
        final first = await container({});
        await first.read(themeModeProvider.notifier).select(ThemeMode.dark);
        final stored = first
            .read(sharedPreferencesProvider)
            .getString(themeModePrefsKey)!;
        final second = await container({themeModePrefsKey: stored});
        expect(second.read(themeModeProvider), ThemeMode.dark);
      },
    );
  });

  group('rendered backgrounds (real pixels)', () {
    Future<Harness> h(
      String mode, {
      String lang = 'ko',
      bool withCafeteria = false,
    }) async {
      final repo = FakeCampusMealRepository(
        cafeteriasByUniversity: {
          '5c0a8f3e-0001-4a6e-9b1d-000000000001': [fakeCafeteria('c1')],
        },
        meals: [fakeMeal('2026-11-03', MealType.lunch, price: 5500)],
      );
      return buildHarness(
        storage: {'app_language': lang, themeModePrefsKey: mode},
        meals: repo,
        extraOverrides: [
          campusMealClockProvider.overrideWithValue(
            () => DateTime.utc(2026, 11, 3, 3),
          ),
          campusMealCacheDurationProvider.overrideWithValue(Duration.zero),
        ],
      );
    }

    Future<void> expectBackground(
      WidgetTester tester,
      Color expected,
      String label,
    ) async {
      final colors = await gutterColors(tester);
      expect(colors, {expected.toARGB32()}, reason: '$label page background');
    }

    for (final (mode, expected, homeExpected) in [
      ('light', AppPalette.light.background, AppPalette.light.pageWarm),
      ('dark', AppPalette.dark.background, AppPalette.dark.pageWarm),
    ]) {
      testWidgets('$mode: Home, MY, Login and Campus Meals backgrounds', (
        tester,
      ) async {
        // Home uses the warm page colour; the other screens keep theirs.
        var harness = await h(mode);
        await pumpThemed(tester, harness, home: const AppShell());
        await expectBackground(tester, homeExpected, 'Home');

        // MY (guest) through the real tab bar
        harness.container
            .read(shellTabProvider.notifier)
            .select(ShellTabs.profile);
        await tester.pumpAndSettle();
        await expectBackground(tester, expected, 'MY');
      });

      testWidgets('$mode: Login', (tester) async {
        await pumpThemed(tester, await h(mode), home: const LoginScreen());
        await expectBackground(tester, expected, 'Login');
      });

      testWidgets('$mode: Campus Meals', (tester) async {
        await pumpThemed(tester, await h(mode), home: const CampusMealScreen());
        await expectBackground(tester, expected, 'Campus Meals');
      });
    }

    testWidgets(
      'light: Home page is the warm neutral, with no peach or orange tint',
      (tester) async {
        await pumpThemed(tester, await h('light'), home: const AppShell());
        // Home cards sit inside a 20px gutter, so the page shows through at
        // the far left and right edges all the way down.
        for (final x in [3.0, 8.0, 386.0]) {
          for (final y in [90.0, 250.0, 420.0, 560.0, 700.0]) {
            final c = await pixelAt(tester, Offset(x, y));
            expect(
              c.toARGB32(),
              AppPalette.light.pageWarm.toARGB32(),
              reason: 'pixel ($x,$y)',
            );
          }
        }
        // Warm, not orange: red barely above blue.
        final page = AppPalette.light.pageWarm;
        expect(page.r - page.b, lessThan(0.05));
      },
    );

    for (final (mode, expected) in [
      ('light', 0xFFF6F5F3),
      ('dark', 0xFF151413),
    ]) {
      // Regression: a brown-tinted card shadow used to overlap in the gap
      // between cards and render the page cream (#F9F5F2) instead of white.
      testWidgets('$mode: the gap BETWEEN restaurant cards is the pure page '
          'colour (no shadow haze)', (tester) async {
        await pumpThemed(
          tester,
          await h(mode),
          home: const RestaurantCategoryScreen(),
        );
        final tiles = find.byType(RestaurantListTile);
        expect(tiles, findsAtLeastNWidgets(2));
        final first = tester.getRect(tiles.at(0));
        final second = tester.getRect(tiles.at(1));
        expect(second.top - first.bottom, greaterThan(8));
        final y = (first.bottom + second.top) / 2;
        for (final x in [first.left + 12, first.center.dx, first.right - 12]) {
          final c = await pixelAt(tester, Offset(x, y));
          expect(c.toARGB32(), expected, reason: '$mode gap pixel ($x,$y)');
        }
        // beside the cards too (the page margin)
        final side = await pixelAt(
          tester,
          Offset(first.left - 4, first.center.dy),
        );
        expect(side.toARGB32(), expected);
      });
    }

    // flutter_test does not rasterise blurred shadows, so the haze itself
    // can only be guarded structurally: no card may drop a shadow, and any
    // shadow that does exist (floating nav) must be neutral, never tinted.
    List<BoxShadow> shadowsOnScreen(WidgetTester tester) => [
      for (final e in find.byType(DecoratedBox).evaluate())
        ...?((e.widget as DecoratedBox).decoration as BoxDecoration?)
            ?.boxShadow,
    ];

    testWidgets('light: restaurant cards drop no shadow at all', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        await h('light'),
        home: const RestaurantCategoryScreen(),
      );
      expect(find.byType(RestaurantListTile), findsWidgets);
      expect(shadowsOnScreen(tester), isEmpty);
    });

    testWidgets('light Home: every remaining shadow is neutral, not warm', (
      tester,
    ) async {
      await pumpThemed(tester, await h('light'), home: const AppShell());
      expect(AppPalette.light.cardShadow, isEmpty);
      expect(AppPalette.dark.cardShadow, isEmpty);
      final all = [
        ...shadowsOnScreen(tester).map((s) => s.color),
        AppPalette.light.shadow,
        AppPalette.light.navShadow,
      ];
      for (final c in all) {
        expect(c.r, c.g, reason: 'shadow $c is tinted');
        expect(c.g, c.b, reason: 'shadow $c is tinted');
      }
    });

    testWidgets('dark: no white or cream page surface (sampled across Home)', (
      tester,
    ) async {
      await pumpThemed(tester, await h('dark'), home: const AppShell());
      for (final y in [90.0, 250.0, 420.0, 560.0, 700.0]) {
        final c = await pixelAt(tester, Offset(4, y));
        expect(luminance(c), lessThan(0.02), reason: 'dark page at y=$y');
      }
    });
  });

  group('Appearance screen and live switching', () {
    Future<Harness> open(
      WidgetTester tester, {
      Map<String, Object> storage = const {'app_language': 'ko'},
    }) async {
      final h = await buildHarness(storage: storage);
      await pumpApp(tester, h, home: const AppShell());
      h.container.read(shellTabProvider.notifier).select(ShellTabs.profile);
      await tester.pumpAndSettle();
      return h;
    }

    ThemeMode appThemeMode(WidgetTester tester) =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

    Brightness brightness(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness;

    testWidgets(
      'MY shows 앱 설정 with 언어 설정 and 화면 테마 (guests too), in clear sections',
      (tester) async {
        await open(tester);
        expect(find.text('앱 설정'), findsOneWidget);
        expect(find.text('언어 설정'), findsOneWidget);
        expect(find.text('화면 테마'), findsOneWidget);
        expect(
          find.text('시스템 설정에 따름'),
          findsOneWidget,
          reason: 'current choice shown: default is System',
        );
      },
    );

    testWidgets(
      'signed-in MY: Account section, App Settings section, then logout',
      (tester) async {
        final h = await buildHarness(
          auth: FakeAuthGateway(user: fakeUser()),
          profiles: FakeProfileRepository(
            onboardingCompleted: true,
            nickname: '민수',
          ),
        );
        await pumpApp(
          tester,
          h,
          home: const AppShell(),
          size: const Size(390, 1400),
        );
        h.container.read(shellTabProvider.notifier).select(ShellTabs.profile);
        await tester.pumpAndSettle();
        final yAccount = tester.getTopLeft(find.text('계정').first).dy;
        final yApp = tester.getTopLeft(find.text('앱 설정')).dy;
        final yLogout = tester.getTopLeft(find.text('로그아웃')).dy;
        expect(find.text('안녕하세요, 민수님'), findsOneWidget);
        expect(find.text('나의 취향 설정'), findsOneWidget);
        expect(find.text('계정 설정'), findsOneWidget);
        expect(yAccount, lessThan(yApp));
        expect(yApp, lessThan(yLogout));
        expect(find.text('화면 테마'), findsOneWidget);
        expect(find.text('언어 설정'), findsOneWidget);
      },
    );

    testWidgets(
      'options: Light / Dark / Device with sun, moon and device icons',
      (tester) async {
        await open(tester);
        await tester.tap(find.text('화면 테마'));
        await tester.pumpAndSettle();
        expect(find.byType(AppearanceScreen), findsOneWidget);
        expect(find.text('라이트 모드'), findsOneWidget);
        expect(find.text('다크 모드'), findsOneWidget);
        expect(find.text('시스템 설정에 따름'), findsOneWidget);
        expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
        expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
        expect(find.byIcon(Icons.phone_iphone_rounded), findsOneWidget);
        // exactly one radio is checked: the default, System
        expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'choosing Dark applies at once; tab, language and navigation are untouched',
      (tester) async {
        final h = await open(tester, storage: {'app_language': 'en'});
        expect(brightness(tester), Brightness.light);
        await tester.tap(find.text('Appearance'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dark Mode'));
        await tester.pumpAndSettle();

        expect(
          brightness(tester),
          Brightness.dark,
          reason: 'immediate, no restart',
        );
        expect(appThemeMode(tester), ThemeMode.dark);
        expect(h.container.read(themeModeProvider), ThemeMode.dark);
        expect(
          h.sp.getString(themeModePrefsKey),
          'dark',
          reason: 'stored locally',
        );
        expect(
          h.container.read(shellTabProvider),
          ShellTabs.profile,
          reason: 'tab preserved',
        );
        expect(
          find.byType(AppearanceScreen),
          findsOneWidget,
          reason: 'route preserved',
        );
        expect(
          h.container.read(appLanguageProvider),
          AppLanguage.en,
          reason: 'language unchanged',
        );
        expect(find.text('Appearance'), findsWidgets);
        expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);

        await tester.tap(find.text('Light Mode'));
        await tester.pumpAndSettle();
        expect(brightness(tester), Brightness.light);
        expect(h.sp.getString(themeModePrefsKey), 'light');
      },
    );

    testWidgets('System follows the operating system, live', (tester) async {
      final h = await open(tester);
      expect(brightness(tester), Brightness.light);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      expect(
        brightness(tester),
        Brightness.dark,
        reason: 'OS switched to dark',
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.light);

      // An explicit choice wins over the OS.
      await h.container
          .read(themeModeProvider.notifier)
          .select(ThemeMode.light);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.light);
      // and System is restorable and persisted
      await h.container
          .read(themeModeProvider.notifier)
          .select(ThemeMode.system);
      await tester.pumpAndSettle();
      expect(brightness(tester), Brightness.dark);
      expect(h.sp.getString(themeModePrefsKey), 'system');
    });

    testWidgets(
      'a saved Dark choice is applied from the very first frame after restart',
      (tester) async {
        final h = await buildHarness(
          storage: {'app_language': 'ko', themeModePrefsKey: 'dark'},
        );
        setPhoneSize(tester);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: h.container,
            child: const MeogeobojoApp(home: AppShell()),
          ),
        );
        // first frame, before any settling
        expect(
          brightness(tester),
          Brightness.dark,
          reason: 'no flash of the light theme',
        );
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'theme survives login, logout and account switching; guests can change it',
      (tester) async {
        final auth = FakeAuthGateway();
        final h = await buildHarness(
          auth: auth,
          profiles: FakeProfileRepository(
            onboardingCompleted: true,
            nickname: '민수',
          ),
        );
        await pumpApp(tester, h, home: const AppShell());
        // guest changes the theme (no account, no network)
        await h.container
            .read(themeModeProvider.notifier)
            .select(ThemeMode.dark);
        await tester.pumpAndSettle();
        expect(brightness(tester), Brightness.dark);

        auth.emit(AuthChangeEvent.signedIn, fakeUser(id: 'A'));
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpAndSettle();
        expect(
          brightness(tester),
          Brightness.dark,
          reason: 'login keeps the theme',
        );
        auth.emit(AuthChangeEvent.signedIn, fakeUser(id: 'B'));
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pumpAndSettle();
        expect(
          brightness(tester),
          Brightness.dark,
          reason: 'account switch keeps the theme',
        );
        await h.container.read(authControllerProvider.notifier).signOut();
        await tester.pumpAndSettle();
        expect(
          brightness(tester),
          Brightness.dark,
          reason: 'logout keeps the theme',
        );
        expect(h.container.read(appLanguageProvider), AppLanguage.ko);
      },
    );

    testWidgets('home / tab state is kept across a theme change', (
      tester,
    ) async {
      final h = await buildHarness();
      await pumpApp(tester, h, home: const AppShell());
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      final before = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      await h.container.read(themeModeProvider.notifier).select(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .pixels,
        before,
        reason: 'scroll position preserved while the theme changes',
      );
    });

    testWidgets('English and Chinese labels', (tester) async {
      await open(tester, storage: {'app_language': 'zh-Hans'});
      expect(find.text('应用设置'), findsOneWidget);
      expect(find.text('外观主题'), findsOneWidget);
      expect(find.text('跟随系统'), findsOneWidget);
      await tester.tap(find.text('外观主题'));
      await tester.pumpAndSettle();
      expect(find.text('浅色模式'), findsOneWidget);
      expect(find.text('深色模式'), findsOneWidget);
    });
  });
}

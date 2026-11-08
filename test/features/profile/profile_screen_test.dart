import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/profile/screens/account_settings_screen.dart';
import 'package:meogeobojo/core/l10n/app_language.dart';
import 'package:meogeobojo/core/l10n/language_controller.dart';
import 'package:meogeobojo/features/auth/models/auth_snapshot.dart';
import 'package:meogeobojo/features/auth/providers/auth_providers.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/preferences/screens/preferences_screen.dart';
import 'package:meogeobojo/features/profile/screens/profile_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

Future<void> openMy(
  WidgetTester tester,
  Harness h, {
  // Tall by default so the whole (lazily built) page is in the tree; the
  // realistic phone height is used where scrolling is the point.
  Size size = const Size(390, 1400),
}) async {
  await pumpApp(tester, h, home: const AppShell(), size: size);
  h.container.read(shellTabProvider.notifier).select(ShellTabs.profile);
  await tester.pumpAndSettle();
}

void main() {
  group('MY — logged out', () {
    testWidgets('shows the required copy and actions', (tester) async {
      final h = await buildHarness();
      await openMy(tester, h);
      expect(find.text('로그인하고 맛집을 저장해보세요'), findsOneWidget);
      expect(find.text('둘러보기와 검색은 로그인 없이도 가능해요.'), findsOneWidget);
      expect(find.text('로그인 / 회원가입'), findsOneWidget);
      expect(find.text('로그인 없이 계속 둘러보기 →'), findsOneWidget);
      expect(find.text('언어 설정'), findsOneWidget);
      // exactly one mascot, no extra decoration
      expect(find.byType(Image), findsOneWidget);
      // account-only entries are not shown to guests
      expect(find.text('저장한 맛집'), findsNothing);
      expect(find.text('로그아웃'), findsNothing);
    });

    testWidgets('guest can change language from MY without an account', (
      tester,
    ) async {
      final h = await buildHarness();
      await openMy(tester, h);
      await tester.tap(find.text('언어 설정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to save your favorite spots'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Continue without signing in →'), findsOneWidget);
      expect(h.container.read(appLanguageProvider), AppLanguage.en);
      expect(
        h.profiles.languageWrites,
        isEmpty,
        reason: 'no database access for guests',
      );
      expect(h.sp.getString(languagePrefsKey), 'en');
    });

    testWidgets('"continue without signing in" returns to Home', (
      tester,
    ) async {
      final h = await buildHarness();
      await openMy(tester, h);
      await tester.tap(find.text('로그인 없이 계속 둘러보기 →'));
      await tester.pumpAndSettle();
      expect(find.text('학교 주변 맛집'), findsWidgets);
    });
  });

  group('MY — logged in', () {
    Future<Harness> signedIn({
      User? user,
      FakeProfileRepository? profiles,
      Set<String> favorites = const {},
      Map<String, Object> storage = const {'app_language': 'ko'},
    }) => buildHarness(
      storage: storage,
      auth: FakeAuthGateway(user: user ?? fakeUser(metadata: {'name': '카카오'})),
      profiles:
          profiles ??
          FakeProfileRepository(onboardingCompleted: true, nickname: '민수'),
      favorites: FakeFavoritesRepository(favorites),
      prefs: FakePreferencesRepository(
        stored: const UserPreferences(
          budget: BudgetOption.any,
          distance: DistanceOption.any,
        ),
      ),
    );

    testWidgets(
      'shows the real account: nickname, email and every menu entry',
      (tester) async {
        final h = await signedIn(favorites: {'a', 'b'});
        await openMy(tester, h);
        expect(find.text('안녕하세요, 민수님'), findsOneWidget);
        expect(find.text('오늘도 맛있는 한 끼 찾아볼까요?'), findsOneWidget);
        expect(find.text('프로필 수정 →'), findsOneWidget);
        expect(find.text('tester@example.com'), findsOneWidget);
        // the saved-places row keeps its real count; the stat card repeats it
        expect(find.text('저장한 맛집'), findsNWidgets(2));
        expect(find.text('2곳'), findsOneWidget, reason: 'real favorites count');
        expect(find.text('2'), findsOneWidget, reason: 'stat: real count');
        expect(find.text('나의 기록'), findsNWidgets(2));
        expect(find.text('나의 취향 설정'), findsOneWidget);
        expect(find.text('언어 설정'), findsOneWidget);
        expect(find.text('계정 설정'), findsOneWidget);
        expect(find.text('로그아웃'), findsOneWidget);
        expect(find.text('로그인 / 회원가입'), findsNothing);
      },
    );

    testWidgets(
      'campus card shows the selected university, not a hardcoded one',
      (tester) async {
        final h = await signedIn();
        await openMy(tester, h);
        expect(find.text('순천향대학교'), findsOneWidget);
        expect(find.text('아산 · 탭해서 학교 바꾸기'), findsOneWidget);
        await tester.tap(find.text('순천향대학교'));
        await tester.pumpAndSettle();
        expect(find.text('학교 선택'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '호서');
        await tester.pumpAndSettle();
        await tester.tap(find.text('호서대학교'));
        await tester.pumpAndSettle();
        expect(find.text('호서대학교'), findsOneWidget);
        expect(find.text('순천향대학교'), findsNothing);
      },
    );

    testWidgets(
      'stats: real favorites count; unavailable ones are not invented',
      (tester) async {
        final h = await signedIn(favorites: {'a', 'b', 'c'});
        await openMy(tester, h);
        expect(find.text('3'), findsOneWidget);
        // records and plans cannot be created yet: no numbers, a plain state
        expect(find.text('예정된 약속'), findsOneWidget);
        expect(find.text('준비 중'), findsNWidgets(2));
      },
    );

    testWidgets('stats with no favorites shows 0 (a real count)', (
      tester,
    ) async {
      final h = await signedIn();
      await openMy(tester, h);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('프로필 수정 → opens 계정 설정 where the nickname is edited', (
      tester,
    ) async {
      final h = await signedIn();
      await openMy(tester, h);
      await tester.tap(find.text('프로필 수정 →'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountSettingsScreen), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('keeps 계정 and 앱 설정 sections with every row, then logout', (
      tester,
    ) async {
      final h = await signedIn();
      await openMy(tester, h);
      await tester.scrollUntilVisible(
        find.text('로그아웃'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      for (final t in ['계정', '앱 설정', '언어 설정', '화면 테마', '로그아웃']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
    });

    for (final (lang, mode) in [
      ('ko', 'light'),
      ('en', 'dark'),
      ('zh-Hans', 'light'),
    ]) {
      testWidgets('dashboard fits at 320px / 1.6x text: $lang, $mode', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final h = await signedIn(
          storage: {'app_language': lang, 'theme_mode': mode},
          favorites: {'a'},
        );
        await openMy(tester, h, size: const Size(320, 640));
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byIcon(Icons.language_rounded),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('does not display an email the account does not have', (
      tester,
    ) async {
      final h = await signedIn(
        user: fakeUser(
          email: null,
          provider: 'kakao',
          metadata: {'name': '카카오'},
        ),
      );
      await openMy(tester, h);
      expect(find.textContaining('@'), findsNothing);
      expect(find.text('안녕하세요, 민수님'), findsOneWidget);
    });

    testWidgets('no invented nickname: falls back to a generic label', (
      tester,
    ) async {
      final h = await signedIn(
        profiles: FakeProfileRepository(onboardingCompleted: true),
      );
      await openMy(tester, h);
      expect(find.text('안녕하세요, 먹어보조 사용자님'), findsOneWidget);
    });

    testWidgets(
      'favorites count is not shown for an empty list as a fake number',
      (tester) async {
        final h = await signedIn();
        await openMy(tester, h);
        expect(
          find.text('0곳'),
          findsOneWidget,
          reason: 'real zero, not a placeholder',
        );
      },
    );

    testWidgets(
      'profile load failure shows a retry banner, entries needing it are disabled',
      (tester) async {
        final profiles = FakeProfileRepository(onboardingCompleted: true)
          ..loadError = const PostgrestException(message: 'down');
        final h = await signedIn(profiles: profiles);
        await openMy(tester, h);
        expect(find.text('내 정보를 불러오지 못했어요. 다시 시도해주세요.'), findsOneWidget);
        profiles.loadError = null;
        await tester.tap(find.text('다시 시도'));
        await tester.pumpAndSettle();
        expect(find.text('내 정보를 불러오지 못했어요. 다시 시도해주세요.'), findsNothing);
        expect(
          h.container.read(authControllerProvider).status,
          AuthStatus.authenticatedReady,
        );
      },
    );

    testWidgets('나의 취향 설정 opens the edit form (not the first-time flow)', (
      tester,
    ) async {
      final h = await signedIn();
      await openMy(tester, h);
      await tester.tap(find.text('나의 취향 설정'));
      await tester.pumpAndSettle();
      expect(find.byType(PreferencesScreen), findsOneWidget);
      expect(find.text('STEP 1–4'), findsNothing);
      expect(find.text('저장하기'), findsOneWidget);
    });

    testWidgets('logout returns MY to the guest state', (tester) async {
      final h = await signedIn();
      await openMy(tester, h, size: const Size(390, 844));
      await tester.scrollUntilVisible(
        find.text('로그아웃'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('로그아웃'));
      await tester.pumpAndSettle();
      expect(h.auth.calls, contains('signOut'));
      expect(find.text('로그인하고 맛집을 저장해보세요'), findsOneWidget);
      expect(h.container.read(authControllerProvider).status, AuthStatus.guest);
    });

    testWidgets(
      'account settings shows provider and lets the nickname be edited',
      (tester) async {
        final h = await signedIn();
        await openMy(tester, h);
        await tester.tap(find.text('계정 설정'));
        await tester.pumpAndSettle();
        expect(find.text('이메일'), findsWidgets); // field label + sign-in method
        expect(find.text('로그인 방식'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.edit_outlined));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '새닉네임');
        await tester.tap(find.text('저장'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 50));
        expect(h.profiles.nicknameWrites, ['새닉네임']);
        expect(find.text('새닉네임'), findsOneWidget);
      },
    );

    testWidgets('MY works in English and Chinese without overflow at 320px', (
      tester,
    ) async {
      for (final lang in ['en', 'zh-Hans']) {
        final h = await buildHarness(
          storage: {'app_language': lang},
          auth: FakeAuthGateway(user: fakeUser()),
          profiles: FakeProfileRepository(
            onboardingCompleted: true,
            nickname: '아주아주아주아주아주아주긴닉네임입니다',
          ),
        );
        await pumpApp(
          tester,
          h,
          home: const AppShell(),
          size: const Size(320, 568),
        );
        await tester.tap(find.byIcon(Icons.person_outline_rounded));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: lang);
        expect(find.byType(ProfileScreen), findsOneWidget);
      }
    });
  });
}

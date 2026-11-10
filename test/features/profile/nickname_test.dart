import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/auth/models/auth_failure.dart';
import 'package:meogeobojo/features/auth/models/auth_snapshot.dart';
import 'package:meogeobojo/features/auth/providers/auth_providers.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/preferences/screens/preferences_screen.dart';
import 'package:meogeobojo/features/profile/models/nickname.dart';
import 'package:meogeobojo/features/profile/screens/nickname_setup_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

NicknameError? err(String v) => checkNickname(v).error;

Finder nicknameField() => find.byType(TextField).first;

void main() {
  group('nickname rules (client side)', () {
    test('Korean, English, Chinese, digits and inner spaces are accepted', () {
      for (final ok in [
        '맛집왕',
        'Foodie',
        '美食家',
        'user42',
        'Food Lover',
        '맛집 왕 2호',
        '가나',
      ]) {
        expect(checkNickname(ok).isValid, isTrue, reason: ok);
      }
    });

    test('empty and blank-only are rejected', () {
      expect(err(''), NicknameError.empty);
      expect(err('    '), NicknameError.empty);
      expect(err('\u3000\u00a0 '), NicknameError.empty);
    });

    test('length is 2-15 Unicode characters, not bytes', () {
      expect(err('a'), NicknameError.tooShort);
      expect(err('맛'), NicknameError.tooShort);
      expect(checkNickname('ab').isValid, isTrue);
      expect(checkNickname('열다섯글자를꽉채운닉네임입니다').isValid, isTrue); // 15
      expect(err('열여섯글자를꽉채운닉네임입니다요'), NicknameError.tooLong); // 16
      expect(checkNickname('美食家美食家美食家美食家美食家').isValid, isTrue); // 15 Chinese
      expect(err('abcdefghijklmnop'), NicknameError.tooLong);
    });

    test('outer whitespace is trimmed and inner runs collapse', () {
      expect(checkNickname('  맛집왕  ').value, '맛집왕');
      expect(checkNickname('Food    Lover').value, 'Food Lover');
      expect(
        checkNickname('美食\u3000家').value,
        '美食 家',
        reason: 'ideographic space',
      );
    });

    test('control and invisible characters are rejected', () {
      for (final bad in [
        'ab\tcd',
        'ab\ncd',
        'ab\u0000cd',
        'ab\u200bcd',
        'ab\u202ecd',
        'ab\ufeffcd',
      ]) {
        expect(
          err(bad),
          NicknameError.invalidChars,
          reason: bad.codeUnits.toString(),
        );
      }
    });

    test('nicknames are not required to be unique (nothing to check)', () {
      expect(checkNickname('맛집왕').value, checkNickname('맛집왕').value);
    });
  });

  group('routing: nickname before preferences', () {
    testWidgets('a NEW user sees nickname setup, then preference onboarding', (
      tester,
    ) async {
      final profiles = FakeProfileRepository(
        nicknameIsCustom: false,
        nickname: '카카오닉',
      );
      final h = await buildHarness(
        auth: FakeAuthGateway(user: fakeUser(provider: 'kakao')),
        profiles: profiles,
      );
      await pumpApp(tester, h);
      expect(find.byType(NicknameSetupScreen), findsOneWidget);
      expect(find.byType(PreferencesScreen), findsNothing);
      expect(
        h.container.read(authControllerProvider).status,
        AuthStatus.authenticatedNeedsNickname,
      );

      await tester.enterText(nicknameField(), '맛집왕');
      await tester.tap(find.text('다음'));
      await settle(tester);

      expect(profiles.nicknameWrites, ['맛집왕']);
      expect(find.byType(NicknameSetupScreen), findsNothing);
      expect(find.byType(PreferencesScreen), findsOneWidget);
      expect(
        h.container.read(authControllerProvider).status,
        AuthStatus.authenticatedNeedsOnboarding,
      );
    });

    testWidgets('the Kakao nickname does NOT count as chosen', (tester) async {
      final h = await buildHarness(
        auth: FakeAuthGateway(user: fakeUser(provider: 'kakao')),
        profiles: FakeProfileRepository(
          onboardingCompleted: true,
          nickname: '에렌자', // copied from Kakao
          nicknameIsCustom: false,
        ),
      );
      await pumpApp(tester, h);
      expect(find.byType(NicknameSetupScreen), findsOneWidget);
    });

    testWidgets(
      'an existing user who finished onboarding sets a nickname ONCE and returns to the app',
      (tester) async {
        final profiles = FakeProfileRepository(
          onboardingCompleted: true,
          nicknameIsCustom: false,
          nickname: '에렌자',
        );
        final h = await buildHarness(
          auth: FakeAuthGateway(user: fakeUser()),
          profiles: profiles,
        );
        await pumpApp(tester, h);
        await tester.enterText(nicknameField(), 'Foodie 7');
        await tester.tap(find.text('다음'));
        await settle(tester);

        expect(find.byType(NicknameSetupScreen), findsNothing);
        expect(
          find.byType(PreferencesScreen),
          findsNothing,
          reason: 'preferences are not reset',
        );
        expect(find.byType(AppShell), findsOneWidget);
        final snap = h.container.read(authControllerProvider);
        expect(snap.status, AuthStatus.authenticatedReady);
        expect(snap.profile?.onboardingCompleted, isTrue);

        // duplicate auth events never ask again
        h.auth.emit(AuthChangeEvent.tokenRefreshed, fakeUser());
        h.auth.emit(AuthChangeEvent.signedIn, fakeUser());
        await settle(tester);
        expect(find.byType(NicknameSetupScreen), findsNothing);
      },
    );

    testWidgets(
      'a returning user with a custom nickname is never asked again (e.g. Kakao re-login)',
      (tester) async {
        final profiles = FakeProfileRepository(
          onboardingCompleted: true,
          nickname: '맛집왕',
        ); // custom by default in the fake
        final h = await buildHarness(profiles: profiles);
        await pumpApp(tester, h);
        // sign in (as Kakao would) with a *different* provider display name
        h.auth.emit(
          AuthChangeEvent.signedIn,
          fakeUser(provider: 'kakao', metadata: {'name': 'Kakao Renamed'}),
        );
        await settle(tester);
        expect(find.byType(NicknameSetupScreen), findsNothing);
        expect(find.byType(PreferencesScreen), findsNothing);
        expect(
          h.container.read(authControllerProvider).profile?.nickname,
          '맛집왕',
        );
        expect(
          profiles.nicknameWrites,
          isEmpty,
          reason: 'nothing overwrote it',
        );
      },
    );

    testWidgets(
      'nickname setup cannot be dismissed, but the user can sign out',
      (tester) async {
        final h = await buildHarness(
          auth: FakeAuthGateway(user: fakeUser()),
          profiles: FakeProfileRepository(nicknameIsCustom: false),
        );
        await pumpApp(tester, h);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(NicknameSetupScreen), findsOneWidget);
        await tester.tap(find.text('로그아웃'));
        await settle(tester);
        expect(find.byType(NicknameSetupScreen), findsNothing);
        expect(
          h.container.read(authControllerProvider).status,
          AuthStatus.guest,
        );
      },
    );

    testWidgets('guests are never asked for a nickname', (tester) async {
      final h = await buildHarness();
      await pumpApp(tester, h);
      expect(find.byType(NicknameSetupScreen), findsNothing);
    });
  });

  group('nickname setup screen', () {
    Future<(Harness, FakeProfileRepository)> open(
      WidgetTester tester, {
      String lang = 'ko',
    }) async {
      final profiles = FakeProfileRepository(nicknameIsCustom: false);
      final h = await buildHarness(
        storage: {'app_language': lang},
        auth: FakeAuthGateway(user: fakeUser()),
        profiles: profiles,
      );
      await pumpApp(tester, h);
      return (h, profiles);
    }

    testWidgets('shows the required copy', (tester) async {
      await open(tester);
      expect(find.text('어떻게 불러드릴까요?'), findsOneWidget);
      expect(find.text('먹어보조에서 사용할 닉네임을 정해주세요.'), findsOneWidget);
      expect(find.text('닉네임'), findsOneWidget);
      expect(find.text('닉네임을 입력해주세요'), findsOneWidget);
      expect(find.text('다음'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget, reason: 'existing mascot');
    });

    testWidgets(
      'empty / too short / too long / invalid are rejected with inline messages',
      (tester) async {
        final (_, profiles) = await open(tester);
        await tester.tap(find.text('다음'));
        await tester.pump();
        expect(find.text('닉네임을 입력해주세요.'), findsOneWidget);

        await tester.enterText(nicknameField(), '가');
        await tester.tap(find.text('다음'));
        await tester.pump();
        expect(find.text('닉네임은 2자 이상이어야 해요.'), findsOneWidget);

        await tester.enterText(nicknameField(), '열여섯글자를꽉채운닉네임입니다요');
        await tester.tap(find.text('다음'));
        await tester.pump();
        expect(find.text('닉네임은 15자 이하여야 해요.'), findsOneWidget);

        await tester.enterText(nicknameField(), 'ab\u200bcd');
        await tester.tap(find.text('다음'));
        await tester.pump();
        expect(find.text('사용할 수 없는 문자가 포함되어 있어요.'), findsOneWidget);
        expect(profiles.nicknameWrites, isEmpty, reason: 'nothing was sent');
      },
    );

    for (final (lang, input) in [
      ('ko', '맛집왕'),
      ('en', 'Food Lover'),
      ('zh-Hans', '美食家'),
    ]) {
      testWidgets('accepts $lang input', (tester) async {
        final (_, profiles) = await open(tester, lang: lang);
        await tester.enterText(nicknameField(), input);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settle(tester);
        expect(profiles.nicknameWrites, [input]);
      });
    }

    testWidgets('typing clears the error; the value is trimmed before saving', (
      tester,
    ) async {
      final (_, profiles) = await open(tester);
      await tester.tap(find.text('다음'));
      await tester.pump();
      expect(find.text('닉네임을 입력해주세요.'), findsOneWidget);
      await tester.enterText(nicknameField(), '  맛집  왕  ');
      await tester.pump();
      expect(find.text('닉네임을 입력해주세요.'), findsNothing);
      await tester.tap(find.text('다음'));
      await settle(tester);
      expect(profiles.nicknameWrites, ['맛집 왕']);
    });

    testWidgets('a failed save keeps the text, explains, and can be retried', (
      tester,
    ) async {
      final (h, profiles) = await open(tester);
      profiles.nicknameErrors.add(
        AuthRetryableFetchException(message: 'offline'),
      );
      await tester.enterText(nicknameField(), '맛집왕');
      await tester.tap(find.text('다음'));
      await settle(tester);
      expect(find.text('인터넷 연결을 확인하고 다시 시도해주세요.'), findsOneWidget);
      expect(tester.widget<TextField>(nicknameField()).controller!.text, '맛집왕');
      expect(find.byType(NicknameSetupScreen), findsOneWidget);
      expect(
        h.container.read(authControllerProvider).status,
        AuthStatus.authenticatedNeedsNickname,
      );

      await tester.tap(find.text('다음'));
      await settle(tester);
      expect(profiles.nicknameWrites, ['맛집왕']);
      expect(find.byType(NicknameSetupScreen), findsNothing);
    });

    testWidgets('a server-side rejection is shown, not swallowed', (
      tester,
    ) async {
      final (_, profiles) = await open(tester);
      profiles.nicknameErrors.add(
        const PostgrestException(message: 'invalid nickname', code: '23514'),
      );
      await tester.enterText(nicknameField(), '맛집왕');
      await tester.tap(find.text('다음'));
      await settle(tester);
      expect(find.text('사용할 수 없는 문자가 포함되어 있어요.'), findsOneWidget);
    });

    testWidgets('no overflow in all languages at 320px / 1.6x text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final lang in ['ko', 'en', 'zh-Hans']) {
        final h = await buildHarness(
          storage: {'app_language': lang},
          auth: FakeAuthGateway(user: fakeUser()),
          profiles: FakeProfileRepository(nicknameIsCustom: false),
        );
        await pumpApp(tester, h, size: const Size(320, 568));
        expect(tester.takeException(), isNull, reason: lang);
      }
    });

    testWidgets('double submit saves once', (tester) async {
      final (_, profiles) = await open(tester);
      await tester.enterText(nicknameField(), '맛집왕');
      await tester.tap(find.text('다음'));
      await tester.tap(find.text('다음'), warnIfMissed: false);
      await settle(tester);
      expect(profiles.nicknameWrites.length, 1);
    });
  });

  group('MY shows the chosen nickname', () {
    Future<void> openMy(WidgetTester tester, Harness h) async {
      await pumpApp(tester, h, home: const AppShell());
      await tester.tap(find.text('MY'));
      await tester.pumpAndSettle();
    }

    testWidgets('custom nickname is the heading, email stays underneath', (
      tester,
    ) async {
      final h = await buildHarness(
        auth: FakeAuthGateway(
          user: fakeUser(
            email: 'me@example.com',
            metadata: {'name': 'KakaoName'},
          ),
        ),
        profiles: FakeProfileRepository(
          onboardingCompleted: true,
          nickname: '맛집왕',
        ),
      );
      await openMy(tester, h);
      expect(find.text('맛집왕'), findsOneWidget);
      expect(find.text('me@example.com'), findsOneWidget);
      expect(
        find.text('KakaoName'),
        findsNothing,
        reason: 'OAuth metadata is not displayed',
      );
    });

    testWidgets(
      'never uses the email as the name; falls back to a generic label',
      (tester) async {
        final h = await buildHarness(
          auth: FakeAuthGateway(user: fakeUser(email: 'me@example.com')),
          profiles: FakeProfileRepository(
            onboardingCompleted: true,
            nickname: null,
          ),
        );
        await openMy(tester, h);
        expect(find.text('먹어보조 사용자'), findsOneWidget);
      },
    );
  });

  group('MY → 계정 설정 → 닉네임 변경', () {
    Future<(Harness, FakeProfileRepository)> openAccount(
      WidgetTester tester,
    ) async {
      final profiles = FakeProfileRepository(
        onboardingCompleted: true,
        nickname: '맛집왕',
      );
      final h = await buildHarness(
        auth: FakeAuthGateway(user: fakeUser()),
        profiles: profiles,
      );
      await pumpApp(tester, h, home: const AppShell());
      await tester.tap(find.text('MY'));
      await tester.pumpAndSettle();
      // The row sits below the fold on a phone: bring it into view first.
      await tester.scrollUntilVisible(
        find.text('계정 설정'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('계정 설정'));
      await tester.pumpAndSettle();
      return (h, profiles);
    }

    testWidgets('is pre-filled, validates, saves and updates MY immediately', (
      tester,
    ) async {
      final (h, profiles) = await openAccount(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      expect(find.text('닉네임 변경'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '맛집왕',
      );

      await tester.enterText(find.byType(TextField), '가');
      await tester.tap(find.text('저장'));
      await tester.pump();
      expect(find.text('닉네임은 2자 이상이어야 해요.'), findsOneWidget);
      expect(profiles.nicknameWrites, isEmpty);

      await tester.enterText(find.byType(TextField), '새 닉네임');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 50));

      expect(profiles.nicknameWrites, ['새 닉네임']);
      expect(find.text('닉네임을 변경했어요.'), findsOneWidget);
      expect(
        find.text('새 닉네임'),
        findsOneWidget,
        reason: 'account settings updated',
      );
      expect(
        h.container.read(authControllerProvider).profile?.nickname,
        '새 닉네임',
      );
      expect(
        h.container.read(authControllerProvider).status,
        AuthStatus.authenticatedReady,
        reason: 'no logout / re-routing',
      );
    });

    testWidgets('a failed save keeps the old nickname and offers retry', (
      tester,
    ) async {
      final (h, profiles) = await openAccount(tester);
      profiles.nicknameErrors.add(
        AuthRetryableFetchException(message: 'offline'),
      );
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '새 닉네임');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(find.text('인터넷 연결을 확인하고 다시 시도해주세요.'), findsOneWidget);
      expect(
        h.container.read(authControllerProvider).profile?.nickname,
        '맛집왕',
        reason: 'old nickname kept',
      );
      expect(find.text('다시 시도'), findsOneWidget, reason: 'retry button');

      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 50));
      expect(profiles.nicknameWrites, ['새 닉네임']);
      expect(
        h.container.read(authControllerProvider).profile?.nickname,
        '새 닉네임',
      );
    });

    testWidgets('saving an unchanged nickname just closes', (tester) async {
      final (_, profiles) = await openAccount(tester);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(profiles.nicknameWrites, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('controller.saveNickname', () {
    test('invalid input never reaches the repository', () async {
      final profiles = FakeProfileRepository(onboardingCompleted: true);
      final h = await buildHarness(
        auth: FakeAuthGateway(user: fakeUser()),
        profiles: profiles,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final f = await h.container
          .read(authControllerProvider.notifier)
          .saveNickname('a');
      expect(f, AuthFailure.nicknameInvalid);
      expect(profiles.nicknameWrites, isEmpty);
    });

    test('guests cannot save a nickname', () async {
      final h = await buildHarness();
      final f = await h.container
          .read(authControllerProvider.notifier)
          .saveNickname('맛집왕');
      expect(f, AuthFailure.sessionExpired);
    });
  });
}

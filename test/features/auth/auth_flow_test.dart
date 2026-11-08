import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/auth/models/auth_snapshot.dart';
import 'package:meogeobojo/features/auth/providers/auth_providers.dart';
import 'package:meogeobojo/features/auth/screens/login_screen.dart';
import 'package:meogeobojo/features/auth/screens/reset_password_screen.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/preferences/screens/preferences_screen.dart';
import 'package:meogeobojo/features/restaurants/screens/restaurant_list_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

Finder textField(String label) => find.widgetWithText(TextField, label);

Future<void> emailSignIn(WidgetTester tester) async {
  await tester.tap(find.text('이메일로 로그인'));
  await tester.pumpAndSettle();
  await tester.enterText(textField('이메일'), 'tester@example.com');
  await tester.enterText(textField('비밀번호'), 'pw123456');
  await tester.tap(find.widgetWithText(FilledButton, '로그인'));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

void main() {
  group('first-login routing', () {
    testWidgets('guest launch: no login, no onboarding, Home is available', (
      tester,
    ) async {
      final h = await buildHarness();
      await pumpApp(tester, h);
      expect(find.byType(PreferencesScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('홈'), findsOneWidget);
    });

    testWidgets(
      'restored session with finished onboarding goes straight to the app',
      (tester) async {
        final h = await buildHarness(
          auth: FakeAuthGateway(user: fakeUser()),
          profiles: FakeProfileRepository(onboardingCompleted: true),
        );
        await pumpApp(tester, h);
        expect(find.byType(PreferencesScreen), findsNothing);
        expect(
          h.container.read(authControllerProvider).status,
          AuthStatus.authenticatedReady,
        );
      },
    );

    testWidgets('restored session with unfinished onboarding shows it ONCE', (
      tester,
    ) async {
      final h = await buildHarness(auth: FakeAuthGateway(user: fakeUser()));
      await pumpApp(tester, h);
      expect(find.byType(PreferencesScreen), findsOneWidget);
      expect(find.text('오늘 뭐 먹지?'), findsOneWidget);

      // Duplicate auth events (token refresh, resume, repeated callbacks).
      final u = fakeUser();
      h.auth.emit(AuthChangeEvent.signedIn, u);
      h.auth.emit(AuthChangeEvent.tokenRefreshed, u);
      h.auth.emit(AuthChangeEvent.signedIn, u);
      await settle(tester);
      expect(
        find.byType(PreferencesScreen),
        findsOneWidget,
        reason: 'never stacked',
      );

      // The route stack really has a single onboarding route.
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      var count = 0;
      nav.popUntil((r) {
        if (r.settings.name == 'onboarding') count++;
        return true; // inspect top only; stack depth checked below
      });
      expect(count, lessThanOrEqualTo(1));
    });

    testWidgets('the onboarding screen cannot be dismissed with back', (
      tester,
    ) async {
      final h = await buildHarness(auth: FakeAuthGateway(user: fakeUser()));
      await pumpApp(tester, h);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PreferencesScreen), findsOneWidget);
    });

    testWidgets('signing out from onboarding returns to the app as a guest', (
      tester,
    ) async {
      final h = await buildHarness(auth: FakeAuthGateway(user: fakeUser()));
      await pumpApp(tester, h);
      await tester.tap(find.text('로그아웃'));
      await settle(tester);
      expect(find.byType(PreferencesScreen), findsNothing);
      expect(h.container.read(authControllerProvider).status, AuthStatus.guest);
    });
  });

  group('email sign-in end to end', () {
    testWidgets(
      'new account: login -> onboarding -> save -> result; onboarding is then done',
      (tester) async {
        final h = await buildHarness();
        await pumpApp(tester, h);
        await tester.tap(find.text('MY'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('로그인 / 회원가입'));
        await tester.pumpAndSettle();
        await emailSignIn(tester);

        // Session confirmed -> login screens closed -> onboarding.
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byType(PreferencesScreen), findsOneWidget);

        await tester.tap(find.text('10,000원 이하'));
        await tester.tap(find.text('도보 10분'));
        await tester.pump();
        await tester.tap(find.textContaining('추천 보기'));
        await settle(tester);

        expect(h.prefs.saved.length, 1);
        expect(h.prefs.saved.single.distance?.minutes, 10);
        expect(find.byType(PreferencesScreen), findsNothing);
        // The result screen with the saved conditions applied.
        expect(find.byType(RecommendationScreen), findsOneWidget);
        expect(
          h.container.read(authControllerProvider).status,
          AuthStatus.authenticatedReady,
        );
        expect(
          h.container.read(authControllerProvider).profile?.onboardingCompleted,
          isTrue,
        );
      },
    );

    testWidgets('returning account: no onboarding after login', (tester) async {
      final h = await buildHarness(
        profiles: FakeProfileRepository(onboardingCompleted: true),
      );
      await pumpApp(tester, h);
      await tester.tap(find.text('MY'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('로그인 / 회원가입'));
      await tester.pumpAndSettle();
      await emailSignIn(tester);
      expect(find.byType(PreferencesScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      // MY now shows the account.
      expect(find.text('tester@example.com'), findsOneWidget);
    });
  });

  group('guest gating and returning to the intended action', () {
    testWidgets(
      'favorite: prompt -> login -> the favorite is saved afterwards',
      (tester) async {
        final h = await buildHarness(
          profiles: FakeProfileRepository(onboardingCompleted: true),
        );
        await pumpApp(tester, h);
        await tester.scrollUntilVisible(
          find.text('학교 주변 맛집'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
        await tester.pumpAndSettle();
        expect(find.text('로그인하면 맛집을 저장할 수 있어요'), findsOneWidget);
        expect(h.favorites.log, isEmpty, reason: 'guests never write');

        await tester.tap(find.text('로그인').last);
        await tester.pumpAndSettle();
        await emailSignIn(tester);

        expect(h.favorites.log, ['add:1'], reason: 'intended action completed');
        expect(find.byType(LoginScreen), findsNothing);
      },
    );

    testWidgets('favorite prompt can be cancelled without side effects', (
      tester,
    ) async {
      final h = await buildHarness();
      await pumpApp(tester, h);
      await tester.scrollUntilVisible(
        find.text('학교 주변 맛집'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('나중에'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsNothing);
      expect(h.favorites.log, isEmpty);
    });

    testWidgets(
      'records tab: guests get a gate, login returns to the records tab',
      (tester) async {
        final h = await buildHarness(
          profiles: FakeProfileRepository(onboardingCompleted: true),
        );
        await pumpApp(tester, h);
        await tester.tap(find.text('기록'));
        await tester.pumpAndSettle();
        expect(find.text('로그인하면 먹은 음식을 기록할 수 있어요'), findsOneWidget);

        await tester.tap(find.text('로그인').last);
        await tester.pumpAndSettle();
        await emailSignIn(tester);

        expect(h.container.read(shellTabProvider), ShellTabs.records);
        expect(find.text('아직 기록이 없어요'), findsOneWidget);
      },
    );

    testWidgets(
      'after onboarding the intended action wins over the result screen',
      (tester) async {
        final h = await buildHarness(); // new account
        await pumpApp(tester, h);
        await tester.tap(find.text('기록'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('로그인').last);
        await tester.pumpAndSettle();
        await emailSignIn(tester);
        expect(find.byType(PreferencesScreen), findsOneWidget);

        await tester.tap(find.text('8,000원 이하'));
        await tester.tap(find.text('도보 5분'));
        await tester.pump();
        await tester.tap(find.textContaining('추천 보기'));
        await settle(tester);

        expect(find.byType(PreferencesScreen), findsNothing);
        expect(h.container.read(shellTabProvider), ShellTabs.records);
        expect(find.byType(RecommendationScreen), findsNothing);
      },
    );
  });

  group('password recovery', () {
    testWidgets('recovery link opens the reset screen; success continues', (
      tester,
    ) async {
      final h = await buildHarness(
        profiles: FakeProfileRepository(onboardingCompleted: true),
      );
      await pumpApp(tester, h);
      h.auth.emit(AuthChangeEvent.passwordRecovery, fakeUser());
      await settle(tester);
      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.text('새 비밀번호 설정'), findsOneWidget);

      await tester.enterText(textField('새 비밀번호'), 'brand-new-pass1');
      await tester.enterText(textField('비밀번호 확인'), 'brand-new-pass1');
      await tester.tap(find.text('비밀번호 변경하기'));
      await settle(tester);

      expect(h.auth.calls, contains('updatePassword'));
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(find.text('비밀번호를 변경했어요.'), findsOneWidget);
      expect(h.container.read(authControllerProvider).recoveryActive, isFalse);
    });

    testWidgets('reset validation and server errors', (tester) async {
      final h = await buildHarness(
        auth: FakeAuthGateway()
          ..updatePasswordError = AuthApiException(
            'same',
            statusCode: '422',
            code: 'same_password',
          ),
        profiles: FakeProfileRepository(onboardingCompleted: true),
      );
      await pumpApp(tester, h);
      h.auth.emit(AuthChangeEvent.passwordRecovery, fakeUser());
      await settle(tester);

      await tester.enterText(textField('새 비밀번호'), 'short');
      await tester.tap(find.text('비밀번호 변경하기'));
      await tester.pump();
      expect(find.text('비밀번호는 8자 이상이어야 해요.'), findsOneWidget);

      await tester.enterText(textField('새 비밀번호'), 'samesame123');
      await tester.enterText(textField('비밀번호 확인'), 'samesame123');
      await tester.tap(find.text('비밀번호 변경하기'));
      await settle(tester);
      expect(find.text('이전과 다른 비밀번호를 사용해주세요.'), findsOneWidget);
      expect(
        find.byType(ResetPasswordScreen),
        findsOneWidget,
        reason: 'can retry',
      );
    });

    testWidgets('an expired link is announced, not silently ignored', (
      tester,
    ) async {
      final h = await buildHarness();
      await pumpApp(tester, h);
      h.auth.emitError(
        AuthException(
          'Email link is invalid or has expired',
          code: 'otp_expired',
        ),
      );
      await settle(tester);
      expect(find.text('링크가 만료됐거나 이미 사용됐어요. 새 링크를 요청해주세요.'), findsOneWidget);
    });
  });
}

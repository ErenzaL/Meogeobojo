import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/l10n/app_language.dart';
import 'package:meogeobojo/core/l10n/language_controller.dart';
import 'package:meogeobojo/features/auth/models/auth_snapshot.dart';
import 'package:meogeobojo/features/auth/providers/auth_providers.dart';
import 'package:meogeobojo/features/auth/screens/login_screen.dart';
import 'package:meogeobojo/features/auth/screens/verification_pending_screen.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/university/providers/university_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

Finder textField(String label) => find.widgetWithText(TextField, label);

void main() {
  group('login landing screen', () {
    testWidgets('shows the required elements in Korean', (tester) async {
      final h = await buildHarness();
      await pumpApp(tester, h, home: const LoginScreen());

      expect(find.text('먹어보조에 오신 걸 환영해요!'), findsOneWidget);
      expect(find.text('로그인하고 나만의 맛집을 찾아보세요.'), findsOneWidget);
      expect(find.text('카카오로 계속하기'), findsOneWidget);
      expect(find.text('이메일로 로그인'), findsOneWidget);
      expect(find.text('이메일로 회원가입'), findsOneWidget);
      expect(find.text('로그인 없이 계속 둘러보기 →'), findsOneWidget);
      expect(find.text('이용약관'), findsOneWidget);
      expect(find.text('개인정보처리방침'), findsOneWidget);
      expect(find.byIcon(Icons.language_rounded), findsOneWidget);
      expect(find.byType(Image), findsOneWidget, reason: 'the existing mascot');
      expect(tester.takeException(), isNull);
    });

    testWidgets('legal links never invent a URL: unpublished -> says so', (
      tester,
    ) async {
      final h = await buildHarness();
      await pumpApp(tester, h, home: const LoginScreen());
      await tester.tap(find.text('이용약관'));
      await tester.pump();
      expect(find.text('문서가 아직 게시되지 않았어요.'), findsOneWidget);
    });

    testWidgets(
      'language globe switches ko -> en -> zh instantly, no restart',
      (tester) async {
        final h = await buildHarness();
        await pumpApp(tester, h, home: const LoginScreen());

        await tester.tap(find.byIcon(Icons.language_rounded));
        await tester.pumpAndSettle();
        expect(find.text('한국어'), findsOneWidget);
        expect(find.text('English'), findsOneWidget);
        expect(find.text('简体中文'), findsOneWidget);
        // current language is highlighted
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

        await tester.tap(find.text('English'));
        await tester.pumpAndSettle();
        expect(find.text('Welcome to 먹어보조!'), findsOneWidget);
        expect(find.text('Continue with Kakao'), findsOneWidget);
        expect(find.text('Sign in with email'), findsOneWidget);
        expect(find.text('Continue without signing in →'), findsOneWidget);
        expect(find.text('먹어보조에 오신 걸 환영해요!'), findsNothing);
        expect(h.container.read(appLanguageProvider), AppLanguage.en);

        await tester.tap(find.byIcon(Icons.language_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('简体中文'));
        await tester.pumpAndSettle();
        expect(find.text('欢迎来到 먹어보조！'), findsOneWidget);
        expect(find.text('使用 Kakao 继续'), findsOneWidget);
        expect(find.text('使用邮箱登录'), findsOneWidget);
        expect(find.text('无需登录，继续浏览 →'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the app name is never translated', (tester) async {
      final h = await buildHarness(storage: {'app_language': 'en'});
      await pumpApp(tester, h, home: const LoginScreen());
      expect(find.textContaining('먹어보조'), findsOneWidget);
      expect(find.textContaining('Meogeobojo'), findsNothing);
    });

    testWidgets('Kakao tap opens the flow but is NOT a login', (tester) async {
      final h = await buildHarness();
      await pumpApp(tester, h, home: const LoginScreen());
      await tester.tap(find.text('카카오로 계속하기'));
      await tester.pump();
      expect(h.auth.calls, contains('signInWithKakao'));
      expect(find.text('카카오 로그인 진행 중…'), findsOneWidget);
      expect(h.container.read(authControllerProvider).isSignedIn, isFalse);
      // other sign-in paths are disabled while waiting
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '이메일로 로그인'))
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('취소'));
      await tester.pump();
      expect(find.text('카카오 로그인을 취소했어요.'), findsOneWidget);
      expect(find.text('카카오로 계속하기'), findsOneWidget, reason: 'retry possible');
    });

    testWidgets('Kakao: returning without a callback shows a retryable error', (
      tester,
    ) async {
      final h = await buildHarness();
      await pumpApp(tester, h, home: const LoginScreen());
      await tester.tap(find.text('카카오로 계속하기'));
      await tester.pump();
      h.container.read(authControllerProvider.notifier).kakaoReturnedToApp();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.textContaining('로그인이 완료되지 않았어요'), findsOneWidget);
      expect(find.text('카카오로 계속하기'), findsOneWidget);
    });

    testWidgets(
      '"continue without signing in" goes to Home and keeps the university',
      (tester) async {
        final h = await buildHarness(
          storage: {
            'app_language': 'ko',
            'selected_university_id': '5c0a8f3e-0003-4a6e-9b1d-000000000003',
          },
        );
        await pumpApp(tester, h, home: const AppShell());
        // MY tab -> login -> guest link
        await tester.tap(find.text('MY'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('로그인 / 회원가입'));
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);

        await tester.tap(find.text('로그인 없이 계속 둘러보기 →'));
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsNothing);
        expect(h.container.read(shellTabProvider), ShellTabs.home);
        expect(
          h.container.read(selectedUniversityProvider).value!.nameKo,
          '선문대학교',
        );
      },
    );
  });

  group('email login', () {
    Future<void> openEmailLogin(WidgetTester tester, Harness h) async {
      await pumpApp(tester, h, home: const LoginScreen());
      await tester.tap(find.text('이메일로 로그인'));
      await tester.pumpAndSettle();
    }

    testWidgets('validates before calling Supabase', (tester) async {
      final h = await buildHarness();
      await openEmailLogin(tester, h);
      await tester.tap(find.widgetWithText(FilledButton, '로그인'));
      await tester.pump();
      expect(find.text('이메일을 입력해주세요.'), findsOneWidget);
      expect(find.text('비밀번호를 입력해주세요.'), findsOneWidget);
      expect(h.auth.calls, isEmpty);

      await tester.enterText(textField('이메일'), 'not-an-email');
      await tester.tap(find.widgetWithText(FilledButton, '로그인'));
      await tester.pump();
      expect(find.text('올바른 이메일 형식이 아니에요.'), findsOneWidget);
    });

    testWidgets('password visibility toggle works', (tester) async {
      final h = await buildHarness();
      await openEmailLogin(tester, h);
      TextField pw() => tester.widget<TextField>(textField('비밀번호'));
      expect(pw().obscureText, isTrue);
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(pw().obscureText, isFalse);
    });

    testWidgets(
      'wrong password shows a friendly Korean error, no stack trace',
      (tester) async {
        final h = await buildHarness(
          auth: FakeAuthGateway()
            ..signInError = AuthApiException(
              'Invalid login credentials',
              statusCode: '400',
              code: 'invalid_credentials',
            ),
        );
        await openEmailLogin(tester, h);
        await tester.enterText(textField('이메일'), 'a@b.co');
        await tester.enterText(textField('비밀번호'), 'wrong-pass');
        await tester.tap(find.widgetWithText(FilledButton, '로그인'));
        await tester.pumpAndSettle();
        expect(find.text('이메일 또는 비밀번호가 올바르지 않아요.'), findsOneWidget);
        expect(find.textContaining('Invalid login'), findsNothing);
        expect(h.container.read(authControllerProvider).isSignedIn, isFalse);
      },
    );

    testWidgets('unverified account offers to resend the verification email', (
      tester,
    ) async {
      final h = await buildHarness(
        auth: FakeAuthGateway()
          ..signInError = AuthApiException(
            'Email not confirmed',
            statusCode: '400',
            code: 'email_not_confirmed',
          ),
      );
      await openEmailLogin(tester, h);
      await tester.enterText(textField('이메일'), 'a@b.co');
      await tester.enterText(textField('비밀번호'), 'pw123456');
      await tester.tap(find.widgetWithText(FilledButton, '로그인'));
      await tester.pumpAndSettle();
      expect(find.textContaining('이메일 인증이 아직 완료되지 않았어요'), findsOneWidget);
      await tester.tap(find.text('인증 메일 다시 받기'));
      await tester.pumpAndSettle();
      expect(h.auth.calls, contains('resend:a@b.co'));
      expect(find.byType(VerificationPendingScreen), findsOneWidget);
    });

    testWidgets(
      'switching language keeps typed values and re-translates visible errors',
      (tester) async {
        final h = await buildHarness();
        await openEmailLogin(tester, h);
        await tester.enterText(textField('이메일'), 'keep@me.co');
        await tester.tap(
          find.widgetWithText(FilledButton, '로그인'),
        ); // password missing
        await tester.pump();
        expect(find.text('비밀번호를 입력해주세요.'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.language_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('English'));
        await tester.pumpAndSettle();

        expect(find.text('Enter your password.'), findsOneWidget);
        expect(find.text('비밀번호를 입력해주세요.'), findsNothing);
        expect(
          tester.widget<TextField>(textField('Email')).controller!.text,
          'keep@me.co',
          reason: 'the form is not reset by a language change',
        );
        expect(
          h.auth.calls,
          isEmpty,
          reason: 'no auth request was interrupted',
        );
      },
    );

    testWidgets('forgot password sends a recovery email and gives feedback', (
      tester,
    ) async {
      final h = await buildHarness();
      await openEmailLogin(tester, h);
      await tester.enterText(textField('이메일'), 'forgot@me.co');
      await tester.tap(find.text('비밀번호를 잊으셨나요?'));
      await tester.pumpAndSettle();
      expect(find.text('비밀번호 찾기'), findsOneWidget);
      // email carried over
      expect(
        tester.widget<TextField>(textField('이메일')).controller!.text,
        'forgot@me.co',
      );
      await tester.tap(find.text('재설정 메일 보내기'));
      await tester.pumpAndSettle();
      expect(h.auth.calls, contains('reset:forgot@me.co'));
      expect(find.textContaining('재설정 링크를 보냈어요'), findsOneWidget);
    });

    testWidgets('forgot password failure is reported', (tester) async {
      final h = await buildHarness(
        auth: FakeAuthGateway()..resetError = StateError('x'),
      );
      await openEmailLogin(tester, h);
      await tester.enterText(textField('이메일'), 'forgot@me.co');
      await tester.tap(find.text('비밀번호를 잊으셨나요?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('재설정 메일 보내기'));
      await tester.pumpAndSettle();
      expect(find.text('비밀번호 재설정에 실패했어요. 다시 시도해주세요.'), findsOneWidget);
    });
  });

  group('email sign-up', () {
    Future<void> openSignUp(WidgetTester tester, Harness h) async {
      await pumpApp(tester, h, home: const LoginScreen());
      await tester.tap(find.text('이메일로 회원가입'));
      await tester.pumpAndSettle();
    }

    testWidgets('requires a long enough password and a matching confirmation', (
      tester,
    ) async {
      final h = await buildHarness();
      await openSignUp(tester, h);
      await tester.enterText(textField('이메일'), 'new@b.co');
      await tester.enterText(textField('비밀번호'), 'short');
      await tester.tap(find.text('가입하기'));
      await tester.pump();
      expect(find.text('비밀번호는 8자 이상이어야 해요.'), findsOneWidget);

      await tester.enterText(textField('비밀번호'), 'longenough1');
      await tester.enterText(textField('비밀번호 확인'), 'different1');
      await tester.tap(find.text('가입하기'));
      await tester.pump();
      expect(find.text('비밀번호가 서로 달라요.'), findsOneWidget);
      expect(h.auth.calls, isEmpty);
    });

    testWidgets(
      'success without a session shows verification-pending, not the app',
      (tester) async {
        final h = await buildHarness();
        await openSignUp(tester, h);
        await tester.enterText(textField('이메일'), 'new@b.co');
        await tester.enterText(textField('비밀번호'), 'longenough1');
        await tester.enterText(textField('비밀번호 확인'), 'longenough1');
        await tester.tap(find.text('가입하기'));
        await tester.pumpAndSettle();

        expect(find.byType(VerificationPendingScreen), findsOneWidget);
        expect(find.text('이메일을 확인해주세요'), findsOneWidget);
        expect(find.textContaining('new@b.co'), findsOneWidget);
        expect(find.text('인증을 마치기 전까지는 로그인되지 않아요.'), findsOneWidget);
        final snap = h.container.read(authControllerProvider);
        expect(snap.status, AuthStatus.emailVerificationPending);
        expect(snap.isSignedIn, isFalse);

        // resend is rate-limited by a visible cooldown
        expect(find.textContaining('초 뒤에 다시 보낼 수 있어요'), findsOneWidget);

        await tester.tap(find.text('로그인으로 돌아가기'));
        await tester.pumpAndSettle();
        expect(find.byType(VerificationPendingScreen), findsNothing);
        expect(find.text('카카오로 계속하기'), findsOneWidget);
        expect(
          h.container.read(authControllerProvider).status,
          AuthStatus.guest,
        );
      },
    );

    testWidgets('already-registered email is reported', (tester) async {
      final h = await buildHarness(
        auth: FakeAuthGateway()
          ..signUpResponse = AuthResponse(user: fakeUser(identities: const [])),
      );
      await openSignUp(tester, h);
      await tester.enterText(textField('이메일'), 'taken@b.co');
      await tester.enterText(textField('비밀번호'), 'longenough1');
      await tester.enterText(textField('비밀번호 확인'), 'longenough1');
      await tester.tap(find.text('가입하기'));
      await tester.pumpAndSettle();
      expect(find.text('이미 가입된 이메일이에요. 로그인해주세요.'), findsOneWidget);
      expect(find.byType(VerificationPendingScreen), findsNothing);
    });

    testWidgets('no overflow in English / Chinese on a small phone', (
      tester,
    ) async {
      for (final lang in ['en', 'zh-Hans']) {
        final h = await buildHarness(storage: {'app_language': lang});
        await pumpApp(
          tester,
          h,
          home: const LoginScreen(),
          size: const Size(320, 568),
        );
        expect(tester.takeException(), isNull, reason: 'login $lang');
        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'sign-up $lang');
      }
    });
  });
}

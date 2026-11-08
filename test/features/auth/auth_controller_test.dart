import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/l10n/app_language.dart';
import 'package:meogeobojo/core/l10n/language_controller.dart';
import 'package:meogeobojo/features/auth/models/auth_failure.dart';
import 'package:meogeobojo/features/auth/models/auth_snapshot.dart';
import 'package:meogeobojo/features/auth/providers/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

Future<void> tick([int ms = 20]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

AuthSnapshot snap(Harness h) => h.container.read(authControllerProvider);

void main() {
  group('session restore (app launch)', () {
    test('no stored session -> guest', () async {
      final h = await buildHarness();
      expect(snap(h).status, AuthStatus.guest);
      expect(snap(h).isSignedIn, isFalse);
    });

    test(
      'stored session + completed onboarding -> ready, no onboarding',
      () async {
        final h = await buildHarness(
          auth: FakeAuthGateway(user: fakeUser()),
          profiles: FakeProfileRepository(
            onboardingCompleted: true,
            nickname: '민수',
          ),
        );
        expect(snap(h).status, AuthStatus.initializing);
        expect(
          snap(h).isSignedIn,
          isTrue,
          reason: 'session is known immediately',
        );
        await tick();
        expect(snap(h).status, AuthStatus.authenticatedReady);
        expect(snap(h).profile?.nickname, '민수');
      },
    );

    test('stored session + onboarding not done -> needs onboarding', () async {
      final h = await buildHarness(auth: FakeAuthGateway(user: fakeUser()));
      await tick();
      expect(snap(h).status, AuthStatus.authenticatedNeedsOnboarding);
    });

    test(
      'profile load failure -> error state that keeps the session; retry works',
      () async {
        final profiles = FakeProfileRepository(onboardingCompleted: true)
          ..loadError = const PostgrestException(message: 'down');
        final h = await buildHarness(
          auth: FakeAuthGateway(user: fakeUser()),
          profiles: profiles,
        );
        await tick();
        expect(snap(h).status, AuthStatus.error);
        expect(snap(h).failure, AuthFailure.profileLoadFailed);
        expect(
          snap(h).isSignedIn,
          isTrue,
          reason: 'still signed in, just no profile',
        );

        profiles.loadError = null;
        await h.container.read(authControllerProvider.notifier).retryProfile();
        expect(snap(h).status, AuthStatus.authenticatedReady);
        expect(snap(h).failure, isNull);
      },
    );
  });

  group('email sign-in / sign-up', () {
    test('success -> signed in, then profile decides the route', () async {
      final h = await buildHarness(
        profiles: FakeProfileRepository(onboardingCompleted: true),
      );
      final f = await h.container
          .read(authControllerProvider.notifier)
          .signInWithEmail(' a@b.co ', 'pw123456');
      expect(f, isNull);
      await tick();
      expect(snap(h).status, AuthStatus.authenticatedReady);
      expect(snap(h).user?.email, 'a@b.co', reason: 'email is trimmed');
    });

    test(
      'wrong password -> guest + invalidCredentials, never signed in',
      () async {
        final gw = FakeAuthGateway()
          ..signInError = AuthApiException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          );
        final h = await buildHarness(auth: gw);
        final f = await h.container
            .read(authControllerProvider.notifier)
            .signInWithEmail('a@b.co', 'nope');
        expect(f, AuthFailure.invalidCredentials);
        expect(snap(h).status, AuthStatus.guest);
        expect(snap(h).isSignedIn, isFalse);
      },
    );

    test('unverified email -> emailNotConfirmed', () async {
      final gw = FakeAuthGateway()
        ..signInError = AuthApiException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        );
      final h = await buildHarness(auth: gw);
      final f = await h.container
          .read(authControllerProvider.notifier)
          .signInWithEmail('a@b.co', 'pw123456');
      expect(f, AuthFailure.emailNotConfirmed);
    });

    test(
      'sign-up WITHOUT a session -> verification pending, NOT authenticated',
      () async {
        final h = await buildHarness();
        final f = await h.container
            .read(authControllerProvider.notifier)
            .signUpWithEmail('new@b.co', 'pw123456');
        expect(f, isNull);
        expect(snap(h).status, AuthStatus.emailVerificationPending);
        expect(snap(h).pendingEmail, 'new@b.co');
        expect(
          snap(h).user,
          isNull,
          reason: 'must not pretend to be signed in',
        );
        expect(snap(h).isSignedIn, isFalse);
      },
    );

    test('sign-up for an already-registered email is detected', () async {
      final gw = FakeAuthGateway()
        ..signUpResponse = AuthResponse(user: fakeUser(identities: const []));
      final h = await buildHarness(auth: gw);
      final f = await h.container
          .read(authControllerProvider.notifier)
          .signUpWithEmail('taken@b.co', 'pw123456');
      expect(f, AuthFailure.emailTaken);
      expect(snap(h).status, AuthStatus.guest);
    });

    test('sign-up with auto-confirm (real session) signs in', () async {
      final u = fakeUser();
      final gw = FakeAuthGateway()
        ..signUpResponse = AuthResponse(user: u, session: fakeSession(u));
      final h = await buildHarness(auth: gw);
      await h.container
          .read(authControllerProvider.notifier)
          .signUpWithEmail('a@b.co', 'pw123456');
      await tick();
      expect(snap(h).isSignedIn, isTrue);
    });

    test('weak password from the server is reported', () async {
      final gw = FakeAuthGateway()
        ..signUpError = AuthApiException(
          'weak',
          statusCode: '422',
          code: 'weak_password',
        );
      final h = await buildHarness(auth: gw);
      final f = await h.container
          .read(authControllerProvider.notifier)
          .signUpWithEmail('a@b.co', 'x');
      expect(f, AuthFailure.weakPassword);
    });

    test('cancelVerification returns to guest', () async {
      final h = await buildHarness();
      final c = h.container.read(authControllerProvider.notifier);
      await c.signUpWithEmail('new@b.co', 'pw123456');
      c.cancelVerification();
      expect(snap(h).status, AuthStatus.guest);
      expect(snap(h).pendingEmail, isNull);
    });
  });

  group('Kakao OAuth', () {
    test('opening the browser is NOT a login', () async {
      final h = await buildHarness();
      final f = await h.container
          .read(authControllerProvider.notifier)
          .startKakaoSignIn();
      expect(f, isNull);
      expect(h.auth.calls, contains('signInWithKakao'));
      expect(snap(h).status, AuthStatus.authenticating);
      expect(snap(h).isSignedIn, isFalse);
    });

    test('a real session on the stream completes the login', () async {
      final h = await buildHarness(
        profiles: FakeProfileRepository(onboardingCompleted: true),
      );
      await h.container
          .read(authControllerProvider.notifier)
          .startKakaoSignIn();
      h.auth.emit(
        AuthChangeEvent.signedIn,
        fakeUser(provider: 'kakao', email: null, metadata: {'name': '카카오유저'}),
      );
      await tick();
      expect(snap(h).status, AuthStatus.authenticatedReady);
      expect(
        snap(h).user?.email,
        isNull,
        reason: 'Kakao may not share an email',
      );
    });

    test('browser could not open -> failure, back to guest', () async {
      final gw = FakeAuthGateway()..kakaoOpens = false;
      final h = await buildHarness(auth: gw);
      final f = await h.container
          .read(authControllerProvider.notifier)
          .startKakaoSignIn();
      expect(f, AuthFailure.unknown);
      expect(snap(h).status, AuthStatus.guest);
    });

    test('returning to the app with no callback -> deepLinkMissing', () async {
      final h = await buildHarness();
      final c = h.container.read(authControllerProvider.notifier);
      await c.startKakaoSignIn();
      c.kakaoReturnedToApp();
      expect(
        snap(h).status,
        AuthStatus.authenticating,
        reason: 'grace period first',
      );
      await tick(120);
      expect(snap(h).status, AuthStatus.guest);
      expect(snap(h).failure, AuthFailure.deepLinkMissing);
    });

    test(
      'a callback during the grace period wins (no false failure)',
      () async {
        final h = await buildHarness();
        final c = h.container.read(authControllerProvider.notifier);
        await c.startKakaoSignIn();
        c.kakaoReturnedToApp();
        h.auth.emit(AuthChangeEvent.signedIn, fakeUser(provider: 'kakao'));
        await tick(120);
        expect(snap(h).isSignedIn, isTrue);
        expect(snap(h).failure, isNull);
      },
    );

    test(
      'closing the system auth sheet is a cancellation, not an error',
      () async {
        final gw = FakeAuthGateway()
          ..kakaoError = PlatformException(code: 'CANCELED');
        final h = await buildHarness(auth: gw);
        final f = await h.container
            .read(authControllerProvider.notifier)
            .startKakaoSignIn();
        expect(f, AuthFailure.kakaoCancelled);
        expect(snap(h).status, AuthStatus.guest);
        expect(snap(h).isSignedIn, isFalse);
      },
    );

    test(
      'no "callback missing" timer races the auth sheet while it is open',
      () async {
        final gate = Completer<void>();
        final gw = FakeAuthGateway()..kakaoGate = gate;
        final h = await buildHarness(auth: gw);
        final c = h.container.read(authControllerProvider.notifier);
        final pending = c.startKakaoSignIn();
        await tick();
        c.kakaoReturnedToApp(); // app lifecycle noise while the sheet is up
        await tick(150); // longer than the grace period
        expect(
          snap(h).status,
          AuthStatus.authenticating,
          reason: 'still waiting',
        );
        expect(snap(h).failure, isNull);
        // user finishes; the SDK emits the session
        h.auth.emit(AuthChangeEvent.signedIn, fakeUser(provider: 'kakao'));
        gate.complete();
        expect(await pending, isNull);
        await tick();
        expect(snap(h).isSignedIn, isTrue);
      },
    );

    test('a duplicate delivery of the callback right after sign-in is ignored', () async {
      final h = await buildHarness(
        profiles: FakeProfileRepository(onboardingCompleted: true),
      );
      h.auth.emit(AuthChangeEvent.signedIn, fakeUser(provider: 'kakao'));
      await tick();
      // The same one-time code arriving a second time is rejected by Supabase.
      h.auth.emitError(
        AuthException('flow state not found', code: 'flow_state_not_found'),
      );
      await tick();
      expect(snap(h).failure, isNull);
      expect(snap(h).isSignedIn, isTrue);
    });

    test('user cancel while waiting', () async {
      final h = await buildHarness();
      final c = h.container.read(authControllerProvider.notifier);
      await c.startKakaoSignIn();
      c.cancelAuthenticating();
      expect(snap(h).status, AuthStatus.guest);
      expect(snap(h).failure, AuthFailure.kakaoCancelled);
    });

    test('provider error delivered via the auth stream is surfaced', () async {
      final h = await buildHarness();
      await h.container
          .read(authControllerProvider.notifier)
          .startKakaoSignIn();
      h.auth.emitError(
        AuthException('Unable to exchange external code', code: 'server_error'),
      );
      await tick();
      expect(snap(h).status, AuthStatus.guest);
      expect(snap(h).failure, AuthFailure.kakaoConfig);
    });
  });

  group('event handling', () {
    test(
      'duplicate signedIn / tokenRefreshed events never reload the profile',
      () async {
        final profiles = FakeProfileRepository(onboardingCompleted: true);
        final h = await buildHarness(profiles: profiles);
        final u = fakeUser();
        h.auth.emit(AuthChangeEvent.signedIn, u);
        await tick();
        h.auth.emit(AuthChangeEvent.signedIn, u);
        h.auth.emit(AuthChangeEvent.tokenRefreshed, u);
        h.auth.emit(AuthChangeEvent.initialSession, u);
        await tick();
        expect(profiles.loads, 1);
        expect(snap(h).status, AuthStatus.authenticatedReady);
      },
    );

    test('sign out returns to guest and drops the profile', () async {
      final h = await buildHarness(
        auth: FakeAuthGateway(user: fakeUser()),
        profiles: FakeProfileRepository(onboardingCompleted: true),
      );
      await tick();
      await h.container.read(authControllerProvider.notifier).signOut();
      expect(snap(h).status, AuthStatus.guest);
      expect(snap(h).profile, isNull);
      expect(snap(h).user, isNull);
    });

    test('account switching loads the new account\'s profile', () async {
      final profiles = FakeProfileRepository(onboardingCompleted: true);
      final h = await buildHarness(profiles: profiles);
      h.auth.emit(AuthChangeEvent.signedIn, fakeUser(id: 'A'));
      await tick();
      expect(snap(h).user?.id, 'A');
      h.auth.emit(AuthChangeEvent.signedIn, fakeUser(id: 'B'));
      await tick();
      expect(snap(h).user?.id, 'B');
      expect(snap(h).profile?.id, 'B');
      expect(profiles.loads, 2);
    });

    test('password recovery link flags recovery mode', () async {
      final h = await buildHarness();
      h.auth.emit(AuthChangeEvent.passwordRecovery, fakeUser());
      await tick();
      expect(snap(h).recoveryActive, isTrue);
      h.container.read(authControllerProvider.notifier).finishRecovery();
      expect(snap(h).recoveryActive, isFalse);
    });

    test('expired confirmation / recovery link -> linkExpired', () async {
      final h = await buildHarness();
      h.auth.emitError(
        AuthException(
          'Email link is invalid or has expired',
          code: 'otp_expired',
        ),
      );
      await tick();
      expect(snap(h).failure, AuthFailure.linkExpired);
    });

    test(
      'expired session while signed in -> signed out with sessionExpired',
      () async {
        final h = await buildHarness(
          auth: FakeAuthGateway(user: fakeUser()),
          profiles: FakeProfileRepository(onboardingCompleted: true),
        );
        await tick();
        h.auth.emitError(
          AuthException(
            'Invalid Refresh Token',
            code: 'refresh_token_not_found',
          ),
        );
        await tick();
        expect(snap(h).status, AuthStatus.guest);
        expect(snap(h).failure, AuthFailure.sessionExpired);
      },
    );

    test(
      'a flaky connection while signed in does not sign the user out',
      () async {
        final h = await buildHarness(
          auth: FakeAuthGateway(user: fakeUser()),
          profiles: FakeProfileRepository(onboardingCompleted: true),
        );
        await tick();
        h.auth.emitError(AuthRetryableFetchException(message: 'offline'));
        await tick();
        expect(snap(h).isSignedIn, isTrue);
        expect(snap(h).failure, isNull);
      },
    );
  });

  group('password flows', () {
    test('reset email success and failure', () async {
      final h = await buildHarness();
      final c = h.container.read(authControllerProvider.notifier);
      expect(await c.sendPasswordReset('a@b.co'), isNull);
      expect(h.auth.calls, contains('reset:a@b.co'));

      h.auth.resetError = StateError('boom');
      expect(
        await c.sendPasswordReset('a@b.co'),
        AuthFailure.passwordResetFailed,
      );
    });

    test('update password: same-as-old is reported', () async {
      final gw = FakeAuthGateway()
        ..updatePasswordError = AuthApiException(
          'same',
          statusCode: '422',
          code: 'same_password',
        );
      final h = await buildHarness(auth: gw);
      expect(
        await h.container
            .read(authControllerProvider.notifier)
            .updatePassword('x'),
        AuthFailure.samePassword,
      );
    });
  });

  group('language sync with the account', () {
    test('explicit local choice wins and is written to the account', () async {
      final profiles = FakeProfileRepository(onboardingCompleted: true)
        ..preferredLanguage = 'en';
      final h = await buildHarness(
        storage: {'app_language': 'zh-Hans'},
        profiles: profiles,
      );
      h.auth.emit(AuthChangeEvent.signedIn, fakeUser());
      await tick();
      expect(h.container.read(appLanguageProvider), AppLanguage.zhHans);
      expect(profiles.languageWrites, ['zh-Hans']);
    });

    test('fresh device: the account language is restored', () async {
      final profiles = FakeProfileRepository(onboardingCompleted: true)
        ..preferredLanguage = 'en';
      final h = await buildHarness(storage: {}, profiles: profiles);
      expect(
        h.container.read(appLanguageProvider),
        AppLanguage.ko,
        reason: 'device default',
      );
      h.auth.emit(AuthChangeEvent.signedIn, fakeUser());
      await tick();
      expect(h.container.read(appLanguageProvider), AppLanguage.en);
      expect(profiles.languageWrites, isEmpty);
    });

    test('changing language while signed in syncs it; guests never touch the account', () async {
      final profiles = FakeProfileRepository(onboardingCompleted: true);
      final h = await buildHarness(
        storage: {'app_language': 'ko'},
        profiles: profiles,
      );
      // guest change: no account write
      await h.container.read(languageProvider.notifier).select(AppLanguage.en);
      expect(profiles.languageWrites, isEmpty);

      h.auth.emit(AuthChangeEvent.signedIn, fakeUser());
      await tick();
      profiles.languageWrites.clear();
      await h.container
          .read(languageProvider.notifier)
          .select(AppLanguage.zhHans);
      await tick();
      expect(profiles.languageWrites, ['zh-Hans']);
    });

    test(
      'signing in never switches language based on account metadata',
      () async {
        final h = await buildHarness(
          storage: {'app_language': 'en'},
          profiles: FakeProfileRepository(onboardingCompleted: true),
        );
        h.auth.emit(
          AuthChangeEvent.signedIn,
          fakeUser(
            provider: 'kakao',
            metadata: {'locale': 'ko', 'name': '홍길동'},
          ),
        );
        await tick();
        expect(h.container.read(appLanguageProvider), AppLanguage.en);
      },
    );
  });
}

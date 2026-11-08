import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/auth/models/auth_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

AuthFailure f(String message, {String? code, String? status}) =>
    authFailureFrom(AuthException(message, code: code, statusCode: status));

void main() {
  group('authFailureFrom', () {
    test('maps Supabase error codes', () {
      expect(
        f('x', code: 'invalid_credentials'),
        AuthFailure.invalidCredentials,
      );
      expect(
        f('x', code: 'email_not_confirmed'),
        AuthFailure.emailNotConfirmed,
      );
      expect(f('x', code: 'user_already_exists'), AuthFailure.emailTaken);
      expect(f('x', code: 'weak_password'), AuthFailure.weakPassword);
      expect(f('x', code: 'same_password'), AuthFailure.samePassword);
      expect(
        f('x', code: 'over_email_send_rate_limit'),
        AuthFailure.rateLimited,
      );
      expect(f('x', code: 'otp_expired'), AuthFailure.linkExpired);
      expect(
        f('x', code: 'refresh_token_not_found'),
        AuthFailure.sessionExpired,
      );
      expect(f('x', code: 'provider_disabled'), AuthFailure.kakaoConfig);
      expect(f('x', code: 'server_error'), AuthFailure.kakaoConfig);
      expect(
        f('Invalid scope%3A account_email', code: 'invalid_scope'),
        AuthFailure.kakaoConfig,
      );
      expect(f('x', code: 'access_denied'), AuthFailure.kakaoCancelled);
    });

    test('falls back to message matching for older servers', () {
      expect(f('Invalid login credentials'), AuthFailure.invalidCredentials);
      expect(f('Email not confirmed'), AuthFailure.emailNotConfirmed);
      expect(f('User already registered'), AuthFailure.emailTaken);
      expect(
        f('Password should be at least 6 characters'),
        AuthFailure.weakPassword,
      );
      expect(
        f('Email link is invalid or has expired'),
        AuthFailure.linkExpired,
      );
      expect(f('boom', status: '429'), AuthFailure.rateLimited);
      expect(
        f('Unable to exchange external code: abc'),
        AuthFailure.kakaoConfig,
      );
    });

    test('network, timeout and permission problems', () {
      expect(
        authFailureFrom(AuthRetryableFetchException(message: 'offline')),
        AuthFailure.network,
      );
      expect(authFailureFrom(TimeoutException('slow')), AuthFailure.timeout);
      expect(
        authFailureFrom(
          const PostgrestException(message: 'denied', code: '42501'),
        ),
        AuthFailure.permissionDenied,
      );
      expect(authFailureFrom(StateError('?')), AuthFailure.unknown);
    });

    test('closing the system auth sheet is a cancellation', () {
      expect(
        authFailureFrom(PlatformException(code: 'CANCELED')),
        AuthFailure.kakaoCancelled,
      );
    });

    test('never leaks the raw server message', () {
      // The enum carries no free text, so raw messages cannot reach the UI.
      expect(
        f('secret internal stack trace: db password=hunter2'),
        AuthFailure.unknown,
      );
    });
  });
}

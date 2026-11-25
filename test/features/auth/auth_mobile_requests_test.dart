import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, DebugPrintCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:meogeobojo/features/auth/models/auth_failure.dart';
import 'package:meogeobojo/features/auth/services/auth_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Regression: on iOS and Android e-mail sign-up showed "문제가 생겼어요" and no request ever reached Supabase.
///
/// Cause: the redirect URL was built with `Uri.base.origin`, which THROWS on a phone (`Uri.base` is a `file://` URI),
/// and it was evaluated as an argument of signUp / resend / reset-password / Android Kakao login. These tests run on the
/// Dart VM, where `Uri.base` is a `file://` URI exactly as on a phone, and use the real gateway and the real
/// supabase auth client against a recording fake server.
class _RecordingClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final bodies = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = await request.finalize().bytesToString();
    bodies.add(body);
    final user = {
      'id': '11111111-1111-4111-8111-111111111111',
      'aud': 'authenticated',
      'email': 'student@example.org',
      'created_at': '2026-11-24T00:00:00Z',
      'app_metadata': <String, Object?>{},
      'user_metadata': <String, Object?>{},
      'identities': [
        {
          'identity_id': 'i1',
          'id': 'i1',
          'user_id': '11111111-1111-4111-8111-111111111111',
          'identity_data': <String, Object?>{},
          'provider': 'email',
        },
      ],
    };
    final json = request.url.path.endsWith('/signup') ? user : <String, Object?>{};
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(json))),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

SupabaseAuthGateway _gateway(_RecordingClient client) => SupabaseAuthGateway(
  GoTrueClient(
    url: 'https://example.supabase.co/auth/v1',
    headers: const {'apikey': 'sb_publishable_test'},
    httpClient: client,
    flowType: AuthFlowType.implicit,
    autoRefreshToken: false,
  ),
);

void main() {
  test('the test really runs where Uri.base.origin would throw (like a phone)', () {
    expect(Uri.base.scheme, 'file');
    expect(() => Uri.base.origin, throwsStateError);
  });

  group('currentAuthRedirectUrl', () {
    test('mobile: the registered custom scheme, WITHOUT reading Uri.base.origin', () {
      expect(currentAuthRedirectUrl(web: false), kAuthRedirectUrl);
      expect(
        currentAuthRedirectUrl(web: false, base: Uri.parse('file:///data/user/0/app/')),
        'com.meogeobojo.app://login-callback/',
      );
      // no argument at all = the running platform (the VM here: not web)
      expect(currentAuthRedirectUrl(), kAuthRedirectUrl);
    });

    test('web: the site itself with a trailing slash', () {
      expect(
        currentAuthRedirectUrl(web: true, base: Uri.parse('https://meogeobojo.onrender.com/#/home')),
        'https://meogeobojo.onrender.com/',
      );
    });
  });

  group('the gateway sends its requests on a phone', () {
    test('signUp reaches the server and carries the app redirect', () async {
      final client = _RecordingClient();
      final res = await _gateway(client).signUp(email: 'student@example.org', password: 'Aa1!aaaaaa');
      expect(client.requests, hasLength(1));
      final r = client.requests.single;
      expect(r.method, 'POST');
      expect(r.url.path, '/auth/v1/signup');
      expect(r.url.queryParameters['redirect_to'], 'com.meogeobojo.app://login-callback/');
      expect(jsonDecode(client.bodies.single)['email'], 'student@example.org');
      expect(res.user?.email, 'student@example.org');
    });

    test('resending the verification e-mail and password reset reach the server too', () async {
      final client = _RecordingClient();
      final gw = _gateway(client);
      await gw.resendSignupEmail('student@example.org');
      await gw.sendPasswordReset('student@example.org');
      expect(client.requests.map((r) => r.url.path), ['/auth/v1/resend', '/auth/v1/recover']);
      for (final r in client.requests) {
        expect(r.url.queryParameters['redirect_to'], 'com.meogeobojo.app://login-callback/');
      }
    });
  });

  group('failure mapping and the diagnostic log', () {
    test('a configuration / redirect StateError is an app-config failure, not "unknown"', () {
      expect(authFailureFrom(StateError('Origin is only applicable schemes http and https: file:///')), AuthFailure.appConfig);
      expect(authFailureFrom(StateError('Missing SUPABASE_URL: set it in .env')), AuthFailure.appConfig);
      expect(authFailureFrom(StateError('something else')), AuthFailure.unknown);
      expect(AuthFailure.appConfig.retryable, isFalse);
      expect(AuthFailure.signUpFailed.retryable, isTrue);
    });

    test('the log line names the step, the mapping and the exception, and redacts personal data', () {
      final lines = <String>[];
      final DebugPrintCallback original = debugPrint;
      debugPrint = (String? msg, {int? wrapWidth}) => lines.add(msg ?? '');
      addTearDown(() => debugPrint = original);

      logAuthFailure(
        'signUp',
        const AuthApiException('User student@example.org not found', statusCode: '422', code: 'validation_failed'),
        AuthFailure.signUpFailed,
      );
      logAuthFailure('x', StateError('token=eyJhbGciOiJIUzI1NiJ9.abcdefghijklmnop.qrstuvwxyz'), AuthFailure.unknown);

      expect(lines.first, contains('[auth] signUp failed -> signUpFailed'));
      expect(lines.first, contains('AuthApiException'));
      expect(lines.first, contains('code=validation_failed status=422'));
      expect(lines.first, isNot(contains('student@example.org')));
      expect(lines.first, contains('<email>'));
      expect(lines.last, contains('<token>'));
      expect(lines.last, isNot(contains('eyJhbGci')));
    });
  });
}

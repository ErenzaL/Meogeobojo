import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/auth/services/auth_gateway.dart';

void main() {
  group('authRedirectUrl', () {
    test('mobile keeps the registered custom scheme', () {
      expect(
        authRedirectUrl(web: false, origin: 'https://x.onrender.com'),
        'com.meogeobojo.app://login-callback/',
      );
    });

    test('web returns to the site itself, with a trailing slash', () {
      expect(
        authRedirectUrl(web: true, origin: 'https://x.onrender.com'),
        'https://x.onrender.com/',
      );
      expect(
        authRedirectUrl(web: true, origin: 'http://localhost:8080/'),
        'http://localhost:8080/',
      );
    });
  });
}

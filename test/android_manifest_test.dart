import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android RELEASE build merges only `src/main`. `src/debug` and `src/profile` declare INTERNET for tooling, so a
/// missing permission in `main` passes every debug run and iOS/web, then every request fails in the installed APK.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('main manifest declares INTERNET (release builds only merge src/main)', () {
    expect(manifest, contains('android.permission.INTERNET'));
  });

  test('main manifest declares ACCESS_NETWORK_STATE', () {
    expect(manifest, contains('android.permission.ACCESS_NETWORK_STATE'));
  });

  test('no cleartext or localhost override sneaks in', () {
    expect(manifest, isNot(contains('usesCleartextTraffic="true"')));
  });
}

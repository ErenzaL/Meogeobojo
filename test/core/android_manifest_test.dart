import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Flutter's template grants INTERNET only in the debug/profile manifests, so a release APK without it in the main
  // manifest cannot reach Supabase at all: every sign-in fails as a "connection" error while debug builds work.
  test('the release (main) Android manifest grants INTERNET', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android.permission.INTERNET'));
  });
}

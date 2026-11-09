import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/navigation/providers/shell_tab_provider.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

Future<void> loadFont() async {
  final loader = FontLoader('Pretendard');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(File('assets/fonts/Pretendard-$w.otf').readAsBytes().then((b) => ByteData.sublistView(b)));
  }
  await loader.load();
}

void main() {
  testWidgets('golden MY signed in', (tester) async {
    await tester.runAsync(loadFont);
    final h = await buildHarness(
      auth: FakeAuthGateway(user: fakeUser(email: 'me@example.com')),
      profiles: FakeProfileRepository(onboardingCompleted: true, nickname: '테스터'),
      favorites: FakeFavoritesRepository({'1', '2'}),
    );
    await pumpApp(tester, h, home: const AppShell(), size: const Size(390, 1200));
    h.container.read(shellTabProvider.notifier).select(ShellTabs.profile);
    await tester.pumpAndSettle();
    await expectLater(find.byType(Scaffold).first, matchesGoldenFile('goldens/my.png'));
  });
}

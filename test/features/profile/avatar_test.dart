import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/auth/providers/auth_providers.dart';
import 'package:meogeobojo/features/preferences/models/user_preferences.dart';
import 'package:meogeobojo/features/profile/models/profile_avatar.dart';
import 'package:meogeobojo/features/profile/widgets/profile_avatar_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';
import 'profile_screen_test.dart' show openMy;

String? _assetOf(Image image) {
  var p = image.image;
  if (p is ResizeImage) p = p.imageProvider;
  return p is AssetImage ? p.assetName : null;
}

/// The asset shown by the big avatar at the top of MY.
String? heroAsset(WidgetTester tester) {
  final heroImage = find.descendant(
    of: find.byType(ProfileAvatarView),
    matching: find.byType(Image),
  );
  return _assetOf(tester.widget<Image>(heroImage.first));
}

Future<Harness> signedIn({FakeProfileRepository? profiles}) => buildHarness(
  auth: FakeAuthGateway(user: fakeUser()),
  profiles:
      profiles ??
      FakeProfileRepository(onboardingCompleted: true, nickname: '민수'),
  prefs: FakePreferencesRepository(
    stored: const UserPreferences(
      budget: BudgetOption.any,
      distance: DistanceOption.any,
    ),
  ),
);

void main() {
  group('ProfileAvatar', () {
    test('stored keys round-trip and unknown values fall back', () {
      for (final a in ProfileAvatar.values) {
        expect(ProfileAvatar.fromKey(a.key), a);
      }
      expect(ProfileAvatar.fromKey(null), isNull);
      expect(ProfileAvatar.fromKey('../../etc/passwd'), isNull);
      expect(ProfileAvatar.fromKey('https://x/y.png'), isNull);
      expect(ProfileAvatar.resolve('garbage'), ProfileAvatar.fallback);
    });

    test('the picker offers exactly 8 distinct existing mascot assets', () {
      expect(ProfileAvatar.values, hasLength(8));
      expect({for (final a in ProfileAvatar.values) a.asset}, hasLength(8));
      expect({for (final a in ProfileAvatar.values) a.key}, hasLength(8));
    });
  });

  group('MY avatar', () {
    testWidgets('shows the default mascot until one is chosen', (tester) async {
      final h = await signedIn();
      await openMy(tester, h);
      expect(heroAsset(tester), ProfileAvatar.fallback.asset);
      expect(find.text('꾸미기'), findsNothing); // the avatar itself is the button
    });

    testWidgets('shows the avatar saved on the account', (tester) async {
      final h = await signedIn(
        profiles: FakeProfileRepository(onboardingCompleted: true)
          ..avatarPath = ProfileAvatar.boba.key,
      );
      await openMy(tester, h);
      expect(heroAsset(tester), ProfileAvatar.boba.asset);
    });

    testWidgets('an unknown stored value falls back to the default', (
      tester,
    ) async {
      final h = await signedIn(
        profiles: FakeProfileRepository(onboardingCompleted: true)
          ..avatarPath = 'something-old',
      );
      await openMy(tester, h);
      expect(heroAsset(tester), ProfileAvatar.fallback.asset);
    });

    {
      testWidgets('tapping the avatar opens the picker, picks and saves', (
        tester,
      ) async {
        final h = await signedIn();
        await openMy(tester, h);
        await tester.tap(find.byType(ProfileAvatarView).first);
        await tester.pumpAndSettle();
        expect(find.text('프로필 이미지 선택'), findsOneWidget);
        expect(find.text('마스코트에서 선택'), findsOneWidget);
        expect(find.text('취소'), findsOneWidget);
        expect(find.text('선택 완료'), findsOneWidget);
        // 8 choices; the current one is checked
        expect(find.bySemanticsLabel(RegExp(r'^마스코트 \d$')), findsNWidgets(8));
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);

        await tester.tap(find.bySemanticsLabel('마스코트 4'));
        await tester.pumpAndSettle();
        expect(
          h.profiles.avatarWrites,
          isEmpty,
          reason: 'nothing is saved before 선택 완료',
        );
        await tester.tap(find.text('선택 완료'));
        await tester.pumpAndSettle();

        expect(h.profiles.avatarWrites, [ProfileAvatar.sparkle.key]);
        expect(find.text('프로필 이미지 선택'), findsNothing);
        expect(heroAsset(tester), ProfileAvatar.sparkle.asset);
        expect(
          h.container.read(authControllerProvider).profile?.avatarPath,
          ProfileAvatar.sparkle.key,
        );
      });
    }

    testWidgets('취소 leaves the avatar and the account untouched', (
      tester,
    ) async {
      final h = await signedIn();
      await openMy(tester, h);
      await tester.tap(find.byType(ProfileAvatarView).first);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('마스코트 6'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(h.profiles.avatarWrites, isEmpty);
      expect(heroAsset(tester), ProfileAvatar.fallback.asset);
    });

    testWidgets('confirming the unchanged avatar does not write', (
      tester,
    ) async {
      final h = await signedIn();
      await openMy(tester, h);
      await tester.tap(find.byType(ProfileAvatarView).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('선택 완료'));
      await tester.pumpAndSettle();
      expect(h.profiles.avatarWrites, isEmpty);
      expect(find.text('프로필 이미지 선택'), findsNothing);
    });

    testWidgets('a failed save keeps the sheet open and the old avatar', (
      tester,
    ) async {
      final profiles = FakeProfileRepository(onboardingCompleted: true)
        ..avatarErrors.add(const PostgrestException(message: 'down'));
      final h = await signedIn(profiles: profiles);
      await openMy(tester, h);
      await tester.tap(find.byType(ProfileAvatarView).first);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('마스코트 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('선택 완료'));
      await tester.pumpAndSettle();
      expect(find.text('프로필 이미지를 저장하지 못했어요. 다시 시도해주세요.'), findsOneWidget);
      expect(find.text('프로필 이미지 선택'), findsOneWidget);
      expect(
        h.container.read(authControllerProvider).profile?.avatarPath,
        isNull,
      );
      // retry succeeds
      await tester.tap(find.text('선택 완료'));
      await tester.pumpAndSettle();
      expect(h.profiles.avatarWrites, [ProfileAvatar.wink.key]);
      expect(heroAsset(tester), ProfileAvatar.wink.asset);
    });

    testWidgets('reloading the account returns the saved choice', (
      tester,
    ) async {
      final profiles = FakeProfileRepository(onboardingCompleted: true);
      final h = await signedIn(profiles: profiles);
      await openMy(tester, h);
      await tester.tap(find.byType(ProfileAvatarView).first);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('마스코트 5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('선택 완료'));
      await tester.pumpAndSettle();
      // A fresh session loads the profile from the account again.
      await h.container.read(authControllerProvider.notifier).retryProfile();
      await tester.pumpAndSettle();
      expect(profiles.avatarPath, ProfileAvatar.burger.key);
      expect(heroAsset(tester), ProfileAvatar.burger.asset);
    });

    for (final (lang, mode) in [
      ('ko', 'light'),
      ('en', 'dark'),
      ('zh-Hans', 'light'),
    ]) {
      testWidgets('picker fits 320px / 1.6x text: $lang, $mode', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final h = await buildHarness(
          storage: {'app_language': lang, 'theme_mode': mode},
          auth: FakeAuthGateway(user: fakeUser()),
          profiles: FakeProfileRepository(
            onboardingCompleted: true,
            nickname: '아주아주아주아주아주아주긴닉네임',
          ),
        );
        await openMy(tester, h, size: const Size(320, 568));
        await tester.tap(find.byType(ProfileAvatarView).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ProfileAvatarView), findsWidgets);
      });
    }
  });
}

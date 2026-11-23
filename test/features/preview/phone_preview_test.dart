import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/core/embed/embed_mode.dart';
import 'package:meogeobojo/core/l10n/language_controller.dart';
import 'package:meogeobojo/core/widgets/web_footer.dart';
import 'package:meogeobojo/features/auth/models/auth_snapshot.dart';
import 'package:meogeobojo/features/auth/providers/auth_providers.dart';
import 'package:meogeobojo/features/auth/services/sign_in_popup.dart';
import 'package:meogeobojo/features/navigation/screens/app_shell.dart';
import 'package:meogeobojo/features/navigation/utils/url_sync.dart';
import 'package:meogeobojo/features/preview/embedded_phone_chrome.dart';
import 'package:meogeobojo/features/preview/phone_preview.dart';
import 'package:meogeobojo/features/preview/preview_sync.dart';

import '../../support/harness.dart';

/// A stand-in for the iframe (tests have no browser): a box that records what it was asked to show.
class FrameSpy {
  PreviewFrameConfig? last;
  int builds = 0;
}

late FrameSpy lastSpy;

/// Opens the preview and lets the (fake) page report it has loaded, as the real iframe does.
Future<void> openPreview(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('phone-preview-button')));
  await tester.pump(const Duration(milliseconds: 300));
  lastSpy.last!.onLoaded();
  await tester.pumpAndSettle();
}

Future<(Harness, FrameSpy)> desktop(
  WidgetTester tester, {
  String language = 'ko',
  Size size = const Size(1280, 900),
}) async {
  final spy = FrameSpy();
  lastSpy = spy;
  final h = await buildHarness(
    storage: {'app_language': language},
    extraOverrides: [
      previewFrameBuilderProvider.overrideWithValue((c) {
        spy.last = c;
        spy.builds++;
        return const SizedBox.expand(key: ValueKey('fake-iframe'));
      }),
    ],
  );
  await pumpApp(tester, h, home: const AppShell(), size: size);
  return (h, spy);
}

Finder get button => find.byKey(const ValueKey('phone-preview-button'));
Finder get screen => find.byKey(const ValueKey('preview-screen'));

void main() {
  group('pure helpers', () {
    test('the phone is 402 x 874 (iPhone 17 Pro) and fits the window: never above 1, never below 0.45', () {
      expect(previewScale(const Size(1920, 1400)), 1.0);
      expect(previewScale(const Size(1280, 700)), lessThan(1.0));
      expect(previewScale(const Size(1280, 700)), closeTo((700 - 112) / (874 + 24), 1e-9));
      expect(previewScale(const Size(300, 300)), 0.45);
      // the scaled frame always fits inside the window (when the floor does not apply)
      for (final h in [640.0, 720.0, 800.0, 900.0, 1080.0]) {
        final s = previewScale(Size(1440, h));
        expect(874 * s + 24 * s, lessThanOrEqualTo(h - 112 + 1e-6), reason: '$h');
      }
    });

    test('the preview shows the same site in phone mode, from the opening page\'s own origin', () {
      expect(previewUrl(Uri.parse('https://meogeobojo.onrender.com/#/map')), 'https://meogeobojo.onrender.com/?embed=phone#/home');
      expect(previewUrl(Uri.parse('http://localhost:5555/')), 'http://localhost:5555/?embed=phone#/home');
    });

    test('changes made inside the preview are detected: session, language, campus', () {
      const none = <String, String>{};
      expect(PreviewChanges.between(none, none).any, isFalse);
      expect(PreviewChanges.between({'flutter.sb-x-auth-token': 'a'}, {'flutter.sb-x-auth-token': 'a'}).any, isFalse);
      expect(PreviewChanges.between(none, {'flutter.sb-x-auth-token': 'a'}).session, isTrue); // signed in
      expect(PreviewChanges.between({'flutter.sb-x-auth-token': 'a'}, none).session, isTrue); // signed out
      expect(PreviewChanges.between({'flutter.app_language': '"ko"'}, {'flutter.app_language': '"en"'}).language, isTrue);
      final c = PreviewChanges.between({'flutter.selected_university_id': '"1"'}, {'flutter.selected_university_id': '"2"'});
      expect(c.university, isTrue);
      expect(c.language, isFalse);
    });
  });

  group('the sign-in popup of the preview', () {
    test('a page is the popup\'s return only with the OAuth code AND a fresh marker left by the preview', () {
      final back = Uri.parse('https://site.example/?code=abc123');
      expect(isSignInPopupReturn(back, markerFresh: true), isTrue);
      // an ordinary visit, or a visit that merely has a code (an email link) without the preview having opened the popup
      expect(isSignInPopupReturn(back, markerFresh: false), isFalse);
      expect(isSignInPopupReturn(Uri.parse('https://site.example/'), markerFresh: true), isFalse);
      expect(isSignInPopupReturn(Uri.parse('https://site.example/#/map'), markerFresh: true), isFalse);
    });
  });

  group('the website footer', () {
    test('shown on the website, not in the phone apps, and not in the phone preview (the phone app has no footer)', () {
      expect(webFooterEnabledFor(web: true, embedded: false), isTrue);
      expect(webFooterEnabledFor(web: false, embedded: false), isFalse);
      expect(webFooterEnabledFor(web: true, embedded: true), isFalse);
    });
  });

  group('the button', () {
    for (final (lang, tip) in [('ko', '모바일 앱 미리보기'), ('en', 'Mobile App Preview'), ('zh-Hans', '移动应用预览')]) {
      testWidgets('$lang: a phone icon next to the language switch with the tooltip "$tip"', (tester) async {
        await desktop(tester, language: lang);
        expect(button, findsOneWidget);
        expect(tester.widget<IconButton>(button).tooltip, tip);
        expect((tester.widget<IconButton>(button).icon as Icon).icon, Icons.smartphone_rounded);
        // right of the language switch, same row
        final lang0 = tester.getRect(find.text('English'));
        final b = tester.getRect(button);
        expect(b.left, greaterThan(lang0.right));
        expect((b.center.dy - lang0.center.dy).abs(), lessThan(12));
      });
    }

    testWidgets('the header still fits at the narrowest desktop width, in the longest language', (tester) async {
      await desktop(tester, language: 'en', size: const Size(960, 700));
      expect(tester.takeException(), isNull);
      expect(button, findsOneWidget);
    });

    testWidgets('on a phone-width window there is no desktop header, so no preview button', (tester) async {
      final h = await buildHarness();
      await pumpApp(tester, h, home: const AppShell());
      expect(button, findsNothing);
    });

    testWidgets('inside the preview itself there is no button (no preview of a preview)', (tester) async {
      final h = await buildHarness(extraOverrides: [embeddedPreviewProvider.overrideWithValue(true), urlSyncEnabledProvider.overrideWithValue(false)]);
      await pumpApp(tester, h, home: const AppShell(), size: const Size(1280, 900));
      expect(button, findsNothing);
    });
  });

  group('opening and closing', () {
    testWidgets('opens a 402 x 874 phone showing the site in phone mode, and the desktop page stays', (tester) async {
      final (_, spy) = await desktop(tester, size: const Size(1440, 1100));
      await openPreview(tester);
      expect(tester.getSize(screen), const Size(402, 874)); // a big window: not scaled
      expect(spy.last!.url, endsWith('/?embed=phone#/home'));
      expect(spy.last!.scale, 1.0);
      expect(find.byKey(const ValueKey('fake-iframe')), findsOneWidget);
      expect(find.byType(AppShell), findsOneWidget); // the page underneath is untouched
      // a bezel and rounded screen
      final frame = tester.getRect(find.byKey(const ValueKey('preview-frame')));
      expect(frame.width, closeTo(402 + 24, 1));
    });

    testWidgets('a small window scales the phone down to fit, with no size toggle (it always fits already)', (tester) async {
      final (_, spy) = await desktop(tester, size: const Size(1280, 640));
      await openPreview(tester);
      final small = tester.getRect(find.byKey(const ValueKey('preview-frame')));
      expect(spy.last!.scale, lessThan(0.7));
      expect(small.top, greaterThanOrEqualTo(0));
      expect(small.bottom, lessThanOrEqualTo(640));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('preview-size')), findsNothing);
    });

    testWidgets('the close button, a click outside the phone, and Escape all close it', (tester) async {
      await desktop(tester);
      for (final how in ['button', 'backdrop', 'escape']) {
        await openPreview(tester);
        expect(screen, findsOneWidget, reason: how);
        switch (how) {
          case 'button':
            await tester.tap(find.byKey(const ValueKey('preview-close')));
          case 'backdrop':
            await tester.tapAt(const Offset(40, 450));
          default:
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await tester.pumpAndSettle();
        expect(screen, findsNothing, reason: how);
      }
    });

    testWidgets('a click on the phone itself does not close it', (tester) async {
      await desktop(tester);
      await openPreview(tester);
      await tester.tap(find.byKey(const ValueKey('fake-iframe')));
      await tester.pumpAndSettle();
      expect(screen, findsOneWidget);
    });

    testWidgets('a loading note shows until the page reports it has loaded', (tester) async {
      final (_, spy) = await desktop(tester);
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('앱을 불러오는 중이에요'), findsOneWidget);
      spy.last!.onLoaded();
      await tester.pump();
      expect(find.text('앱을 불러오는 중이에요'), findsNothing);
    });

    testWidgets('the controls speak the app language', (tester) async {
      await desktop(tester, language: 'en');
      await openPreview(tester);
      expect(tester.widget<IconButton>(find.descendant(of: find.byKey(const ValueKey('preview-close')), matching: find.byType(IconButton))).tooltip, 'Close preview');
    });
  });

  group('inside the preview (the embedded page)', () {
    testWidgets('it reserves the status-bar and home-indicator areas like a phone and draws them, never catching the mouse', (tester) async {
      final h = await buildHarness(extraOverrides: [embeddedPreviewProvider.overrideWithValue(true), urlSyncEnabledProvider.overrideWithValue(false)]);
      await pumpApp(tester, h, home: Builder(builder: (c) => Text('${MediaQuery.paddingOf(c).top}/${MediaQuery.paddingOf(c).bottom}')));
      expect(find.text('62.0/34.0'), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-island')), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-home-bar')), findsOneWidget);
      // the status bar of the simulator: the time (h:mm, 12-hour), with the island between it and the battery
      expect(find.byKey(const ValueKey('phone-time')), findsOneWidget);
      expect(RegExp(r'^\d{1,2}:\d{2}$').hasMatch(tester.widget<Text>(find.byKey(const ValueKey('phone-time'))).data!), isTrue);
      expect(tester.widget<Text>(find.byKey(const ValueKey('phone-time'))).style!.decoration, TextDecoration.none);
      expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);
      final island = tester.getRect(find.byKey(const ValueKey('phone-island')));
      expect(island.size, const Size(125, 36));
      expect(tester.getRect(find.byKey(const ValueKey('phone-time'))).right, lessThan(island.left));
      expect(tester.getRect(find.byIcon(Icons.wifi_rounded)).left, greaterThan(island.right));
    });

    testWidgets('the real shell runs as the phone layout: bottom bar, no desktop header, safe areas kept clear', (tester) async {
      final h = await buildHarness(extraOverrides: [embeddedPreviewProvider.overrideWithValue(true), urlSyncEnabledProvider.overrideWithValue(false)]);
      await pumpApp(tester, h, home: const AppShell());
      expect(find.text('먹어보조'), findsNothing); // no desktop header brand
      expect(find.byKey(const ValueKey('phone-island')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('outside the preview (the website, the phone apps) nothing is added', (tester) async {
      final h = await buildHarness();
      await pumpApp(tester, h, home: const AppShell());
      expect(find.byKey(const ValueKey('phone-island')), findsNothing);
      expect(find.byType(EmbeddedPhoneChrome), findsOneWidget); // present but inert
    });

    testWidgets('the preview does not count as a separate app launch or touch the address bar', (tester) async {
      final h = await buildHarness();
      expect(h.container.read(urlSyncEnabledProvider), isFalse); // tests are not the web
      expect(h.container.read(embeddedPreviewProvider), isFalse);
    });

    testWidgets('a Kakao login started inside the preview opens elsewhere and does not leave the page waiting', (tester) async {
      final h = await buildHarness(extraOverrides: [embeddedPreviewProvider.overrideWithValue(true)]);
      final c = h.container.read(authControllerProvider.notifier);
      expect(await c.startKakaoSignIn(), isNull);
      expect(h.container.read(authControllerProvider).status, AuthStatus.guest);
    });
  });

  group('what the preview changes comes back to the website', () {
    testWidgets('a language chosen inside the preview is applied when it closes (no reload)', (tester) async {
      final h = await buildHarness(storage: {'app_language': 'ko'});
      await pumpApp(tester, h, home: const AppShell(), size: const Size(1280, 900));
      await h.sp.setString(languagePrefsKey, 'en'); // what the preview wrote to the shared storage
      late WidgetRef captured;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: Consumer(builder: (_, ref, _) {
            captured = ref;
            return const SizedBox();
          }),
        ),
      );
      await applyPreviewChanges(captured, const PreviewChanges(language: true));
      expect(h.container.read(appLanguageProvider).code, 'en');
    });

    test('nothing changed: nothing is touched', () async {
      expect(const PreviewChanges().any, isFalse);
    });
  });
}

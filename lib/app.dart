import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/language_controller.dart';
import 'core/l10n/l10n.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/widgets/responsive.dart';
import 'features/auth/widgets/auth_flow_host.dart';
import 'features/navigation/screens/app_shell.dart';
import 'features/navigation/utils/url_sync.dart';
import 'main.dart' show SplashScreen;

class MeogeobojoApp extends ConsumerWidget {
  const MeogeobojoApp({super.key, this.home = const SplashGate()});

  /// Overridable so tests can mount a single screen with the real theme and
  /// localization setup.
  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final themeMode = ref.watch(themeModeProvider);
    final urlSync = ref.watch(urlSyncEnabledProvider);
    return MaterialApp(
      // The brand name is never translated.
      title: '먹어보조',
      debugShowCheckedModeBanner: false,
      // Web: the URL path is read by the shell (shellTabForPath); the Navigator itself always starts at the app, so a
      // direct link such as /#/map can never end in an "unknown route" error. Mobile is untouched.
      initialRoute: kIsWeb ? '/' : null,
      // Browser Back / Forward / typed URLs arrive as named pushes; they select the tab (see url_sync.dart).
      onGenerateRoute: urlSync ? generateUrlRoute : null,
      onUnknownRoute: urlSync ? unknownUrlRoute : null,
      navigatorObservers: [if (urlSync) UrlHistoryObserver(ref)],
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      // System Default unless the user picked Light or Dark.
      themeMode: themeMode,
      // Status-bar icons follow the resolved brightness (light icons on dark).
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: AppFrame(child: child ?? const SizedBox.shrink()),
      ),
      locale: language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );
  }
}

/// Shows the existing [SplashScreen] briefly, then the app shell wrapped in
/// the auth flow host (first-login onboarding, password recovery, ...).
///
/// On the web there is no splash ([skipSplash] defaults to [kIsWeb]): the site opens straight into the app shell
/// (the session is restored by Supabase before runApp, and data shows its own small skeletons). Android and iOS
/// keep the splash exactly as before.
class SplashGate extends StatefulWidget {
  const SplashGate({
    super.key,
    this.duration = const Duration(milliseconds: 1500),
    this.skipSplash = kIsWeb,
  });

  final Duration duration;
  final bool skipSplash;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  late bool _done = widget.skipSplash;

  @override
  void initState() {
    super.initState();
    if (_done) return;
    Future<void>.delayed(widget.duration, () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // No switcher either: nothing to fade from.
    if (widget.skipSplash) return const AuthFlowHost(child: AppShell());
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _done
          ? const AuthFlowHost(child: AppShell())
          : const SplashScreen(),
    );
  }
}

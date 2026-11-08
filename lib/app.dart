import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/language_controller.dart';
import 'core/l10n/l10n.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/widgets/auth_flow_host.dart';
import 'features/navigation/screens/app_shell.dart';
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
    return MaterialApp(
      // The brand name is never translated.
      title: '먹어보조',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      // System Default unless the user picked Light or Dark.
      themeMode: themeMode,
      // Status-bar icons follow the resolved brightness (light icons on dark).
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: child ?? const SizedBox.shrink(),
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
class SplashGate extends StatefulWidget {
  const SplashGate({
    super.key,
    this.duration = const Duration(milliseconds: 1500),
  });

  final Duration duration;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.duration, () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _done
          ? const AuthFlowHost(child: AppShell())
          : const SplashScreen(),
    );
  }
}

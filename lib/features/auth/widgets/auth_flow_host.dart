import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../favorites/providers/favorites_providers.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../../preferences/screens/preferences_screen.dart';
import '../../restaurants/screens/restaurant_list_screen.dart';
import '../models/auth_failure.dart';
import '../models/auth_snapshot.dart';
import '../providers/auth_providers.dart';
import '../providers/pending_action.dart';
import '../../profile/screens/nickname_setup_screen.dart';
import '../screens/reset_password_screen.dart';

const _nicknameRoute = 'nickname';
const _onboardingRoute = 'onboarding';
const _resetRoute = 'reset-password';

/// The only place that reacts to auth status changes with navigation, so
/// that repeated auth events can never stack duplicate screens:
///
///  * signed in, no app nickname yet      -> [NicknameSetupScreen] (once)
///  * signed in, onboarding not completed -> [PreferencesScreen] (once)
///  * signed in and ready                 -> close login screens, resume the
///                                           action the guest was attempting
///  * password-recovery link opened       -> [ResetPasswordScreen]
///  * signed out                          -> close account-only screens
class AuthFlowHost extends ConsumerStatefulWidget {
  const AuthFlowHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AuthFlowHost> createState() => _AuthFlowHostState();
}

class _AuthFlowHostState extends ConsumerState<AuthFlowHost> {
  /// `userId:status` key that has already been routed.
  String? _handled;
  bool _nicknameOpen = false;
  bool _onboardingOpen = false;
  bool _resetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _evaluate(ref.read(authControllerProvider));
    });
  }

  NavigatorState get _nav => Navigator.of(context);

  void _evaluate(AuthSnapshot s) {
    if (!mounted) return;
    _announceFailure(s);

    // Password recovery has priority; nothing else is routed until it is done.
    if (s.recoveryActive && s.isSignedIn) {
      if (!_resetOpen) _openReset();
      return;
    }
    if (_resetOpen) {
      _resetOpen = false;
      _nav.popUntil((r) => r.isFirst);
      _handled = null; // re-route the (now normal) session below
    }

    final user = s.user;
    switch (s.status) {
      case AuthStatus.authenticatedNeedsNickname:
        final key = '${user?.id}:${s.status.name}';
        if (user == null || _handled == key) return;
        _handled = key;
        _openNickname();
      case AuthStatus.authenticatedNeedsOnboarding:
        final key = '${user?.id}:${s.status.name}';
        if (user == null || _handled == key) return;
        _handled = key;
        _openOnboarding();
      case AuthStatus.authenticatedReady:
        final key = '${user?.id}:${s.status.name}';
        if (user == null || _handled == key) return;
        final fromOnboarding = _onboardingOpen;
        _handled = key;
        _afterSignIn(showRecommendations: fromOnboarding);
      case AuthStatus.guest:
        _handled = null;
        if (_onboardingOpen || _nicknameOpen) {
          _onboardingOpen = false;
          _nicknameOpen = false;
          _nav.popUntil((r) => r.isFirst);
        }
      case AuthStatus.initializing:
      case AuthStatus.authenticating:
      case AuthStatus.emailVerificationPending:
      case AuthStatus.error:
        break;
    }
  }

  void _announceFailure(AuthSnapshot s) {
    final f = s.failure;
    if (f != AuthFailure.sessionExpired && f != AuthFailure.linkExpired) return;
    final message = f!.message(context.l10n);
    ref.read(authControllerProvider.notifier).clearFailure();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openNickname() {
    _nav.popUntil((r) => r.isFirst);
    _nicknameOpen = true;
    _nav
        .push<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: _nicknameRoute),
            builder: (_) => const NicknameSetupScreen(),
          ),
        )
        .whenComplete(() => _nicknameOpen = false);
  }

  void _openOnboarding() {
    _nav.popUntil((r) => r.isFirst);
    _onboardingOpen = true;
    _nav
        .push<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: _onboardingRoute),
            builder: (_) =>
                const PreferencesScreen(mode: PreferencesMode.firstTime),
          ),
        )
        .whenComplete(() => _onboardingOpen = false);
  }

  void _openReset() {
    _resetOpen = true;
    _nav.popUntil((r) => r.isFirst);
    _nav.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: _resetRoute),
        builder: (_) => const ResetPasswordScreen(),
      ),
    );
  }

  Future<void> _afterSignIn({required bool showRecommendations}) async {
    _nav.popUntil((r) => r.isFirst);
    final pending = ref.read(pendingAuthActionProvider.notifier).take();
    switch (pending) {
      case PendingFavorite(:final kakaoId):
        try {
          await ref.read(favoritesProvider.notifier).addIfMissing(kakaoId);
        } catch (_) {
          // Saving failed; the heart simply stays unfilled and can be retried.
        }
      case PendingOpenTab(:final tab):
        ref.read(shellTabProvider.notifier).select(tab);
      case null:
        if (showRecommendations && mounted) {
          await _nav.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const RecommendationScreen(usePreferences: true),
            ),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthSnapshot>(
      authControllerProvider,
      (_, next) => _evaluate(next),
    );
    return widget.child;
  }
}

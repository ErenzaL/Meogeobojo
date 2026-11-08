import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../models/auth_failure.dart';
import '../models/auth_snapshot.dart';
import '../providers/auth_providers.dart';
import '../providers/pending_action.dart';
import '../widgets/auth_fields.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/kakao_login_button.dart';
import '../widgets/legal_links.dart';
import 'email_login_screen.dart';
import 'sign_up_screen.dart';
import '../../../core/theme/app_palette.dart';

const _loginRoute = 'login';

/// Pushes the login landing screen. [ShellTabs]/pending action are set by the
/// caller beforehand when something should resume after sign-in.
Future<void> openLogin(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: _loginRoute),
      builder: (_) => const LoginScreen(),
    ),
  );
}

/// Pops back to the login landing (used from verification / forgot screens).
void popToLogin(BuildContext context) =>
    Navigator.of(context)
        .popUntil((r) => r.settings.name == _loginRoute || r.isFirst);

/// "Continue without signing in": back to the shell on the Home tab. The
/// selected university is untouched (it lives in its own provider).
void continueAsGuest(BuildContext context, WidgetRef ref) {
  ref.read(pendingAuthActionProvider.notifier).set(null);
  ref.read(authControllerProvider.notifier).clearFailure();
  ref.read(shellTabProvider.notifier).select(ShellTabs.home);
  Navigator.of(context).popUntil((r) => r.isFirst);
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _kakaoStarted = false;
  AuthFailure? _failure;

  @override
  void initState() {
    super.initState();
    // Returning from the Kakao browser with no session means the attempt was
    // cancelled or the callback never arrived.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed && _kakaoStarted) {
          ref.read(authControllerProvider.notifier).kakaoReturnedToApp();
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(authControllerProvider.notifier).clearFailure();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _startKakao() async {
    setState(() {
      _failure = null;
      _kakaoStarted = true;
    });
    final f = await ref
        .read(authControllerProvider.notifier)
        .startKakaoSignIn();
    if (!mounted) return;
    if (f != null) setState(() => _failure = f);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snap = ref.watch(authControllerProvider);
    final waitingForKakao =
        _kakaoStarted && snap.status == AuthStatus.authenticating;
    // A failure delivered by the auth stream (deep-link error, timeout, ...).
    final streamFailure = switch (snap.failure) {
      AuthFailure.sessionExpired || AuthFailure.linkExpired => null,
      final f => f,
    };
    final failure = _failure ?? (_kakaoStarted ? streamFailure : null);

    return AuthScaffold(
      bottom: const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: LegalLinks(),
      ),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Image.asset(
            AppAssets.mascotStanding,
            height: 132,
            semanticLabel: l10n.mascotSemantics,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          l10n.authWelcomeTitle,
          textAlign: TextAlign.center,
          style: AppText.heroTitle.copyWith(fontSize: 26),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.authWelcomeSubtitle,
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: context.palette.textSecondary),
        ),
        const SizedBox(height: 28),
        if (failure != null) ...[
          AuthMessage.error(failure.message(l10n)),
          const SizedBox(height: 12),
        ],
        if (waitingForKakao)
          _KakaoWaiting(
            onCancel: ref
                .read(authControllerProvider.notifier)
                .cancelAuthenticating,
          )
        else
          KakaoLoginButton(
            label: l10n.authContinueKakao,
            onPressed: _startKakao,
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: waitingForKakao
              ? null
              : () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const EmailLoginScreen(),
                  ),
                ),
          child: Text(l10n.authEmailLogin),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: waitingForKakao
              ? null
              : () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
                ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: const StadiumBorder(),
            foregroundColor: context.palette.accentStrong,
            side: BorderSide(color: context.palette.accent, width: 1.4),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text(l10n.authEmailSignUp),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: waitingForKakao
              ? null
              : () => continueAsGuest(context, ref),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 48),
            foregroundColor: context.palette.textSecondary,
          ),
          child: Text(
            l10n.authBrowseAsGuest,
            textAlign: TextAlign.center,
            style: AppText.link(context).copyWith(fontSize: 14),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _KakaoWaiting extends StatelessWidget {
  const _KakaoWaiting({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(l10n.authKakaoWaiting, style: AppText.body)),
          TextButton(onPressed: onCancel, child: Text(l10n.commonCancel)),
        ],
      ),
    );
  }
}

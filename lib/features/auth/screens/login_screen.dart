import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/responsive.dart';
import '../../language/widgets/language_button.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../../university/models/university_display.dart';
import '../../university/providers/university_providers.dart';
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

/// 로그인 (V5): the campus line "OO 앞 맛집을 취향대로 찾아봐요", then the ways in. Phones get one centred column;
/// a desktop window gets the two-panel layout (campus panel left, the buttons right).
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
    final p = context.palette;
    final snap = ref.watch(authControllerProvider);
    final busy = _kakaoStarted && snap.status == AuthStatus.authenticating;
    // A failure delivered by the auth stream (deep-link error, timeout, ...).
    final streamFailure = switch (snap.failure) {
      AuthFailure.sessionExpired || AuthFailure.linkExpired => null,
      final f => f,
    };
    final failure = _failure ?? (_kakaoStarted ? streamFailure : null);
    final campus =
        ref
            .watch(selectedUniversityProvider)
            .value
            ?.displayName(Localizations.localeOf(context)) ??
        l10n.universityFallbackName;
    final canPop = Navigator.of(context).canPop();

    // The ways in (V5 order): Kakao, email sign-in (outlined), email sign-up (tonal), continue as a guest.
    final buttons = <Widget>[
      if (failure != null) ...[
        AuthMessage.error(failure.message(l10n)),
        const SizedBox(height: 12),
      ],
      if (busy)
        _KakaoWaiting(
          onCancel: ref
              .read(authControllerProvider.notifier)
              .cancelAuthenticating,
        )
      else
        KakaoLoginButton(label: l10n.authContinueKakao, onPressed: _startKakao),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: busy
            ? null
            : () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const EmailLoginScreen(),
                ),
              ),
        icon: const Icon(Icons.mail_outline_rounded, size: 20),
        label: Text(l10n.authEmailLogin),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: busy
            ? null
            : () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
              ),
        style: FilledButton.styleFrom(
          backgroundColor: p.fillMuted,
          foregroundColor: p.textPrimary,
        ),
        icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
        label: Text(l10n.authEmailSignUp),
      ),
      const SizedBox(height: 4),
      TextButton(
        onPressed: busy ? null : () => continueAsGuest(context, ref),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 48),
          foregroundColor: p.rustText,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: Text(l10n.authBrowseAsGuest, textAlign: TextAlign.center),
      ),
    ];

    Widget thumb(double size) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.accentFaint,
        borderRadius: BorderRadius.circular(size * 0.16),
        border: Border.all(color: p.border),
      ),
      child: Image.asset(
        AppAssets.mascotStanding,
        height: size * 0.78,
        semanticLabel: l10n.mascotSemantics,
      ),
    );

    if (MediaQuery.sizeOf(context).width >= Breakpoints.desktop) {
      return Scaffold(
        backgroundColor: p.background,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: p.accentFaint,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(64, 56, 64, 56),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Brand(size: 28),
                      const SizedBox(height: 20),
                      _CampusChip(campus),
                      const SizedBox(height: 32),
                      Center(child: thumb(240)),
                      const SizedBox(height: 32),
                      Text(
                        l10n.authHeroTitle(campus),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.authWebPanelBody,
                        style: AppText.body.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          if (canPop) BackButton(color: p.textPrimary),
                          const Spacer(),
                          const LanguageButton(),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  l10n.authWebStartTitle,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.authWebStartSubtitle,
                                  style: AppText.body.copyWith(
                                    color: p.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                ...buttons,
                                const SizedBox(height: 24),
                                const LegalLinks(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AuthScaffold(
      leading: canPop ? null : const _Brand(size: 20),
      bottom: const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: LegalLinks(),
      ),
      children: [
        const SizedBox(height: 8),
        Center(child: thumb(160)),
        const SizedBox(height: 20),
        Text(
          l10n.authHeroTitle(campus),
          textAlign: TextAlign.center,
          style: AppText.heroTitle.copyWith(fontSize: 26, height: 1.3),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.authHeroSubtitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: p.textSecondary),
        ),
        const SizedBox(height: 32),
        ...buttons,
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Accent dot + 먹어보조 (V5 `.brand`).
class _Brand extends StatelessWidget {
  const _Brand({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: size * 0.45,
        height: size * 0.45,
        decoration: BoxDecoration(
          color: context.palette.rust,
          shape: BoxShape.circle,
        ),
      ),
      SizedBox(width: size * 0.4),
      Text(
        '먹어보조', // the brand name is never translated
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _CampusChip extends StatelessWidget {
  const _CampusChip(this.campus);

  final String campus;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on_outlined, size: 16, color: p.textSecondary),
          const SizedBox(width: 4),
          Text(
            campus,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
        ],
      ),
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

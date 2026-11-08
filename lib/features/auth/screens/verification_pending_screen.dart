import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../models/auth_failure.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_fields.dart';
import '../widgets/auth_scaffold.dart';
import 'login_screen.dart';
import '../../../core/theme/app_palette.dart';

const _resendCooldown = Duration(seconds: 30);

/// Shown after sign-up when Supabase created the account but returned no
/// session. The user is NOT signed in here; they must open the email link.
class VerificationPendingScreen extends ConsumerStatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  ConsumerState<VerificationPendingScreen> createState() =>
      _VerificationPendingScreenState();
}

class _VerificationPendingScreenState
    extends ConsumerState<VerificationPendingScreen> {
  Timer? _timer;
  int _cooldown = _resendCooldown.inSeconds;
  bool _busy = false;
  bool _resent = false;
  AuthFailure? _failure;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendCooldown.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _cooldown = (_cooldown - 1).clamp(0, 999));
      if (_cooldown == 0) t.cancel();
    });
  }

  Future<void> _resend(String email) async {
    setState(() {
      _busy = true;
      _failure = null;
      _resent = false;
    });
    final f = await ref
        .read(authControllerProvider.notifier)
        .resendVerification(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = f;
      _resent = f == null;
    });
    if (f == null) _startCooldown();
  }

  void _backToLogin() {
    ref.read(authControllerProvider.notifier).cancelVerification();
    popToLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snap = ref.watch(authControllerProvider);
    final email = snap.pendingEmail ?? '';
    final streamFailure = snap.failure == AuthFailure.linkExpired
        ? AuthFailure.linkExpired
        : null;
    final failure = _failure ?? streamFailure;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToLogin();
      },
      child: AuthScaffold(
        showBack: false,
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: context.palette.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mark_email_unread_outlined,
                size: 42,
                color: context.palette.accentStrong,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.authVerifyTitle,
            textAlign: TextAlign.center,
            style: AppText.heroTitle.copyWith(fontSize: 26),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.authVerifyMessage(email),
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: context.palette.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.authVerifyNotSignedIn,
            textAlign: TextAlign.center,
            style: AppText.caption(context),
          ),
          const SizedBox(height: 20),
          if (failure != null) ...[
            AuthMessage.error(failure.message(l10n)),
            const SizedBox(height: 12),
          ],
          if (_resent) ...[
            AuthMessage.info(l10n.authVerifyResent),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: (_busy || _cooldown > 0 || email.isEmpty)
                ? null
                : () => _resend(email),
            child: Text(
              _cooldown > 0
                  ? l10n.authVerifyResendIn(_cooldown)
                  : l10n.authVerifyResend,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _backToLogin,
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
            child: Text(l10n.authVerifyBackToLogin),
          ),
        ],
      ),
    );
  }
}

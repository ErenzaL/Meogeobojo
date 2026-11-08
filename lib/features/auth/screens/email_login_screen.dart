import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../models/auth_failure.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_fields.dart';
import '../widgets/auth_scaffold.dart';
import 'forgot_password_screen.dart';
import 'sign_up_screen.dart';
import 'verification_pending_screen.dart';
import '../../../core/theme/app_palette.dart';

class EmailLoginScreen extends ConsumerStatefulWidget {
  const EmailLoginScreen({super.key});

  @override
  ConsumerState<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends ConsumerState<EmailLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  FieldError? _emailError;
  FieldError? _passwordError;
  AuthFailure? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final emailError = validateEmail(_email.text);
    final passwordError = validatePassword(_password.text);
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _failure = null;
    });
    if (emailError != null || passwordError != null) return;

    setState(() => _busy = true);
    final f = await ref
        .read(authControllerProvider.notifier)
        .signInWithEmail(_email.text, _password.text);
    if (!mounted) return;
    // On success the auth flow host takes over navigation.
    setState(() {
      _busy = false;
      _failure = f;
    });
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    final f = await ref
        .read(authControllerProvider.notifier)
        .resendVerification(_email.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = f;
    });
    if (f == null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const VerificationPendingScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthScaffold(
      children: [
        Text(
          l10n.authEmailLoginTitle,
          style: AppText.heroTitle.copyWith(fontSize: 26),
        ),
        const SizedBox(height: 24),
        EmailField(controller: _email, error: _emailError, enabled: !_busy),
        const SizedBox(height: 12),
        PasswordField(
          controller: _password,
          label: l10n.authPasswordLabel,
          error: _passwordError,
          enabled: !_busy,
          onSubmitted: _submit,
        ),
        if (_failure != null) ...[
          const SizedBox(height: 12),
          AuthMessage.error(_failure!.message(l10n)),
          if (_failure == AuthFailure.emailNotConfirmed)
            TextButton(
              onPressed: _busy ? null : _resend,
              child: Text(l10n.authVerifyResend),
            ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text(l10n.authLoginButton),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ForgotPasswordScreen(initialEmail: _email.text.trim()),
                  ),
                ),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            foregroundColor: context.palette.textSecondary,
          ),
          child: Text(l10n.authForgotPasswordLink, textAlign: TextAlign.center),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).pushReplacement<void, void>(
                  MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
                ),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            foregroundColor: context.palette.accentStrong,
          ),
          child: Text(l10n.authNoAccountSignUp, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

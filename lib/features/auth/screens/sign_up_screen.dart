import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../models/auth_failure.dart';
import '../models/auth_snapshot.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_fields.dart';
import '../widgets/auth_scaffold.dart';
import '../widgets/legal_links.dart';
import 'email_login_screen.dart';
import 'verification_pending_screen.dart';
import '../../../core/theme/app_palette.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  FieldError? _emailError;
  FieldError? _passwordError;
  FieldError? _confirmError;
  AuthFailure? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final e = validateEmail(_email.text);
    final p = validatePassword(_password.text, forNewPassword: true);
    final c = p == null ? validateConfirm(_password.text, _confirm.text) : null;
    setState(() {
      _emailError = e;
      _passwordError = p;
      _confirmError = c;
      _failure = null;
    });
    if (e != null || p != null || c != null) return;

    setState(() => _busy = true);
    final controller = ref.read(authControllerProvider.notifier);
    final f = await controller.signUpWithEmail(_email.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = f;
    });
    // No session yet: show the verification screen, never the signed-in UI.
    if (f == null &&
        ref.read(authControllerProvider).status ==
            AuthStatus.emailVerificationPending) {
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
      bottom: const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: LegalLinks(),
      ),
      children: [
        Text(
          l10n.authSignUpTitle,
          style: AppText.heroTitle.copyWith(fontSize: 26),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.authSignUpSubtitle,
          style: AppText.body.copyWith(color: context.palette.textSecondary),
        ),
        const SizedBox(height: 24),
        EmailField(controller: _email, error: _emailError, enabled: !_busy),
        const SizedBox(height: 12),
        PasswordField(
          controller: _password,
          label: l10n.authPasswordLabel,
          error: _passwordError,
          enabled: !_busy,
          newPassword: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 6),
        Text(
          l10n.authPasswordRule(kMinPasswordLength),
          style: AppText.caption(context),
        ),
        const SizedBox(height: 12),
        PasswordField(
          controller: _confirm,
          label: l10n.authPasswordConfirmLabel,
          error: _confirmError,
          enabled: !_busy,
          newPassword: true,
          onSubmitted: _submit,
        ),
        if (_failure != null) ...[
          const SizedBox(height: 12),
          AuthMessage.error(_failure!.message(l10n)),
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
              : Text(l10n.authSignUpButton),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.of(context).pushReplacement<void, void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const EmailLoginScreen(),
                  ),
                ),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            foregroundColor: context.palette.accentStrong,
          ),
          child: Text(l10n.authHaveAccountLogin, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

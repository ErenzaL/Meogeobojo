import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../models/auth_failure.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_fields.dart';
import '../widgets/auth_scaffold.dart';
import '../../../core/theme/app_palette.dart';

/// Opened by the auth flow host when a password-recovery link returns to the
/// app. By then Supabase has already created the recovery session.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  FieldError? _passwordError;
  FieldError? _confirmError;
  AuthFailure? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final p = validatePassword(_password.text, forNewPassword: true);
    final c = p == null ? validateConfirm(_password.text, _confirm.text) : null;
    setState(() {
      _passwordError = p;
      _confirmError = c;
      _failure = null;
    });
    if (p != null || c != null) return;

    setState(() => _busy = true);
    final controller = ref.read(authControllerProvider.notifier);
    final f = await controller.updatePassword(_password.text);
    if (!mounted) return;
    if (f != null) {
      setState(() {
        _busy = false;
        _failure = f;
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final message = context.l10n.authResetSuccess;
    controller.finishRecovery();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    // The host pops this route and continues (onboarding or back to the app).
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthScaffold(
      showBack: false,
      children: [
        Text(
          l10n.authResetTitle,
          style: AppText.heroTitle.copyWith(fontSize: 26),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.authResetMessage,
          style: AppText.body.copyWith(color: context.palette.textSecondary),
        ),
        const SizedBox(height: 24),
        PasswordField(
          controller: _password,
          label: l10n.authNewPasswordLabel,
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
              : Text(l10n.authResetButton),
        ),
      ],
    );
  }
}

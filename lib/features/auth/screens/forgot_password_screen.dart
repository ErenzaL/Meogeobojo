import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../models/auth_failure.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_fields.dart';
import '../widgets/auth_scaffold.dart';
import '../../../core/theme/app_palette.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.initialEmail);
  FieldError? _emailError;
  AuthFailure? _failure;
  bool _busy = false;
  String? _sentTo;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final e = validateEmail(_email.text);
    setState(() {
      _emailError = e;
      _failure = null;
    });
    if (e != null) return;
    setState(() => _busy = true);
    final f = await ref
        .read(authControllerProvider.notifier)
        .sendPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = f;
      if (f == null) _sentTo = _email.text.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sent = _sentTo != null;
    return AuthScaffold(
      children: [
        Text(
          l10n.authForgotTitle,
          style: AppText.heroTitle.copyWith(fontSize: 26),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.authForgotMessage,
          style: AppText.body.copyWith(color: context.palette.textSecondary),
        ),
        const SizedBox(height: 24),
        EmailField(
          controller: _email,
          error: _emailError,
          enabled: !_busy,
          textInputAction: TextInputAction.done,
          onSubmitted: _submit,
        ),
        if (_failure != null) ...[
          const SizedBox(height: 12),
          AuthMessage.error(_failure!.message(l10n)),
        ],
        if (sent) ...[
          const SizedBox(height: 12),
          AuthMessage.info(l10n.authForgotSent(_sentTo!)),
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
              : Text(sent ? l10n.authForgotResend : l10n.authForgotSend),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            foregroundColor: context.palette.accentStrong,
          ),
          child: Text(l10n.authVerifyBackToLogin),
        ),
      ],
    );
  }
}

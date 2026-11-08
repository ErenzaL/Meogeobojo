import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';

const kMinPasswordLength = 8;

/// Form problems, kept as codes so the text follows the current language.
enum FieldError {
  emailRequired,
  emailInvalid,
  passwordRequired,
  passwordShort,
  mismatch,
}

extension FieldErrorText on FieldError {
  String text(AppLocalizations l10n) => switch (this) {
    FieldError.emailRequired => l10n.errEmailRequired,
    FieldError.emailInvalid => l10n.errEmailInvalid,
    FieldError.passwordRequired => l10n.errPasswordRequired,
    FieldError.passwordShort => l10n.errPasswordShort(kMinPasswordLength),
    FieldError.mismatch => l10n.errPasswordMismatch,
  };
}

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

FieldError? validateEmail(String value) {
  final v = value.trim();
  if (v.isEmpty) return FieldError.emailRequired;
  if (!_emailPattern.hasMatch(v)) return FieldError.emailInvalid;
  return null;
}

/// [forNewPassword] enforces the minimum length; login only requires input.
FieldError? validatePassword(String value, {bool forNewPassword = false}) {
  if (value.isEmpty) return FieldError.passwordRequired;
  if (forNewPassword && value.length < kMinPasswordLength) {
    return FieldError.passwordShort;
  }
  return null;
}

FieldError? validateConfirm(String password, String confirm) =>
    password == confirm ? null : FieldError.mismatch;

InputDecoration authInputDecoration(
  BuildContext context, {
  required String label,
  String? errorText,
  String? hint,
  Widget? suffix,
}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    floatingLabelBehavior: hint == null ? null : FloatingLabelBehavior.always,
    errorText: errorText,
    errorMaxLines: 3,
    suffixIcon: suffix,
    filled: true,
    fillColor: context.palette.card,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: border(context.palette.border),
    enabledBorder: border(context.palette.border),
    focusedBorder: border(context.palette.accent, 1.8),
    errorBorder: border(context.palette.error),
    focusedErrorBorder: border(context.palette.error, 1.8),
  );
}

class EmailField extends StatelessWidget {
  const EmailField({
    super.key,
    required this.controller,
    this.error,
    this.enabled = true,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final FieldError? error;
  final bool enabled;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.emailAddress,
      textInputAction: textInputAction,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [AutofillHints.email],
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: authInputDecoration(
        context,
        label: l10n.authEmailLabel,
        errorText: error?.text(l10n),
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.error,
    this.enabled = true,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.newPassword = false,
  });

  final TextEditingController controller;
  final String label;
  final FieldError? error;
  final bool enabled;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;
  final bool newPassword;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscure,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: widget.textInputAction,
      autofillHints: [
        widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
      ],
      onSubmitted: widget.onSubmitted == null
          ? null
          : (_) => widget.onSubmitted!(),
      decoration: authInputDecoration(
        context,
        label: widget.label,
        errorText: widget.error?.text(l10n),
        suffix: IconButton(
          tooltip: _obscure ? l10n.authPasswordShow : l10n.authPasswordHide,
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: context.palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Inline error / info box used by every auth form.
class AuthMessage extends StatelessWidget {
  const AuthMessage.error(this.text, {super.key}) : isError = true;
  const AuthMessage.info(this.text, {super.key}) : isError = false;

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? context.palette.error
        : context.palette.accentStrong;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 13.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

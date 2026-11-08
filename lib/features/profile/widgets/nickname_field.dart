import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../auth/widgets/auth_fields.dart';
import '../models/nickname.dart';

String nicknameErrorText(AppLocalizations l10n, NicknameError e) => switch (e) {
  NicknameError.empty => l10n.nicknameErrEmpty,
  NicknameError.tooShort => l10n.nicknameErrTooShort(kNicknameMinLength),
  NicknameError.tooLong => l10n.nicknameErrTooLong(kNicknameMaxLength),
  NicknameError.invalidChars => l10n.nicknameErrInvalidChars,
};

/// The nickname input used by first-login setup and by "닉네임 변경". Accepts
/// any language; the text itself is never translated.
class NicknameField extends StatelessWidget {
  const NicknameField({
    super.key,
    required this.controller,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final VoidCallback? onSubmitted;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: authInputDecoration(
        context,
        label: l10n.nicknameLabel,
        hint: l10n.nicknameHint,
        errorText: errorText,
      ),
    );
  }
}

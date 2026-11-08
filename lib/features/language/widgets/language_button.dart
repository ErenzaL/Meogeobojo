import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import 'language_sheet.dart';
import '../../../core/theme/app_palette.dart';

/// Small globe in the top-right of the login / sign-up screens.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.l10n.languageButtonTooltip,
      onPressed: () => showLanguageSheet(context),
      icon: Icon(Icons.language_rounded, color: context.palette.textPrimary),
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    );
  }
}

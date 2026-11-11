import 'package:flutter/material.dart';

import '../../language/widgets/language_button.dart';
import '../../../core/theme/app_palette.dart';

/// Shared frame for every auth screen: back button on the left, the language
/// globe on the right, a centered scrollable column that clears the keyboard.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.children,
    this.showBack = true,
    this.showLanguage = true,
    this.bottom,
    this.leading,
  });

  final List<Widget> children;
  final bool showBack;
  final bool showLanguage;

  /// Pinned below the scroll area (e.g. legal links).
  final Widget? bottom;

  /// Shown at the top left instead of the back button when there is nothing to go back to (the brand on the
  /// login landing).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  if (showBack && canPop)
                    BackButton(color: context.palette.textPrimary)
                  else if (leading != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: leading,
                    )
                  else
                    const SizedBox(width: 48),
                  const Spacer(),
                  if (showLanguage) const LanguageButton(),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: children,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ?bottom,
          ],
        ),
      ),
    );
  }
}

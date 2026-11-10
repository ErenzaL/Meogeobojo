import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';

/// Full-width primary action under the filters, in the app's own button
/// style (same fill, radius and type as every other primary button).
class HomeRecommendButton extends StatelessWidget {
  const HomeRecommendButton({
    super.key,
    required this.onPressed,
    this.onRestart,
  });

  final VoidCallback onPressed;

  /// Shown beside the button once a pick is on screen: back to the untouched
  /// Home (conditions, categories and the pick cleared).
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: _main(context)),
      if (onRestart != null) ...[
        const SizedBox(width: 10),
        SizedBox.square(
          dimension: 54,
          child: OutlinedButton(
            onPressed: onRestart,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              side: BorderSide(color: context.palette.borderStrong),
            ),
            child: Tooltip(
              message: context.l10n.homeRestart,
              child: Icon(
                Icons.refresh_rounded,
                size: 24,
                semanticLabel: context.l10n.homeRestart,
              ),
            ),
          ),
        ),
      ],
    ],
  );

  Widget _main(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              context.l10n.homeRecommendButton,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right_rounded, size: 22),
        ],
      ),
    ),
  );
}

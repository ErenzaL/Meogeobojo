import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';

/// The three actions of the recommendation, one at a time where it fits:
/// first "조건에 맞게 추천받기"; once a result is on screen "다른 후보 보기"
/// beside "조건 수정"; and "조건 초기화" spelled out (an icon alone read as
/// "recommend again").
class HomeRecommendButton extends StatelessWidget {
  const HomeRecommendButton({
    super.key,
    required this.onPressed,
    this.onOther,
    this.onEdit,
    this.onRestart,
    this.onlyOne = false,
  });

  /// "조건에 맞게 추천받기" (before a result is shown).
  final VoidCallback onPressed;

  /// "다른 후보 보기". Non-null once a result is shown (the button then
  /// replaces the first one); disabled when [onlyOne].
  final VoidCallback? onOther;

  /// "조건 수정", shown with [onOther].
  final VoidCallback? onEdit;

  /// "조건 초기화": back to the untouched Home.
  final VoidCallback? onRestart;

  /// Only one place matches: it shows again, and the reason is said.
  final bool onlyOne;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final showing = onOther != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!showing)
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.homeRecommendButton,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: onlyOne ? null : onOther,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                  label: Text(
                    l10n.homeOtherCandidate,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    side: BorderSide(color: p.borderStrong),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 19),
                  label: Text(
                    l10n.homeEditConditions,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        if (showing && onlyOne)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.homeOnlyOneMatch,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: p.textSecondary),
            ),
          ),
        if (onRestart != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRestart,
              style: TextButton.styleFrom(foregroundColor: p.textSecondary),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: Text(l10n.homeRestart),
            ),
          ),
      ],
    );
  }
}

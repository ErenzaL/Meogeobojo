import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import 'home_top_bar.dart';

/// Desktop Home, section A: which university this is for (changeable right here), and the page's question.
class HomeWelcome extends StatelessWidget {
  const HomeWelcome({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const UniversityButton(),
          const SizedBox(height: 6),
          Text(
            l10n.homeTitle,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              color: p.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

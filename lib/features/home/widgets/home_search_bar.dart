import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/tappable_card.dart';
import '../../search/screens/search_screen.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';

void openSearch(BuildContext context, {String? query}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => SearchScreen(initialQuery: query)),
  );
}

class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.homeSearchLabel,
      child: TappableCard(
        radius: AppRadius.pill,
        onTap: () => openSearch(context),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 24,
                color: context.palette.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.searchHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: context.palette.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: context.palette.accentFaint,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.tune_rounded,
                  size: 19,
                  color: context.palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

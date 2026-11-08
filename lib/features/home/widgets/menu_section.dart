import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/tappable_card.dart';
import 'home_header.dart';
import 'home_search_bar.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';

/// Menu keywords the user can jump into a search with. These are search
/// shortcuts, NOT a popularity ranking: no trend data exists yet, so the
/// section title says "browse by menu" instead of claiming "most searched".
class _MenuKeyword {
  const _MenuKeyword(this.query, this.label, this.icon);

  /// Korean keyword sent to the search (Kakao data is Korean).
  final String query;
  final String Function(AppLocalizations) label;
  final IconData icon;
}

final _menus = [
  _MenuKeyword('마라탕', (l) => l.menuMalatang, Icons.ramen_dining_rounded),
  _MenuKeyword('돈까스', (l) => l.menuPorkCutlet, Icons.restaurant_rounded),
  _MenuKeyword('냉면', (l) => l.menuNaengmyeon, Icons.set_meal_rounded),
  _MenuKeyword('순두부찌개', (l) => l.menuSoondubu, Icons.soup_kitchen_rounded),
  _MenuKeyword('치킨', (l) => l.menuChicken, Icons.lunch_dining_rounded),
  _MenuKeyword('떡볶이', (l) => l.menuTteokbokki, Icons.fastfood_rounded),
  _MenuKeyword('파스타', (l) => l.menuPasta, Icons.dinner_dining_rounded),
  _MenuKeyword('아메리카노', (l) => l.menuAmericano, Icons.local_cafe_rounded),
];

class MenuSection extends StatelessWidget {
  const MenuSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: SectionHeader(
            title: context.l10n.homeMenuTitle,
            icon: Icons.restaurant_menu_rounded,
            onMore: () => openSearch(context),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            6,
            AppSpacing.screenH,
            16,
          ),
          child: Row(
            children: [
              for (final m in _menus)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _MenuCard(
                    menu: m,
                    onTap: () => openSearch(context, query: m.query),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.menu, required this.onTap});

  final _MenuKeyword menu;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: TappableCard(
        radius: 18,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.palette.accentFaint,
                  shape: BoxShape.circle,
                ),
                child: Icon(menu.icon, size: 24, color: context.palette.accent),
              ),
              const SizedBox(height: 8),
              Text(
                menu.label(context.l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
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

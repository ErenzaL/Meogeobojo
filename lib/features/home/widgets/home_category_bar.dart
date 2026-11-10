import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../restaurants/models/food_category.dart';
import '../../restaurants/widgets/category_tile.dart';
import '../../missions/providers/mission_providers.dart';
import '../providers/home_providers.dart';

/// Horizontally scrolling category shortcuts: 전체, then every food category.
/// (학식 has its own card further down Home.) Tap food categories to
/// narrow Home's recommendations to any of them; several can be on at once
/// (soft orange when selected), and 전체 clears the choice.
class HomeCategoryBar extends ConsumerWidget {
  const HomeCategoryBar({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  static const _tileWidth = 64.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selected = ref.watch(homeCategoryProvider);
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final all = FoodCategory.all;
    final rest = [
      for (final c in FoodCategory.values)
        if (c != all) c,
    ];

    Widget tile(FoodCategory c) => SizedBox(
      width: _tileWidth,
      child: CategoryTile(
        icon: c.icon,
        image: c.image,
        label: c.label(l10n),
        selected: c == FoodCategory.all
            ? selected.isEmpty
            : selected.contains(c),
        maxBox: 52,
        onTap: () {
          final wasOn = selected.contains(c);
          ref.read(homeCategoryProvider.notifier).toggle(c);
          // Exploring a category counts toward 캠퍼스 맛집 탐험가.
          if (c != FoodCategory.all && !wasOn) {
            logMissionActivity(ref, 'category_explore', key: c.name);
          }
        },
      ),
    );

    return SizedBox(
      height: 90 + 16 * (scale - 1),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        children: [
          tile(all),
          for (final c in rest) ...[const SizedBox(width: 6), tile(c)],
        ],
      ),
    );
  }
}

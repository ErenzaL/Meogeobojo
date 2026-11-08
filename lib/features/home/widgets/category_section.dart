import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../campus_meals/screens/campus_meal_screen.dart';
import '../../restaurants/models/food_category.dart';
import '../../restaurants/screens/restaurant_category_screen.dart';
import '../../restaurants/widgets/category_tile.dart';

/// Home category shortcuts: 학식 followed by every [FoodCategory], always
/// visible in a 5-column grid that wraps onto extra rows. No horizontal
/// scrolling and nothing to expand. Every food category is a navigation button
/// that opens [RestaurantCategoryScreen]; nothing is filtered on Home itself.
class CategorySection extends StatelessWidget {
  const CategorySection({super.key});

  static const _columns = 5;
  static const _gap = 4.0;

  void _open(BuildContext context, FoodCategory c) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RestaurantCategoryScreen(initialCategory: c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = (constraints.maxWidth - _gap * (_columns - 1)) / _columns;

          return Wrap(
            spacing: _gap,
            runSpacing: 14,
            children: [
              // 학식 is its own feature (campus cafeterias), not a Kakao cuisine.
              SizedBox(
                width: w,
                child: CategoryTile(
                  icon: Icons.food_bank_rounded,
                  label: l10n.homeCampusMeals,
                  highlighted: true,
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const CampusMealScreen(),
                    ),
                  ),
                ),
              ),
              for (final c in FoodCategory.values)
                SizedBox(
                  width: w,
                  child: CategoryTile(
                    icon: c.icon,
                    label: c.label(l10n),
                    onTap: () => _open(context, c),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

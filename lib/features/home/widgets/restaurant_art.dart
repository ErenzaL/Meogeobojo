import 'package:flutter/material.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/theme/app_palette.dart';
import '../../recommendation/restaurant_insight.dart';
import '../../restaurants/models/food_category.dart';
import '../../restaurants/models/restaurant.dart';

/// The category artwork that fits [r] (Kakao's own classification), or the
/// generic one.
String categoryArtFor(Restaurant r) {
  for (final c in FoodCategory.values) {
    if (c == FoodCategory.all || c == FoodCategory.etc) continue;
    if (c.image != null && c.matches(r)) return c.image!;
  }
  return AppAssets.categoryAll;
}

/// A restaurant's photo when one is known, otherwise its category
/// illustration on a calm backdrop. Kakao provides no photos, so today this is
/// always the illustration.
class RestaurantArt extends StatelessWidget {
  const RestaurantArt({
    super.key,
    required this.restaurant,
    required this.insight,
    required this.radius,
    this.width,
    this.height,
    this.compact = false,
  });

  final Restaurant restaurant;
  final RestaurantInsight insight;
  final double radius;
  final double? width;
  final double? height;

  /// Thumbnail: lighter backdrop and a tighter illustration.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final art = Image.asset(
      categoryArtFor(restaurant),
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    final url = insight.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: url != null
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _illustration(p, art),
              )
            : _illustration(p, art),
      ),
    );
  }

  Widget _illustration(AppPalette p, Widget art) => ColoredBox(
    color: compact ? p.fillMuted : p.artBackdrop,
    child: Padding(
      padding: EdgeInsets.all(compact ? 8 : 18),
      child: Center(child: art),
    ),
  );
}

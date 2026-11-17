import 'dart:ui' show ImageFilter;

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
    this.wholePhoto = false,
  });

  final Restaurant restaurant;
  final RestaurantInsight insight;
  final double radius;
  final double? width;
  final double? height;

  /// Thumbnail: lighter backdrop and a tighter illustration.
  final bool compact;

  /// Show the whole photo (no cropping) over a blurred copy of itself that
  /// fills the rest of the box. For a wide box such as the home #1 card,
  /// where `BoxFit.cover` would keep only a thin strip of the photo.
  final bool wholePhoto;

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
        child: url == null
            ? _illustration(p, art)
            : wholePhoto
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: p.artBackdrop),
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: _photo(url, BoxFit.cover, p, art),
                  ),
                  _photo(url, BoxFit.contain, p, art),
                ],
              )
            : _photo(url, BoxFit.cover, p, art),
      ),
    );
  }

  Widget _photo(String url, BoxFit fit, AppPalette p, Widget art) =>
      Image.network(
        url,
        fit: fit,
        errorBuilder: (_, _, _) => _illustration(p, art),
      );

  Widget _illustration(AppPalette p, Widget art) => ColoredBox(
    color: compact ? p.fillMuted : p.artBackdrop,
    child: Padding(
      padding: EdgeInsets.all(compact ? 8 : 18),
      child: Center(child: art),
    ),
  );
}

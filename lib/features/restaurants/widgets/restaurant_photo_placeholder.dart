import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';

/// Neutral stand-in used because Kakao Local returns no photos. Deliberately
/// not a mascot or stock image, so it can't be mistaken for the real place.
class RestaurantPhotoPlaceholder extends StatelessWidget {
  const RestaurantPhotoPlaceholder({super.key, this.iconSize = 36});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.palette.placeholder, context.palette.surfaceAlt],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.restaurant_rounded,
          size: iconSize,
          color: context.palette.placeholderIcon,
        ),
      ),
    );
  }
}

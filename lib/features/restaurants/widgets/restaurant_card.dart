import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/geo.dart';
import '../../../core/widgets/tappable_card.dart';
import '../../favorites/widgets/favorite_button.dart';
import '../models/restaurant.dart';
import '../screens/restaurant_detail_screen.dart';
import 'restaurant_photo_placeholder.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';

/// Vertical card for the Home horizontal list. Shows only facts we have:
/// name, Kakao category, straight-line distance.
class RestaurantCard extends StatelessWidget {
  const RestaurantCard({
    super.key,
    required this.restaurant,
    required this.width,
  });

  final Restaurant restaurant;
  final double width;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    return SizedBox(
      width: width,
      child: TappableCard(
        onTap: () => openRestaurantDetail(context, r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.2,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const RestaurantPhotoPlaceholder(),
                  Positioned(left: 8, bottom: 8, child: _Tag(r.categoryTag)),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: FavoriteButton(restaurant: r, size: 18),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.place_rounded,
                        size: 14,
                        color: context.palette.accent,
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          context.l10n.restaurantDistanceFromSchool(
                            formatDistance(r.distanceMeters),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.palette.accent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: const TextStyle(
          color: AppColors.textOnPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

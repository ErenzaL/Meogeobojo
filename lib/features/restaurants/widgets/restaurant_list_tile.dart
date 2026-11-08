import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/geo.dart';
import '../../../core/widgets/tappable_card.dart';
import '../../favorites/widgets/favorite_button.dart';
import '../models/restaurant.dart';
import '../screens/restaurant_detail_screen.dart';
import 'restaurant_photo_placeholder.dart';
import '../../../core/l10n/l10n.dart';

/// Horizontal row card for search / list screens.
class RestaurantListTile extends StatelessWidget {
  const RestaurantListTile({super.key, required this.restaurant, this.rank});

  final Restaurant restaurant;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    return TappableCard(
      onTap: () => openRestaurantDetail(context, r),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: const SizedBox(
                width: 72,
                height: 72,
                child: RestaurantPhotoPlaceholder(iconSize: 28),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.restaurantTagDistance(
                      r.categoryTag,
                      formatDistance(r.distanceMeters),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption(context),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r.displayAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption(context),
                  ),
                ],
              ),
            ),
            FavoriteButton(restaurant: r),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../favorites/widgets/favorite_button.dart';
import '../../recommendation/home_ranking.dart';
import '../../restaurants/models/food_category.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/screens/restaurant_category_screen.dart';
import '../../restaurants/screens/restaurant_detail_screen.dart';
import 'home_header.dart';
import 'restaurant_art.dart';

/// "오늘의 추천": a sideways list of the places that pass the current filters,
/// in ranking order. Every fact on a card comes from the restaurant data or
/// from what an admin entered; a missing rating or price is left out or shown
/// as "정보 없음", never made up.
class TodayPicksSection extends StatelessWidget {
  const TodayPicksSection({
    super.key,
    required this.ranked,
    required this.categories,
    this.bleed = 0,
  });

  final List<RankedRestaurant> ranked;

  /// The categories chosen in the Home bar (empty = 전체).
  final Set<FoodCategory> categories;

  /// How far the list scrolls past each side of its parent (the page gutter
  /// on phones), so cards slide to the screen edge.
  final double bleed;

  static const maxCards = 10;
  static const _cardWidth = 196.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = ranked.take(maxCards).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final height = 118 + 128 * scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: l10n.homeTodayPicksTitle,
          onMore: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => RestaurantCategoryScreen(
                initialCategory: categories.length == 1
                    ? categories.first
                    : FoodCategory.all,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) => SizedBox(
            height: height,
            child: OverflowBox(
              minWidth: box.maxWidth + 2 * bleed,
              maxWidth: box.maxWidth + 2 * bleed,
              minHeight: height,
              maxHeight: height,
              child: SizedBox(
                height: height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: bleed),
                  clipBehavior: Clip.none,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) =>
                      _PickCard(item: items[i], height: height),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({required this.item, required this.height});

  final RankedRestaurant item;
  final double height;

  /// Up to two tags from Kakao's own category path: the cuisine and the most
  /// specific part ("한식", "불백").
  static List<String> tagsOf(Restaurant r) {
    final parts = [
      for (final s in r.categoryName.split('>'))
        if (s.trim().isNotEmpty) s.trim(),
    ];
    if (parts.length < 2) return [r.categoryTag];
    final tags = <String>[parts[1]];
    if (parts.length > 2 && parts.last != parts[1]) tags.add(parts.last);
    return tags;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final r = item.restaurant;
    final i = item.insight;
    final km = (item.meters / 1000).toStringAsFixed(1);
    return SizedBox(
      width: TodayPicksSection._cardWidth,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: softCardShadow(p),
        ),
        child: Material(
          color: p.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: BorderSide(color: p.border),
          ),
          child: InkWell(
            onTap: () => openRestaurantDetail(context, r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 108,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RestaurantArt(
                        restaurant: r,
                        insight: i,
                        radius: 0,
                        compact: true,
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: FavoriteButton(restaurant: r, size: 18),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            for (final (n, t) in tagsOf(r).indexed) ...[
                              if (n > 0) const SizedBox(width: 6),
                              Flexible(child: _Tag(t)),
                            ],
                          ],
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: i.rating == null
                                  ? const SizedBox.shrink()
                                  : FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.star_rounded,
                                            size: 16,
                                            color: p.starAmber,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            i.rating!.toStringAsFixed(1),
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          if (i.reviewCount != null)
                                            Text(
                                              ' (${i.reviewCount})',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: p.textMuted,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.place_outlined,
                              size: 15,
                              color: p.textMuted,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${km}km',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: p.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          i.minPriceKrw == null
                              ? l10n.homeNoInfo
                              : '₩ ${l10n.homePriceFrom(i.minPriceKrw!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: i.minPriceKrw == null
                                ? p.textMuted
                                : p.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: p.fillMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: p.textSecondary),
      ),
    );
  }
}

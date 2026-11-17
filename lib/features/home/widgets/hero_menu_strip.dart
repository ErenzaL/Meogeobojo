import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/seoul_clock.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../restaurants/models/restaurant_override.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../restaurants/screens/restaurant_detail_screen.dart';
import '../utils/home_text.dart';

/// Under the pick: the dishes of THAT restaurant that match the chosen conditions (the budget, and being served when the
/// user would arrive), in a row that slides sideways rather than a list that fills the page. Nothing shows when the
/// restaurant has no dish that matches or has no published menu.
class HeroMenuStrip extends ConsumerWidget {
  const HeroMenuStrip({super.key, required this.hero});

  final RankedRestaurant hero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menus = ref.watch(restaurantMenusProvider(hero.restaurant.kakaoId));
    final conditions = ref.watch(conditionsProvider);
    final now = minutesOfDay(ref.watch(seoulNowProvider));
    final items = menusMatchingConditions(
      menus.value ?? const <RestaurantMenuItem>[],
      conditions,
      now + hero.walkMinutes,
      cafe: hero.restaurant.categoryGroupCode == 'CE7',
    );
    if (items.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        key: const ValueKey('hero-menu-strip'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.homeMatchingMenus(items.length),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 148,
            // drag with a mouse on the website too, not only a finger
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: ListView.separated(
                key: const ValueKey('hero-menu-list'),
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _MenuTile(
                  item: items[i],
                  p: p,
                  onTap: () => openRestaurantDetail(context, hero.restaurant),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item, required this.p, required this.onTap});

  final RestaurantMenuItem item;
  final AppPalette p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final image = item.imageUrl;
    return SizedBox(
      width: 150,
      child: Material(
        color: p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 76,
                width: double.infinity,
                child: image != null
                    ? Image.network(
                        image,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholder(),
                      )
                    : _placeholder(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      wonSigned(item.priceKrw!),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: p.rustText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => ColoredBox(
    color: p.fillMuted,
    child: Center(
      child: Icon(Icons.restaurant_rounded, color: p.textMuted, size: 26),
    ),
  );
}

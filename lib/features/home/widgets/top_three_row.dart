import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../recommendation/home_ranking.dart';
import '../providers/home_providers.dart';

/// "Top 3 추천": the three best matches side by side under the recommend
/// buttons. The one on the card below is highlighted; tapping another shows
/// it there instead.
class TopThreeRow extends ConsumerWidget {
  const TopThreeRow({super.key, required this.recs});

  final HomeRecs recs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = recs.ranked.take(3).toList();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _TopTile(
                rank: i + 1,
                item: top[i],
                selected: top[i] == recs.hero,
                onTap: () => ref
                    .read(heroPickProvider.notifier)
                    .choose(top[i].restaurant.kakaoId),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopTile extends StatelessWidget {
  const _TopTile({
    required this.rank,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final int rank;
  final RankedRestaurant item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(14);
    // Read out as a button, and which one is on the card.
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? p.accentSoft : p.card,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? p.rustText : p.hairline),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
            // The name gets the tile's full width (under the rank), so Korean
            // names wrap at a space, not mid-word.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor: rank == 1 ? p.rustText : p.fillMuted,
                  foregroundColor: rank == 1 ? p.card : p.textPrimary,
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.restaurant.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
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

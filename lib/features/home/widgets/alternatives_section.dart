import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/seoul_clock.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../../origin/providers/origin_providers.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../restaurants/screens/restaurant_detail_screen.dart';
import '../../restaurants/utils/directions.dart';
import '../providers/home_providers.dart';
import '../utils/home_text.dart';
import 'home_card_parts.dart';
import 'restaurant_art.dart';

/// "마음에 안 들면": a shuffle button and the next two picks, each compared
/// with the pick above.
class AlternativesSection extends ConsumerWidget {
  const AlternativesSection({super.key, required this.recs});

  final HomeRecs recs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.homeAltTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.sectionTitle.copyWith(fontSize: 21),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: _PickButton(
                label: l10n.homePickForMe,
                onTap: () =>
                    ref.read(heroPickProvider.notifier).pickRandom(recs),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (recs.alternatives.isNotEmpty)
          HomeCard(
            clip: true,
            child: Column(
              children: [
                for (var i = 0; i < recs.alternatives.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, color: context.palette.hairline),
                  _AltRow(top: recs.hero, item: recs.alternatives[i]),
                ],
              ],
            ),
          ),
        const SizedBox(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () =>
              ref.read(shellTabProvider.notifier).select(ShellTabs.map),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    l10n.homeSeeOnMap(recs.total),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.palette.fillMuted,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shuffle_rounded, size: 19),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AltRow extends ConsumerWidget {
  const _AltRow({required this.top, required this.item});

  final RankedRestaurant top;
  final RankedRestaurant item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final r = item.restaurant;
    final origin = ref.watch(originProvider);
    final nowMin = minutesOfDay(ref.watch(seoulNowProvider));
    final status = orderStatus(item, nowMin);
    final walk = l10n.homeWalkAbout(item.walkMinutes);

    final (statusText, statusColor) = switch (status.kind) {
      OrderStatusKind.available => (l10n.homeStatusOrderable, p.statusOpen),
      OrderStatusKind.closesSoon || OrderStatusKind.closedBeforeArrival => (
        l10n.homeStatusClosesAt(formatMinutesOfDay(status.lastOrderMinutes!)),
        p.statusWarn,
      ),
      OrderStatusKind.unknown => (null, p.textSecondary),
    };

    return InkWell(
      onTap: () => openRestaurantDetail(context, r),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            RestaurantArt(
              restaurant: r,
              insight: item.insight,
              radius: 12,
              width: 64,
              height: 64,
              compact: true,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    comparisonText(l10n, compareAgainst(top, item), item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, color: p.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        if (statusText != null) ...[
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: StatusDot(statusColor, size: 8),
                            ),
                          ),
                          TextSpan(
                            text: statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const TextSpan(text: ' · '),
                        ],
                        TextSpan(text: walk),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: p.textSecondary),
                  ),
                ],
              ),
            ),
            if (item.insight.minPriceKrw != null) ...[
              const SizedBox(width: 8),
              Text(
                l10n.homePriceFrom(item.insight.minPriceKrw!),
                style: AppText.numeric(size: 15.5, weight: FontWeight.w600),
              ),
            ],
            IconButton(
              tooltip: l10n.homeDirections,
              onPressed: origin == null
                  ? null
                  : () => openDirections(
                      context,
                      to: r,
                      fromName: origin.label(l10n),
                      fromLat: origin.latitude,
                      fromLng: origin.longitude,
                    ),
              icon: Icon(Icons.directions_outlined, color: p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

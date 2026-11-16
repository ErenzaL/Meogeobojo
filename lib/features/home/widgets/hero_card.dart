import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/seoul_clock.dart';
import '../../origin/providers/origin_providers.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../restaurants/screens/restaurant_detail_screen.dart';
import '../../restaurants/utils/directions.dart';
import '../providers/home_providers.dart';
import '../utils/home_text.dart';
import 'home_card_parts.dart';
import 'restaurant_art.dart';

/// The #1 pick: photo/illustration, name and price, why it is first, when you
/// would arrive versus when the kitchen stops taking orders, and two actions.
class HeroCard extends ConsumerWidget {
  const HeroCard({super.key, required this.recs});

  final HomeRecs recs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final hero = recs.hero;
    final r = hero.restaurant;
    final i = hero.insight;
    final origin = ref.watch(originProvider);
    final nowMin = minutesOfDay(ref.watch(seoulNowProvider));
    final status = orderStatus(hero, nowMin);
    final arrival = nowMin + hero.walkMinutes;

    final segments = r.categoryName
        .split('>')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .skip(1)
        .take(2)
        .toList();
    final meta = <String>[
      ...segments,
      if (i.mainMenu != null && !segments.contains(i.mainMenu)) i.mainMenu!,
    ];

    return HomeCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              RestaurantArt(
                restaurant: r,
                insight: i,
                radius: 16,
                height: 184,
                width: double.infinity,
              ),
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: p.card.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    l10n.homeHeroRank(recs.total, recs.heroRank),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              if (i.minPriceKrw != null) ...[
                const SizedBox(width: 12),
                Text(
                  l10n.homePriceFrom(i.minPriceKrw!),
                  style: AppText.numeric(size: 17),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: meta.join(' · ')),
                if (i.rating != null) ...[
                  if (meta.isNotEmpty) const TextSpan(text: ' · '),
                  TextSpan(
                    text: '★ ',
                    style: TextStyle(color: p.starAmber),
                  ),
                  TextSpan(text: i.rating!.toStringAsFixed(1)),
                ],
                if (i.reviewCount != null)
                  TextSpan(text: ' · ${l10n.homeMetaReviews(i.reviewCount!)}'),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, color: p.textSecondary),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              StatusDot(p.statusOpen),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  reasonText(l10n, hero.reason, hero.walkMinutes),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const DashedDivider(),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TimeColumn(
                  label: l10n.homeArrival,
                  value: formatMinutesOfDay(arrival),
                  sub: l10n.homeWalkAbout(hero.walkMinutes),
                ),
              ),
              Expanded(child: _lastOrderColumn(context, status)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: RustButton(
                  icon: Icons.directions_outlined,
                  label: l10n.homeDirections,
                  onPressed: origin == null
                      ? null
                      : () {
                          ref
                              .read(activeRecommendationProvider.notifier)
                              .markWent(r);
                          openDirections(
                            context,
                            to: r,
                            fromName: origin.label(l10n),
                            fromLat: origin.latitude,
                            fromLng: origin.longitude,
                          );
                        },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlineActionButton(
                  label: l10n.homeInfo,
                  onPressed: () => openRestaurantDetail(context, r),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _lastOrderColumn(BuildContext context, OrderStatus status) {
    final l10n = context.l10n;
    final last = status.lastOrderMinutes;
    if (last == null || status.kind == OrderStatusKind.notOpenYet) {
      return _TimeColumn(
        label: l10n.homeLastOrder,
        value: last == null ? '—' : formatMinutesOfDay(last),
        sub: last == null ? l10n.homeNoInfo : l10n.detailOrderNotOpen,
        subColor: last == null ? null : context.palette.statusWarn,
      );
    }
    final tooLate = status.kind == OrderStatusKind.closedBeforeArrival;
    return _TimeColumn(
      label: l10n.homeLastOrder,
      value: formatMinutesOfDay(last),
      sub: tooLate
          ? l10n.homeClosesBeforeArrival
          : slackText(l10n, status.slackMinutes ?? 0),
      subColor: tooLate ? context.palette.statusWarn : null,
    );
  }
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn({
    required this.label,
    required this.value,
    required this.sub,
    this.subColor,
  });

  final String label;
  final String value;
  final String sub;
  final Color? subColor;

  @override
  Widget build(BuildContext context) {
    final secondary = context.palette.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: secondary)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: AppText.numeric(size: 32)),
        ),
        const SizedBox(height: 6),
        Text(
          sub,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, color: subColor ?? secondary),
        ),
      ],
    );
  }
}

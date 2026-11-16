import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../restaurants/screens/restaurant_detail_screen.dart';
import '../providers/home_providers.dart';

/// 전체 추천 순위, its own page: the current ranking, top [_maxRanks]; a row
/// opens 식당 정보.
Future<void> openRankingScreen(BuildContext context, HomeRecs recs) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => RankingScreen(recs: recs)),
    );

const _maxRanks = 10;

class RankingScreen extends StatelessWidget {
  const RankingScreen({super.key, required this.recs});

  final HomeRecs recs;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final items = recs.ranked.take(_maxRanks).toList();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.homeRankingTitle)),
      body: Center(
        // The website: a readable column, not rows stretched across the window.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Text(
                l10n.homeRankingSub(items.length),
                style: TextStyle(fontSize: 14, color: p.textSecondary),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < items.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  selected: items[i] == recs.hero,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: i == 0 ? p.rustText : p.fillMuted,
                    foregroundColor: i == 0 ? p.card : p.textPrimary,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  title: Text(
                    items[i].restaurant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      l10n.homeWalkAbout(items[i].walkMinutes),
                      if (items[i].insight.minPriceKrw != null)
                        l10n.homePriceFrom(items[i].insight.minPriceKrw!),
                      if (!items[i].verified) l10n.homeUnverifiedTag,
                      if (items[i].demoBasis) l10n.demoTag,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      openRestaurantDetail(context, items[i].restaurant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

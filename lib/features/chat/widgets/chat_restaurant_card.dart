import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/geo.dart';
import '../../../core/utils/seoul_clock.dart';
import '../../home/utils/home_text.dart';
import '../../home/widgets/restaurant_art.dart';
import '../../origin/providers/origin_providers.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../recommendation/restaurant_insight.dart';
import '../../restaurants/models/restaurant_override.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../restaurants/screens/restaurant_detail_screen.dart';
import '../../restaurants/utils/directions.dart';
import '../../university/models/university_display.dart';
import '../../university/providers/university_providers.dart';
import '../models/chat_models.dart';
import '../providers/chat_controller.dart';
import 'chat_text.dart';

/// A recommended restaurant, compact enough for the chat. Collapsed it shows the real photo, name, category, campus,
/// walk, the cheapest real price and the reason; tapping it opens the restaurant's REAL menu (from the database) with
/// a link to the full detail page and to directions.
class ChatRestaurantCard extends ConsumerStatefulWidget {
  const ChatRestaurantCard({
    super.key,
    required this.hit,
    this.initiallyExpanded = false,
  });

  final ChatHit hit;
  final bool initiallyExpanded;

  @override
  ConsumerState<ChatRestaurantCard> createState() => _ChatRestaurantCardState();
}

class _ChatRestaurantCardState extends ConsumerState<ChatRestaurantCard> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final hit = widget.hit;
    final ranked = hit.ranked;
    final r = ranked.restaurant;
    final university = ref
        .watch(selectedUniversityProvider)
        .value
        ?.displayName(Localizations.localeOf(context));
    final nowMin = minutesOfDay(ref.watch(seoulNowProvider));
    final price = hit.matched.isNotEmpty
        ? hit.matched.map((m) => m.priceKrw).whereType<int>().fold<int?>(
            null,
            (a, b) => a == null || b < a ? b : a,
          )
        : cheapestOffered(ranked);
    final status = ranked.insight.demo ? null : _status(l10n, p, ranked, nowMin);

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: p.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: ValueKey('chat-card-${r.kakaoId}'),
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Photo(hit: hit),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    r.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.title.copyWith(fontSize: 15),
                                  ),
                                ),
                                AnimatedRotation(
                                  turns: _open ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 180),
                                  child: Icon(
                                    Icons.expand_more_rounded,
                                    size: 20,
                                    color: p.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [r.categoryTag, ?university].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: p.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _Chip(
                                  icon: Icons.directions_walk_rounded,
                                  text:
                                      '${l10n.chatCardWalk(ranked.walkMinutes)} · ${formatDistance(ranked.meters)}',
                                ),
                                _Chip(
                                  icon: Icons.payments_outlined,
                                  text: price == null
                                      ? l10n.chatCardPriceUnknown
                                      : l10n.chatCardPriceFrom(groupedKrw(price)),
                                  muted: price == null,
                                ),
                                if (status != null)
                                  _Chip(text: status.$1, color: status.$2),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              chatReasonText(l10n, hit),
                              maxLines: _open ? 6 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: p.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _open
                    ? _Expanded(hit: hit)
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String, Color)? _status(
    AppLocalizations l10n,
    AppPalette p,
    RankedRestaurant ranked,
    int nowMin,
  ) {
    final s = orderStatus(ranked, nowMin);
    return switch (s.kind) {
      OrderStatusKind.available => (l10n.homeStatusOrderable, p.statusOpen),
      OrderStatusKind.closesSoon ||
      OrderStatusKind.closedBeforeArrival => (
        l10n.homeStatusClosesAt(formatMinutesOfDay(s.lastOrderMinutes!)),
        p.statusWarn,
      ),
      OrderStatusKind.notOpenYet => (l10n.homeStatusNotOpen, p.statusWarn),
      OrderStatusKind.unknown => null,
    };
  }
}

/// The restaurant's own cover photo (admin-uploaded, published), else the photo on its record, else the app's usual
/// category illustration. Never a generated picture.
class _Photo extends ConsumerWidget {
  const _Photo({required this.hit});

  final ChatHit hit;
  static const _size = 78.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = hit.ranked.restaurant;
    final cover = ref.watch(restaurantPhotosProvider(r.kakaoId)).value;
    final url = (cover != null && cover.isNotEmpty)
        ? cover.first.url
        : hit.ranked.insight.imageUrl;
    final insight = url == null
        ? RestaurantInsight.unknown
        : _withImage(url);
    return RestaurantArt(
      restaurant: r,
      insight: insight,
      radius: 12,
      width: _size,
      height: _size,
      compact: true,
    );
  }

  RestaurantInsight _withImage(String url) => RestaurantInsight(imageUrl: url);
}

class _Chip extends StatelessWidget {
  const _Chip({this.icon, required this.text, this.color, this.muted = false});

  final IconData? icon;
  final String text;
  final Color? color;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = color ?? (muted ? p.textSecondary : p.accentStrong);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color == null ? p.accentFaint : color!.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: fg),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The real menu plus the two actions.
class _Expanded extends ConsumerWidget {
  const _Expanded({required this.hit});

  final ChatHit hit;
  static const _maxRows = 15;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = context.palette;
    final r = hit.ranked.restaurant;
    final menus = ref.watch(restaurantMenusProvider(r.kakaoId));
    final origin = ref.watch(originProvider);
    final matchedNames = {for (final m in hit.matched) m.name};

    Widget body = menus.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, _) => _Note(l10n.chatCardNoMenu),
      data: (items) {
        if (items.isEmpty) return _Note(l10n.chatCardNoMenu);
        final sorted = [...items]
          ..sort((a, b) {
            final am = matchedNames.contains(a.name);
            final bm = matchedNames.contains(b.name);
            if (am != bm) return am ? -1 : 1;
            if (a.representative != b.representative) {
              return a.representative ? -1 : 1;
            }
            return 0;
          });
        return Column(
          children: [
            for (final m in sorted.take(_maxRows))
              _MenuRow(item: m, highlighted: matchedNames.contains(m.name)),
          ],
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: p.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Text(
            l10n.restaurantMenuTitle,
            style: AppText.title.copyWith(fontSize: 13),
          ),
        ),
        body,
        if (hit.spiceUnrecorded)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Text(
              l10n.chatCardSpiceUnrecorded,
              style: TextStyle(
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
                color: p.textSecondary,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  key: ValueKey('chat-details-${r.kakaoId}'),
                  onPressed: () => openRestaurantDetail(context, r),
                  child: Text(l10n.chatCardDetails),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: origin == null
                      ? null
                      : () => openDirections(
                          context,
                          to: r,
                          fromName: origin.label(l10n),
                          fromLat: origin.latitude,
                          fromLng: origin.longitude,
                        ),
                  child: Text(l10n.chatCardDirections),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, color: context.palette.textSecondary),
    ),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item, required this.highlighted});

  final RestaurantMenuItem item;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final image = item.imageUrl;
    final sold = !item.available;
    final desc = item.description;
    return Container(
      color: highlighted ? p.accentFaint : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (image != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                image,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(width: 44, height: 44),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: sold ? p.textSecondary : p.textPrimary,
                    decoration: sold ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (desc != null && desc.isNotEmpty)
                  Text(
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                  ),
                if (sold)
                  Text(
                    l10n.restaurantMenuSoldOut,
                    style: TextStyle(fontSize: 11.5, color: p.error),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.priceKrw == null ? '—' : wonSigned(item.priceKrw!),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: sold ? p.textSecondary : p.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

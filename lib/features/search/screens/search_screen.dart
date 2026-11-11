import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pill_chip.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../conditions/widgets/conditions_sheet.dart';
import '../../origin/providers/origin_providers.dart';
import '../../origin/widgets/origin_sheet.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/widgets/restaurant_async_list.dart';
import '../../restaurants/widgets/restaurant_list_tile.dart';
import '../providers/search_providers.dart';

/// Menu keywords offered before a search. They are search terms sent to Kakao Local, so they stay in Korean.
const searchSuggestions = ['제육', '국밥', '떡볶이', '카페', '마라탕', '돈까스', '초밥'];

/// 검색 (V5): back + search field, the shared conditions, recent and suggested searches, then the results that match
/// the conditions first and the ones outside them below (still openable).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  /// When set (e.g. from a menu keyword chip) the search runs immediately.
  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery ?? '',
  );

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery;
    if (q != null && q.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search(q);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A finished search (submitted, or a chip): runs now and goes into the recent list.
  void _search(String q) {
    final t = q.trim();
    if (_controller.text != q) {
      _controller.text = q;
      _controller.selection = TextSelection.collapsed(offset: q.length);
    }
    setState(() {});
    ref.read(searchProvider.notifier).onQueryChanged(t, immediate: true);
    if (t.isNotEmpty) ref.read(recentSearchesProvider.notifier).add(t);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final state = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);

    // Search obeys the same conditions as Home and the map.
    final origin = ref.watch(originProvider);
    final conditions = ref.watch(conditionsProvider);
    final hidden = ref.watch(hiddenPlaceIdsProvider);
    final now = ref.watch(seoulNowProvider);
    final inside = origin == null
        ? [
            for (final r in state.results)
              if (!hidden.contains(r.kakaoId)) r,
          ]
        : [
            for (final r in rankRestaurants(
              all: state.results,
              lat: origin.latitude,
              lng: origin.longitude,
              conditions: conditions,
              insights: ref.watch(restaurantInsightsProvider),
              hiddenIds: hidden,
              nowMinutes: now.hour * 60 + now.minute,
            ))
              r.restaurant,
          ];
    final insideIds = {for (final r in inside) r.kakaoId};
    final outside = [
      for (final r in state.results)
        if (!insideIds.contains(r.kakaoId) && !hidden.contains(r.kakaoId)) r,
    ];

    final conditionChips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        PillChip(
          icon: Icons.tune_rounded,
          label: conditions.activeCount > 0
              ? '${l10n.homeConditionsChip} ${conditions.activeCount}'
              : l10n.homeConditionsChip,
          selected: conditions.activeCount > 0,
          onTap: () => showConditionsSheet(context),
        ),
        if (origin != null)
          PillChip(
            icon: Icons.place_outlined,
            label: l10n.homeOriginChip(origin.label(l10n)),
            selected: false,
            onTap: () => showOriginSheet(context),
          ),
      ],
    );

    List<Widget> tiles(List<Restaurant> list, {bool dim = false}) => [
      for (final r in list)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Opacity(
            opacity: dim ? 0.6 : 1,
            child: RestaurantListTile(restaurant: r),
          ),
        ),
    ];

    final Widget body = switch (state.status) {
      SearchStatus.idle => _list([conditionChips, ..._idle()]),
      SearchStatus.loading when state.results.isEmpty =>
        const RestaurantListSkeleton(),
      SearchStatus.error => RestaurantErrorView(
        error: state.error!,
        onRetry: notifier.retry,
      ),
      SearchStatus.data when state.results.isEmpty => _list([
        conditionChips,
        V5EmptyState(
          icon: Icons.search_off_rounded,
          title: l10n.searchNoResultsTitle(state.query),
          message: l10n.searchNoResultsMessage,
        ),
      ]),
      _ => _list([
        conditionChips,
        const SizedBox(height: 14),
        Text(
          l10n.searchResultsLine(
            state.query,
            inside.length + outside.length,
            inside.length,
          ),
          style: TextStyle(fontSize: 14, color: p.textSecondary),
        ),
        if (inside.isEmpty && conditions.activeCount > 0) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: V5SmallButton(
              label: l10n.condResetAll,
              onPressed: ref.read(conditionsProvider.notifier).clear,
            ),
          ),
        ],
        ...tiles(inside),
        if (outside.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            l10n.searchOutsideTitle,
            style: TextStyle(fontSize: 13, color: p.textMuted),
          ),
          ...tiles(outside, dim: true),
        ],
      ]),
    };

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
                  child: Row(
                    children: [
                      BackButton(color: p.textPrimary),
                      Expanded(child: _field(context, notifier)),
                    ],
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _list(List<Widget> children) => ListView(
    padding: EdgeInsets.fromLTRB(
      16,
      8,
      16,
      24 + MediaQuery.paddingOf(context).bottom,
    ),
    children: children,
  );

  List<Widget> _idle() {
    final l10n = context.l10n;
    final p = context.palette;
    final recent = ref.watch(recentSearchesProvider);
    return [
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: Text(l10n.searchRecentTitle, style: AppText.sectionTitle),
          ),
          if (recent.isNotEmpty)
            TextButton(
              onPressed: ref.read(recentSearchesProvider.notifier).clear,
              child: Text(l10n.searchRecentClear),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (recent.isEmpty)
        Text(
          l10n.searchRecentEmpty,
          style: TextStyle(fontSize: 14, color: p.textSecondary),
        )
      else
        ChipWrap(
          children: [
            for (final q in recent)
              PillChip(
                icon: Icons.history_rounded,
                label: q,
                selected: false,
                onTap: () => _search(q),
              ),
          ],
        ),
      const SizedBox(height: 24),
      Text(l10n.searchSuggestTitle, style: AppText.sectionTitle),
      const SizedBox(height: 8),
      ChipWrap(
        children: [
          for (final q in searchSuggestions)
            PillChip(label: q, selected: false, onTap: () => _search(q)),
        ],
      ),
    ];
  }

  Widget _field(BuildContext context, SearchNotifier notifier) {
    final p = context.palette;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      borderSide: BorderSide(color: p.border),
    );
    return TextField(
      controller: _controller,
      autofocus: widget.initialQuery == null,
      textInputAction: TextInputAction.search,
      onChanged: (v) {
        setState(() {});
        notifier.onQueryChanged(v);
      },
      onSubmitted: _search,
      decoration: InputDecoration(
        hintText: context.l10n.searchHint,
        hintStyle: AppText.body.copyWith(color: p.textSecondary),
        prefixIcon: Icon(Icons.search_rounded, color: p.textSecondary),
        filled: true,
        fillColor: p.card,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: context.l10n.searchRecentClear,
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                  notifier.onQueryChanged('');
                },
              ),
        border: border,
        enabledBorder: border,
      ),
    );
  }
}

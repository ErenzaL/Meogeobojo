import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../conditions/providers/conditions_providers.dart';
import '../../origin/providers/origin_providers.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../restaurants/widgets/restaurant_async_list.dart';
import '../../university/providers/university_providers.dart';
import '../providers/search_providers.dart';
import '../../../core/l10n/l10n.dart';
import '../../university/models/university_display.dart';
import '../../../core/theme/app_palette.dart';

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
        if (mounted) {
          ref.read(searchProvider.notifier).onQueryChanged(q, immediate: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);
    final univ = ref.watch(selectedUniversityProvider).value;
    final notifier = ref.read(searchProvider.notifier);

    // Search obeys the same conditions as Home and the map.
    final origin = ref.watch(originProvider);
    final conditions = ref.watch(conditionsProvider);
    final insights = ref.watch(restaurantInsightsProvider);
    final now = ref.watch(seoulNowProvider);
    final shown = origin == null
        ? state.results
        : [
            for (final r in rankRestaurants(
              all: state.results,
              lat: origin.latitude,
              lng: origin.longitude,
              conditions: conditions,
              insights: insights,
              nowMinutes: now.hour * 60 + now.minute,
            ))
              r.restaurant,
          ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.screenH),
          child: TextField(
            controller: _controller,
            autofocus: widget.initialQuery == null,
            textInputAction: TextInputAction.search,
            onChanged: (v) {
              setState(() {});
              notifier.onQueryChanged(v);
            },
            onSubmitted: (v) => notifier.onQueryChanged(v, immediate: true),
            decoration: InputDecoration(
              hintText: context.l10n.searchHint,
              hintStyle: AppText.body.copyWith(
                color: context.palette.textSecondary,
              ),
              filled: true,
              fillColor: context.palette.card,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        _controller.clear();
                        setState(() {});
                        notifier.onQueryChanged('');
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: BorderSide(color: context.palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                borderSide: BorderSide(color: context.palette.border),
              ),
            ),
          ),
        ),
      ),
      body: switch (state.status) {
        SearchStatus.idle => MascotMessage(
          asset: AppAssets.mascotSearching,
          title: context.l10n.searchIdleTitle,
          message: context.l10n.searchIdleMessage(
            univ?.displayName(Localizations.localeOf(context)) ??
                context.l10n.universityFallbackName,
          ),
        ),
        SearchStatus.loading when state.results.isEmpty =>
          const RestaurantListSkeleton(),
        SearchStatus.error => RestaurantErrorView(
          error: state.error!,
          onRetry: notifier.retry,
        ),
        SearchStatus.data when state.results.isNotEmpty && shown.isEmpty =>
          MascotMessage(
            asset: AppAssets.mascotSearching,
            title: context.l10n.homeEmptyTitle,
            message: context.l10n.homeEmptyMessage,
            actionLabel: context.l10n.condResetAll,
            onAction: ref.read(conditionsProvider.notifier).clear,
          ),
        SearchStatus.data when state.results.isEmpty => MascotMessage(
          asset: AppAssets.mascotSearching,
          title: context.l10n.searchNoResultsTitle(state.query),
          message: context.l10n.searchNoResultsMessage,
        ),
        _ => RestaurantListView(
          restaurants: shown,
          header: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              context.l10n.searchResultsSummary(
                univ?.displayName(Localizations.localeOf(context)) ?? '',
                shown.length,
              ),
              style: AppText.caption(context),
            ),
          ),
        ),
      },
    );
  }
}

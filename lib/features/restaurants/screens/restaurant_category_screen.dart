import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../../core/widgets/skeleton.dart';
import '../../home/widgets/home_search_bar.dart';
import '../../university/models/university_display.dart';
import '../../university/providers/university_providers.dart';
import '../../university/widgets/university_sheet.dart';
import '../models/food_category.dart';
import '../models/restaurant.dart';
import '../providers/restaurant_providers.dart';
import '../widgets/category_tile.dart';
import '../widgets/restaurant_async_list.dart';
import '../widgets/restaurant_list_tile.dart';

enum RestaurantSort { distance, name }

/// 학교 주변 맛집: restaurants around the selected university for one
/// category, with the categories as tabs along the top. Opened from the Home
/// category shortcuts (and keeps its own category, so Home is never filtered
/// or rebuilt). Uses the SAME selected university as Home and the map.
class RestaurantCategoryScreen extends ConsumerStatefulWidget {
  const RestaurantCategoryScreen({
    super.key,
    this.initialCategory = FoodCategory.all,
  });

  final FoodCategory initialCategory;

  @override
  ConsumerState<RestaurantCategoryScreen> createState() =>
      _RestaurantCategoryScreenState();
}

class _RestaurantCategoryScreenState
    extends ConsumerState<RestaurantCategoryScreen> {
  late FoodCategory _category = widget.initialCategory;
  GlobalCuisine _cuisine = GlobalCuisine.all;
  RestaurantSort _sort = RestaurantSort.distance;

  CategoryQuery get _query => categoryQuery(_category, _cuisine);

  void _select(FoodCategory c) {
    if (c == _category) return;
    setState(() {
      _category = c;
      _cuisine = GlobalCuisine.all; // a fresh visit to 세계 음식 starts at 전체
    });
  }

  Future<void> _openAllCategories() async {
    final l10n = context.l10n;
    final picked = await showModalBottomSheet<FoodCategory>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ctx.palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(l10n.categoryAllTitle, style: AppText.sectionTitle),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (ctx, c) {
                  const columns = 4;
                  const gap = 6.0;
                  final w = (c.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: 14,
                    children: [
                      for (final cat in FoodCategory.values)
                        SizedBox(
                          width: w,
                          child: CategoryTile(
                            icon: cat.icon,
                            image: cat.image,
                            label: cat.label(l10n),
                            selected: cat == _category,
                            onTap: () => Navigator.of(ctx).pop(cat),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) _select(picked);
  }

  List<Restaurant> _sorted(List<Restaurant> items) {
    final list = [...items];
    switch (_sort) {
      case RestaurantSort.distance:
        list.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      case RestaurantSort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
    }
    return list;
  }

  /// "한식 음식점"; under 세계 음식 the name already says it ("세계 음식",
  /// "베트남 음식"), so no "음식점" is appended.
  String _heading(AppLocalizations l10n) {
    if (_category != FoodCategory.global) {
      return l10n.categoryHeading(_category.label(l10n));
    }
    return _cuisine == GlobalCuisine.all
        ? _category.label(l10n)
        : _cuisine.label(l10n);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final locale = Localizations.localeOf(context);
    final university = ref.watch(selectedUniversityProvider).value;
    final async = ref.watch(categoryRestaurantsProvider(_query));

    final location = university == null
        ? l10n.universityFallbackName
        : (university.city == null
              ? university.displayName(locale)
              : l10n.categoryLocation(
                  university.displayName(locale),
                  cityLabel(l10n, university.city!),
                ));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // App bar: back, title, search.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  const BackButton(),
                  Expanded(
                    child: Text(
                      l10n.homeNearbyTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.sectionTitle.copyWith(fontSize: 20),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.homeSearchLabel,
                    icon: const Icon(Icons.search_rounded),
                    onPressed: () => openSearch(context),
                  ),
                ],
              ),
            ),
            // University / campus (the same selection as Home and the map).
            Semantics(
              button: true,
              label: l10n.universitySelectCurrent(location),
              excludeSemantics: true,
              child: InkWell(
                onTap: () => showUniversitySheet(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    8,
                    AppSpacing.screenH,
                    8,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.place_outlined, size: 20, color: p.accent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.title.copyWith(fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: p.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: p.border),
            _CategoryTabs(
              selected: _category,
              onSelect: _select,
              onOpenAll: _openAllCategories,
            ),
            Divider(height: 1, color: p.border),
            if (_category == FoodCategory.global)
              _CuisineChips(
                selected: _cuisine,
                onSelect: (c) => setState(() => _cuisine = c),
              ),
            Expanded(
              child: async.when(
                loading: () => _Content(
                  heading: _heading(l10n),
                  sort: _sort,
                  onSort: (s) => setState(() => _sort = s),
                  body: const [
                    SkeletonBox(height: 96, radius: 20),
                    SizedBox(height: 12),
                    SkeletonBox(height: 96, radius: 20),
                    SizedBox(height: 12),
                    SkeletonBox(height: 96, radius: 20),
                    SizedBox(height: 12),
                    SkeletonBox(height: 96, radius: 20),
                  ],
                ),
                error: (e, _) => RestaurantErrorView(
                  error: e,
                  onRetry: () =>
                      ref.invalidate(categoryRestaurantsProvider(_query)),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return MascotMessage(
                      asset: AppAssets.mascotSearching,
                      title: l10n.categoryEmptyTitle,
                      message: _category == FoodCategory.global
                          ? l10n.cuisineEmptyHint
                          : l10n.categoryEmptyHint,
                      actionLabel: l10n.commonRetry,
                      onAction: () =>
                          ref.invalidate(categoryRestaurantsProvider(_query)),
                      secondaryLabel: l10n.universityChange,
                      onSecondary: () => showUniversitySheet(context),
                    );
                  }
                  return _Content(
                    heading: _heading(l10n),
                    sort: _sort,
                    onSort: (s) => setState(() => _sort = s),
                    count: items.length,
                    note: _category == FoodCategory.global
                        ? l10n.categoryGlobalNote
                        : l10n.categoryResultsNote,
                    body: [
                      for (final r in _sorted(items)) ...[
                        RestaurantListTile(restaurant: r),
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "[Category] 음식점"  +  sort control, then the results.
class _Content extends StatelessWidget {
  const _Content({
    required this.heading,
    required this.sort,
    required this.onSort,
    required this.body,
    this.count,
    this.note,
  });

  final String heading;
  final RestaurantSort sort;
  final ValueChanged<RestaurantSort> onSort;
  final List<Widget> body;
  final int? count;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        16,
        AppSpacing.screenH,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: heading, style: AppText.sectionTitle),
                    if (count != null)
                      TextSpan(
                        text: '  ${l10n.categoryResultCount(count!)}',
                        style: AppText.caption(context)
                            .copyWith(fontSize: 13.5),
                      ),
                  ],
                ),
              ),
            ),
            PopupMenuButton<RestaurantSort>(
              tooltip: l10n.categorySortDistance,
              initialValue: sort,
              onSelected: onSort,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: RestaurantSort.distance,
                  child: Text(l10n.categorySortDistance),
                ),
                PopupMenuItem(
                  value: RestaurantSort.name,
                  child: Text(l10n.categorySortName),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sort == RestaurantSort.distance
                          ? l10n.categorySortDistance
                          : l10n.categorySortName,
                      style: AppText.link(context),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: p.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (note != null) ...[
          Text(note!, style: AppText.caption(context).copyWith(fontSize: 12)),
        ],
        const SizedBox(height: 14),
        ...body,
      ],
    );
  }
}

/// Horizontal category tabs with an orange underline on the selected one, and a
/// chevron that opens all categories. The selected tab is kept in view.
class _CategoryTabs extends StatefulWidget {
  const _CategoryTabs({
    required this.selected,
    required this.onSelect,
    required this.onOpenAll,
  });

  final FoodCategory selected;
  final ValueChanged<FoodCategory> onSelect;
  final VoidCallback onOpenAll;

  @override
  State<_CategoryTabs> createState() => _CategoryTabsState();
}

class _CategoryTabsState extends State<_CategoryTabs> {
  final _keys = {for (final c in FoodCategory.values) c: GlobalKey()};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reveal(animate: false),
    );
  }

  @override
  void didUpdateWidget(_CategoryTabs old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  void _reveal({bool animate = true}) {
    final ctx = _keys[widget.selected]?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: animate ? const Duration(milliseconds: 260) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (final c in FoodCategory.values)
                    _Tab(
                      key: _keys[c],
                      label: c.label(l10n),
                      selected: c == widget.selected,
                      onTap: () => widget.onSelect(c),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.categoryOpenAll,
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.textPrimary),
            onPressed: widget.onOpenAll,
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? p.accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected ? p.textPrimary : p.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Optional cuisine filter shown under the tabs while 세계 음식 is selected.
class _CuisineChips extends StatelessWidget {
  const _CuisineChips({required this.selected, required this.onSelect});

  final GlobalCuisine selected;
  final ValueChanged<GlobalCuisine> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      key: const ValueKey('cuisine-chips'),
      height: 52,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenH,
          vertical: 8,
        ),
        child: Row(
          children: [
            for (final c in GlobalCuisine.values) ...[
              if (c != GlobalCuisine.values.first) const SizedBox(width: 8),
              _CuisineChip(
                label: c.label(l10n),
                selected: c == selected,
                onTap: () => onSelect(c),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CuisineChip extends StatelessWidget {
  const _CuisineChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? p.accentSoft : p.card,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? p.accent : p.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? p.accentStrong : p.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

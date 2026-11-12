import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/geo.dart';
import '../../../core/utils/seoul_clock.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/v5_widgets.dart';
import '../../auth/providers/auth_providers.dart';
import '../../auth/widgets/auth_prompt.dart';
import '../../contributions/screens/my_contributions_screen.dart';
import '../../contributions/widgets/photo_contribution_sheet.dart';
import '../../favorites/widgets/favorite_button.dart';
import '../../home/providers/home_providers.dart';
import '../../home/widgets/home_card_parts.dart';
import '../../home/widgets/restaurant_art.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../../origin/providers/origin_providers.dart';
import '../../origin/widgets/origin_sheet.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../recommendation/restaurant_insight.dart';
import '../../records/meal_records.dart';
import '../../reviews/models/student_review.dart';
import '../../reviews/providers/review_providers.dart';
import '../../reviews/widgets/reviews_section.dart';
import '../models/restaurant.dart';
import '../models/restaurant_override.dart';
import '../providers/restaurant_providers.dart';
import '../utils/directions.dart';
import '../widgets/restaurant_photo_placeholder.dart';

Future<void> openRestaurantDetail(BuildContext context, Restaurant r) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RestaurantDetailScreen(restaurant: r),
    ),
  );
}

/// 맛집 정보 (V5): photos, rating, order status, the info box (location, how to get there, phone, amenities, price),
/// the admin's description and menu, reviews, and the directions / map actions. Only real data is shown: a part
/// with nothing behind it is left out or says so.
class RestaurantDetailScreen extends ConsumerStatefulWidget {
  const RestaurantDetailScreen({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  ConsumerState<RestaurantDetailScreen> createState() =>
      _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState
    extends ConsumerState<RestaurantDetailScreen> {
  final _reviewsKey = GlobalKey();

  Restaurant get r => widget.restaurant;

  Future<void> _open(Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.restaurantLinkOpenFailed;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }

  /// Back to the shell on the map tab, with this place selected.
  void _showOnMap() {
    ref.read(mapFocusProvider.notifier).show(r);
    ref.read(shellTabProvider.notifier).select(ShellTabs.map);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _toReviews() {
    final ctx = _reviewsKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.05,
      );
    }
  }

  Future<void> _uploadPhoto() async {
    final ok = await requireAuth(context, ref, reason: AuthReason.contribute);
    if (!ok || !mounted) return;
    await showPhotoContributionSheet(context, restaurant: r);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final override = ref.watch(restaurantOverridesProvider).value?[r.kakaoId];
    final insight =
        ref.watch(restaurantInsightsProvider)[r.kakaoId] ??
        RestaurantInsight.unknown;
    final menus =
        ref.watch(restaurantMenusProvider(r.kakaoId)).value ?? const [];
    final photos =
        ref.watch(restaurantPhotosProvider(r.kakaoId)).value ?? const [];
    final reviews =
        ref.watch(restaurantReviewsProvider(r.kakaoId)).value ?? const [];
    final origin = ref.watch(originProvider);
    final meters = origin == null
        ? r.distanceMeters
        : haversineMeters(
            origin.latitude,
            origin.longitude,
            r.latitude,
            r.longitude,
          ).round();
    final walk = walkMinutesFor(meters);
    final status = orderStatusAt(
      lastOrderMinutes: insight.lastOrderMinutes,
      walkMinutes: walk,
      nowMinutes: minutesOfDay(ref.watch(seoulNowProvider)),
    );

    // The live cover (also mirrored to the override's image) leads, the other uploads follow. Nothing is invented
    // when there are none.
    final coverUrl =
        photos.where((p) => p.isCover).firstOrNull?.url ??
        override?.insight.imageUrl;
    final shots = [
      if (coverUrl != null) _Shot(coverUrl, null),
      for (final p in photos)
        if (!p.isCover) _Shot(p.url, p.caption),
    ];
    final description = override?.description;

    void directions() {
      final o = origin;
      if (o == null) return;
      ref.read(activeRecommendationProvider.notifier).markWent(r.kakaoId);
      openDirections(
        context,
        to: r,
        fromName: o.label(l10n),
        fromLat: o.latitude,
        fromLng: o.longitude,
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.desktop;

    final head = _Head(
      restaurant: r,
      insight: insight,
      status: status,
      summary: ReviewSummary.of(reviews),
      large: wide,
      onRating: _toReviews,
    );
    final info = _InfoBox(
      restaurant: r,
      insight: insight,
      originLabel: origin?.label(l10n),
      meters: meters,
      walkMinutes: walk,
      onPhone: (phone) => _open(Uri(scheme: 'tel', path: phone)),
      onKakaoMap: r.placeUrl == null
          ? null
          : () => _open(Uri.parse(r.placeUrl!)),
    );
    final details = <Widget>[
      // Only say "not provided" when an admin has added nothing.
      if (description == null && menus.isEmpty) ...[
        const SizedBox(height: 10),
        Text(l10n.restaurantDataNotice, style: AppText.caption(context)),
      ],
      if (description != null) ...[
        _SectionTitle(l10n.restaurantAboutTitle),
        Text(description, style: AppText.body),
      ],
      if (menus.isNotEmpty) ...[
        _SectionTitle(l10n.restaurantMenuTitle),
        HomeCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < menus.length; i++) ...[
                if (i > 0) Divider(height: 1, color: context.palette.hairline),
                _MenuRow(item: menus[i]),
              ],
            ],
          ),
        ),
      ],
    ];
    final reviewsBlock = Padding(
      key: _reviewsKey,
      padding: const EdgeInsets.only(top: 24),
      child: ReviewsSection(restaurant: r),
    );
    final contribute = Padding(
      padding: const EdgeInsets.only(top: 20),
      child: V5RowGroup(
        rows: [
          V5Row(
            icon: Icons.check_circle_outline_rounded,
            title: l10n.mealAteButton,
            subtitle: l10n.mealAteSub,
            onTap: () => markEaten(context, ref, r),
          ),
          V5Row(
            icon: Icons.add_a_photo_outlined,
            title: l10n.photoUploadButton,
            subtitle: l10n.detailPhotoUploadSub,
            onTap: _uploadPhoto,
          ),
          if (ref.watch(currentUserProvider) != null)
            V5Row(
              icon: Icons.rate_review_outlined,
              title: l10n.myContribOpen,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const MyContributionsScreen(),
                ),
              ),
            ),
        ],
      ),
    );

    final directionsLabel = origin == null
        ? l10n.homeDirections
        : l10n.detailDirectionsWalk(walk);

    final Widget body;
    if (wide) {
      final gutter = WebLayout.gutterOf(context);
      body = SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Gallery(
                        shots: shots,
                        height: 340,
                        restaurant: r,
                        insight: insight,
                      ),
                      reviewsBlock,
                    ],
                  ),
                ),
                const SizedBox(width: 32),
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      head,
                      const SizedBox(height: 16),
                      info,
                      ...details,
                      contribute,
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: origin == null ? null : directions,
                              icon: const Icon(Icons.directions_outlined),
                              label: Text(directionsLabel),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _showOnMap,
                              icon: const Icon(Icons.map_outlined),
                              label: Text(l10n.detailShowOnMap),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Gallery(
              shots: shots,
              height: 200,
              restaurant: r,
              insight: insight,
            ),
            const SizedBox(height: 16),
            head,
            const SizedBox(height: 16),
            info,
            ...details,
            reviewsBlock,
            contribute,
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: Text(l10n.detailTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FavoriteButton(restaurant: r, size: 22),
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: wide
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _showOnMap,
                      icon: const Icon(Icons.map_outlined),
                      label: Text(l10n.detailMap),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: origin == null ? null : directions,
                        icon: const Icon(Icons.directions_outlined),
                        label: Text(
                          directionsLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Shot {
  const _Shot(this.url, this.caption);

  final String url;
  final String? caption;
}

/// Rounded photo strip with a "사진 N장" tag; one photo fills the width. With no photo it is the neutral
/// placeholder, never stock art.
class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.shots,
    required this.height,
    required this.restaurant,
    required this.insight,
  });

  final List<_Shot> shots;
  final double height;

  /// With no photo: the place's category illustration, as on Home (never a stock photo).
  final Restaurant restaurant;
  final RestaurantInsight insight;

  void _view(BuildContext context, _Shot s) => showDialog<void>(
    context: context,
    builder: (_) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              child: Image.network(
                s.url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: context.l10n.commonClose,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_outlined, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (shots.isEmpty) {
      return RestaurantArt(
        restaurant: restaurant,
        insight: insight,
        radius: AppRadius.card,
        width: double.infinity,
        height: height,
      );
    }
    Widget tile(_Shot s) => Semantics(
      button: true,
      label: s.caption,
      child: GestureDetector(
        onTap: () => _view(context, s),
        child: Image.network(
          s.url,
          fit: BoxFit.cover,
          height: height,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : ColoredBox(color: p.fillMuted),
          errorBuilder: (_, _, _) =>
              const RestaurantPhotoPlaceholder(iconSize: 40),
        ),
      ),
    );
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, box) => shots.length == 1
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      child: SizedBox(
                        width: box.maxWidth,
                        child: tile(shots.single),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: shots.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        child: SizedBox(
                          width: box.maxWidth * 0.82,
                          child: tile(shots[i]),
                        ),
                      ),
                    ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: p.card.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: 16,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      context.l10n.detailPhotoCount(shots.length),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rating line (taps through to the reviews), name, order status, price and category chips.
class _Head extends StatelessWidget {
  const _Head({
    required this.restaurant,
    required this.insight,
    required this.status,
    required this.summary,
    required this.large,
    required this.onRating,
  });

  final Restaurant restaurant;
  final RestaurantInsight insight;
  final OrderStatus status;
  final ReviewSummary summary;
  final bool large;
  final VoidCallback onRating;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final r = restaurant;
    final segments = r.categoryName
        .split('>')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .skip(1)
        // two levels like the Home card: a third level is often the franchise name, not a category
        .take(2)
        .toList();
    final last = status.lastOrderMinutes;
    final statusText = last == null
        ? null
        : switch (status.kind) {
            OrderStatusKind.closedBeforeArrival => l10n.detailOrderTooLate(
              formatMinutesOfDay(last),
            ),
            OrderStatusKind.closesSoon => l10n.detailOrderSoon(
              formatMinutesOfDay(last),
            ),
            _ => l10n.detailOrderOpen(formatMinutesOfDay(last)),
          };
    final statusColor = status.kind == OrderStatusKind.available
        ? p.statusOpen
        : p.statusWarn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onRating,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_rounded, size: 18, color: p.starAmber),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    [
                      summary.count > 0
                          ? l10n.detailRatingLine(
                              summary.average.toStringAsFixed(1),
                              summary.count,
                            )
                          : l10n.detailNoReviews,
                      if (segments.isNotEmpty) segments.first,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          r.name,
          style: TextStyle(
            fontSize: large ? 36 : 28,
            fontWeight: FontWeight.w600,
            letterSpacing: large ? -0.4 : -0.3,
            height: 1.25,
          ),
        ),
        if (statusText != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              StatusDot(statusColor, size: 8),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (insight.minPriceKrw != null)
              _Tag(l10n.detailPriceFrom(insight.minPriceKrw!), strong: true),
            for (final s in segments) _Tag(s),
          ],
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.strong = false, this.icon});

  final String label;
  final bool strong;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: strong ? p.rustSoft : p.card,
        borderRadius: BorderRadius.circular(8),
        border: strong ? null : Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: p.textSecondary),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              color: strong ? p.rustText : p.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The V5 info box: label column on the left, the fact on the right.
class _InfoBox extends StatelessWidget {
  const _InfoBox({
    required this.restaurant,
    required this.insight,
    required this.originLabel,
    required this.meters,
    required this.walkMinutes,
    required this.onPhone,
    required this.onKakaoMap,
  });

  final Restaurant restaurant;
  final RestaurantInsight insight;
  final String? originLabel;
  final int meters;
  final int walkMinutes;
  final void Function(String phone) onPhone;
  final VoidCallback? onKakaoMap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final r = restaurant;
    final muted = AppText.body.copyWith(color: p.textSecondary);
    final note = TextStyle(fontSize: 12, height: 1.5, color: p.textMuted);
    final phone = r.phone.trim();
    final amenities = <(IconData, String)>[
      if (insight.hasBreakTime == false)
        (Icons.schedule_outlined, l10n.condAmenityNoBreak),
      if (insight.parking == true)
        (Icons.local_parking_outlined, l10n.condAmenityParking),
      if (insight.localCurrency == true)
        (Icons.payments_outlined, l10n.condAmenityLocalCurrency),
      if (insight.fastTurnover == true)
        (Icons.bolt_outlined, l10n.condAmenityFast),
      if (insight.takeout == true)
        (Icons.takeout_dining_outlined, l10n.condAmenityTakeout),
      if (insight.openLate == true)
        (Icons.nightlight_outlined, l10n.condAmenityLate),
    ];

    return HomeCard(
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.place_outlined,
            label: l10n.detailInfoLocation,
            child: Text(
              r.displayAddress.isEmpty
                  ? l10n.restaurantNoAddress
                  : r.displayAddress,
              style: r.displayAddress.isEmpty ? muted : AppText.body,
            ),
          ),
          _InfoRow(
            icon: Icons.directions_walk_outlined,
            label: l10n.detailInfoRoute,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  originLabel == null
                      ? l10n.restaurantDistanceStraight(formatDistance(meters))
                      : l10n.detailRoute(
                          originLabel!,
                          walkMinutes,
                          formatDistance(meters),
                        ),
                  style: AppText.body,
                ),
                if (originLabel != null)
                  InkWell(
                    onTap: () => showOriginSheet(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        l10n.detailRouteChange,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: p.rustText,
                        ),
                      ),
                    ),
                  ),
                Text(l10n.detailRouteNote, style: note),
                if (onKakaoMap != null) ...[
                  const SizedBox(height: 8),
                  V5SmallButton(
                    icon: Icons.open_in_new_outlined,
                    label: l10n.restaurantOpenKakaoMap,
                    onPressed: onKakaoMap!,
                  ),
                ],
              ],
            ),
          ),
          _InfoRow(
            icon: Icons.phone_outlined,
            label: l10n.detailInfoPhone,
            child: phone.isEmpty
                ? Text(l10n.restaurantNoPhone, style: muted)
                : InkWell(
                    onTap: () => onPhone(phone),
                    child: Text(
                      phone,
                      style: AppText.body.copyWith(
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
          ),
          _InfoRow(
            icon: Icons.storefront_outlined,
            label: l10n.detailInfoAmenities,
            child: amenities.isEmpty
                ? Text(l10n.detailAmenitiesNone, style: muted)
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (icon, label) in amenities)
                        _Tag(label, icon: icon),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Row(
              children: [
                Icon(icon, size: 18, color: p.textSecondary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 14, color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(text, style: AppText.sectionTitle),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item});

  final RestaurantMenuItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = AppText.caption(context).copyWith(fontSize: 13);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox.square(
                dimension: 56,
                child: Image.network(
                  item.imageUrl!,
                  fit: BoxFit.cover,
                  semanticLabel: item.name,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : ColoredBox(color: context.palette.fillMuted),
                  errorBuilder: (_, _, _) =>
                      const RestaurantPhotoPlaceholder(iconSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.recommended)
                  Text(
                    l10n.restaurantMenuRecommended,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.palette.rustText,
                    ),
                  ),
                Text(
                  item.name,
                  style: AppText.body.copyWith(
                    fontWeight: item.representative
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: item.available
                        ? null
                        : context.palette.textSecondary,
                  ),
                ),
                if (item.description != null && item.description!.isNotEmpty)
                  Text(item.description!, style: muted),
                if (!item.available)
                  Text(l10n.restaurantMenuSoldOut, style: muted),
              ],
            ),
          ),
          if (item.priceKrw != null) ...[
            const SizedBox(width: 12),
            Text(
              l10n.restaurantPriceWon(item.priceKrw!),
              style: AppText.numeric(size: 14.5, weight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}

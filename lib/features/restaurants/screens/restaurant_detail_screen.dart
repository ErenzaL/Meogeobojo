import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/geo.dart';
import '../../favorites/widgets/favorite_button.dart';
import '../models/restaurant.dart';
import '../models/restaurant_override.dart';
import '../providers/restaurant_providers.dart';
import '../widgets/restaurant_photo_placeholder.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';

Future<void> openRestaurantDetail(BuildContext context, Restaurant r) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RestaurantDetailScreen(restaurant: r),
    ),
  );
}

class RestaurantDetailScreen extends ConsumerWidget {
  const RestaurantDetailScreen({super.key, required this.restaurant});

  final Restaurant restaurant;

  Future<void> _open(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.restaurantLinkOpenFailed;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {}
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final r = restaurant;
    // Admin-entered info (description, menus); null / empty when none.
    final override = ref.watch(restaurantOverridesProvider).value?[r.kakaoId];
    final menus =
        ref.watch(restaurantMenusProvider(r.kakaoId)).value ?? const [];
    final photos =
        ref.watch(restaurantPhotosProvider(r.kakaoId)).value ?? const [];
    // The live cover (also mirrored to the override's image) leads; the rest
    // of the uploads form the gallery. Nothing is invented when there are none.
    final coverUrl =
        photos.where((p) => p.isCover).firstOrNull?.url ??
        override?.insight.imageUrl;
    final gallery = [
      for (final p in photos)
        if (!p.isCover) p,
    ];
    final description = override?.description;
    final phone = r.phone.trim();
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            backgroundColor: context.palette.background,
            flexibleSpace: FlexibleSpaceBar(
              background: _CoverImage(url: coverUrl),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FavoriteButton(restaurant: r, size: 22),
              ),
            ],
          ),
          SliverSafeArea(
            top: false,
            sliver: SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.screenH),
              sliver: SliverList.list(
                children: [
                  Text(r.name, style: AppText.heroTitle.copyWith(fontSize: 24)),
                  const SizedBox(height: 6),
                  Text(
                    r.categoryName.replaceAll('>', '·'),
                    style: AppText.caption(context).copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  _InfoRow(
                    icon: Icons.directions_walk_rounded,
                    label: l10n.restaurantDistanceStraight(
                      formatDistance(r.distanceMeters),
                    ),
                  ),
                  _InfoRow(
                    icon: Icons.place_outlined,
                    label: r.displayAddress.isEmpty ? null : r.displayAddress,
                    empty: l10n.restaurantNoAddress,
                  ),
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    label: phone.isEmpty ? null : phone,
                    empty: l10n.restaurantNoPhone,
                    onTap: phone.isEmpty
                        ? null
                        : () => _open(context, Uri(scheme: 'tel', path: phone)),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 16),
                    Text(l10n.restaurantAboutTitle, style: AppText.title),
                    const SizedBox(height: 6),
                    Text(description, style: AppText.body),
                  ],
                  if (gallery.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(l10n.restaurantGalleryTitle, style: AppText.title),
                    const SizedBox(height: 8),
                    _Gallery(photos: gallery),
                  ],
                  if (menus.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(l10n.restaurantMenuTitle, style: AppText.title),
                    const SizedBox(height: 6),
                    for (final m in menus) _MenuRow(item: m),
                  ],
                  // Only say "not provided" when an admin has added nothing.
                  if (description == null && menus.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.restaurantDataNotice,
                      style: AppText.caption(context),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: r.placeUrl == null
                        ? null
                        : () => _open(context, Uri.parse(r.placeUrl!)),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(l10n.restaurantOpenKakaoMap),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The place's cover. While loading it is a quiet block; if the file cannot be
/// loaded (or there is none) it is the neutral placeholder, never stock art.
class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null) return const RestaurantPhotoPlaceholder(iconSize: 56);
    return Image.network(
      u,
      fit: BoxFit.cover,
      width: double.infinity,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : ColoredBox(color: context.palette.fillMuted),
      errorBuilder: (_, _, _) => const RestaurantPhotoPlaceholder(iconSize: 56),
    );
  }
}

/// Horizontal strip of uploaded photos; tapping one opens it full screen.
class _Gallery extends StatelessWidget {
  const _Gallery({required this.photos});

  final List<RestaurantPhoto> photos;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 116,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: photos.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final p = photos[i];
        return Semantics(
          button: true,
          label: p.caption,
          child: GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog.fullscreen(
                backgroundColor: Colors.black,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: InteractiveViewer(
                        child: Image.network(
                          p.url,
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
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.network(
                  p.url,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : ColoredBox(color: context.palette.fillMuted),
                  errorBuilder: (_, _, _) =>
                      const RestaurantPhotoPlaceholder(iconSize: 24),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, this.label, this.empty, this.onTap});

  final IconData icon;
  final String? label;
  final String? empty;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final has = label != null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: context.palette.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                has ? label! : (empty ?? ''),
                style: has
                    ? AppText.body
                    : AppText.body.copyWith(
                        color: context.palette.textSecondary,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item});

  final RestaurantMenuItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = AppText.caption(context).copyWith(fontSize: 13);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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

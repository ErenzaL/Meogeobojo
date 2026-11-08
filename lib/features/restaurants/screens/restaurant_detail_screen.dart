import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/geo.dart';
import '../../favorites/widgets/favorite_button.dart';
import '../models/restaurant.dart';
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

class RestaurantDetailScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final r = restaurant;
    final phone = r.phone.trim();
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            backgroundColor: context.palette.background,
            flexibleSpace: const FlexibleSpaceBar(
              background: RestaurantPhotoPlaceholder(iconSize: 56),
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
                  const SizedBox(height: 12),
                  Text(
                    l10n.restaurantDataNotice,
                    style: AppText.caption(context),
                  ),
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

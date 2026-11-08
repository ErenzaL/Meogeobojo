import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../auth/providers/pending_action.dart';
import '../../auth/widgets/auth_prompt.dart';
import '../../restaurants/models/restaurant.dart';
import '../providers/favorites_providers.dart';
import '../../../core/theme/app_palette.dart';

/// Heart toggle. Guests are asked to sign in (and the save is completed for
/// them afterwards) instead of a write being attempted.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({super.key, required this.restaurant, this.size = 20});

  final Restaurant restaurant;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isFav =
        ref.watch(favoritesProvider).value?.contains(restaurant.kakaoId) ??
        false;
    return Semantics(
      button: true,
      label: isFav ? l10n.favoriteRemove : l10n.favoriteAdd,
      child: Material(
        color: context.palette.card.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _onTap(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: size,
              color: isFav
                  ? context.palette.heart
                  : context.palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.favoriteSaveFailed;
    final signedIn = await requireAuth(
      context,
      ref,
      reason: AuthReason.favorite,
      resume: PendingFavorite(restaurant.kakaoId),
    );
    if (!signedIn) return;
    try {
      await ref.read(favoritesProvider.notifier).toggle(restaurant.kakaoId);
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failed)));
    }
  }
}

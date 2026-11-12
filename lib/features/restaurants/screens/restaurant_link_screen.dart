import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_assets.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/mascot_message.dart';
import '../../university/providers/university_providers.dart';
import '../models/restaurant.dart';
import '../providers/restaurant_providers.dart';
import 'restaurant_detail_screen.dart';

/// What a restaurant link leads to.
enum LinkOutcome { found, hidden, missing }

typedef LinkedPlace = ({LinkOutcome outcome, Restaurant? restaurant});

/// Finds the place a link names, without signing in: an admin may have hidden
/// it (then it says so), it may be among the places around the campus, or it
/// is looked up by the name the link carries. Kakao has no lookup by id, so a
/// place that neither finds is reported as gone.
final linkedPlaceProvider = FutureProvider.autoDispose
    .family<LinkedPlace, ({String id, String? name})>((ref, link) async {
      final overrides = await ref
          .watch(restaurantOverrideRepositoryProvider)
          .forPlaces([link.id]);
      if (overrides[link.id]?.isHidden ?? false) {
        return (outcome: LinkOutcome.hidden, restaurant: null);
      }
      Restaurant? pick(List<Restaurant> list) =>
          list.where((r) => r.kakaoId == link.id).firstOrNull;
      try {
        final near = pick(await ref.watch(allNearbyRestaurantsProvider.future));
        if (near != null) return (outcome: LinkOutcome.found, restaurant: near);
      } catch (_) {
        // The nearby list failed; the name search below may still find it.
      }
      final name = link.name;
      if (name != null) {
        final university = await ref.watch(selectedUniversityProvider.future);
        final found = pick(
          await ref
              .watch(restaurantRepositoryProvider)
              .search(university: university, query: name),
        );
        if (found != null) {
          return (outcome: LinkOutcome.found, restaurant: found);
        }
      }
      return (outcome: LinkOutcome.missing, restaurant: null);
    });

/// The route a restaurant link opens: the details once the place is found,
/// a notice when it was removed or made private. [fromBrowser]: the browser
/// opened it (a pasted link, Forward), so the address bar already shows it.
RestaurantDetailRoute restaurantLinkRoute(
  ({String id, String? name}) link, {
  bool fromBrowser = true,
}) => RestaurantDetailRoute(
  path: Uri(
    path: '/restaurant/${link.id}',
    queryParameters: {'name': ?link.name},
  ).toString(),
  fromBrowser: fromBrowser,
  builder: (_) => RestaurantLinkScreen(link: link),
);

class RestaurantLinkScreen extends ConsumerWidget {
  const RestaurantLinkScreen({super.key, required this.link});

  final ({String id, String? name}) link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final result = ref.watch(linkedPlaceProvider(link));
    final place = result.value;
    if (place?.restaurant != null) {
      return RestaurantDetailScreen(restaurant: place!.restaurant!);
    }
    Widget notice(String title, String message, {VoidCallback? retry}) =>
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: MascotMessage(
              asset: AppAssets.mascotMapConfused,
              title: title,
              message: message,
              actionLabel: retry == null ? l10n.linkGoHome : l10n.commonRetry,
              onAction:
                  retry ??
                  () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(link.name ?? l10n.detailTitle)),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => notice(
          l10n.linkUnavailableTitle,
          l10n.tryAgainLater,
          retry: () => ref.invalidate(linkedPlaceProvider(link)),
        ),
        data: (p) => notice(
          l10n.linkUnavailableTitle,
          p.outcome == LinkOutcome.hidden
              ? l10n.linkHiddenMessage
              : l10n.linkMissingMessage,
        ),
      ),
    );
  }
}

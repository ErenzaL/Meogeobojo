import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../navigation/providers/shell_tab_provider.dart';
import '../../restaurants/models/food_category.dart';
import '../../restaurants/screens/restaurant_category_screen.dart';
import '../models/mission_models.dart';

/// Label of a mission's action button ("맛집 찾으러 가기", "리뷰 작성하기" ...).
String? missionActionLabel(AppLocalizations l10n, MissionAction a) =>
    switch (a) {
      MissionAction.none => null,
      MissionAction.recommend => l10n.missionActionRecommend,
      MissionAction.map => l10n.missionActionMap,
      MissionAction.favorites => l10n.missionActionFavorites,
      MissionAction.categories => l10n.missionActionCategories,
      MissionAction.review => l10n.missionActionReview,
      MissionAction.photo => l10n.missionActionPhoto,
      MissionAction.correct => l10n.missionActionCorrect,
    };

/// Takes the user to the feature that moves the mission. Reviews and photos
/// belong to a restaurant, so those send the student to pick one; suggesting a
/// correction does not exist yet and says so instead of pretending.
void runMissionAction(BuildContext context, WidgetRef ref, MissionAction a) {
  final tabs = ref.read(shellTabProvider.notifier);
  switch (a) {
    case MissionAction.none:
      break;
    case MissionAction.recommend:
    case MissionAction.favorites:
      tabs.select(ShellTabs.home);
    case MissionAction.map:
      tabs.select(ShellTabs.map);
    case MissionAction.categories:
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              const RestaurantCategoryScreen(initialCategory: FoodCategory.all),
        ),
      );
    case MissionAction.review:
    case MissionAction.photo:
      // Reviews and photos belong to a restaurant: pick one, then use its page.
      tabs.select(ShellTabs.map);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(context.l10n.missionActionPickPlace)),
        );
    case MissionAction.correct:
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.missionActionSoon)));
  }
}

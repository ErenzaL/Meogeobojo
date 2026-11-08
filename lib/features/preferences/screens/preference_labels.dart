import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../models/user_preferences.dart';

String budgetLabel(AppLocalizations l10n, BudgetOption o) => switch (o) {
  BudgetOption.max8000 => l10n.onbBudgetMax(8000),
  BudgetOption.max10000 => l10n.onbBudgetMax(10000),
  BudgetOption.max12000 => l10n.onbBudgetMax(12000),
  BudgetOption.min12000 => l10n.onbBudgetMin(12000),
  BudgetOption.any => l10n.onbAny,
};

String distanceLabel(AppLocalizations l10n, DistanceOption o) => switch (o) {
  DistanceOption.walk5 => l10n.onbWalkMinutes(5),
  DistanceOption.walk10 => l10n.onbWalkMinutes(10),
  DistanceOption.walk15 => l10n.onbWalkMinutes(15),
  DistanceOption.drive10 => l10n.onbDriveMinutes(10),
  DistanceOption.drive15 => l10n.onbDriveMinutes(15),
  DistanceOption.any => l10n.onbAny,
};

String companionLabel(AppLocalizations l10n, CompanionType c) => switch (c) {
  CompanionType.solo => l10n.companionSolo,
  CompanionType.friends => l10n.companionFriends,
  CompanionType.group => l10n.companionGroup,
  CompanionType.senior => l10n.companionSenior,
  CompanionType.junior => l10n.companionJunior,
  CompanionType.professor => l10n.companionProfessor,
};

IconData companionIcon(CompanionType c) => switch (c) {
  CompanionType.solo => Icons.person_outline_rounded,
  CompanionType.friends => Icons.people_outline_rounded,
  CompanionType.group => Icons.groups_2_outlined,
  CompanionType.senior => Icons.school_outlined,
  CompanionType.junior => Icons.groups_outlined,
  CompanionType.professor => Icons.workspace_premium_outlined,
};

String cuisineLabel(AppLocalizations l10n, Cuisine c) => switch (c) {
  Cuisine.korean => l10n.cuisineKorean,
  Cuisine.japanese => l10n.cuisineJapanese,
  Cuisine.chinese => l10n.cuisineChinese,
  Cuisine.snack => l10n.cuisineSnack,
  Cuisine.cafe => l10n.cuisineCafe,
  Cuisine.western => l10n.cuisineWestern,
  Cuisine.salad => l10n.cuisineSalad,
  Cuisine.any => l10n.cuisineAny,
};

String tagLabel(AppLocalizations l10n, FoodTag t) => switch (t) {
  FoodTag.spicy => l10n.tagSpicy,
  FoodTag.hearty => l10n.tagHearty,
  FoodTag.value => l10n.tagValue,
  FoodTag.light => l10n.tagLight,
};

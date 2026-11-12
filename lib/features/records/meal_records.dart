import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../auth/providers/auth_providers.dart';
import '../auth/widgets/auth_prompt.dart';
import '../home/providers/home_providers.dart';
import '../restaurants/models/restaurant.dart';
import '../reviews/models/student_review.dart';
import '../reviews/providers/review_providers.dart';
import '../reviews/widgets/review_editor_sheet.dart';
import '../university/providers/university_providers.dart';
import 'screens/records_screen.dart';

/// One "먹었어요": where and when.
class MealRecord {
  const MealRecord({
    required this.kakaoId,
    required this.name,
    required this.category,
    required this.eatenAt,
  });

  final String kakaoId;
  final String name;

  /// Short tag ("한식", "카페").
  final String category;
  final DateTime eatenAt;

  Map<String, Object> toJson() => {
    'id': kakaoId,
    'name': name,
    'category': category,
    'at': eatenAt.millisecondsSinceEpoch,
  };

  static MealRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], at = j['at'];
    if (id is! String || name is! String || at is! int) return null;
    final category = j['category'];
    return MealRecord(
      kakaoId: id,
      name: name,
      category: category is String ? category : '',
      eatenAt: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

// ponytail: kept on this device per account. The `food_records` table exists
// but has no API grants yet; move these there (one migration + a repository)
// when records must follow the account across devices.
String mealRecordsPrefsKey(String userId) => 'meal_records_$userId';

/// The signed-in user's meals, newest first. Empty for guests.
final mealRecordsProvider =
    NotifierProvider<MealRecordsNotifier, List<MealRecord>>(
      MealRecordsNotifier.new,
    );

class MealRecordsNotifier extends Notifier<List<MealRecord>> {
  @override
  List<MealRecord> build() {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const [];
    final raw = ref
        .read(sharedPreferencesProvider)
        .getString(mealRecordsPrefsKey(user.id));
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final j in list) ?MealRecord.fromJson(j)];
    } on FormatException {
      return const [];
    }
  }

  void add(Restaurant r, {DateTime? at}) {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    state = [
      MealRecord(
        kakaoId: r.kakaoId,
        name: r.name,
        category: r.categoryTag,
        eatenAt: at ?? DateTime.now(),
      ),
      ...state,
    ];
    ref
        .read(sharedPreferencesProvider)
        .setString(
          mealRecordsPrefsKey(user.id),
          jsonEncode([for (final m in state) m.toJson()]),
        );
  }
}

/// "먹었어요 · 평가 남기기": records the meal in MY 식사 기록 (signing in first
/// if needed), ends the recommendation in use, then opens the review editor.
Future<void> markEaten(
  BuildContext context,
  WidgetRef ref,
  Restaurant r,
) async {
  final ok = await requireAuth(context, ref, reason: AuthReason.records);
  if (!ok || !context.mounted) return;
  ref.read(mealRecordsProvider.notifier).add(r);
  // Also takes the 다녀오셨어요? banner (and [context] with it) off the screen.
  ref.read(activeRecommendationProvider.notifier).finish();

  final l10n = context.l10n;
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        action: SnackBarAction(
          label: l10n.mealSeeRecords,
          onPressed: () => nav.push<void>(
            MaterialPageRoute<void>(builder: (_) => const RecordsScreen()),
          ),
        ),
      ),
    );
  say(l10n.mealSaved);

  // The editor must open on the user's own review: saving an empty form over
  // it would erase its text. So it is fetched, never taken from a list that
  // may still be loading, and a failed fetch opens no editor.
  final me = ref.read(currentUserProvider)?.id;
  final List<StudentReview> reviews;
  try {
    reviews = await ref.read(reviewRepositoryProvider).forPlace(r.kakaoId);
  } catch (e) {
    debugPrint('Own review lookup failed: $e');
    say(l10n.mealSavedReviewLoadFailed);
    return;
  }
  if (!nav.mounted) return;
  await showReviewEditorSheet(
    nav.context,
    restaurant: r,
    existing: reviews.where((x) => x.userId == me).firstOrNull,
  );
}

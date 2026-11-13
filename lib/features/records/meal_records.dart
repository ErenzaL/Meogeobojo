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

  /// The write in progress. Writes run one after another, each starting from
  /// the list the previous one left: two quick 먹었어요 never overwrite each
  /// other.
  Future<bool> _writing = Future.value(true);

  /// Records [r] and waits until it is really written to the device. Returns
  /// false (and leaves the list as it was) when the write failed.
  Future<bool> add(Restaurant r, {DateTime? at}) {
    final eatenAt = at ?? DateTime.now();
    return _writing = _writing.then((_) => _add(r, eatenAt));
  }

  Future<bool> _add(Restaurant r, DateTime eatenAt) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return false;
    final next = [
      MealRecord(
        kakaoId: r.kakaoId,
        name: r.name,
        category: r.categoryTag,
        eatenAt: eatenAt,
      ),
      ...state,
    ];
    bool ok;
    try {
      ok = await ref
          .read(sharedPreferencesProvider)
          .setString(
            mealRecordsPrefsKey(user.id),
            jsonEncode([for (final m in next) m.toJson()]),
          );
    } catch (e) {
      debugPrint('Meal record not saved: ${e.runtimeType}');
      ok = false;
    }
    if (ok) state = next;
    return ok;
  }
}

/// The place a meal was just recorded for from Home, while "리뷰도
/// 남길까요?" is offered (a choice, never an editor that opens by itself).
final reviewPromptProvider = NotifierProvider<ReviewPrompt, Restaurant?>(
  ReviewPrompt.new,
);

class ReviewPrompt extends Notifier<Restaurant?> {
  @override
  Restaurant? build() => null;

  void offer(Restaurant r) => state = r;

  void dismiss() => state = null;
}

/// "먹었어요": records the meal in MY 식사 기록 (signing in first if needed)
/// and only then says so: "MY 식사 기록에 저장했어요" for about 3 seconds,
/// with 기록 보기. A failed write says so and offers a retry instead, and the
/// recommendation in use is ended only once the record is stored. A new
/// notice replaces the previous one. Returns whether the meal was stored.
///
/// [offerReview]: Home then offers "리뷰도 남길까요?" (see [reviewPromptProvider]).
Future<bool> markEaten(
  BuildContext context,
  WidgetRef ref,
  Restaurant r, {
  bool offerReview = false,
}) async {
  final ok = await requireAuth(context, ref, reason: AuthReason.records);
  if (!ok || !context.mounted) return false;
  // What follows can outlive the widget behind [context] and [ref] (the
  // 다녀오셨어요? banner closes; 다시 시도 is tapped after leaving the screen), so
  // it holds the container and the app-level navigator / messenger instead.
  return _saveMeal(
    ProviderScope.containerOf(context, listen: false),
    Navigator.of(context),
    ScaffoldMessenger.of(context),
    context.l10n,
    r,
    offerReview: offerReview,
  );
}

Future<bool> _saveMeal(
  ProviderContainer c,
  NavigatorState nav,
  ScaffoldMessengerState messenger,
  AppLocalizations l10n,
  Restaurant r, {
  required bool offerReview,
}) async {
  final saved = await c.read(mealRecordsProvider.notifier).add(r);
  if (!messenger.mounted) return saved;
  messenger.clearSnackBars();
  if (!saved) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.mealSaveFailed),
        persist: false,
        action: SnackBarAction(
          label: l10n.commonRetry,
          onPressed: () =>
              _saveMeal(c, nav, messenger, l10n, r, offerReview: offerReview),
        ),
      ),
    );
    return false;
  }
  if (offerReview) c.read(reviewPromptProvider.notifier).offer(r);
  // Also takes the 다녀오셨어요? banner off the screen.
  c.read(activeRecommendationProvider.notifier).finish();
  messenger.showSnackBar(
    SnackBar(
      content: Text(l10n.mealSaved),
      duration: const Duration(seconds: 3),
      // With an action a SnackBar stays until dismissed unless told not to.
      persist: false,
      action: SnackBarAction(
        label: l10n.mealSeeRecords,
        onPressed: () => nav.push<void>(
          MaterialPageRoute<void>(builder: (_) => const RecordsScreen()),
        ),
      ),
    ),
  );
  return true;
}

/// "리뷰 쓰기" after a meal was recorded. The editor must open on the user's
/// own review: saving an empty form over it would erase its text. So it is
/// fetched, never taken from a list that may still be loading, and a failed
/// fetch opens no editor.
Future<void> writeReviewFor(
  BuildContext context,
  WidgetRef ref,
  Restaurant r,
) async {
  final l10n = context.l10n;
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final me = ref.read(currentUserProvider)?.id;
  final List<StudentReview> reviews;
  try {
    reviews = await ref.read(reviewRepositoryProvider).forPlace(r.kakaoId);
  } catch (e) {
    debugPrint('Own review lookup failed: $e');
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.mealSavedReviewLoadFailed)));
    return;
  }
  if (!nav.mounted) return;
  await showReviewEditorSheet(
    nav.context,
    restaurant: r,
    existing: reviews.where((x) => x.userId == me).firstOrNull,
  );
}

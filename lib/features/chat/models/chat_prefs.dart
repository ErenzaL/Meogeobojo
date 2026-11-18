import 'package:flutter/foundation.dart';

import '../../conditions/models/conditions.dart';
import '../../preferences/models/user_preferences.dart';

/// What the user asked for in the chat, split the way the assistant understands it.
///
/// HARD constraints are stated by the user and are never relaxed silently: a restaurant that cannot satisfy them is not
/// recommended. SOFT preferences only change the order. The same shape travels to and from the `ai-restaurant-chat`
/// Edge Function (snake_case JSON), which returns the FULL updated preferences each turn.
@immutable
class ChatPrefs {
  const ChatPrefs({
    this.maxPriceKrw,
    this.minPriceKrw,
    this.maxWalkMinutes,
    this.cuisines = const {},
    this.dishKeywords = const [],
    this.avoidSpicy = false,
    this.openNow = false,
    this.softKeywords = const [],
    this.cheap = false,
    this.filling = false,
    this.closer = false,
    this.groupSize,
  });

  static const none = ChatPrefs();

  // hard
  final int? maxPriceKrw;
  final int? minPriceKrw;
  final int? maxWalkMinutes;
  final Set<Cuisine> cuisines;

  /// A dish the user asked for by name (Korean menu words): the restaurant must have a matching dish.
  final List<String> dishKeywords;
  final bool avoidSpicy;
  final bool openNow;

  // soft
  final List<String> softKeywords;
  final bool cheap;
  final bool filling;
  final bool closer;
  final int? groupSize;

  /// Nothing hard is asked, nothing soft either.
  bool get isEmpty =>
      maxPriceKrw == null &&
      minPriceKrw == null &&
      maxWalkMinutes == null &&
      cuisines.isEmpty &&
      dishKeywords.isEmpty &&
      !avoidSpicy &&
      !openNow &&
      softKeywords.isEmpty &&
      !cheap &&
      !filling &&
      !closer &&
      groupSize == null;

  static ChatPrefs fromJson(Object? json) {
    if (json is! Map) return none;
    final h = json['hard'] is Map ? json['hard'] as Map : const {};
    final s = json['soft'] is Map ? json['soft'] as Map : const {};
    int? n(Object? v) => v is num ? v.round() : null;
    List<String> words(Object? v) => [
      if (v is List)
        for (final x in v)
          if (x is String && x.trim().isNotEmpty) x.trim(),
    ];
    return ChatPrefs(
      maxPriceKrw: n(h['max_price_krw']),
      minPriceKrw: n(h['min_price_krw']),
      maxWalkMinutes: n(h['max_walk_minutes']),
      cuisines: {
        for (final c in words(h['cuisines']))
          if (Cuisine.fromDb(c) case final cu? when cu != Cuisine.any) cu,
      },
      dishKeywords: words(h['dish_keywords']),
      avoidSpicy: h['avoid_spicy'] == true,
      openNow: h['open_now'] == true,
      softKeywords: words(s['dish_keywords']),
      cheap: s['cheap'] == true,
      filling: s['filling'] == true,
      closer: s['closer'] == true,
      groupSize: n(s['group_size']),
    );
  }

  Map<String, dynamic> toJson() => {
    'hard': {
      'max_price_krw': maxPriceKrw,
      'min_price_krw': minPriceKrw,
      'max_walk_minutes': maxWalkMinutes,
      'cuisines': [for (final c in cuisines) c.name],
      'dish_keywords': dishKeywords,
      'avoid_spicy': avoidSpicy,
      'open_now': openNow,
    },
    'soft': {
      'dish_keywords': softKeywords,
      'cheap': cheap,
      'filling': filling,
      'closer': closer,
      'group_size': groupSize,
      'occasion': '',
    },
  };

  /// The filters the user already set in the app (used when the AI cannot be reached, so the chat still answers with
  /// the one recommendation engine).
  factory ChatPrefs.fromConditions(Conditions c) => ChatPrefs(
    maxPriceKrw: c.budget.type == BudgetType.max ? c.budget.amountKrw : null,
    minPriceKrw: c.budget.type == BudgetType.min ? c.budget.amountKrw : null,
    maxWalkMinutes: c.distance.mode == TravelMode.walk
        ? c.distance.minutes
        : null,
    cuisines: {...c.cuisines}..remove(Cuisine.any),
    openNow: c.openNowOnly,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatPrefs &&
      other.maxPriceKrw == maxPriceKrw &&
      other.minPriceKrw == minPriceKrw &&
      other.maxWalkMinutes == maxWalkMinutes &&
      setEquals(other.cuisines, cuisines) &&
      listEquals(other.dishKeywords, dishKeywords) &&
      other.avoidSpicy == avoidSpicy &&
      other.openNow == openNow &&
      listEquals(other.softKeywords, softKeywords) &&
      other.cheap == cheap &&
      other.filling == filling &&
      other.closer == closer &&
      other.groupSize == groupSize;

  @override
  int get hashCode => Object.hash(
    maxPriceKrw,
    minPriceKrw,
    maxWalkMinutes,
    Object.hashAllUnordered(cuisines),
    Object.hashAll(dishKeywords),
    avoidSpicy,
    openNow,
    Object.hashAll(softKeywords),
    cheap,
    filling,
    closer,
    groupSize,
  );
}

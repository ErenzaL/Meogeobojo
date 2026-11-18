import '../../conditions/models/conditions.dart';
import '../../preferences/models/user_preferences.dart';
import '../../recommendation/home_ranking.dart';
import '../../recommendation/preference_filter.dart';
import '../../recommendation/restaurant_insight.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/models/restaurant_override.dart';
import '../models/chat_models.dart';
import '../models/chat_prefs.dart';

/// Everything the chat needs to search: the SAME inputs Home ranks with (the published restaurants around the campus,
/// their insights, menus, the chosen origin, the review signal), gathered once per question.
class ChatSearchContext {
  const ChatSearchContext({
    required this.pool,
    required this.insights,
    required this.menus,
    required this.lat,
    required this.lng,
    required this.nowMinutes,
    this.hiddenIds = const {},
    this.visitedIds = const {},
    this.reviewSignals = const {},
  });

  final List<Restaurant> pool;
  final Map<String, RestaurantInsight> insights;
  final Map<String, List<RestaurantMenuItem>> menus;
  final double lat;
  final double lng;
  final int nowMinutes;
  final Set<String> hiddenIds;
  final Set<String> visitedIds;
  final Map<String, double> reviewSignals;
}

class ChatSearchResult {
  const ChatSearchResult(this.hits, {this.hoursIgnored = false});

  /// Every restaurant that satisfies all HARD constraints, best first.
  final List<ChatHit> hits;

  /// "Open now" was asked but no restaurant has opening hours on record, so it could not be applied.
  final bool hoursIgnored;
}

/// Dishes whose NAME says they are spicy. The database has no spice-level field, so this is only a way to leave out
/// the obviously spicy ones for someone who asked to avoid spice. Nothing is ever claimed to be "not spicy".
final _spicyName = RegExp(
  '매운|매콤|얼큰|마라|땡초|청양|불닭|불짬뽕|짬뽕|떡볶이|쭈꾸미|낙곱새|닭발|김치찌개|부대찌개|육개장|낙지|spicy',
  caseSensitive: false,
);

bool spicyByName(String text) =>
    _spicyName.hasMatch(text.replaceAll('백짬뽕', ''));

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

bool _hits(String text, List<String> keywords) {
  final t = _norm(text);
  return keywords.any((k) => k.trim().isNotEmpty && t.contains(_norm(k)));
}

/// "8,000원 이하" / "10,000원 이하" / "12,000원 이하" / "12,000원 이상" are the engine's own budget options, so the
/// engine judges them exactly as it does on Home. Any other amount is checked here against the real menu prices.
BudgetOption? _engineBudget(ChatPrefs p) {
  final max = p.maxPriceKrw, min = p.minPriceKrw;
  if (max != null && min == null) return BudgetOption.from('max', max);
  if (min != null && max == null) return BudgetOption.from('min', min);
  return null;
}

/// Searches with the app's one recommendation engine ([rankRestaurants]) and then applies what only a conversation can
/// ask for: an exact price range, a walking limit in minutes, a named dish, avoiding spicy dishes, and the soft wishes
/// (a mood's dishes, cheap, closer). Only restaurants whose every hard constraint is CONFIRMED by data are returned.
///
/// [exclude] holds restaurants already shown or rejected in this conversation.
ChatSearchResult searchForChat(
  ChatPrefs p,
  ChatSearchContext c, {
  Set<String> exclude = const {},
}) {
  final conditions = usableConditions(
    Conditions(
      budget: _engineBudget(p) ?? BudgetOption.any,
      openNowOnly: p.openNow,
      cuisines: p.cuisines,
    ),
    c.pool,
    c.insights,
  );
  final ranked = rankRestaurants(
    all: c.pool,
    lat: c.lat,
    lng: c.lng,
    conditions: conditions.conditions,
    insights: c.insights,
    nowMinutes: c.nowMinutes,
    hiddenIds: c.hiddenIds,
    visitedIds: c.visitedIds,
    reviewSignals: c.reviewSignals,
  ).confirmed;

  final priceAsked = p.maxPriceKrw != null || p.minPriceKrw != null;
  final softWords = [...p.softKeywords, ...p.dishKeywords];
  final scored =
      <({ChatHit hit, int order, bool softHit, int? price, int meters})>[];

  for (var i = 0; i < ranked.length; i++) {
    final r = ranked[i];
    final id = r.restaurant.kakaoId;
    if (exclude.contains(id)) continue;
    if (p.maxWalkMinutes != null && r.walkMinutes > p.maxWalkMinutes!) continue;
    if (p.cuisines.isNotEmpty &&
        !p.cuisines.any((cu) => cuisineMatches(r.restaurant, cu))) {
      continue;
    }

    final cafe = r.restaurant.categoryGroupCode == 'CE7';
    final arrival = c.nowMinutes + r.walkMinutes;
    final menus = c.menus[id] ?? const <RestaurantMenuItem>[];
    final offered = [
      for (final m in menus)
        if (m.available &&
            m.priceKrw != null &&
            m.line.isOffered(cafe: cafe) &&
            m.line.servedAt(arrival))
          m,
    ];
    bool fits(RestaurantMenuItem m) {
      final price = m.priceKrw!;
      if (p.maxPriceKrw != null && price > p.maxPriceKrw!) return false;
      if (p.minPriceKrw != null && price < p.minPriceKrw!) return false;
      if (p.dishKeywords.isNotEmpty &&
          !_hits('${m.name} ${m.description ?? ''}', p.dishKeywords)) {
        return false;
      }
      if (p.avoidSpicy && spicyByName('${m.name} ${m.description ?? ''}')) {
        return false;
      }
      return true;
    }

    final fitting = [
      for (final m in offered)
        if (fits(m)) m,
    ];
    // A price, or a spicy-free menu, must be confirmed by a real dish.
    if ((priceAsked || p.avoidSpicy) && fitting.isEmpty) continue;
    // A named dish may also be confirmed by the restaurant's own name or Kakao category ("국밥" in "음식점 > 한식 > 국밥").
    final placeHit = _hits(
      '${r.restaurant.name} ${r.restaurant.categoryName}',
      softWords,
    );
    if (p.dishKeywords.isNotEmpty &&
        fitting.isEmpty &&
        !_hits(
          '${r.restaurant.name} ${r.restaurant.categoryName}',
          p.dishKeywords,
        )) {
      continue;
    }

    final shown = [...fitting]
      ..sort((a, b) {
        final ah = _hits('${a.name} ${a.description ?? ''}', softWords);
        final bh = _hits('${b.name} ${b.description ?? ''}', softWords);
        if (ah != bh) return ah ? -1 : 1;
        if (a.representative != b.representative) {
          return a.representative ? -1 : 1;
        }
        if (a.line.isMeal != b.line.isMeal) return a.line.isMeal ? -1 : 1;
        return a.priceKrw!.compareTo(b.priceKrw!);
      });
    final mealPrices = [
      for (final m in fitting)
        if (m.line.isMeal) m.priceKrw!,
    ];
    final prices = mealPrices.isNotEmpty
        ? mealPrices
        : [for (final m in fitting) m.priceKrw!];
    final cheapest = prices.isEmpty
        ? r.insight.minPriceKrw
        : prices.reduce((a, b) => a < b ? a : b);
    final softHit =
        placeHit ||
        fitting.any((m) => _hits('${m.name} ${m.description ?? ''}', softWords));

    scored.add((
      hit: ChatHit(
        ranked: r,
        matched: shown.take(3).toList(),
        spiceUnrecorded: p.avoidSpicy,
      ),
      order: i,
      softHit: softWords.isNotEmpty && softHit,
      price: cheapest,
      meters: r.meters,
    ));
  }

  scored.sort((a, b) {
    if (a.softHit != b.softHit) return a.softHit ? -1 : 1;
    if (p.closer) {
      final d = a.meters.compareTo(b.meters);
      if (d != 0) return d;
    } else if (p.cheap) {
      final ap = a.price, bp = b.price;
      if (ap != bp) {
        if (ap == null) return 1;
        if (bp == null) return -1;
        return ap.compareTo(bp);
      }
    }
    return a.order.compareTo(b.order);
  });

  return ChatSearchResult([
    for (final s in scored) s.hit,
  ], hoursIgnored: conditions.ignoredHours);
}

/// [p] with the named hard constraints dropped (used only to find what to OFFER when nothing matched; it is never
/// applied without the user saying yes).
ChatPrefs relaxedPrefs(
  ChatPrefs p, {
  bool price = false,
  bool walk = false,
  bool cuisine = false,
  bool dish = false,
}) => ChatPrefs(
  maxPriceKrw: price ? null : p.maxPriceKrw,
  minPriceKrw: price ? null : p.minPriceKrw,
  maxWalkMinutes: walk ? null : p.maxWalkMinutes,
  cuisines: cuisine ? const {} : p.cuisines,
  dishKeywords: dish ? const [] : p.dishKeywords,
  avoidSpicy: p.avoidSpicy,
  openNow: p.openNow,
  softKeywords: p.softKeywords,
  cheap: p.cheap,
  filling: p.filling,
  closer: p.closer,
  groupSize: p.groupSize,
);

/// When nothing matched: the first single adjustment that WOULD produce results, to offer to the user.
NoteKind suggestAdjustment(
  ChatPrefs p,
  ChatSearchContext c, {
  Set<String> exclude = const {},
}) {
  bool works(ChatPrefs q) =>
      searchForChat(q, c, exclude: exclude).hits.isNotEmpty;
  if ((p.maxPriceKrw != null || p.minPriceKrw != null) &&
      works(relaxedPrefs(p, price: true))) {
    return NoteKind.noneRaiseBudget;
  }
  if (p.maxWalkMinutes != null && works(relaxedPrefs(p, walk: true))) {
    return NoteKind.noneWiderDistance;
  }
  if (p.cuisines.isNotEmpty && works(relaxedPrefs(p, cuisine: true))) {
    return NoteKind.noneAnyCuisine;
  }
  if (p.dishKeywords.isNotEmpty && works(relaxedPrefs(p, dish: true))) {
    return NoteKind.noneDropDish;
  }
  return NoteKind.noneGeneric;
}

/// The opening status as the Edge Function understands it, or null when it is not reliably known (no last-order data, or
/// the hours come from the simulated demo dataset).
String? openStatusWire(RankedRestaurant r, int nowMinutes) {
  if (r.insight.demo) return null;
  return switch (orderStatus(r, nowMinutes).kind) {
    OrderStatusKind.available => 'open',
    OrderStatusKind.closesSoon => 'last_order_soon',
    OrderStatusKind.closedBeforeArrival => 'closed',
    OrderStatusKind.notOpenYet => 'opens_later',
    OrderStatusKind.unknown => null,
  };
}

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'restaurant.dart';

/// Restaurant categories shown on Home (shortcuts) and on the category page
/// (tabs). Order here is the display order.
///
/// Kakao only exposes a category *path* per place, not a cuisine facet, so
/// each category is backed by (a) keyword queries sent to Kakao and (b) a
/// strict client-side check of the returned `category_name`. A place is only
/// listed under a category when Kakao itself classifies it that way, and each
/// query returns at most ~15 places, so a list is "the nearest matches", not a
/// complete catalogue.
///
/// The queries below were checked against the deployed `search_restaurants`
/// function: e.g. "치킨" alone returned only 2 chicken places in its 15
/// results, while "치킨집" returned 15 of 15, so chicken uses the latter.
enum FoodCategory {
  all(Icons.restaurant_rounded, ['음식점']),
  korean(Icons.rice_bowl_rounded, ['한식']),
  western(Icons.local_pizza_rounded, ['양식']),
  chinese(Icons.ramen_dining_rounded, ['중식']),
  japanese(Icons.set_meal_rounded, ['일식']),
  snack(Icons.tapas_rounded, ['분식']),
  cafe(Icons.local_cafe_rounded, ['카페', '디저트']),
  chicken(Icons.kebab_dining_rounded, ['치킨집', '양념치킨']),
  fastFood(Icons.fastfood_rounded, ['패스트푸드', '햄버거']),

  /// 세계 음식: what Kakao files under 아시아음식 (Vietnamese, Thai, Indian,
  /// Turkish, ...) plus 양식 > 멕시칸. See [GlobalCuisine] for the optional
  /// sub-filter. Italian / French stay under 양식.
  global(Icons.public_rounded, [
    '아시아음식',
    '베트남음식',
    '태국음식',
    '인도음식',
    '멕시칸',
    '튀르키예음식',
  ]),

  /// Everything else Kakao lists under 음식점 (snacks & bakeries, buffet,
  /// lunch boxes, salad ...): anything not covered above. Asian / global
  /// places live under [global], so a place is never listed in both.
  etc(Icons.more_horiz_rounded, ['간식', '뷔페', '샐러드', '도시락']);

  const FoodCategory(this.icon, this.queries);

  /// Label for the active language. (The Korean [queries] below are what is
  /// sent to Kakao and never change with the interface language.)
  String label(AppLocalizations l10n) => switch (this) {
    all => l10n.categoryAll,
    korean => l10n.categoryKorean,
    western => l10n.categoryWestern,
    chinese => l10n.categoryChinese,
    japanese => l10n.categoryJapanese,
    snack => l10n.categorySnack,
    cafe => l10n.categoryCafeDessert,
    chicken => l10n.categoryChicken,
    fastFood => l10n.categoryFastFood,
    global => l10n.categoryGlobal,
    etc => l10n.categoryEtc,
  };

  final IconData icon;

  /// Keyword queries issued to the Edge Function for this category.
  final List<String> queries;

  /// Kakao category segments that have their own category above.
  static const _specific = [
    '한식',
    '양식',
    '중식',
    '일식',
    '분식',
    '치킨',
    '패스트푸드',
    '카페',
    '디저트',
    ...GlobalCuisine._kakaoSegments,
  ];

  bool matches(Restaurant r) {
    if (!r.isFoodPlace) return false;
    final path = r.categoryName;
    bool has(String seg) => path.contains('> $seg');
    switch (this) {
      case FoodCategory.all:
        return true;
      case FoodCategory.korean:
        return has('한식');
      case FoodCategory.western:
        // 멕시칸 is a 양식 sub-path in Kakao but belongs to 세계 음식 here.
        return has('양식') && !GlobalCuisine.all.matches(r);
      case FoodCategory.chinese:
        return has('중식');
      case FoodCategory.japanese:
        return has('일식');
      case FoodCategory.snack:
        return has('분식');
      case FoodCategory.cafe:
        return r.categoryGroupCode == 'CE7' || has('카페') || has('디저트');
      case FoodCategory.chicken:
        return has('치킨');
      case FoodCategory.fastFood:
        return has('패스트푸드');
      case FoodCategory.global:
        return GlobalCuisine.all.matches(r);
      case FoodCategory.etc:
        return r.categoryGroupCode == 'FD6' && !_specific.any(has);
    }
  }
}

/// Optional sub-filter for [FoodCategory.global].
///
/// Kakao has no country facet. What it does have is a category *path* per
/// place, and these path segments were confirmed against the deployed
/// `search_restaurants` function (Seoul + Asan campuses):
///
///  - 음식점 > 아시아음식 > 동남아음식 > 베트남음식
///  - 음식점 > 아시아음식 > 동남아음식 > 태국음식
///  - 음식점 > 아시아음식 > 인도음식
///  - 음식점 > 아시아음식 > 튀르키예음식
///  - 음식점 > 양식 > 멕시칸,브라질   (Mexican AND Brazilian share a segment)
///  - 음식점 > 아시아음식             (no cuisine given)
///
/// A place is only listed under a cuisine when Kakao's own path says so; the
/// restaurant NAME is never used, so e.g. a Korean place called "방콕" is not
/// treated as Thai. Places Kakao files only as generic 아시아음식 fall under
/// [other].
enum GlobalCuisine {
  all([]),
  vietnamese(['베트남음식']),
  thai(['태국음식']),
  indian(['인도음식']),
  mexican(['멕시칸']),
  other(['아시아음식', '튀르키예음식', '동남아음식']);

  const GlobalCuisine(this.queries);

  /// Keyword queries for this cuisine. Empty for [all]: the parent
  /// category's queries are used instead.
  final List<String> queries;

  String label(AppLocalizations l10n) => switch (this) {
    all => l10n.cuisineAll,
    vietnamese => l10n.cuisineVietnamese,
    thai => l10n.cuisineThai,
    indian => l10n.cuisineIndian,
    mexican => l10n.cuisineMexican,
    other => l10n.cuisineOther,
  };

  /// Kakao path segments that make a place "global" at all.
  static const _kakaoSegments = ['아시아음식', '멕시칸'];

  static const _named = {
    GlobalCuisine.vietnamese: '베트남음식',
    GlobalCuisine.thai: '태국음식',
    GlobalCuisine.indian: '인도음식',
    GlobalCuisine.mexican: '멕시칸',
  };

  static bool _has(Restaurant r, String seg) =>
      r.categoryName.contains('> $seg');

  bool matches(Restaurant r) {
    if (!r.isFoodPlace || !_kakaoSegments.any((s) => _has(r, s))) return false;
    switch (this) {
      case GlobalCuisine.all:
        return true;
      case GlobalCuisine.other:
        return !_named.values.any((s) => _has(r, s));
      default:
        return _has(r, _named[this]!);
    }
  }
}

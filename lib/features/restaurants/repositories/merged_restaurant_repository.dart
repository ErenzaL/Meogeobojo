import '../../university/models/university.dart';
import '../models/food_category.dart';
import '../models/restaurant.dart';
import 'restaurant_override_repository.dart';
import 'restaurant_repository.dart';

/// The ONE place Kakao results and admin data are merged, so Home, the map,
/// search, the category pages and saved places all agree:
///
///  * a place an admin hid or archived is dropped everywhere;
///  * a published override's name / address / phone replace Kakao's values;
///  * the Kakao id (and so favorites, markers, ranking and reviews) is untouched.
///
/// Kakao stays the live source for what it owns; nothing from it is stored.
/// Override lookups never fail the list: with no admin data the Kakao result
/// is returned as is.
class OverrideAwareRestaurantRepository implements RestaurantRepository {
  OverrideAwareRestaurantRepository(this._inner, this._overrides);

  final RestaurantRepository _inner;
  final RestaurantOverrideRepository _overrides;

  @override
  Future<List<Restaurant>> nearby({
    required University university,
    FoodCategory category = FoodCategory.all,
    GlobalCuisine cuisine = GlobalCuisine.all,
  }) async => _merge(
    await _inner.nearby(
      university: university,
      category: category,
      cuisine: cuisine,
    ),
  );

  @override
  Future<List<Restaurant>> search({
    required University university,
    required String query,
  }) async => _merge(await _inner.search(university: university, query: query));

  Future<List<Restaurant>> _merge(List<Restaurant> places) async {
    if (places.isEmpty) return places;
    final byId = await _overrides.forPlaces([
      for (final r in places) r.kakaoId,
    ]);
    if (byId.isEmpty) return places;
    return [
      for (final r in places)
        if (!(byId[r.kakaoId]?.isHidden ?? false))
          byId[r.kakaoId]?.applyTo(r) ?? r,
    ];
  }
}

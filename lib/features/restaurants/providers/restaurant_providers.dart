import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../university/providers/university_providers.dart';
import '../models/food_category.dart';
import '../models/restaurant.dart';
import '../repositories/restaurant_repository.dart';

final restaurantRepositoryProvider = Provider<RestaurantRepository>((ref) {
  final client = Supabase.instance.client;
  return KakaoRestaurantRepository(
    (body) => supabaseSearchGateway(client, body),
  );
});

class SelectedCategoryNotifier extends Notifier<FoodCategory> {
  @override
  FoodCategory build() => FoodCategory.all;

  void select(FoodCategory c) => state = c;
}

final selectedCategoryProvider =
    NotifierProvider<SelectedCategoryNotifier, FoodCategory>(
      SelectedCategoryNotifier.new,
    );

/// Places around the selected university for the selected chip. Watching
/// both providers means a university or category change recomputes it and
/// drops the previous result.
final nearbyRestaurantsProvider = FutureProvider<List<Restaurant>>((ref) async {
  final university = await ref.watch(selectedUniversityProvider.future);
  final category = ref.watch(selectedCategoryProvider);
  return ref
      .watch(restaurantRepositoryProvider)
      .nearby(university: university, category: category);
});

/// What the category page is showing. A record, so it has value equality and
/// works as a provider family key. [cuisine] only matters for
/// [FoodCategory.global]; use [categoryQuery] to build one.
typedef CategoryQuery = ({FoodCategory category, GlobalCuisine cuisine});

CategoryQuery categoryQuery(FoodCategory category, GlobalCuisine cuisine) => (
  category: category,
  cuisine: category == FoodCategory.global ? cuisine : GlobalCuisine.all,
);

/// Places around the selected university for ONE category of the category
/// page. It watches the selected university, so switching campus reloads the
/// list (showing loading, not the previous campus's places) while the page
/// keeps the category it was on. The repository's 5-minute cache keeps
/// flipping between tabs from re-calling Kakao.
final categoryRestaurantsProvider = FutureProvider.autoDispose
    .family<List<Restaurant>, CategoryQuery>((ref, query) async {
      final university = await ref.watch(selectedUniversityProvider.future);
      return ref
          .watch(restaurantRepositoryProvider)
          .nearby(
            university: university,
            category: query.category,
            cuisine: query.cuisine,
          );
    });

/// Unfiltered places around the selected university (map markers and the
/// recommendation baseline).
final allNearbyRestaurantsProvider = FutureProvider<List<Restaurant>>((
  ref,
) async {
  final university = await ref.watch(selectedUniversityProvider.future);
  return ref.watch(restaurantRepositoryProvider).nearby(university: university);
});

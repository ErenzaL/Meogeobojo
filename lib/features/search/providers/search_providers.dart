import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recommendation/home_ranking.dart';
import '../../recommendation/providers/ranking_providers.dart';
import '../../restaurants/models/restaurant.dart';
import '../../restaurants/providers/restaurant_providers.dart';
import '../../restaurants/repositories/restaurant_repository.dart';
import '../../university/providers/university_providers.dart';

enum SearchStatus { idle, loading, data, error }

class SearchState {
  const SearchState({
    this.query = '',
    this.status = SearchStatus.idle,
    this.results = const [],
    this.error,
  });

  final String query;
  final SearchStatus status;
  final List<Restaurant> results;
  final RestaurantException? error;
}

/// Debounced search around the selected university. Re-runs when the
/// university changes so results never belong to a previous campus.
class SearchNotifier extends Notifier<SearchState> {
  static const debounce = Duration(milliseconds: 400);

  Timer? _timer;
  int _generation = 0;

  @override
  SearchState build() {
    ref.onDispose(() => _timer?.cancel());
    // Re-run for the new campus when the selection changes.
    ref.listen(selectedUniversityProvider, (prev, next) {
      if (prev?.value != next.value && state.query.isNotEmpty) {
        _run(state.query);
      }
    });
    return const SearchState();
  }

  void onQueryChanged(String raw, {bool immediate = false}) {
    final q = raw.trim();
    _timer?.cancel();
    _generation++;
    if (q.isEmpty) {
      state = const SearchState();
      return;
    }
    state = SearchState(
      query: q,
      status: SearchStatus.loading,
      results: state.results,
    );
    if (immediate) {
      _run(q);
    } else {
      _timer = Timer(debounce, () => _run(q));
    }
  }

  void retry() => onQueryChanged(state.query, immediate: true);

  Future<void> _run(String q) async {
    final gen = ++_generation;
    state = SearchState(
      query: q,
      status: SearchStatus.loading,
      results: state.results,
    );
    try {
      final university = await ref.read(selectedUniversityProvider.future);
      final results = await ref
          .read(restaurantRepositoryProvider)
          .search(university: university, query: q);
      if (gen != _generation) return; // superseded by a newer query
      state = SearchState(
        query: q,
        status: SearchStatus.data,
        results: results,
      );
    } on RestaurantException catch (e) {
      if (gen != _generation) return;
      state = SearchState(query: q, status: SearchStatus.error, error: e);
    } catch (e) {
      if (gen != _generation) return;
      state = SearchState(
        query: q,
        status: SearchStatus.error,
        error: RestaurantException(RestaurantErrorKind.unknown, '$e'),
      );
    }
  }
}

final searchProvider =
    NotifierProvider.autoDispose<SearchNotifier, SearchState>(
      SearchNotifier.new,
    );

/// The search results judged exactly like Home and the map (same origin,
/// conditions and admin data, fetched for these places): confirmed matches
/// first, then the "정보 미확인" ones. Places that fail a condition are not in
/// it (the screen shows them apart, dimmed).
final searchRankedProvider =
    Provider.autoDispose<AsyncValue<List<RankedRestaurant>>>((ref) {
      final s = ref.watch(searchProvider);
      if (s.status != SearchStatus.data) return const AsyncData([]);
      return rankPool(ref, AsyncData(s.results));
    });

/// The last searches the student finished (submitted or picked), newest first. Stored on the device only.
class RecentSearchesNotifier extends Notifier<List<String>> {
  static const _key = 'search_recent';
  static const max = 8;

  @override
  List<String> build() =>
      ref.read(sharedPreferencesProvider).getStringList(_key) ?? const [];

  void add(String query) => _save(
    [
      query,
      for (final q in state)
        if (q != query) q,
    ].take(max).toList(),
  );

  void clear() => _save(const []);

  void _save(List<String> next) {
    state = next;
    ref.read(sharedPreferencesProvider).setStringList(_key, next);
  }
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
      RecentSearchesNotifier.new,
    );

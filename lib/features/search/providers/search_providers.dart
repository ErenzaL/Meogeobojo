import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

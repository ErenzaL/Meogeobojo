import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../l10n/app_localizations.dart';
import '../../university/models/university.dart';
import '../models/food_category.dart';
import '../models/restaurant.dart';

enum RestaurantErrorKind {
  network,
  timeout,
  quota,
  auth,
  invalid,
  upstream,
  unknown,
}

class RestaurantException implements Exception {
  const RestaurantException(this.kind, [this.detail]);

  final RestaurantErrorKind kind;
  final String? detail;

  String localizedMessage(AppLocalizations l10n) => switch (kind) {
    RestaurantErrorKind.network => l10n.restaurantErrNetwork,
    RestaurantErrorKind.timeout => l10n.restaurantErrTimeout,
    RestaurantErrorKind.quota => l10n.restaurantErrQuota,
    RestaurantErrorKind.auth => l10n.restaurantErrAuth,
    RestaurantErrorKind.invalid => l10n.restaurantErrInvalid,
    RestaurantErrorKind.upstream => l10n.restaurantErrUpstream,
    RestaurantErrorKind.unknown => l10n.restaurantErrUnknown,
  };

  @override
  String toString() => 'RestaurantException($kind, $detail)';
}

/// Discovery of places around a university. Kept behind an interface so a
/// recommendation / enrichment backend can be swapped in later.
abstract interface class RestaurantRepository {
  Future<List<Restaurant>> nearby({
    required University university,
    FoodCategory category = FoodCategory.all,
    GlobalCuisine cuisine = GlobalCuisine.all,
  });

  Future<List<Restaurant>> search({
    required University university,
    required String query,
  });
}

/// Calls the deployed `search_restaurants` function with
/// `{query, latitude, longitude}` and returns the decoded JSON body.
typedef SearchGateway = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> body,
);

Future<Map<String, dynamic>> supabaseSearchGateway(
  SupabaseClient client,
  Map<String, dynamic> body,
) async {
  try {
    final res = await client.functions.invoke('search_restaurants', body: body);
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    throw const RestaurantException(
      RestaurantErrorKind.upstream,
      'Unexpected response format',
    );
  } on FunctionException catch (e) {
    throw RestaurantException(
      _kindForStatus(e.status),
      '${e.status}: ${e.details}',
    );
  }
}

RestaurantErrorKind _kindForStatus(int status) {
  if (status == 429) return RestaurantErrorKind.quota;
  if (status == 401 || status == 403) return RestaurantErrorKind.auth;
  if (status == 400) return RestaurantErrorKind.invalid;
  if (status >= 500) return RestaurantErrorKind.upstream;
  return RestaurantErrorKind.unknown;
}

class KakaoRestaurantRepository implements RestaurantRepository {
  KakaoRestaurantRepository(
    this._gateway, {
    this.timeout = const Duration(seconds: 12),
    this.cacheTtl = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final SearchGateway _gateway;
  final Duration timeout;
  final Duration cacheTtl;
  final DateTime Function() _now;

  // Short-lived in-memory cache (quota protection only; never persisted).
  final _cache = <String, ({DateTime at, List<Restaurant> items})>{};

  @override
  Future<List<Restaurant>> nearby({
    required University university,
    FoodCategory category = FoodCategory.all,
    GlobalCuisine cuisine = GlobalCuisine.all,
  }) async {
    // The cuisine sub-filter only exists under 세계 음식.
    final sub = category == FoodCategory.global ? cuisine : GlobalCuisine.all;
    final queries = sub == GlobalCuisine.all ? category.queries : sub.queries;
    final keep = sub == GlobalCuisine.all ? category.matches : sub.matches;
    final results = await Future.wait(
      queries.map((q) => _query(university, q)).map(_settle),
    );
    final failures = results.where((r) => r.error != null).toList();
    if (failures.length == results.length) throw failures.first.error!;
    final merged = results.expand((r) => r.items).toList();
    return _finalize(merged, keep);
  }

  @override
  Future<List<Restaurant>> search({
    required University university,
    required String query,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final items = await _query(university, q);
    return _finalize(items, FoodCategory.all.matches);
  }

  List<Restaurant> _finalize(
    List<Restaurant> items,
    bool Function(Restaurant) keep,
  ) {
    final seen = <String>{};
    final out = [
      for (final r in items)
        if (keep(r) && seen.add(r.kakaoId)) r,
    ]..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return out;
  }

  Future<({List<Restaurant> items, RestaurantException? error})> _settle(
    Future<List<Restaurant>> f,
  ) async {
    try {
      return (items: await f, error: null);
    } on RestaurantException catch (e) {
      return (items: const <Restaurant>[], error: e);
    }
  }

  Future<List<Restaurant>> _query(University u, String query) async {
    final key = '$query|${u.latitude}|${u.longitude}';
    final hit = _cache[key];
    if (hit != null && _now().difference(hit.at) < cacheTtl) return hit.items;

    final Map<String, dynamic> body;
    try {
      body = await _gateway({
        'query': query,
        'latitude': u.latitude,
        'longitude': u.longitude,
      }).timeout(timeout);
    } on RestaurantException {
      rethrow;
    } on TimeoutException {
      throw const RestaurantException(RestaurantErrorKind.timeout);
    } on SocketException catch (e) {
      throw RestaurantException(RestaurantErrorKind.network, e.message);
    } catch (e) {
      // package:http's ClientException (e.g. DNS / connection failures) is not
      // a direct dependency, so it is recognised by name.
      if (e.runtimeType.toString().contains('ClientException')) {
        throw RestaurantException(RestaurantErrorKind.network, '$e');
      }
      debugPrint('search_restaurants unexpected error: $e');
      throw RestaurantException(RestaurantErrorKind.unknown, '$e');
    }

    if (body['success'] == false || body['restaurants'] is! List) {
      throw RestaurantException(
        RestaurantErrorKind.upstream,
        body['error']?.toString() ?? 'Unexpected response format',
      );
    }
    final items = <Restaurant>[];
    for (final raw in body['restaurants'] as List) {
      if (raw is! Map<String, dynamic>) continue;
      final r = Restaurant.fromKakao(
        raw,
        originLat: u.latitude,
        originLng: u.longitude,
      );
      if (r != null) items.add(r);
    }
    _cache[key] = (at: _now(), items: items);
    return items;
  }
}

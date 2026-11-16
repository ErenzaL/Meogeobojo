import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/geo.dart';
import '../../university/models/university.dart';
import '../models/food_category.dart';
import '../models/restaurant.dart';
import '../models/restaurant_override.dart';
import 'restaurant_override_repository.dart' show isDatabaseKey;
import 'restaurant_repository.dart';

/// The restaurants an admin PUBLISHED for one university (`restaurant_university_links` ->
/// `restaurant_overrides`). This is the inventory the app shows: the Admin decides what is listed.
abstract interface class ManagedInventory {
  Future<List<RestaurantOverride>> publishedFor(String universityId);
}

class SupabaseManagedInventory implements ManagedInventory {
  SupabaseManagedInventory(this._db);

  final SupabaseClient _db;

  @override
  Future<List<RestaurantOverride>> publishedFor(String universityId) async {
    // Row-level security already hides drafts from students; the explicit filter also keeps a signed-in admin's
    // draft and hidden restaurants out of the student view.
    final rows = await _db
        .from('restaurant_university_links')
        .select('restaurant_overrides!inner(*)')
        .eq('university_id', universityId)
        .eq('restaurant_overrides.visibility', 'published')
        .timeout(const Duration(seconds: 10));
    final out = <String, RestaurantOverride>{};
    for (final r in rows) {
      final row = r['restaurant_overrides'];
      if (row is! Map<String, dynamic>) continue;
      final o = RestaurantOverride.fromJson(row);
      if (o != null) out[o.kakaoId] = o;
    }
    return out.values.toList();
  }
}

/// What the `resolve_places` function returned: Kakao documents for the places it could identify by id.
typedef ResolvedPlaces = ({List<Map<String, dynamic>> docs, bool partial});

/// Looks up the live Kakao details of managed restaurants, by Kakao place id, in one request.
typedef PlaceResolver = Future<ResolvedPlaces> Function(
  University university,
  List<({String id, String name})> places,
);

Future<ResolvedPlaces> supabaseResolvePlaces(
  SupabaseClient client,
  University university,
  List<({String id, String name})> places,
) async {
  final res = await client.functions.invoke(
    'resolve_places',
    body: {
      'universityId': university.id,
      'places': [
        for (final p in places) {'id': p.id, 'name': p.name},
      ],
    },
  );
  final data = res.data;
  if (data is! Map<String, dynamic> || data['success'] != true) {
    throw const RestaurantException(
      RestaurantErrorKind.upstream,
      'resolve_places: unexpected response',
    );
  }
  return (
    docs: [
      for (final d in (data['places'] as List? ?? const []))
        if (d is Map<String, dynamic>) d,
    ],
    partial: data['partial'] == true,
  );
}

/// Restaurants for the app: PUBLISHED Supabase records are the inventory, so what an admin creates, edits,
/// imports, publishes or unpublishes is what students see. Kakao stays the live provider of what it owns
/// (coordinates, category path, distance, map link) and is asked about the managed restaurants by their Kakao
/// place id; it never adds a restaurant to the list. Managed values win over Kakao's (name, address, phone,
/// category, coordinates).
///
/// A campus with no published restaurant yet keeps the earlier behaviour ([fallback]: Kakao discovery with the
/// admin data merged in), so it is not empty before an admin publishes restaurants there. [fallback] is also
/// used when the inventory or the Kakao lookup cannot be read, so an outage never leaves the list empty.
///
/// A published restaurant whose position cannot be determined (no Kakao match and no coordinates of its own)
/// is left out of the geographic lists rather than shown at a made-up place.
class ManagedRestaurantRepository implements RestaurantRepository {
  ManagedRestaurantRepository({
    required this.inventory,
    required this.resolver,
    required this.fallback,
  });

  final ManagedInventory inventory;
  final PlaceResolver resolver;
  final RestaurantRepository fallback;

  // Requests that are running right now, so Home's several providers asking at once cost ONE read. Nothing is
  // kept afterwards: every later call reads the database again, so an admin's change is never served stale.
  final _inFlight = <String, Future<List<Restaurant>?>>{};

  @override
  Future<List<Restaurant>> nearby({
    required University university,
    FoodCategory category = FoodCategory.all,
    GlobalCuisine cuisine = GlobalCuisine.all,
  }) async {
    final all = await _managed(university);
    if (all == null) {
      return fallback.nearby(
        university: university,
        category: category,
        cuisine: cuisine,
      );
    }
    final sub = category == FoodCategory.global ? cuisine : GlobalCuisine.all;
    final keep = sub == GlobalCuisine.all ? category.matches : sub.matches;
    return [
      for (final r in all)
        if (keep(r)) r,
    ];
  }

  @override
  Future<List<Restaurant>> search({
    required University university,
    required String query,
  }) async {
    final all = await _managed(university);
    if (all == null) {
      return fallback.search(university: university, query: query);
    }
    final q = _norm(query);
    if (q.isEmpty) return const [];
    return [
      for (final r in all)
        if (_norm('${r.name} ${r.categoryName} ${r.displayAddress}')
            .contains(q))
          r,
    ];
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// The managed restaurants of [u] with their live details, nearest first; null when this campus should use
  /// [fallback] (nothing published yet, or something could not be read).
  Future<List<Restaurant>?> _managed(University u) {
    final running = _inFlight[u.id];
    if (running != null) return running;
    // (a block body: `remove` returns the future itself, and whenComplete would wait for it forever)
    final f = _load(u).whenComplete(() {
      _inFlight.remove(u.id);
    });
    _inFlight[u.id] = f;
    return f;
  }

  Future<List<Restaurant>?> _load(University u) async {
    final List<RestaurantOverride> managed;
    try {
      managed = [
        for (final o in await inventory.publishedFor(u.id))
          if (o.visibility == 'published') o,
      ];
    } catch (e) {
      debugPrint('published restaurants unavailable: ${e.runtimeType}');
      return null;
    }
    if (managed.isEmpty) return null;

    final out = <Restaurant>[];
    final toResolve = <RestaurantOverride>[];
    for (final o in managed) {
      if (o.latitude != null && o.longitude != null) {
        out.add(_fromManaged(o, u));
      } else if (!isDatabaseKey(o.kakaoId) && (o.name ?? '').isNotEmpty) {
        toResolve.add(o);
      }
    }
    if (toResolve.isNotEmpty) {
      final ResolvedPlaces resolved;
      try {
        resolved = await resolver(u, [
          for (final o in toResolve) (id: o.kakaoId, name: o.name!),
        ]);
      } catch (e) {
        debugPrint('resolve_places unavailable: ${e.runtimeType}');
        return null;
      }
      final byId = <String, RestaurantOverride>{
        for (final o in toResolve) o.kakaoId: o,
      };
      for (final d in resolved.docs) {
        final r = Restaurant.fromKakao(
          d,
          originLat: u.latitude,
          originLng: u.longitude,
        );
        final o = r == null ? null : byId[r.kakaoId];
        if (r != null && o != null) out.add(o.applyTo(r));
      }
    }
    final seen = <String>{};
    out
      ..retainWhere((r) => seen.add(r.kakaoId))
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return out;
  }

  /// A restaurant with coordinates of its own needs nothing from Kakao.
  Restaurant _fromManaged(RestaurantOverride o, University u) {
    final lat = o.latitude!;
    final lng = o.longitude!;
    final cat = o.category ?? '';
    return Restaurant(
      kakaoId: o.kakaoId,
      name: o.name ?? '',
      categoryName: cat,
      categoryGroupCode: cat.contains('카페') ? 'CE7' : 'FD6',
      address: '',
      roadAddress: o.address ?? '',
      phone: o.phone ?? '',
      latitude: lat,
      longitude: lng,
      distanceMeters: haversineMeters(
        u.latitude,
        u.longitude,
        lat,
        lng,
      ).round(),
      placeUrl: null,
    );
  }
}

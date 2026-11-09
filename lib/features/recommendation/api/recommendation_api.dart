import 'dart:async';

import 'package:flutter/foundation.dart';

/// Typed contract for the external recommendation model (version 1).
/// See docs/recommendation-api.md. Nothing here invents scores or claims a
/// model exists: a response says whether it came from a real model.
@immutable
class RecommendRequest {
  const RecommendRequest({
    required this.universityId,
    required this.candidatePlaceIds,
    this.latitude,
    this.longitude,
    this.diningPurpose,
    this.budgetMaxKrw,
    this.budgetMinKrw,
    this.preferredCategories = const [],
    this.maxResults = 10,
  });

  final String universityId;
  final List<String> candidatePlaceIds;
  final double? latitude;
  final double? longitude;
  final String? diningPurpose;
  final int? budgetMaxKrw;
  final int? budgetMinKrw;
  final List<String> preferredCategories;
  final int maxResults;

  /// Null when valid; otherwise why the request must not be sent.
  String? validate() {
    if (universityId.trim().isEmpty) return 'universityId is empty';
    if (candidatePlaceIds.isEmpty) return 'no candidates';
    if (candidatePlaceIds.length > 200) return 'too many candidates (max 200)';
    if (candidatePlaceIds.any((p) => p.trim().isEmpty)) return 'blank place id';
    if (maxResults < 1 || maxResults > 50) return 'maxResults must be 1..50';
    if ((budgetMaxKrw ?? 0) < 0 || (budgetMinKrw ?? 0) < 0) {
      return 'negative budget';
    }
    final lat = latitude, lng = longitude;
    if ((lat != null && (lat < -90 || lat > 90)) ||
        (lng != null && (lng < -180 || lng > 180))) {
      return 'coordinates out of range';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'university_id': universityId,
    'candidate_place_ids': candidatePlaceIds,
    if (latitude != null && longitude != null)
      'location': {'latitude': latitude, 'longitude': longitude},
    'dining_purpose': ?diningPurpose,
    'budget_max_krw': ?budgetMaxKrw,
    'budget_min_krw': ?budgetMinKrw,
    'preferred_categories': preferredCategories,
    'max_results': maxResults,
  };
}

@immutable
class ModelInfo {
  const ModelInfo({required this.version, required this.isMock});

  final String version;
  final bool isMock;
}

@immutable
class RankedPlace {
  const RankedPlace(this.placeId, this.rank, [this.score]);

  final String placeId;
  final int rank;

  /// Only present when the model supplied it. Never fabricated.
  final double? score;
}

/// Where a ranking came from. UI copy must follow this, not guess.
enum RecommendationSource {
  /// A real model answered.
  model,

  /// The documented test mock answered: NOT a prediction.
  mock,

  /// The service failed or was unavailable; the caller's own order is used.
  fallback,
}

@immutable
class RecommendResponse {
  const RecommendResponse({required this.model, required this.results});

  final ModelInfo model;
  final List<RankedPlace> results;

  /// Parses and validates the wire format; throws [FormatException] on junk.
  factory RecommendResponse.fromJson(Map<String, dynamic> j) {
    final m = j['model'];
    final r = j['results'];
    if (m is! Map ||
        r is! List ||
        m['version'] is! String ||
        m['is_mock'] is! bool) {
      throw const FormatException('unexpected recommendation response');
    }
    final ranked = <RankedPlace>[];
    for (final e in r) {
      if (e is! Map || e['place_id'] is! String || e['rank'] is! int) {
        throw const FormatException('unexpected result entry');
      }
      ranked.add(
        RankedPlace(
          e['place_id'] as String,
          e['rank'] as int,
          (e['score'] as num?)?.toDouble(),
        ),
      );
    }
    return RecommendResponse(
      model: ModelInfo(
        version: m['version'] as String,
        isMock: m['is_mock'] as bool,
      ),
      results: ranked,
    );
  }
}

/// Transport seam: the real HTTP / Edge Function client implements this once
/// the contract is confirmed.
abstract interface class RecommendationApiClient {
  Future<RecommendResponse> recommend(RecommendRequest request);
}

/// Test double with the same contract. Keeps the caller's order and invents no
/// scores; its responses are flagged `isMock`.
class MockRecommendationApiClient implements RecommendationApiClient {
  @override
  Future<RecommendResponse> recommend(RecommendRequest request) async {
    final ids = request.candidatePlaceIds.toSet().take(request.maxResults);
    return RecommendResponse(
      model: const ModelInfo(version: 'mock-0', isMock: true),
      results: [for (final (i, id) in ids.indexed) RankedPlace(id, i + 1)],
    );
  }
}

class RecommendationOutcome {
  const RecommendationOutcome(
    this.placeIds,
    this.source, {
    this.modelVersion,
    this.error,
  });

  final List<String> placeIds;
  final RecommendationSource source;
  final String? modelVersion;
  final String? error;
}

/// Calls the API with validation and a timeout; on any failure, falls back to
/// the caller's own candidate order and says so ([RecommendationSource.fallback]).
class ResilientRecommender {
  ResilientRecommender(
    this._client, {
    this.timeout = const Duration(seconds: 4),
  });

  final RecommendationApiClient _client;
  final Duration timeout;

  Future<RecommendationOutcome> recommend(RecommendRequest request) async {
    List<String> fallback() =>
        request.candidatePlaceIds.take(request.maxResults).toList();
    final invalid = request.validate();
    if (invalid != null) {
      return RecommendationOutcome(
        fallback(),
        RecommendationSource.fallback,
        error: invalid,
      );
    }
    try {
      final res = await _client.recommend(request).timeout(timeout);
      final allowed = request.candidatePlaceIds.toSet();
      // Never trust the wire: only known candidates, ordered by rank.
      final ids = ([...res.results]..sort((a, b) => a.rank.compareTo(b.rank)))
          .map((r) => r.placeId)
          .where(allowed.contains)
          .toList();
      if (ids.isEmpty) {
        return RecommendationOutcome(
          fallback(),
          RecommendationSource.fallback,
          error: 'empty result',
        );
      }
      return RecommendationOutcome(
        ids,
        res.model.isMock
            ? RecommendationSource.mock
            : RecommendationSource.model,
        modelVersion: res.model.version,
      );
    } on TimeoutException {
      return RecommendationOutcome(
        fallback(),
        RecommendationSource.fallback,
        error: 'timeout',
      );
    } catch (e) {
      return RecommendationOutcome(
        fallback(),
        RecommendationSource.fallback,
        error: e.runtimeType.toString(),
      );
    }
  }
}

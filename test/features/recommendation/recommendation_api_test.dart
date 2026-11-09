import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/recommendation/api/recommendation_api.dart';

class _Client implements RecommendationApiClient {
  _Client(this.fn);
  final Future<RecommendResponse> Function(RecommendRequest) fn;
  @override
  Future<RecommendResponse> recommend(RecommendRequest r) => fn(r);
}

RecommendRequest req([List<String> ids = const ['a', 'b', 'c']]) =>
    RecommendRequest(universityId: 'u', candidatePlaceIds: ids, maxResults: 2);

void main() {
  group('RecommendRequest', () {
    test('serialises to the documented wire format', () {
      final j = RecommendRequest(
        universityId: 'u',
        candidatePlaceIds: const ['a'],
        latitude: 36.7,
        longitude: 126.9,
        diningPurpose: 'solo',
        budgetMaxKrw: 9000,
      ).toJson();
      expect(j['university_id'], 'u');
      expect(j['location'], {'latitude': 36.7, 'longitude': 126.9});
      expect(j['dining_purpose'], 'solo');
      expect(j.containsKey('budget_min_krw'), isFalse);
    });
    test('validation catches bad input before anything is sent', () {
      expect(req().validate(), isNull);
      expect(
        const RecommendRequest(
          universityId: '',
          candidatePlaceIds: ['a'],
        ).validate(),
        isNotNull,
      );
      expect(
        const RecommendRequest(
          universityId: 'u',
          candidatePlaceIds: [],
        ).validate(),
        isNotNull,
      );
      expect(
        const RecommendRequest(
          universityId: 'u',
          candidatePlaceIds: [' '],
        ).validate(),
        isNotNull,
      );
      expect(
        const RecommendRequest(
          universityId: 'u',
          candidatePlaceIds: ['a'],
          latitude: 95,
          longitude: 0,
        ).validate(),
        isNotNull,
      );
      expect(
        const RecommendRequest(
          universityId: 'u',
          candidatePlaceIds: ['a'],
          maxResults: 0,
        ).validate(),
        isNotNull,
      );
    });
  });

  group('RecommendResponse.fromJson', () {
    test('parses a valid response; score stays null when absent', () {
      final r = RecommendResponse.fromJson({
        'model': {'version': 'v1', 'is_mock': false},
        'results': [
          {'place_id': 'a', 'rank': 1},
          {'place_id': 'b', 'rank': 2, 'score': 0.5},
        ],
      });
      expect(r.model.isMock, isFalse);
      expect(r.results[0].score, isNull);
      expect(r.results[1].score, 0.5);
    });
    test('rejects malformed payloads', () {
      expect(
        () => RecommendResponse.fromJson({'results': []}),
        throwsFormatException,
      );
      expect(
        () => RecommendResponse.fromJson({
          'model': {'version': 'v', 'is_mock': 'no'},
          'results': [],
        }),
        throwsFormatException,
      );
      expect(
        () => RecommendResponse.fromJson({
          'model': {'version': 'v', 'is_mock': false},
          'results': [
            {'place_id': 1},
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('ResilientRecommender', () {
    test('a mock answer is labelled mock, never model', () async {
      final out = await ResilientRecommender(MockRecommendationApiClient())
          .recommend(req());
      expect(out.source, RecommendationSource.mock);
      expect(out.placeIds, ['a', 'b']);
      expect(out.modelVersion, 'mock-0');
    });
    test('a real model answer is labelled model and ordered by rank', () async {
      final c = _Client(
        (_) async => const RecommendResponse(
          model: ModelInfo(version: 'v1', isMock: false),
          results: [RankedPlace('b', 1), RankedPlace('a', 2)],
        ),
      );
      final out = await ResilientRecommender(c).recommend(req());
      expect(out.source, RecommendationSource.model);
      expect(out.placeIds, ['b', 'a']);
    });
    test('unknown place ids from the wire are dropped', () async {
      final c = _Client(
        (_) async => const RecommendResponse(
          model: ModelInfo(version: 'v1', isMock: false),
          results: [RankedPlace('zzz', 1), RankedPlace('c', 2)],
        ),
      );
      expect((await ResilientRecommender(c).recommend(req())).placeIds, ['c']);
    });
    test(
      'errors, timeouts, empty answers and invalid requests fall back',
      () async {
        final boom = await ResilientRecommender(
          _Client((_) async => throw StateError('x')),
        ).recommend(req());
        expect(boom.source, RecommendationSource.fallback);
        expect(boom.placeIds, ['a', 'b']);

        final slow = await ResilientRecommender(
          _Client((_) => Completer<RecommendResponse>().future),
          timeout: const Duration(milliseconds: 20),
        ).recommend(req());
        expect(slow.source, RecommendationSource.fallback);
        expect(slow.error, 'timeout');

        final empty = await ResilientRecommender(
          _Client(
            (_) async => const RecommendResponse(
              model: ModelInfo(version: 'v1', isMock: false),
              results: [],
            ),
          ),
        ).recommend(req());
        expect(empty.source, RecommendationSource.fallback);

        var called = false;
        final bad =
            await ResilientRecommender(
              _Client((_) async {
                called = true;
                throw StateError('no');
              }),
            ).recommend(
              const RecommendRequest(
                universityId: '',
                candidatePlaceIds: ['a'],
              ),
            );
        expect(called, isFalse, reason: 'invalid requests are never sent');
        expect(bad.source, RecommendationSource.fallback);
      },
    );
  });
}

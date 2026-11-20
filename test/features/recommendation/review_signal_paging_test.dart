import 'package:flutter_test/flutter_test.dart';
import 'package:meogeobojo/features/recommendation/review_signal_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Imported reviews make `student_reviews` large, and one request returns at most 1000 rows: the ranking's review signal
/// must read every page, not just the first.
void main() {
  // [total] rows, served the way the database would: rows from .. from + 999
  ({SupabaseReviewSignalSource source, List<int> reads}) sourceOf(
    int total, {
    int unrated = 0,
  }) {
    final reads = <int>[];
    final source = SupabaseReviewSignalSource(
      () => throw StateError('no client in this test'),
      pageReader: (from) async {
        reads.add(from);
        return [
          for (var i = from; i < from + 1000 && i < total; i++)
            {
              'kakao_place_id': 'p${i % 7}',
              // every 10th of the first [unrated] rows has no stars
              'rating': (i < unrated && i % 10 == 0) ? null : 1 + i % 5,
              'created_at': '2026-06-13T00:00:00Z',
            },
        ];
      },
    );
    return (source: source, reads: reads);
  }

  test('a few hundred rows: one wave is enough', () async {
    final t = sourceOf(300);
    expect(await t.source.visibleReviews(), hasLength(300));
    expect(t.reads, [0, 1000, 2000, 3000]); // four pages at once, the rest are empty
  });

  test('thousands of rows are all read (the old single request stopped at 5000, the server at 1000)', () async {
    final t = sourceOf(7600);
    final all = await t.source.visibleReviews();
    expect(all, hasLength(7600));
    expect(t.reads, [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000]); // two waves
  });

  test('a total that is an exact multiple of the page size reads one more (empty) page', () async {
    final t = sourceOf(4000);
    expect(await t.source.visibleReviews(), hasLength(4000));
    expect(t.reads.last, 7000);
  });

  test('rows without stars are not part of the signal', () async {
    final t = sourceOf(100, unrated: 100);
    expect(await t.source.visibleReviews(), hasLength(90));
  });

  test('a failed read means "no review signal", never an exception', () async {
    final source = SupabaseReviewSignalSource(
      () => throw const PostgrestException(message: 'down'),
      pageReader: (_) async => throw const PostgrestException(message: 'down'),
    );
    expect(await source.visibleReviews(), isEmpty);
  });
}

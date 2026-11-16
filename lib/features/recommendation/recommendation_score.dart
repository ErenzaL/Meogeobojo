import 'dart:math' as math;

/// The "V3" ranking score of the recommendation model (team notes, 순천향대 experiment):
///
///     C  = 1 if the place is in a preferred food class, else 0
///     D  = max(0, 1 - straight-line distance / max allowed distance)
///     V0 = D                              (distance only)
///     V1 = 0.5 * C + 0.5 * D              (V1 = D when no food preference is chosen)
///     V3 = clip(V1 + 0.2 * R, 0, 1)       (R = review signal, 0 without reviews)
///
/// Places that pass the same conditions are ordered by V3 (highest first), then the nearer one, then the place id.
/// Nothing here is learned at run time: it is a fixed formula, so the same request always gives the same order.
const kPreferenceWeight = 0.5;
const kDistanceWeight = 0.5;
const kReviewWeight = 0.2;

/// Reviews count less as they age: a review's weight halves every 90 days.
const kReviewHalfLifeDays = 90.0;

/// A place with few reviews is pulled toward the overall average: the average gets 20 imaginary reviews.
const kReviewPriorCount = 20.0;

/// Within R: the star rating counts 0.7 and the review text 0.3. If only one of them exists, that one alone is used.
const kRatingShare = 0.7;
const kTextShare = 0.3;

/// D: 1 at the starting point, 0 at (or beyond) the largest allowed distance.
double distanceScore(double meters, double maxMeters) {
  if (maxMeters <= 0) return 0;
  return math.max(0, 1 - meters / maxMeters);
}

/// V1. [matchesPreference] is null when the user chose no food preference (then the score is just D).
double preferenceDistanceScore({
  required bool? matchesPreference,
  required double distance,
}) => matchesPreference == null
    ? distance
    : kPreferenceWeight * (matchesPreference ? 1 : 0) +
          kDistanceWeight * distance;

/// V3 from V1 and the review signal R.
double v3Score(double v1, double review) =>
    (v1 + kReviewWeight * review).clamp(0.0, 1.0);

/// One review as the signal needs it.
class ReviewSample {
  const ReviewSample({required this.rating, required this.at, this.text});

  /// Stars, 1..5.
  final int rating;
  final DateTime at;

  /// A 0..1 positivity score of the review text, when a text model has scored it. Null otherwise.
  final double? text;
}

/// w = 2^(-age in days / 90). A review from the future (clock skew) counts as brand new.
double reviewWeight(DateTime at, DateTime now) {
  final days = math.max(0, now.difference(at).inHours / 24.0);
  return math.pow(2, -days / kReviewHalfLifeDays).toDouble();
}

/// (sum(w * x) + 20 * overall) / (sum(w) + 20): the recency-weighted average pulled toward [overall].
double shrunkMean(
  Iterable<(double value, double weight)> samples,
  double overall,
) {
  var num = kReviewPriorCount * overall;
  var den = kReviewPriorCount;
  for (final (v, w) in samples) {
    num += w * v;
    den += w;
  }
  return num / den;
}

/// R for one place: how far its adjusted rating (and review-text score) are from the overall averages.
///
///     R = 0.7 * (adjusted stars - overall stars) / 4  +  0.3 * (adjusted text - overall text)
///
/// A place without reviews has R = 0. When the text model's scores are not available (no [overallText]) only the
/// stars are used.
double reviewSignal({
  required List<ReviewSample> reviews,
  required DateTime now,
  required double overallRating,
  double? overallText,
}) {
  if (reviews.isEmpty) return 0;
  final parts = <(double share, double value)>[];
  parts.add((
    kRatingShare,
    (shrunkMean([
              for (final r in reviews)
                (r.rating.toDouble(), reviewWeight(r.at, now)),
            ], overallRating) -
            overallRating) /
        4,
  ));
  final scored = [
    for (final r in reviews)
      if (r.text != null) r,
  ];
  if (overallText != null && scored.isNotEmpty) {
    parts.add((
      kTextShare,
      shrunkMean([
            for (final r in scored) (r.text!, reviewWeight(r.at, now)),
          ], overallText) -
          overallText,
    ));
  }
  final share = parts.fold<double>(0, (s, p) => s + p.$1);
  return parts.fold<double>(0, (s, p) => s + p.$1 * p.$2) / share;
}

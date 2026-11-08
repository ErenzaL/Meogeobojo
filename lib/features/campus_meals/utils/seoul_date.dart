/// Date helpers for the weekly meal schedule. All dates are plain calendar
/// dates in Asia/Seoul, represented as UTC midnights so arithmetic across
/// month/year boundaries never meets a daylight-saving shift.
///
/// South Korea has no DST, so Seoul is always UTC+9.
DateTime seoulDate(DateTime instant) {
  final k = instant.toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day);
}

/// Hour of day (0-23) in Seoul.
int seoulHour(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 9)).hour;

/// Monday of the week containing [date] (weeks run Monday-Sunday).
DateTime weekStartOf(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

/// The seven dates Monday-Sunday starting at [weekStart].
List<DateTime> weekDays(DateTime weekStart) => [
  for (var i = 0; i < 7; i++)
    DateTime.utc(weekStart.year, weekStart.month, weekStart.day + i),
];

DateTime addWeeks(DateTime weekStart, int weeks) =>
    DateTime.utc(weekStart.year, weekStart.month, weekStart.day + 7 * weeks);

/// `yyyy-MM-dd`, as stored in `cafeteria_meals.meal_date`.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseIsoDate(String s) {
  final p = s.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

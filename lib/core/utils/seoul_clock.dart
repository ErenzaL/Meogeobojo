/// Wall-clock helpers for Asia/Seoul (UTC+9, no DST). The app is for Korean
/// campuses, so "now", arrival times and last-order times are always read on
/// the Seoul clock regardless of the phone's time zone.
///
/// A "wall" value is a UTC-flagged [DateTime] whose fields are the Seoul
/// calendar fields, so arithmetic never meets a time-zone shift.
DateTime seoulWall(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 9));

int minutesOfDay(DateTime wall) => wall.hour * 60 + wall.minute;

/// "19:01" for minute-of-day [m] (wraps past midnight).
String formatMinutesOfDay(int m) {
  final v = ((m % 1440) + 1440) % 1440;
  return '${(v ~/ 60).toString().padLeft(2, '0')}:'
      '${(v % 60).toString().padLeft(2, '0')}';
}

String formatHm(DateTime wall) => formatMinutesOfDay(minutesOfDay(wall));

/// Part of the day shown in the Home subtitle: 05-10 breakfast, 10-15 lunch,
/// 15-21 dinner, otherwise late night.
enum DayPart {
  breakfast,
  lunch,
  dinner,
  lateNight;

  static DayPart at(DateTime wall) {
    final h = wall.hour;
    if (h >= 5 && h < 10) return breakfast;
    if (h >= 10 && h < 15) return lunch;
    if (h >= 15 && h < 21) return dinner;
    return lateNight;
  }
}

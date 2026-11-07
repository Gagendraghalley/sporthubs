/// Bhutan Time (UTC+6, no daylight saving). Memberships start and end on
/// Bhutan dates, whatever the phone's time zone; the database uses the same
/// dates (Asia/Thimphu).
abstract final class BhutanTime {
  static const offset = Duration(hours: 6);

  /// Now, as a wall-clock time in Bhutan (its fields read as Bhutan time).
  static DateTime now() => toBhutan(DateTime.now());

  /// [moment] as Bhutan wall-clock time.
  static DateTime toBhutan(DateTime moment) {
    final utc = moment.toUtc().add(offset);
    return DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second);
  }

  /// Today's date in Bhutan (midnight, no time).
  static DateTime today() => dateOnly(now());

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// A date column ('2026-11-07') as a date.
  static DateTime parseDate(String value) {
    final d = DateTime.parse(value);
    return DateTime(d.year, d.month, d.day);
  }

  /// A date as the database stores it ('2026-11-07').
  static String formatIsoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Whole days from [from] to [to] (dates only; negative when [to] is earlier).
  static int daysBetween(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}

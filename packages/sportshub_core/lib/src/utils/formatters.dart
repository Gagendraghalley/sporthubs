import 'package:intl/intl.dart';

import 'bhutan_time.dart';

final _money = NumberFormat('#,##0', 'en_US');
final _date = DateFormat('d MMM yyyy', 'en_US');
final _shortDate = DateFormat('d MMM', 'en_US');
final _time = DateFormat('h:mm a', 'en_US');
final _month = DateFormat('MMMM yyyy', 'en_US');

/// Ngultrum: 'Nu. 1,500'.
String formatNu(num amount) => 'Nu. ${_money.format(amount)}';

/// '7 Nov 2026'.
String formatDate(DateTime date) => _date.format(date);

/// '7 Nov'.
String formatShortDate(DateTime date) => _shortDate.format(date);

/// 'November 2026'.
String formatMonth(DateTime date) => _month.format(date);

/// A moment in Bhutan time: 'Today, 6:30 PM', 'Yesterday, 7:05 AM' or
/// '3 Nov, 6:30 PM'.
String formatMoment(DateTime moment) {
  final local = BhutanTime.toBhutan(moment);
  final days = BhutanTime.daysBetween(local, BhutanTime.today());
  final time = _time.format(local);
  if (days == 0) return 'Today, $time';
  if (days == 1) return 'Yesterday, $time';
  return '${days < 300 ? _shortDate.format(local) : _date.format(local)}, $time';
}

/// Just the time of [moment], in Bhutan: '6:30 PM'.
String formatTime(DateTime moment) => _time.format(BhutanTime.toBhutan(moment));

/// '1 day', '30 days', '1 month', '3 months', '1 year'.
String formatDuration(int days) {
  if (days % 365 == 0) return days == 365 ? '1 year' : '${days ~/ 365} years';
  if (days % 30 == 0) return days == 30 ? '1 month' : '${days ~/ 30} months';
  if (days % 7 == 0) return days == 7 ? '1 week' : '${days ~/ 7} weeks';
  return days == 1 ? '1 day' : '$days days';
}

/// 'just now', '5 min ago', '3 h ago', 'yesterday', '4 days ago', then the
/// date: when [moment] was, from [now].
String timeAgo(DateTime moment, {DateTime? now}) {
  final gap = (now ?? DateTime.now()).toUtc().difference(moment.toUtc());
  if (gap.inMinutes < 1) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
  if (gap.inHours < 24) return '${gap.inHours} h ago';
  if (gap.inDays == 1) return 'yesterday';
  if (gap.inDays < 7) return '${gap.inDays} days ago';
  return formatShortDate(BhutanTime.toBhutan(moment));
}

/// 'Good morning', 'Good afternoon' or 'Good evening', at [bhutanNow].
String greeting(DateTime bhutanNow) => bhutanNow.hour < 12
    ? 'Good morning'
    : bhutanNow.hour < 17
        ? 'Good afternoon'
        : 'Good evening';

/// 'Pema' from 'Pema Wangmo'; [fallback] when empty.
String firstName(String fullName, {String fallback = 'there'}) {
  final first = fullName.trim().split(RegExp(r'\s+')).first;
  return first.isEmpty ? fallback : first;
}

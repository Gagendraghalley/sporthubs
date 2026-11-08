import 'package:sportshub_core/sportshub_core.dart';

import 'gym_models.dart';
import 'registered_member.dart';

// A gym's reports, worked out from its own records: check-ins, memberships,
// the register and payments. Dates and hours are Bhutan's.

const weekdayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The periods a report covers.
enum ReportRange {
  month('30D', 30),
  quarter('90D', 90),
  year('12M', 365);

  const ReportRange(this.label, this.days);
  final String label;
  final int days;

  /// The first day it covers, [today] being the last.
  DateTime from(DateTime today) => DateTime(today.year, today.month, today.day - (days - 1));

  String get description => switch (this) {
        ReportRange.month => 'the last 30 days',
        ReportRange.quarter => 'the last 90 days',
        ReportRange.year => 'the last 12 months',
      };
}

/// Check-ins on each day of the week, Monday first.
List<({String label, num value})> checkInsByWeekday(Iterable<GymCheckIn> checkIns) {
  final counts = List.filled(7, 0);
  for (final c in checkIns) {
    counts[BhutanTime.toBhutan(c.checkedInAt).weekday - 1]++;
  }
  return [for (var i = 0; i < 7; i++) (label: _weekdayShort[i], value: counts[i])];
}

/// Check-ins in each hour, from the earliest hour anyone came (6 am at the
/// latest) to the last (9 pm at the earliest): '6a', '12p', '7p'.
List<({String label, num value})> checkInsByHour(Iterable<GymCheckIn> checkIns) {
  final counts = List.filled(24, 0);
  for (final c in checkIns) {
    counts[BhutanTime.toBhutan(c.checkedInAt).hour]++;
  }
  var first = 6;
  var last = 21;
  for (var h = 0; h < 24; h++) {
    if (counts[h] > 0) {
      if (h < first) first = h;
      if (h > last) last = h;
    }
  }
  String label(int h) => '${h == 0 || h == 12 ? 12 : h % 12}${h < 12 ? 'a' : 'p'}';
  return [for (var h = first; h <= last; h++) (label: label(h), value: counts[h])];
}

/// '6–7 pm': the hour of [hourLabel] ('6p') as a span.
String hourSpan(String hourLabel) {
  final pm = hourLabel.endsWith('p');
  final hour = int.parse(hourLabel.substring(0, hourLabel.length - 1)) % 12 + (pm ? 12 : 0);
  final next = (hour + 1) % 24;
  String clock(int h) => '${h % 12 == 0 ? 12 : h % 12}';
  String half(int h) => h < 12 ? 'am' : 'pm';
  return half(hour) == half(next)
      ? '${clock(hour)}–${clock(next)} ${half(next)}'
      : '${clock(hour)} ${half(hour)}–${clock(next)} ${half(next)}';
}

/// Members who joined in each week (30 and 90 days) or month (12 months) of
/// [range], oldest first.
List<({String label, num value})> joinedOverTime(Iterable<GymMember> members, ReportRange range, DateTime today) {
  if (range == ReportRange.year) {
    final months = [for (var i = 11; i >= 0; i--) DateTime(today.year, today.month - i)];
    return [
      for (final m in months)
        (
          label: _monthShort[m.month - 1],
          value: members.where((x) => x.joinedOn.year == m.year && x.joinedOn.month == m.month).length,
        ),
    ];
  }
  final from = range.from(today);
  final weeks = (range.days / 7).ceil();
  return [
    for (var w = 0; w < weeks; w++)
      () {
        final start = DateTime(from.year, from.month, from.day + w * 7);
        final end = DateTime(start.year, start.month, start.day + 6);
        return (
          label: formatShortDate(start),
          value: members.where((x) => !x.joinedOn.isBefore(start) && !x.joinedOn.isAfter(end)).length,
        );
      }(),
  ];
}

/// Of the members whose package ended in [from]..[today], how many have
/// another one after it: renewed, out of those it could be.
({int renewed, int ended}) renewals(Iterable<GymSubscription> subs, DateTime from, DateTime today) {
  final paid = subs.where((s) => s.endDate != null && (s.status == SubscriptionStatus.active || s.status == SubscriptionStatus.expired));
  final byMember = <String, List<GymSubscription>>{};
  for (final s in paid) {
    byMember.putIfAbsent(s.memberId, () => []).add(s);
  }
  var ended = 0;
  var renewed = 0;
  for (final list in byMember.values) {
    final endedHere = list.where((s) => !s.endDate!.isBefore(from) && !s.endDate!.isAfter(today)).toList();
    if (endedHere.isEmpty) continue;
    ended++;
    final first = endedHere.map((s) => s.endDate!).reduce((a, b) => a.isBefore(b) ? a : b);
    if (list.any((s) => !s.startDate!.isBefore(first) && s.endDate!.isAfter(first))) renewed++;
  }
  return (renewed: renewed, ended: ended);
}

/// Members on each package today, the most first.
List<({String name, int members})> packageMix(Iterable<GymSubscription> subs, DateTime today) {
  final byPlan = <String, Set<String>>{};
  for (final s in subs.where((s) => s.isCurrentOn(today))) {
    byPlan.putIfAbsent(s.planName, () => {}).add(s.memberId);
  }
  return [for (final e in byPlan.entries) (name: e.key, members: e.value.length)]..sort((a, b) => b.members - a.members);
}

/// Who came most often, with how many visits: the [top] of them.
List<({String name, String? gymMemberId, int visits})> regulars(Iterable<GymCheckIn> checkIns, {int top = 5}) {
  final visits = <String, int>{};
  final names = <String, String>{};
  final registered = <String, String?>{};
  for (final c in checkIns) {
    visits[c.memberId] = (visits[c.memberId] ?? 0) + 1;
    names[c.memberId] = c.memberName ?? 'Member';
    registered[c.memberId] = c.gymMemberId;
  }
  final order = visits.keys.toList()..sort((a, b) => visits[b]! - visits[a]!);
  return [for (final id in order.take(top)) (name: names[id]!, gymMemberId: registered[id], visits: visits[id]!)];
}

/// What the figures say, in a sentence or two: the busiest day and hour, and
/// how renewals are going. Empty with nothing to go on.
List<String> insights({
  required List<({String label, num value})> byWeekday,
  required List<({String label, num value})> byHour,
  required ({int renewed, int ended}) renewal,
  required int endingSoon,
}) {
  final out = <String>[];
  num most(List<({String label, num value})> l) => l.fold<num>(0, (m, p) => p.value > m ? p.value : m);
  if (most(byWeekday) > 0 && most(byHour) > 0) {
    final day = byWeekday.indexWhere((p) => p.value == most(byWeekday));
    final hour = byHour.firstWhere((p) => p.value == most(byHour)).label;
    out.add('${weekdayNames[day]}s are the busiest, and ${hourSpan(hour)} the busiest hour: '
        'have the desk and trainers ready then.');
  }
  if (renewal.ended > 0) {
    final rate = (100 * renewal.renewed / renewal.ended).round();
    out.add(rate >= 70
        ? '$rate% of members whose package ended renewed it. Keep it up.'
        : 'Only $rate% of members whose package ended renewed it: a WhatsApp reminder before it ends helps.');
  }
  if (endingSoon > 0) {
    out.add(endingSoon == 1
        ? '1 package ends this week: the Members page lists who.'
        : '$endingSoon packages end this week: the Members page lists who.');
  }
  return out;
}

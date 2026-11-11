import 'package:sportshub_core/sportshub_core.dart';

import 'gym_models.dart';

/// Where a gym's members stand today, one count per member.
class MemberStanding {
  /// A paid membership covering today, or starting later.
  final int active;

  /// Had one; none now.
  final int expired;

  /// Only a request, waiting for the gym to confirm the payment.
  final int waiting;

  const MemberStanding({required this.active, required this.expired, required this.waiting});

  /// Everyone who has had a membership here.
  int get members => active + expired;
}

Map<String, List<GymSubscription>> _byMember(Iterable<GymSubscription> subs) {
  final byMember = <String, List<GymSubscription>>{};
  for (final s in subs) {
    byMember.putIfAbsent(s.memberId, () => []).add(s);
  }
  return byMember;
}

MemberStanding memberStanding(Iterable<GymSubscription> subs, DateTime today) {
  var active = 0;
  var expired = 0;
  var waiting = 0;
  for (final list in _byMember(subs).values) {
    if (list.any((s) => s.isCurrentOn(today) || s.isUpcomingOn(today))) {
      active++;
    } else if (list.any((s) =>
        s.status == SubscriptionStatus.expired ||
        // Past its end, before the daily job has marked it expired.
        (s.status == SubscriptionStatus.active && s.endDate != null && s.endDate!.isBefore(today)))) {
      expired++;
    } else if (list.any((s) => s.isPending)) {
      waiting++;
    }
  }
  return MemberStanding(active: active, expired: expired, waiting: waiting);
}

/// The memberships ending within [days] days ([today] counted), with no
/// renewal paid after them; soonest first.
List<GymSubscription> endingWithin(Iterable<GymSubscription> subs, DateTime today, int days) {
  final ending = <GymSubscription>[];
  for (final list in _byMember(subs).values) {
    if (list.any((s) => s.isUpcomingOn(today))) continue;
    final current = list.where((s) => s.isCurrentOn(today)).toList()..sort((a, b) => b.endDate!.compareTo(a.endDate!));
    if (current.isNotEmpty && current.first.daysLeftOn(today) <= days) ending.add(current.first);
  }
  return ending..sort((a, b) => a.endDate!.compareTo(b.endDate!));
}

/// The periods the revenue chart shows.
enum RevenueRange {
  week('7D', 'last 7 days'),
  month('30D', 'last 30 days'),
  quarter('90D', 'last 90 days'),
  year('1Y', 'last 12 months');

  const RevenueRange(this.label, this.description);
  final String label;
  final String description;
}

/// One point of a chart over [start] to [end] (Bhutan dates, both
/// included): what came in (revenue), or a member's visits (visitSeries).
class RevenuePoint {
  final String label;
  final DateTime start;
  final DateTime end;
  final int amount;

  const RevenuePoint({required this.label, required this.start, required this.end, required this.amount});
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The first day the chart can need: the 1st of the month 11 months back.
DateTime revenueFrom(DateTime today) => DateTime(today.year, today.month - 11, 1);

/// Completed payments in [range] up to [today], added up by day (7 and 30
/// days), week (90 days) or month (12 months).
List<RevenuePoint> revenueSeries(Iterable<Payment> payments, DateTime today, RevenueRange range) => _series(
      [for (final p in payments.where((p) => p.isCompleted)) (p.createdAt, p.amount)],
      today,
      range,
    );

/// Completed payments from the 1st to [today], against the same days of
/// last month (to the same date, or that month's last day): the change as a
/// share (0.12 is 12% more). Null when last month had nothing in those days,
/// so there's nothing fair to compare with.
double? incomeChangeMonthToDate(Iterable<Payment> payments, DateTime today) {
  final thisStart = DateTime(today.year, today.month, 1);
  final lastStart = DateTime(today.year, today.month - 1, 1);
  final lastLength = DateTime(today.year, today.month, 0).day;
  final lastEnd = DateTime(lastStart.year, lastStart.month, today.day < lastLength ? today.day : lastLength);
  var now = 0;
  var before = 0;
  for (final p in payments.where((p) => p.isCompleted)) {
    final day = _bhutanDay(p.createdAt);
    if (!day.isBefore(thisStart) && !day.isAfter(today)) {
      now += p.amount;
    } else if (!day.isBefore(lastStart) && !day.isAfter(lastEnd)) {
      before += p.amount;
    }
  }
  if (before == 0) return null;
  return (now - before) / before;
}

/// A member's check-ins in [range] up to [today], counted by day (7 and 30
/// days) or week (90 days).
List<RevenuePoint> visitSeries(Iterable<GymCheckIn> checkIns, DateTime today, RevenueRange range) =>
    _series([for (final c in checkIns) (c.checkedInAt, 1)], today, range);

/// [events] (a moment and an amount) added up into [range]'s points.
List<RevenuePoint> _series(List<(DateTime, int)> events, DateTime today, RevenueRange range) {
  final List<(DateTime, DateTime, String)> buckets;
  switch (range) {
    case RevenueRange.week:
    case RevenueRange.month:
      final days = range == RevenueRange.week ? 7 : 30;
      buckets = [
        for (var i = days - 1; i >= 0; i--)
          () {
            final d = DateTime(today.year, today.month, today.day - i);
            return (d, d, range == RevenueRange.week ? _weekdays[d.weekday - 1] : formatShortDate(d));
          }(),
      ];
    case RevenueRange.quarter:
      // 13 weeks; the first is a day short, so the last ends today.
      buckets = [
        for (var i = 12; i >= 0; i--)
          () {
            final end = DateTime(today.year, today.month, today.day - 7 * i);
            final start = i == 12
                ? DateTime(today.year, today.month, today.day - 89)
                : DateTime(end.year, end.month, end.day - 6);
            return (start, end, formatShortDate(start));
          }(),
      ];
    case RevenueRange.year:
      buckets = [
        for (var i = 11; i >= 0; i--)
          () {
            final start = DateTime(today.year, today.month - i, 1);
            final end = DateTime(start.year, start.month + 1, 0);
            return (start, end, _months[start.month - 1]);
          }(),
      ];
  }
  final amounts = List.filled(buckets.length, 0);
  for (final (at, amount) in events) {
    final day = _bhutanDay(at);
    for (var i = 0; i < buckets.length; i++) {
      if (!day.isBefore(buckets[i].$1) && !day.isAfter(buckets[i].$2)) {
        amounts[i] += amount;
        break;
      }
    }
  }
  return [
    for (var i = 0; i < buckets.length; i++)
      RevenuePoint(label: buckets[i].$3, start: buckets[i].$1, end: buckets[i].$2, amount: amounts[i]),
  ];
}

enum GymActivityKind { checkIn, request, joined, renewed }

/// Something that happened at the gym, for Recent activity.
class GymActivity {
  final DateTime at;
  final GymActivityKind kind;
  final String text;

  const GymActivity({required this.at, required this.kind, required this.text});
}

/// The latest check-ins, requests and memberships started, newest first.
/// With [payments] (owners and managers), a start says what was paid.
List<GymActivity> recentActivity({
  required Iterable<GymSubscription> subs,
  required Iterable<GymCheckIn> checkIns,
  Iterable<Payment>? payments,
  int limit = 8,
}) {
  final paidFor = {
    for (final p in payments ?? const <Payment>[])
      if (p.referenceId != null) p.referenceId!: p
  };
  final firstStart = <String, DateTime>{};
  for (final s in subs) {
    final at = s.activatedAt;
    if (at != null && (firstStart[s.memberId] == null || at.isBefore(firstStart[s.memberId]!))) {
      firstStart[s.memberId] = at;
    }
  }
  final events = <GymActivity>[
    for (final c in checkIns)
      GymActivity(
        at: c.checkedInAt,
        kind: GymActivityKind.checkIn,
        text: '${(c.memberName ?? '').trim().isEmpty ? 'A member' : c.memberName!.trim()} checked in',
      ),
    for (final s in subs) ...[
      GymActivity(
          at: s.requestedAt, kind: GymActivityKind.request, text: '${s.memberDisplayName} asked to join ${s.planName}'),
      if (s.activatedAt != null)
        () {
          final renewed = firstStart[s.memberId] != null && firstStart[s.memberId]!.isBefore(s.activatedAt!);
          final paid = paidFor[s.id];
          final what = renewed ? 'renewed ${s.planName}' : 'started ${s.planName}';
          return GymActivity(
            at: s.activatedAt!,
            kind: renewed ? GymActivityKind.renewed : GymActivityKind.joined,
            text:
                '${s.memberDisplayName} $what${paid == null ? '' : ' · ${formatNu(paid.amount)} by ${paid.method.label}'}',
          );
        }(),
    ],
  ]..sort((a, b) => b.at.compareTo(a.at));
  return events.take(limit).toList();
}

// ─── A member's own: the signed-in home ────────────────────────────────────

DateTime _bhutanDay(DateTime at) => BhutanTime.dateOnly(BhutanTime.toBhutan(at));

/// Visits in each of the last [weeks] 7-day stretches, oldest first; the
/// last is the 7 days to [today].
List<int> weeklyVisits(Iterable<GymCheckIn> checkIns, DateTime today, {int weeks = 8}) {
  final counts = List.filled(weeks, 0);
  for (final c in checkIns) {
    final back = today.difference(_bhutanDay(c.checkedInAt)).inDays;
    if (back < 0) continue;
    final week = back ~/ 7;
    if (week < weeks) counts[weeks - 1 - week]++;
  }
  return counts;
}

/// Whether the member checked in on each of the last [days] days, oldest
/// first; the last is [today].
List<bool> visitedDays(Iterable<GymCheckIn> checkIns, DateTime today, {int days = 7}) {
  final visited = {for (final c in checkIns) _bhutanDay(c.checkedInAt)};
  return [for (var i = days - 1; i >= 0; i--) visited.contains(DateTime(today.year, today.month, today.day - i))];
}

/// Days in a row with a check-in, to today; or to yesterday, while today
/// can still keep it going.
int visitStreak(Iterable<GymCheckIn> checkIns, DateTime today) {
  final visited = {for (final c in checkIns) _bhutanDay(c.checkedInAt)};
  var day = visited.contains(today) ? today : DateTime(today.year, today.month, today.day - 1);
  var streak = 0;
  while (visited.contains(day)) {
    streak++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return streak;
}

/// What the member did lately, newest first: check-ins, requests, and
/// memberships started or renewed.
List<GymActivity> myActivity({
  required Iterable<GymSubscription> subs,
  required Iterable<GymCheckIn> checkIns,
  int limit = 5,
}) {
  final firstStart = <String, DateTime>{};
  for (final s in subs) {
    final at = s.activatedAt;
    if (at != null && (firstStart[s.venueId] == null || at.isBefore(firstStart[s.venueId]!))) {
      firstStart[s.venueId] = at;
    }
  }
  final events = <GymActivity>[
    for (final c in checkIns)
      GymActivity(at: c.checkedInAt, kind: GymActivityKind.checkIn, text: 'Checked in at ${c.gymName ?? 'the gym'}'),
    for (final s in subs) ...[
      GymActivity(
        at: s.requestedAt,
        kind: GymActivityKind.request,
        text: 'Asked to join ${s.planName} at ${s.gymName ?? 'a gym'}',
      ),
      if (s.activatedAt != null)
        () {
          final renewed = firstStart[s.venueId]!.isBefore(s.activatedAt!);
          return GymActivity(
            at: s.activatedAt!,
            kind: renewed ? GymActivityKind.renewed : GymActivityKind.joined,
            text: '${renewed ? 'Renewed' : 'Started'} ${s.planName} at ${s.gymName ?? 'your gym'}',
          );
        }(),
    ],
  ]..sort((a, b) => b.at.compareTo(a.at));
  return events.take(limit).toList();
}

/// Good morning / afternoon / evening, by the hour in Bhutan.
String greetingAt(DateTime bhutanNow) {
  if (bhutanNow.hour < 12) return 'Good morning';
  if (bhutanNow.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

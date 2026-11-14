import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportshub_core/sportshub_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../gym_permissions.dart';
import '../gym_routes.dart';
import 'dashboard_data.dart';
import 'gym_models.dart';
import 'registered_member.dart';

// Ask AI. The ask-ai Edge Function (supabase/functions/ask-ai) has Cloudflare
// Workers AI turn a question into an [AskReply]: which of these reports
// answers it, or a short how-to. The app then works the report out from the
// gym's own records, so the numbers are always the app's own and members'
// details never leave SportsHub. The keys are the ones in reply.ts.

/// What a question about the gym is answered with.
enum AskReport {
  visitsOverTime('visits_over_time', 'Check-ins'),
  busiestDays('busiest_days', 'Busiest days'),
  busiestHours('busiest_hours', 'Busiest hours'),
  newMembers('new_members', 'New members'),
  revenue('revenue', 'Revenue'),
  revenueByMethod('revenue_by_method', 'Revenue by payment method'),
  packageMix('package_mix', 'Package mix today'),
  renewalRate('renewal_rate', 'Renewal rate'),
  memberCounts('member_counts', 'Where members stand'),
  endingSoon('ending_soon', 'Packages ending soon'),
  inactiveMembers('inactive_members', "Members who haven't come"),
  topMembers('top_members', 'Most regular'),
  findMember('find_member', 'Find a member');

  const AskReport(this.key, this.title);
  final String key;
  final String title;

  /// Money: only for those who see income.
  bool get needsIncome => this == AskReport.revenue || this == AskReport.revenueByMethod;

  /// Over the last week, 30 days, 90 days or 12 months; the rest are about
  /// today (or a number of days).
  bool get overPeriod => switch (this) {
        AskReport.packageMix ||
        AskReport.memberCounts ||
        AskReport.endingSoon ||
        AskReport.inactiveMembers ||
        AskReport.findMember =>
          false,
        _ => true,
      };

  /// How many days, when the question doesn't say: packages ending within a
  /// week, members not seen for two.
  int? get defaultDays => switch (this) {
        AskReport.endingSoon => 7,
        AskReport.inactiveMembers => 14,
        _ => null,
      };

  /// Whether [access] (a role at the gym) may see it: the members' records,
  /// and income for money.
  bool allowedFor(VenueAccess access) =>
      access.can(GymPermission.members) && (!needsIncome || access.can(VenuePermission.income));

  static AskReport? fromKey(Object? key) {
    for (final r in values) {
      if (r.key == key) return r;
    }
    return null;
  }
}

/// The stretch a report covers, [today] being its last day.
enum AskPeriod {
  week('week', RevenueRange.week, 'last 7 days'),
  month('month', RevenueRange.month, 'last 30 days'),
  quarter('quarter', RevenueRange.quarter, 'last 90 days'),
  year('year', RevenueRange.year, 'last 12 months');

  const AskPeriod(this.key, this.range, this.label);
  final String key;

  /// How its charts count: by day (7 and 30 days), week or month.
  final RevenueRange range;

  /// 'last 30 days'.
  final String label;

  /// 'the last 30 days'.
  String get description => 'the $label';

  /// Its first day. A year's is the 1st of the month 11 months back, as its
  /// charts count whole months.
  DateTime from(DateTime today) => switch (this) {
        AskPeriod.week => DateTime(today.year, today.month, today.day - 6),
        AskPeriod.month => DateTime(today.year, today.month, today.day - 29),
        AskPeriod.quarter => DateTime(today.year, today.month, today.day - 89),
        AskPeriod.year => revenueFrom(today),
      };

  static AskPeriod fromKey(Object? key) => values.firstWhere((p) => p.key == key, orElse: () => AskPeriod.month);
}

/// The gym's pages a how-to answer can open, with the permission each needs.
enum AskPage {
  checkIn('check_in', 'Check-in', GymPermission.checkIn),
  registerMember('register_member', 'Register member', GymPermission.register),
  members('members', 'Members', GymPermission.members),
  packages('packages', 'Memberships & packages', GymPermission.plans),
  income('income', 'Payments & income', VenuePermission.income),
  reports('reports', 'Reports & analytics', GymPermission.members),
  staff('staff', 'Staff', VenuePermission.staff),
  roles('roles', 'Roles & permissions', VenuePermission.roles),
  settings('settings', 'Gym settings', VenuePermission.edit);

  const AskPage(this.key, this.label, this.permission);
  final String key;
  final String label;
  final String permission;

  String route(String venueId) => switch (this) {
        AskPage.checkIn => GymRoutes.checkInFor(venueId),
        AskPage.registerMember => GymRoutes.registerMemberFor(venueId),
        AskPage.members => GymRoutes.membersFor(venueId),
        AskPage.packages => GymRoutes.plansFor(venueId),
        AskPage.income => GymRoutes.incomeFor(venueId),
        AskPage.reports => GymRoutes.reportsFor(venueId),
        AskPage.staff => CoreRoutes.venueStaffFor(venueId),
        AskPage.roles => CoreRoutes.venueRolesFor(venueId),
        AskPage.settings => CoreRoutes.editVenueFor(venueId),
      };

  static AskPage? fromKey(Object? key) {
    for (final p in values) {
      if (p.key == key) return p;
    }
    return null;
  }
}

enum AskKind { report, help, other }

/// What Ask AI says when a question isn't one it can answer.
const askWhatICanDo =
    'I answer questions about your gym (members, visits, packages and payments) and how to use SportsHub. '
    'Try one of the suggestions.';

/// What answers a question: one of the app's reports, a how-to (with the
/// page that does it), or what Ask AI can do.
class AskReply {
  final AskKind kind;
  final AskReport? report;
  final AskPeriod period;

  /// Days ahead (packages ending soon) or without a visit (members who
  /// haven't come).
  final int? days;

  /// Whom 'find a member' looks for: a name, phone number or member code.
  final String? name;
  final AskPage? page;

  /// A how-to, written by the AI from SportsHub's guide; or what it can do.
  final String? answer;

  const AskReply.report(AskReport this.report, {this.period = AskPeriod.month, this.days, this.name})
      : kind = AskKind.report,
        page = null,
        answer = null;

  const AskReply._(this.kind, {this.report, this.period = AskPeriod.month, this.days, this.name, this.page, this.answer});

  /// The ask-ai function's answer. It checks it already; anything the app
  /// can't act on still becomes [AskKind.other].
  factory AskReply.fromJson(Map<String, dynamic> json) {
    final report = AskReport.fromKey(json['report']);
    final page = AskPage.fromKey(json['page']);
    final answer = (json['answer'] as String?)?.trim();
    final hasAnswer = answer != null && answer.isNotEmpty;
    final name = (json['name'] as String?)?.trim();
    if (json['kind'] == 'report' && report != null && (report != AskReport.findMember || (name ?? '').isNotEmpty)) {
      return AskReply._(
        AskKind.report,
        report: report,
        period: AskPeriod.fromKey(json['period']),
        days: report.defaultDays == null ? null : (json['days'] as num?)?.toInt() ?? report.defaultDays,
        name: report == AskReport.findMember ? name : null,
      );
    }
    if (json['kind'] == 'help' && (page != null || hasAnswer)) {
      return AskReply._(AskKind.help, page: page, answer: hasAnswer ? answer : null);
    }
    return AskReply._(AskKind.other, answer: json['kind'] == 'other' && hasAnswer ? answer : askWhatICanDo);
  }

  /// As the ask-ai function takes it back, in the conversation so far.
  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (report != null) ...{'report': report!.key, 'period': period.key},
        if (days != null) 'days': days,
        if (name != null) 'name': name,
        if (page != null) 'page': page!.key,
      };
}

/// Questions answered straight away, without the AI, so they don't count
/// against the day's questions.
const askSuggestions = <({String label, AskReply reply})>[
  (label: 'Busiest hours this month', reply: AskReply.report(AskReport.busiestHours)),
  (label: 'Check-ins this week', reply: AskReply.report(AskReport.visitsOverTime, period: AskPeriod.week)),
  (label: "Who hasn't come in 2 weeks?", reply: AskReply.report(AskReport.inactiveMembers, days: 14)),
  (label: 'Packages ending this week', reply: AskReply.report(AskReport.endingSoon, days: 7)),
  (label: 'Revenue, last 12 months', reply: AskReply.report(AskReport.revenue, period: AskPeriod.year)),
  (label: 'New members, last 12 months', reply: AskReply.report(AskReport.newMembers, period: AskPeriod.year)),
  (label: 'Renewal rate, last 90 days', reply: AskReply.report(AskReport.renewalRate, period: AskPeriod.quarter)),
  (label: 'Package mix today', reply: AskReply.report(AskReport.packageMix)),
];

final askRepositoryProvider = Provider<AskRepository>((ref) => AskRepository(ref.watch(supabaseProvider)));

class AskRepository {
  AskRepository(this._client);
  final SupabaseClient _client;

  /// Asks which report answers [question] at gym [venueId]. The last turns
  /// of [history] go along, so "and last year?" follows on. With it, how
  /// many questions they have left today. What the function says went
  /// wrong is an [AssistantProblem].
  Future<({AskReply reply, int? left})> ask(
    String venueId,
    String question,
    List<({String question, AskReply reply})> history,
  ) async {
    final recent = history.length > 3 ? history.sublist(history.length - 3) : history;
    final data = await invokeAssistant(_client, 'ask-ai', {
      'venue_id': venueId,
      'question': question,
      'history': [for (final t in recent) {'question': t.question, 'reply': t.reply.toJson()}],
    });
    return (reply: AskReply.fromJson(data), left: (data['left'] as num?)?.toInt());
  }
}

/// A gym's Ask AI conversation: the same in the floating panel and on the
/// full page, kept while the app runs; a new one for whoever signs in next.
final askChatProvider =
    NotifierProvider.family<AskChatNotifier, AssistantChat<AskReply>, String>(AskChatNotifier.new);

class AskChatNotifier extends FamilyNotifier<AssistantChat<AskReply>, String> with AssistantConversation<AskReply> {
  @override
  AssistantChat<AskReply> build(String venueId) {
    ref.watch(currentUserIdProvider);
    return const AssistantChat();
  }

  @override
  Future<({AskReply reply, int? left})> answer(String question, List<({String question, AskReply reply})> before) =>
      ref.read(askRepositoryProvider).ask(arg, question, [
        for (final t in before)
          if (t.reply.kind != AskKind.other) t,
      ]);
}

// ─── Working the answers out ───────────────────────────────────────────────

DateTime _bhutanDay(DateTime at) => BhutanTime.dateOnly(BhutanTime.toBhutan(at));

/// Members whose package covers [today] but who haven't checked in for
/// [days] days ([today] counted; [checkIns] must go back that far), by name:
/// each one's current membership. Those who first joined within those days
/// aren't counted; they haven't had the time.
List<GymSubscription> notComingMembers(
  Iterable<GymSubscription> subs,
  Iterable<GymCheckIn> checkIns,
  DateTime today,
  int days,
) {
  final from = DateTime(today.year, today.month, today.day - (days - 1));
  final came = {
    for (final c in checkIns)
      if (!_bhutanDay(c.checkedInAt).isBefore(from)) c.memberId,
  };
  final byMember = <String, List<GymSubscription>>{};
  for (final s in subs) {
    if (s.startDate != null && (s.status == SubscriptionStatus.active || s.status == SubscriptionStatus.expired)) {
      byMember.putIfAbsent(s.memberId, () => []).add(s);
    }
  }
  final out = <GymSubscription>[];
  for (final MapEntry(key: member, value: list) in byMember.entries) {
    if (came.contains(member)) continue;
    final current = list.where((s) => s.isCurrentOn(today)).toList();
    if (current.isEmpty) continue;
    final firstStart = list.map((s) => s.startDate!).reduce((a, b) => a.isBefore(b) ? a : b);
    if (firstStart.isAfter(from)) continue;
    current.sort((a, b) => b.endDate!.compareTo(a.endDate!));
    out.add(current.first);
  }
  return out..sort((a, b) => a.memberDisplayName.toLowerCase().compareTo(b.memberDisplayName.toLowerCase()));
}

/// Completed payments added up by how they were paid, the most first.
List<({String label, int amount})> revenueByMethod(Iterable<Payment> payments) {
  final totals = <PaymentMethod, int>{};
  for (final p in payments.where((p) => p.isCompleted)) {
    totals[p.method] = (totals[p.method] ?? 0) + p.amount;
  }
  return [for (final e in totals.entries) (label: e.key.label, amount: e.value)]..sort((a, b) => b.amount - a.amount);
}

/// The registered members [query] is about: their member code; every word
/// of it in their name; or (4 digits or more) part of their phone number.
/// The code first, then the whole name, names that start with it, the rest.
List<GymMember> findMembers(Iterable<GymMember> members, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final words = q.split(RegExp(r'\s+'));
  final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
  final code = q.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  int? rank(GymMember m) {
    final name = m.fullName.toLowerCase();
    if (m.code.toUpperCase() == code) return 0;
    if (name == q) return 1;
    if (words.every(name.contains)) return name.startsWith(words.first) ? 2 : 3;
    if (digits.length >= 4 && m.phone.replaceAll(RegExp(r'[^0-9]'), '').contains(digits)) return 4;
    return null;
  }

  final found = [
    for (final m in members)
      if (rank(m) case final r?) (member: m, rank: r),
  ]..sort((a, b) => a.rank != b.rank ? a.rank - b.rank : a.member.fullName.compareTo(b.member.fullName));
  return [for (final f in found) f.member];
}

/// Each member's latest check-in in [checkIns].
Map<String, DateTime> lastVisits(Iterable<GymCheckIn> checkIns) {
  final last = <String, DateTime>{};
  for (final c in checkIns) {
    final seen = last[c.memberId];
    if (seen == null || c.checkedInAt.isAfter(seen)) last[c.memberId] = c.checkedInAt;
  }
  return last;
}

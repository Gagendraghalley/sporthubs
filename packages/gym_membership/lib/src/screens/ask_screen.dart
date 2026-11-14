import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/ask_data.dart';
import '../data/dashboard_data.dart';
import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/reports_data.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';

/// Ask AI: a gym's staff ask in their own words ("busiest hours this
/// month?", "who hasn't come in two weeks?", "when did Pema last come?",
/// "how do I renew a member?"). The AI (Cloudflare Workers AI, through the
/// ask-ai Edge Function) only chooses which of the app's reports answers it,
/// or writes a short how-to from SportsHub's guide. The chart or list is
/// worked out here from the gym's records, as the person's role allows, so
/// the numbers are the app's own and members' details never leave
/// SportsHub. Suggestions skip the AI and don't count.
///
/// It opens from the floating Ask AI button on the gym's pages
/// ([GymAssistantPanel]); this is the same conversation full size.
class AskScreen extends ConsumerWidget {
  final String venueId;

  const AskScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(askChatProvider(venueId));
    return GymStaffPage(
      venueId: venueId,
      title: 'Ask AI',
      builder: (context, access) => AppPage(
        title: 'Ask AI',
        maxWidth: 1000,
        actions: [
          if (chat.turns.isNotEmpty)
            IconButton(
              tooltip: 'Start again',
              icon: const Icon(Icons.restart_alt_rounded),
              onPressed: chat.busy ? null : ref.read(askChatProvider(venueId).notifier).startAgain,
            ),
        ],
        body: AskChat(access: access),
      ),
    );
  }
}

/// A gym's Ask AI in the floating panel, for its staff; anyone else there
/// gets SportsHub's assistant.
class GymAssistantPanel extends ConsumerWidget {
  final String venueId;

  const GymAssistantPanel({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(venueAccessProvider(venueId));
    final a = access.valueOrNull;
    if (access.hasValue && (a == null || a.venue.type != gymVenueType)) return const SportsHubAssistantPanel();
    final chat = ref.watch(askChatProvider(venueId));
    return AssistantPanel(
      title: 'Ask AI',
      subtitle: a == null ? null : '${a.venue.name} · your gym\'s records',
      actions: [
        if (chat.turns.isNotEmpty)
          IconButton(
            tooltip: 'Start again',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: chat.busy ? null : ref.read(askChatProvider(venueId).notifier).startAgain,
          ),
        IconButton(
          tooltip: 'Open full size',
          icon: const Icon(Icons.open_in_full_rounded),
          onPressed: () => assistantGo(context, GymRoutes.askFor(venueId)),
        ),
      ],
      child: a == null ? const LoadingSkeleton.rows() : AskChat(access: a, compact: true),
    );
  }
}

/// The conversation: questions about the gym, answered from its records.
class AskChat extends ConsumerWidget {
  final VenueAccess access;
  final bool compact;

  const AskChat({super.key, required this.access, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = access.venue.id;
    final chat = ref.watch(askChatProvider(id));
    final notifier = ref.read(askChatProvider(id).notifier);
    final seesReports = access.can(GymPermission.members);
    final suggestions = [
      for (final s in askSuggestions)
        if (s.reply.report!.allowedFor(access)) AssistantSuggestion(s.label, () => notifier.suggest(s.label, s.reply)),
    ];
    return AssistantConversationView<AskReply>(
      compact: compact,
      chat: chat,
      hint: 'Ask about your gym…',
      suggestions: suggestions,
      onAsk: notifier.ask,
      onRetry: notifier.retryLast,
      welcome: AssistantWelcome(
        title: 'Ask about ${access.venue.name}',
        intro: seesReports
            ? 'Ask in your own words, in English or Dzongkha: about members, visits, packages and money, '
                'or how to do something in SportsHub.'
            : 'Ask in your own words, in English or Dzongkha, how to do something in SportsHub.',
        points: [
          if (seesReports)
            (Icons.insights_rounded, "Charts and lists come from your gym's own records, as your role allows."),
          (Icons.lock_outline_rounded, "Only your question is sent to the AI (Cloudflare). Members' details stay in SportsHub."),
          if (suggestions.isNotEmpty)
            (Icons.bolt_rounded, "Suggestions answer straight away and don't count against today's questions."),
        ],
        suggestions: suggestions,
        examples: seesReports
            ? 'Or ask, for example: "Who hasn\'t come since last week?" · "When did Pema last come?" · '
                '"How do I renew a member?"'
            : 'Or ask, for example: "How do I check someone in without their card?" · "How do I register a member?"',
      ),
      answer: (context, reply) => switch (reply.kind) {
        AskKind.report => _ReportAnswer(access: access, reply: reply),
        AskKind.help => _HelpAnswer(access: access, reply: reply),
        AskKind.other => ConsoleCard(
            icon: Icons.auto_awesome_rounded,
            title: 'Ask AI',
            child: Text(reply.answer ?? askWhatICanDo, style: const TextStyle(height: 1.45)),
          ),
      },
    );
  }
}

/// A how-to, from SportsHub's guide, with the page that does it.
class _HelpAnswer extends StatelessWidget {
  final VenueAccess access;
  final AskReply reply;

  const _HelpAnswer({required this.access, required this.reply});

  @override
  Widget build(BuildContext context) {
    final page = reply.page;
    final muted = context.brand.muted;
    return ConsoleCard(
      icon: Icons.lightbulb_outline_rounded,
      title: page == null ? 'How to' : 'How to · ${page.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reply.answer ?? 'The ${page!.label} page does that.', style: const TextStyle(height: 1.45)),
          if (page != null) ...[
            const SizedBox(height: 12),
            if (access.can(page.permission))
              FilledButton.tonalIcon(
                onPressed: () => assistantGo(context, page.route(access.venue.id)),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text('Open ${page.label}'),
              )
            else
              Text("Your role here doesn't include ${page.label}. Ask the gym's owner if you need it.",
                  style: TextStyle(color: muted)),
          ],
          const SizedBox(height: 10),
          Text("Written by AI from SportsHub's guide.", style: TextStyle(color: muted, fontSize: 12)),
        ],
      ),
    );
  }
}

const _palette = [BrandColors.orange, BrandColors.blue, BrandColors.green, Color(0xFF7C4DFF), BrandColors.amber, Color(0xFF00A3A3)];

IconData _iconOf(AskReport r) => switch (r) {
      AskReport.visitsOverTime => Icons.login_rounded,
      AskReport.busiestDays => Icons.calendar_view_week_rounded,
      AskReport.busiestHours => Icons.schedule_rounded,
      AskReport.newMembers => Icons.group_add_rounded,
      AskReport.revenue => Icons.show_chart_rounded,
      AskReport.revenueByMethod => Icons.account_balance_wallet_rounded,
      AskReport.packageMix => Icons.sell_rounded,
      AskReport.renewalRate => Icons.autorenew_rounded,
      AskReport.memberCounts => Icons.donut_large_rounded,
      AskReport.endingSoon => Icons.event_busy_rounded,
      AskReport.inactiveMembers => Icons.person_off_rounded,
      AskReport.topMembers => Icons.emoji_events_rounded,
      AskReport.findMember => Icons.person_search_rounded,
    };

/// '1 visit', '3 visits'.
String _count(int n, String one, [String? many]) => '$n ${n == 1 ? one : many ?? '${one}s'}';

/// Where the largest of [points] is, or null when they're all 0.
int? _best(List<({String label, num value})> points) {
  int? best;
  for (var i = 0; i < points.length; i++) {
    if (points[i].value > 0 && (best == null || points[i].value > points[best].value)) best = i;
  }
  return best;
}

/// A report, worked out from the gym's records: a sentence that answers the
/// question, then the chart or list.
class _ReportAnswer extends ConsumerWidget {
  final VenueAccess access;
  final AskReply reply;

  const _ReportAnswer({required this.access, required this.reply});

  AskReport get report => reply.report!;
  String get id => access.venue.id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = report.overPeriod ? '${report.title} · ${reply.period.label}' : report.title;
    if (!report.allowedFor(access)) {
      return ConsoleCard(
        icon: Icons.lock_outline_rounded,
        title: report.title,
        child: Text("Your role here doesn't include this. Ask the gym's owner if you need it.",
            style: TextStyle(color: context.brand.muted)),
      );
    }
    final today = BhutanTime.today();
    final Widget body = switch (report) {
      AskReport.visitsOverTime || AskReport.busiestDays || AskReport.busiestHours || AskReport.topMembers =>
        _visits(context, ref, today),
      AskReport.revenue || AskReport.revenueByMethod => _money(context, ref, today),
      AskReport.newMembers => _newMembers(context, ref, today),
      AskReport.inactiveMembers => _notComing(context, ref, today),
      AskReport.findMember => _find(context, ref, today),
      AskReport.packageMix || AskReport.memberCounts || AskReport.endingSoon || AskReport.renewalRate =>
        _memberships(context, ref, today),
    };
    final (link, route) = switch (report) {
      AskReport.revenue || AskReport.revenueByMethod => ('Income', GymRoutes.incomeFor(id)),
      AskReport.endingSoon || AskReport.inactiveMembers || AskReport.findMember || AskReport.topMembers =>
        ('Members', GymRoutes.membersFor(id)),
      _ => ('Reports', GymRoutes.reportsFor(id)),
    };
    return ConsoleCard(
      icon: _iconOf(report),
      title: title,
      trailing: ConsoleLink(label: link, onPressed: () => assistantGo(context, route)),
      child: body,
    );
  }

  /// [build] once all of [values] have loaded: a skeleton until then, or
  /// what went wrong.
  Widget _when(BuildContext context, List<AsyncValue<Object?>> values, VoidCallback retry, Widget Function() build) {
    for (final v in values) {
      if (v.hasError && !v.hasValue) {
        return Row(
          children: [
            Expanded(child: Text(friendlyError(v.error!), style: TextStyle(color: context.brand.muted))),
            TextButton(onPressed: retry, child: const Text('Try again')),
          ],
        );
      }
    }
    if (values.any((v) => !v.hasValue)) return const LoadingSkeleton.rows();
    return build();
  }

  Widget _visits(BuildContext context, WidgetRef ref, DateTime today) {
    final since = reply.period.from(today);
    final key = (venueId: id, since: since);
    final value = ref.watch(gymCheckInsSinceProvider(key));
    return _when(context, [value], () => ref.invalidate(gymCheckInsSinceProvider(key)), () {
      final visits = value.value!;
      final period = reply.period.description;
      final capped = visits.length >= 5000 ? 'Counting the latest 5,000 check-ins.' : null;
      String none() => 'No check-ins in $period.';
      switch (report) {
        case AskReport.busiestDays:
          final points = checkInsByWeekday(visits);
          final best = _best(points);
          return _Answer(
            summary: best == null
                ? none()
                : '${weekdayNames[best]}s are the busiest: ${_count(points[best].value.toInt(), 'check-in')} in $period.',
            note: capped,
            child: ConsoleBarChart(
                name: 'Check-ins by day of the week', points: points, format: (v) => '${v.round()}', color: BrandColors.green),
          );
        case AskReport.busiestHours:
          final points = checkInsByHour(visits);
          final best = _best(points);
          return _Answer(
            summary: best == null
                ? none()
                : '${hourSpan(points[best].label)} is the busiest hour: '
                    '${_count(points[best].value.toInt(), 'check-in')} in $period.',
            note: capped,
            child: ConsoleBarChart(
                name: 'Check-ins by hour', points: points, format: (v) => '${v.round()}', color: BrandColors.blue),
          );
        case AskReport.topMembers:
          final top = regulars(visits, top: 8);
          return _Answer(
            summary: top.isEmpty ? none() : '${top.first.name} came most: ${_count(top.first.visits, 'visit')} in $period.',
            note: capped,
            child: top.isEmpty
                ? null
                : _MemberRows(venueId: id, rows: [
                    for (final (i, r) in top.indexed)
                      (
                        title: r.name,
                        subtitle: _count(r.visits, 'visit'),
                        lead: '${i + 1}',
                        trailing: null,
                        gymMemberId: r.gymMemberId,
                      ),
                  ]),
          );
        default:
          final days = BhutanTime.daysBetween(since, today) + 1;
          return _Answer(
            summary: visits.isEmpty
                ? none()
                : '${_count(visits.length, 'check-in')} in $period: ${(visits.length / days).toStringAsFixed(1)} a day.',
            note: capped,
            child: ConsoleBarChart(
              name: 'Check-ins',
              points: [for (final p in visitSeries(visits, today, reply.period.range)) (label: p.label, value: p.amount)],
              format: (v) => '${v.round()}',
              color: BrandColors.green,
            ),
          );
      }
    });
  }

  Widget _money(BuildContext context, WidgetRef ref, DateTime today) {
    final key = (
      venueId: id,
      moduleKey: gymModuleKey,
      from: bhutanMidnightUtc(reply.period.from(today)),
      to: bhutanMidnightUtc(DateTime(today.year, today.month, today.day + 1)),
    );
    final value = ref.watch(venuePaymentsProvider(key));
    return _when(context, [value], () => ref.invalidate(venuePaymentsProvider(key)), () {
      final payments = value.value!.where((p) => p.isCompleted).toList();
      final total = payments.fold(0, (s, p) => s + p.amount);
      final period = reply.period.description;
      if (report == AskReport.revenueByMethod) {
        final methods = revenueByMethod(payments);
        return _Answer(
          summary: methods.isEmpty
              ? 'No payments in $period.'
              : 'Most came by ${methods.first.label}: ${formatNu(methods.first.amount)} of ${formatNu(total)} '
                  '(${(100 * methods.first.amount / total).round()}%) in $period.',
          child: methods.isEmpty
              ? null
              : Column(children: [
                  for (final (i, m) in methods.indexed)
                    ConsoleShareRow(
                        color: _palette[i % _palette.length], label: m.label, value: formatNu(m.amount), share: m.amount / total),
                ]),
        );
      }
      return _Answer(
        summary: total == 0 ? 'No payments in $period.' : '${formatNu(total)} received in $period.',
        child: SizedBox(
          height: 220,
          child: ConsoleLineChart(
            name: 'Revenue',
            noneText: 'no payments yet',
            points: [for (final p in revenueSeries(payments, today, reply.period.range)) (label: p.label, value: p.amount)],
            format: (v) => formatNu(v),
          ),
        ),
      );
    });
  }

  Widget _newMembers(BuildContext context, WidgetRef ref, DateTime today) {
    final value = ref.watch(gymMembersProvider(id));
    return _when(context, [value], () => ref.invalidate(gymMembersProvider(id)), () {
      final members = value.value!;
      final from = reply.period.from(today);
      final joined = members.where((m) => !m.joinedOn.isBefore(from) && !m.joinedOn.isAfter(today)).length;
      return _Answer(
        summary: '${_count(joined, 'new member')} in ${reply.period.description}.',
        child: ConsoleBarChart(
          name: 'New members',
          points: [for (final p in joinedSeries(members, today, reply.period.range)) (label: p.label, value: p.amount)],
          format: (v) => '${v.round()}',
        ),
      );
    });
  }

  Widget _memberships(BuildContext context, WidgetRef ref, DateTime today) {
    final value = ref.watch(gymSubscriptionsProvider(id));
    return _when(context, [value], () => ref.invalidate(gymSubscriptionsProvider(id)), () {
      final subs = value.value!;
      switch (report) {
        case AskReport.packageMix:
          final mix = packageMix(subs, today);
          final total = mix.fold(0, (s, p) => s + p.members);
          return _Answer(
            summary: mix.isEmpty
                ? 'Nobody is on a package today.'
                : '${_count(total, 'member')} on a package today; ${mix.first.name} has the most (${mix.first.members}).',
            child: mix.isEmpty
                ? null
                : Column(children: [
                    for (final (i, p) in mix.indexed)
                      ConsoleShareRow(
                          color: _palette[i % _palette.length], label: p.name, value: '${p.members}', share: p.members / total),
                  ]),
          );
        case AskReport.memberCounts:
          final s = memberStanding(subs, today);
          final all = s.active + s.expired + s.waiting;
          double share(int n) => all == 0 ? 0 : n / all;
          return _Answer(
            summary: '${s.active} active, ${s.expired} whose package ended'
                '${s.waiting > 0 ? ', ${s.waiting} waiting for payment' : ''}.',
            child: Column(children: [
              ConsoleShareRow(color: BrandColors.green, label: 'Active', value: '${s.active}', share: share(s.active)),
              ConsoleShareRow(color: BrandColors.red, label: 'Ended', value: '${s.expired}', share: share(s.expired)),
              if (s.waiting > 0)
                ConsoleShareRow(color: BrandColors.amber, label: 'Waiting', value: '${s.waiting}', share: share(s.waiting)),
            ]),
          );
        case AskReport.renewalRate:
          final period = reply.period.description;
          final r = renewals(subs, reply.period.from(today), today);
          if (r.ended == 0) return _Answer(summary: "No package ended in $period, so there's nothing to count yet.");
          return _Answer(
            summary: '${(100 * r.renewed / r.ended).round()}% renewed: ${r.renewed} of the '
                '${_count(r.ended, 'member')} whose package ended in $period.',
            child: Column(children: [
              ConsoleShareRow(color: BrandColors.green, label: 'Renewed', value: '${r.renewed}', share: r.renewed / r.ended),
              ConsoleShareRow(
                  color: BrandColors.red,
                  label: 'Not renewed',
                  value: '${r.ended - r.renewed}',
                  share: (r.ended - r.renewed) / r.ended),
            ]),
          );
        default:
          final days = reply.days ?? 7;
          final when = days == 1 ? 'today' : 'in the next $days days';
          final ending = endingWithin(subs, today, days);
          return _Answer(
            summary: ending.isEmpty
                ? 'No package ends $when.'
                : '${_count(ending.length, 'package')} ${ending.length == 1 ? 'ends' : 'end'} $when.',
            note: ending.isEmpty ? null : 'Renew them from their page.',
            child: ending.isEmpty
                ? null
                : _MemberRows(venueId: id, rows: [
                    for (final s in ending)
                      (
                        title: s.memberDisplayName,
                        subtitle: '${s.planName} · ends ${formatShortDate(s.endDate!)}',
                        lead: null,
                        trailing: SubscriptionStatusChip(subscription: s),
                        gymMemberId: s.gymMemberId,
                      ),
                  ]),
          );
      }
    });
  }

  Widget _notComing(BuildContext context, WidgetRef ref, DateTime today) {
    final days = reply.days ?? 14;
    final key = (venueId: id, since: DateTime(today.year, today.month, today.day - (days - 1)));
    final subs = ref.watch(gymSubscriptionsProvider(id));
    final visits = ref.watch(gymCheckInsSinceProvider(key));
    return _when(context, [subs, visits], () {
      ref.invalidate(gymSubscriptionsProvider(id));
      ref.invalidate(gymCheckInsSinceProvider(key));
    }, () {
      final away = notComingMembers(subs.value!, visits.value!, today, days);
      return _Answer(
        summary: away.isEmpty
            ? 'Everyone with a package has come in the last $days days.'
            : '${_count(away.length, 'member')} with a package ${away.length == 1 ? "hasn't" : "haven't"} '
                'come in the last $days days.',
        note: away.isEmpty ? null : 'A call or a WhatsApp from their page can bring them back.',
        child: away.isEmpty
            ? null
            : _MemberRows(venueId: id, rows: [
                for (final s in away)
                  (
                    title: s.memberDisplayName,
                    subtitle: s.memberPhone == null ? s.planName : '${s.planName} · ${s.memberPhone}',
                    lead: null,
                    trailing: SubscriptionStatusChip(subscription: s),
                    gymMemberId: s.gymMemberId,
                  ),
              ]),
      );
    });
  }

  Widget _find(BuildContext context, WidgetRef ref, DateTime today) {
    final key = (venueId: id, since: DateTime(today.year, today.month, today.day - 89));
    final members = ref.watch(gymMembersProvider(id));
    final subs = ref.watch(gymSubscriptionsProvider(id));
    final visits = ref.watch(gymCheckInsSinceProvider(key));
    return _when(context, [members, subs, visits], () {
      ref.invalidate(gymMembersProvider(id));
      ref.invalidate(gymSubscriptionsProvider(id));
      ref.invalidate(gymCheckInsSinceProvider(key));
    }, () {
      final name = reply.name ?? '';
      final found = findMembers(members.value!, name);
      final last = lastVisits(visits.value!);
      GymSubscription? latest(String memberId) {
        final mine = subs.value!.where((s) => s.memberId == memberId && s.status != SubscriptionStatus.cancelled).toList();
        if (mine.isEmpty) return null;
        return mine.firstWhere((s) => s.isCurrentOn(today), orElse: () {
          mine.sort((a, b) => (b.endDate ?? b.requestedAt).compareTo(a.endDate ?? a.requestedAt));
          return mine.first;
        });
      }

      String lastCame(String memberId) {
        final at = last[memberId];
        if (at == null) return 'No visit in 90 days';
        final day = BhutanTime.dateOnly(BhutanTime.toBhutan(at));
        return day == today ? 'Came today' : 'Last came ${formatShortDate(day)}';
      }

      return _Answer(
        summary: found.isEmpty
            ? 'No member matches "$name".'
            : found.length == 1
                ? '1 member matches "$name".'
                : '${found.length} members match "$name".',
        note: found.isEmpty ? 'Try their phone number or member code.' : null,
        child: found.isEmpty
            ? null
            : _MemberRows(venueId: id, rows: [
                for (final m in found)
                  () {
                    final s = latest(m.id);
                    return (
                      title: '${m.fullName} · ${m.code}',
                      subtitle: '${s?.planName ?? 'No package'} · ${lastCame(m.id)}',
                      lead: null,
                      trailing: s == null
                          ? StatusChip(label: 'No package', color: context.brand.muted)
                          : SubscriptionStatusChip(subscription: s) as Widget,
                      gymMemberId: m.id,
                    );
                  }(),
              ]),
      );
    });
  }
}

/// A report's answer: the sentence that answers the question, then what
/// shows it.
class _Answer extends StatelessWidget {
  final String summary;
  final Widget? child;
  final String? note;

  const _Answer({required this.summary, this.child, this.note});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(summary,
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.4, color: ConsoleInk.of(context).heading)),
        if (child != null) ...[const SizedBox(height: 16), child!],
        if (note != null) ...[
          const SizedBox(height: 10),
          Text(note!, style: TextStyle(color: context.brand.muted, fontSize: 12.5)),
        ],
      ],
    );
  }
}

typedef _MemberRow = ({String title, String subtitle, String? lead, Widget? trailing, String? gymMemberId});

/// Members in an answer, each opening their page; the first [limit], then
/// the way to the rest.
class _MemberRows extends StatelessWidget {
  final String venueId;
  final List<_MemberRow> rows;

  const _MemberRows({required this.venueId, required this.rows});

  static const limit = 8;

  @override
  Widget build(BuildContext context) {
    final blue = context.colors.tertiary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows.take(limit))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: blue.withValues(alpha: 0.14),
              child: Text(
                r.lead ?? (r.title.trim().isEmpty ? '?' : r.title.trim()[0].toUpperCase()),
                style: TextStyle(fontWeight: FontWeight.w800, color: blue),
              ),
            ),
            title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(r.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: r.trailing,
            onTap: r.gymMemberId == null ? null : () => assistantGo(context, GymRoutes.memberFor(venueId, r.gymMemberId!)),
          ),
        if (rows.length > limit)
          TextButton.icon(
            onPressed: () => assistantGo(context, GymRoutes.membersFor(venueId)),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text('${rows.length - limit} more in Members'),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/dashboard_data.dart';
import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/registered_member.dart';
import '../data/reports_data.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_widgets.dart';

/// Reports & analytics: how the gym is doing over 30 days, 90 days or a
/// year, from its own records. New members, visits by day and hour,
/// renewals, the package mix, revenue (for those who see income), the most
/// regular members, and what it all says.
class ReportsScreen extends ConsumerStatefulWidget {
  final String venueId;

  const ReportsScreen({super.key, required this.venueId});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportRange _range = ReportRange.month;

  String get _id => widget.venueId;

  @override
  Widget build(BuildContext context) {
    final today = BhutanTime.today();
    final from = _range.from(today);
    return GymStaffPage(
      venueId: _id,
      title: 'Reports & analytics',
      permission: GymPermission.members,
      builder: (context, access) {
        final checkIns = ref.watch(gymCheckInsSinceProvider((venueId: _id, since: from)));
        return AppPage(
          title: 'Reports & analytics',
          actions: [
            ConsoleRangePicker<ReportRange>(
              values: ReportRange.values,
              value: _range,
              label: (r) => r.label,
              onChanged: (r) => setState(() => _range = r),
            ),
          ],
          body: AsyncValueView<List<GymCheckIn>>(
            value: checkIns,
            onRetry: () => ref.invalidate(gymCheckInsSinceProvider((venueId: _id, since: from))),
            data: (visits) => _Report(
              access: access,
              range: _range,
              from: from,
              today: today,
              visits: visits,
            ),
          ),
        );
      },
    );
  }
}

class _Report extends ConsumerWidget {
  final VenueAccess access;
  final ReportRange range;
  final DateTime from;
  final DateTime today;
  final List<GymCheckIn> visits;

  const _Report({required this.access, required this.range, required this.from, required this.today, required this.visits});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = access.venue.id;
    final members = ref.watch(gymMembersProvider(id)).valueOrNull ?? const <GymMember>[];
    final subs = ref.watch(gymSubscriptionsProvider(id)).valueOrNull ?? const <GymSubscription>[];
    final seesIncome = access.can(VenuePermission.income);
    final payments = seesIncome
        ? ref.watch(venuePaymentsProvider((
            venueId: id,
            moduleKey: gymModuleKey,
            from: bhutanMidnightUtc(from),
            to: bhutanMidnightUtc(DateTime(today.year, today.month, today.day + 1)),
          ))).valueOrNull
        : null;

    final joined = members.where((m) => !m.joinedOn.isBefore(from) && !m.joinedOn.isAfter(today)).length;
    final visitors = visits.map((c) => c.memberId).toSet().length;
    final byWeekday = checkInsByWeekday(visits);
    final byHour = checkInsByHour(visits);
    final renewal = renewals(subs, from, today);
    final mix = packageMix(subs, today);
    final mixTotal = mix.fold(0, (s, p) => s + p.members);
    final top = regulars(visits);
    final revenue = payments?.where((p) => p.isCompleted).fold(0, (s, p) => s + p.amount);
    final ending = endingWithin(subs, today, 7).length;
    final notes = insights(byWeekday: byWeekday, byHour: byHour, renewal: renewal, endingSoon: ending);
    const palette = [BrandColors.orange, BrandColors.blue, BrandColors.green, Color(0xFF7C4DFF), BrandColors.amber, Color(0xFF00A3A3)];

    return RefreshIndicator(
      onRefresh: () async {
        refreshGym(ref, id);
      },
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 1000;
          Widget pair(Widget a, Widget b) => wide
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [Expanded(child: a), const SizedBox(width: 20), Expanded(child: b)],
                  ),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 16), b]);
          return ListView(
            padding: pagePadding(context, bottom: 40),
            children: [
              Text('${access.venue.name} · ${range.description}', style: TextStyle(color: context.brand.muted, fontSize: 15)),
              const SizedBox(height: 16),
              ConsoleCells(
                columns: c.maxWidth >= 900 ? 4 : 2,
                children: staggered([
                  ConsoleKpi(
                    icon: Icons.person_add_alt_1_rounded,
                    color: BrandColors.blue,
                    value: '$joined',
                    count: joined,
                    label: 'New members',
                    note: '${members.length} registered in all',
                  ),
                  ConsoleKpi(
                    icon: Icons.login_rounded,
                    color: BrandColors.green,
                    value: '${visits.length}',
                    count: visits.length,
                    label: 'Check-ins',
                    note: '$visitors members · ${(visits.length / range.days).toStringAsFixed(1)} a day',
                  ),
                  ConsoleKpi(
                    icon: Icons.autorenew_rounded,
                    color: const Color(0xFF7C4DFF),
                    value: renewal.ended == 0 ? '—' : '${(100 * renewal.renewed / renewal.ended).round()}%',
                    count: renewal.ended == 0 ? null : (100 * renewal.renewed / renewal.ended).round(),
                    format: (v) => '${v.round()}%',
                    label: 'Renewal rate',
                    note: renewal.ended == 0 ? 'No package ended yet' : '${renewal.renewed} of ${renewal.ended} renewed',
                  ),
                  if (seesIncome)
                    ConsoleKpi(
                      icon: Icons.payments_rounded,
                      color: BrandColors.orange,
                      value: revenue == null ? '…' : formatNu(revenue),
                      count: revenue,
                      format: (v) => formatNu(v.round()),
                      label: 'Revenue',
                      note: 'Payments received',
                      onTap: () => context.go(GymRoutes.incomeFor(id)),
                    )
                  else
                    ConsoleKpi(
                      icon: Icons.event_busy_rounded,
                      color: BrandColors.amber,
                      value: '$ending',
                      count: ending,
                      label: 'Ending this week',
                      note: 'Packages to renew',
                      onTap: () => context.go(GymRoutes.membersFor(id)),
                    ),
                ]),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                FadeSlideIn(child: _Insights(notes: notes)),
              ],
              const SizedBox(height: 20),
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: pair(
                  ConsoleCard(
                    icon: Icons.calendar_view_week_rounded,
                    title: 'Busiest days',
                    child: ConsoleBarChart(
                      name: 'Check-ins by day of the week',
                      points: byWeekday,
                      format: (v) => '${v.round()}',
                      color: BrandColors.green,
                    ),
                  ),
                  ConsoleCard(
                    icon: Icons.schedule_rounded,
                    title: 'Busiest hours',
                    child: ConsoleBarChart(
                      name: 'Check-ins by hour',
                      points: byHour,
                      format: (v) => '${v.round()}',
                      color: BrandColors.blue,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FadeSlideIn(
                delay: const Duration(milliseconds: 140),
                child: pair(
                  ConsoleCard(
                    icon: Icons.group_add_rounded,
                    title: range == ReportRange.year ? 'New members by month' : 'New members by week',
                    child: ConsoleBarChart(
                      name: 'New members',
                      points: joinedOverTime(members, range, today),
                      format: (v) => '${v.round()}',
                    ),
                  ),
                  ConsoleCard(
                    icon: Icons.sell_rounded,
                    title: 'Package mix today',
                    child: mix.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text('Nobody is on a package today.', style: TextStyle(color: context.brand.muted)),
                          )
                        : Row(
                            children: [
                              ConsoleRing(
                                size: 140,
                                stroke: 16,
                                parts: [for (final (i, p) in mix.indexed) (p.members, palette[i % palette.length])],
                                center: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AnimatedCount(
                                      value: mixTotal,
                                      format: AnimatedCount.whole,
                                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ConsoleInk.of(context).heading),
                                    ),
                                    Text('members', style: TextStyle(color: context.brand.muted, fontSize: 12)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  children: [
                                    for (final (i, p) in mix.take(6).indexed)
                                      ConsoleShareRow(
                                        color: palette[i % palette.length],
                                        label: p.name,
                                        value: '${p.members}',
                                        share: p.members / mixTotal,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FadeSlideIn(
                delay: const Duration(milliseconds: 200),
                child: pair(
                  seesIncome
                      ? ConsoleCard(
                          icon: Icons.show_chart_rounded,
                          title: 'Revenue',
                          trailing: ConsoleLink(label: 'Income', onPressed: () => context.go(GymRoutes.incomeFor(id))),
                          child: SizedBox(
                            height: 220,
                            child: payments == null
                                ? const LoadingSkeleton.rows()
                                : ConsoleLineChart(
                                    name: 'Revenue',
                                    noneText: 'no payments yet',
                                    points: [
                                      for (final p in revenueSeries(payments, today, switch (range) {
                                        ReportRange.month => RevenueRange.month,
                                        ReportRange.quarter => RevenueRange.quarter,
                                        ReportRange.year => RevenueRange.year,
                                      }))
                                        (label: p.label, value: p.amount),
                                    ],
                                    format: (v) => formatNu(v),
                                  ),
                          ),
                        )
                      : _MembershipCard(subs: subs, today: today),
                  ConsoleCard(
                    icon: Icons.emoji_events_rounded,
                    title: 'Most regular',
                    child: top.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text('No check-ins in ${range.description}.', style: TextStyle(color: context.brand.muted)),
                          )
                        : Column(
                            children: [
                              for (final (i, r) in top.indexed)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor: (i == 0 ? BrandColors.amber : BrandColors.blue).withValues(alpha: 0.14),
                                    child: Text('${i + 1}',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800, color: i == 0 ? BrandColors.amber : BrandColors.blue)),
                                  ),
                                  title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: Text('${r.visits} visit${r.visits == 1 ? '' : 's'}',
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  onTap: r.gymMemberId == null ? null : () => context.go(GymRoutes.memberFor(id, r.gymMemberId!)),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// For staff who don't see income: where members stand, in place of revenue.
class _MembershipCard extends StatelessWidget {
  final List<GymSubscription> subs;
  final DateTime today;

  const _MembershipCard({required this.subs, required this.today});

  @override
  Widget build(BuildContext context) {
    final s = memberStanding(subs, today);
    return ConsoleCard(
      icon: Icons.donut_large_rounded,
      title: 'Where members stand',
      child: Column(
        children: [
          ConsoleShareRow(
            color: BrandColors.green,
            label: 'Active',
            value: '${s.active}',
            share: s.members == 0 ? 0 : s.active / s.members,
          ),
          ConsoleShareRow(
            color: BrandColors.red,
            label: 'Ended',
            value: '${s.expired}',
            share: s.members == 0 ? 0 : s.expired / s.members,
          ),
        ],
      ),
    );
  }
}

/// What the figures say, in plain words.
class _Insights extends StatelessWidget {
  final List<String> notes;

  const _Insights({required this.notes});

  @override
  Widget build(BuildContext context) {
    final blue = context.colors.tertiary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: [blue.withValues(alpha: 0.10), BrandColors.orange.withValues(alpha: 0.06)]),
        border: Border.all(color: blue.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, color: blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What this says', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                for (final n in notes)
                  Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('•  $n', style: const TextStyle(height: 1.4))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

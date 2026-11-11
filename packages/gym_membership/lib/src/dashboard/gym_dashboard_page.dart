import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/dashboard_data.dart';
import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import '../widgets/gym_type.dart';
import '../widgets/gym_widgets.dart';

/// Where a gym's owner, managers and front desk land: today's numbers,
/// revenue (for those who may see income), where members stand, what just
/// happened and whose package ends soon. In the app's frame: the gym's
/// pages are in its menu.
///
/// Every number comes from the gym's own records.
class GymDashboardPage extends StatelessWidget {
  final String venueId;

  const GymDashboardPage({super.key, required this.venueId});

  @override
  Widget build(BuildContext context) {
    return GymStaffPage(
      venueId: venueId,
      title: 'Dashboard',
      builder: (context, access) => GymType(child: _Console(access: access)),
    );
  }
}

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];



class _Console extends ConsumerStatefulWidget {
  final VenueAccess access;

  const _Console({required this.access});

  @override
  ConsumerState<_Console> createState() => _ConsoleState();
}

class _ConsoleState extends ConsumerState<_Console> {
  RevenueRange _range = RevenueRange.week;

  String get _id => widget.access.venue.id;

  /// A year of the gym's payments: every range of the chart.
  ({String venueId, String moduleKey, DateTime from, DateTime to}) _paymentsQuery(DateTime today) => (
        venueId: _id,
        moduleKey: gymModuleKey,
        from: bhutanMidnightUtc(revenueFrom(today)),
        to: bhutanMidnightUtc(DateTime(today.year, today.month, today.day + 1)),
      );

  Future<void> _refresh() async {
    refreshGym(ref, _id);
    if (widget.access.can(VenuePermission.income)) ref.invalidate(venuePaymentsProvider(_paymentsQuery(BhutanTime.today())));
    await ref.read(gymDashboardProvider(_id).future);
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: widget.access.venue.name,
      maxWidth: double.infinity,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: AsyncValueView<List<GymSubscription>>(
          value: ref.watch(gymSubscriptionsProvider(_id)),
          onRetry: () => ref.invalidate(gymSubscriptionsProvider(_id)),
          data: (subs) => AsyncValueView<GymDashboard>(
            value: ref.watch(gymDashboardProvider(_id)),
            onRetry: () => ref.invalidate(gymDashboardProvider(_id)),
            // The room the page really has, the menu folding or not.
            data: (dash) => LayoutBuilder(
              builder: (context, constraints) => _content(context, subs, dash, constraints.maxWidth),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, List<GymSubscription> subs, GymDashboard dash, double areaWidth) {
    final access = widget.access;
    final venue = access.venue;
    final today = BhutanTime.today();
    final pad = areaWidth >= 900 ? 32.0 : 16.0;
    final contentWidth = areaWidth - pad * 2;
    final standing = memberStanding(subs, today);
    final ending = endingWithin(subs, today, 30);
    final checkIns = ref.watch(gymRecentCheckInsProvider(_id)).valueOrNull ?? const <GymCheckIn>[];
    final payments = access.can(VenuePermission.income) ? ref.watch(venuePaymentsProvider(_paymentsQuery(today))) : null;
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final registered = ref.watch(gymMembersProvider(_id)).valueOrNull;
    final newThisMonth =
        registered?.where((m) => m.joinedOn.year == today.year && m.joinedOn.month == today.month).length ?? 0;
    final ink = ConsoleInk.of(context);

    // Getting started: what's left to do, from the gym's own records; gone
    // once it's all done (or nothing left is theirs to do).
    final plans = access.can(GymPermission.plans) ? ref.watch(gymPlansProvider((venueId: _id, all: true))).valueOrNull : null;
    final staff = access.can(VenuePermission.staff) ? ref.watch(venueStaffProvider(_id)).valueOrNull : null;
    final steps = [
      if (plans != null)
        _Step(
          done: plans.isNotEmpty,
          title: 'Create your first membership package',
          text: 'What the front desk sells, and its price.',
          action: 'Add a package',
          route: GymRoutes.newPlanFor(_id),
        ),
      if (registered != null && access.can(GymPermission.register))
        _Step(
          done: registered.isNotEmpty,
          title: 'Register your first member',
          text: 'Their details, a photo and a package; they get a QR card.',
          action: 'Register a member',
          route: GymRoutes.registerMemberFor(_id),
        ),
      if (staff != null)
        _Step(
          done: staff.length > 1,
          title: 'Add your gym staff',
          text: 'The front desk and trainers, each with their own role.',
          action: 'Add staff',
          route: CoreRoutes.venueStaffFor(_id),
        ),
    ];
    final setup = steps.isEmpty || steps.every((s) => s.done) ? null : _SetupCard(steps: steps);

    // What needs the desk's attention now.
    final soon = endingWithin(subs, today, 3);
    final noPackage = registered == null
        ? 0
        : registered.where((m) => !subs.any((s) => s.gymMemberId == m.id && s.status != SubscriptionStatus.cancelled)).length;
    final alerts = [
      if (!venue.isVerified)
        _Alert(
          icon: Icons.hourglass_top_rounded,
          color: context.brand.warning,
          text: 'SportsHub is still checking ${venue.name}. You can set it up meanwhile; '
              'it shows on the public gym list once verified.',
        ),
      if (soon.isNotEmpty)
        _Alert(
          icon: Icons.alarm_rounded,
          color: context.brand.danger,
          text: soon.length == 1
              ? "${soon.first.memberDisplayName}'s package ends ${soon.first.daysLeftOn(today) == 1 ? 'today' : 'in ${soon.first.daysLeftOn(today)} days'}"
              : '${soon.length} packages end in the next 3 days',
          onTap: () => context.push(GymRoutes.membersFor(_id)),
        ),
      if (noPackage > 0 && access.can(GymPermission.payments))
        _Alert(
          icon: Icons.person_off_outlined,
          color: BrandColors.blue,
          text: noPackage == 1 ? '1 member has no package yet' : '$noPackage members have no package yet',
          onTap: () => context.push(GymRoutes.membersFor(_id)),
        ),
    ];


    // Against last month, from the payments already here: only when last
    // month had some in the same days, so the trend is a fair one.
    final incomeChange = payments?.valueOrNull == null ? null : incomeChangeMonthToDate(payments!.valueOrNull!, today);
    final lastMonth = DateTime(today.year, today.month - 1, 1);
    final kpis = [
      ConsoleKpi(
        icon: Icons.groups_rounded,
        color: BrandColors.blue,
        value: '${standing.members}',
        count: standing.members,
        label: 'Total members',
        note: '${standing.active} active now',
        trailing: newThisMonth > 0
            ? ConsoleTrend(
                text: '+$newThisMonth new',
                up: true,
                tooltip: '$newThisMonth joined in ${formatMonth(today)}',
              )
            : null,
        onTap: () => context.push(GymRoutes.membersFor(_id)),
      ),
      ConsoleKpi(
        icon: Icons.qr_code_scanner_rounded,
        color: BrandColors.green,
        value: '${dash.checkInsToday}',
        count: dash.checkInsToday,
        label: 'Check-ins today',
        note: 'Since midnight, Bhutan time',
        onTap: () => context.push(GymRoutes.checkInFor(_id)),
      ),
      if (dash.incomeThisMonth != null)
        ConsoleKpi(
          icon: Icons.payments_outlined,
          color: BrandColors.orange,
          value: formatNu(dash.incomeThisMonth!),
          count: dash.incomeThisMonth,
          format: (v) => formatNu(v.round()),
          label: 'Income this month',
          note: formatMonth(today),
          trailing: incomeChange == null
              ? null
              : ConsoleTrend.percent(
                  incomeChange,
                  tooltip: 'Against 1–${today.day} ${formatMonth(lastMonth).split(' ').first}',
                ),
          onTap: () => context.push(GymRoutes.incomeFor(_id)),
        )
      else
        ConsoleKpi(
          icon: Icons.person_add_alt_1_rounded,
          color: BrandColors.amber,
          value: '${registered?.length ?? '–'}',
          count: registered?.length,
          label: 'Registered members',
          note: '$newThisMonth joined this month',
          onTap: () => context.push(GymRoutes.membersFor(_id)),
        ),
      ConsoleKpi(
        icon: Icons.event_busy_rounded,
        color: const Color(0xFF7C4DFF),
        value: '${ending.length}',
        count: ending.length,
        label: 'Ending in 30 days',
        note: ending.isEmpty
            ? 'No renewals due'
            : 'Next: ${firstName(ending.first.memberDisplayName, fallback: 'a member')}, '
                '${_daysText(ending.first.daysLeftOn(today))}',
        onTap: () => context.push(GymRoutes.membersFor(_id)),
      ),
    ];

    // Revenue and the members' status side by side (each filling the row's
    // height) on a wide page; one under the other otherwise.
    final sideBySideCards = contentWidth >= 900 && payments != null;
    final revenue = payments == null
        ? null
        : _RevenueCard(
            payments: payments,
            range: _range,
            today: today,
            pickerInHeader: contentWidth >= 640,
            fill: sideBySideCards,
            onRange: (r) => setState(() => _range = r),
          );
    final status = _StatusCard(standing: standing, fill: sideBySideCards);
    final activity = _ActivityCard(
      activity: recentActivity(subs: subs, checkIns: checkIns, payments: payments?.valueOrNull),
      today: today,
    );
    final endingCard = _EndingCard(ending: ending, today: today, venueId: _id);
    final checkInCard = _CheckInsCard(checkIns: checkIns, today: today, venueId: _id);

    Widget sideBySide(List<(int, Widget)> cards, {double? height}) {
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 20),
            Expanded(flex: cards[i].$1, child: cards[i].$2),
          ],
        ],
      );
      return height != null ? SizedBox(height: height, child: row) : IntrinsicHeight(child: row);
    }

    return ListView(
      padding: pagePadding(context, horizontal: pad, top: 18, bottom: 40),
      children: [
        Text(
          '${greetingAt(BhutanTime.now())}, ${firstName(profile?.fullName ?? '')}',
          style: TextStyle(
              fontSize: contentWidth >= 640 ? 30 : 24,
              fontWeight: FontWeight.w800,
              color: ink.heading,
              letterSpacing: -0.5),
        ),
        const SizedBox(height: 4),
        Text(
          "Here's what's happening at ${venue.name} today · ${_weekdays[today.weekday - 1]}, ${formatShortDate(today)}",
          style: TextStyle(fontSize: 15, color: context.brand.muted),
        ),
        const SizedBox(height: 16),
        FadeSlideIn(child: _QuickActions(access: access)),
        if (setup != null) ...[const SizedBox(height: 20), FadeSlideIn(child: setup)],
        if (alerts.isNotEmpty) ...[
          const SizedBox(height: 16),
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: Wrap(spacing: 12, runSpacing: 12, children: alerts),
          ),
        ],
        const SizedBox(height: 24),
        ConsoleCells(columns: contentWidth >= 900 ? 4 : 2, spacing: 16, children: staggered(kpis)),
        const SizedBox(height: 20),
        FadeSlideIn(
          delay: const Duration(milliseconds: 120),
          child: sideBySideCards
              ? sideBySide([(5, revenue!), (3, status)], height: 410)
              : revenue == null && contentWidth >= 900
                  // The front desk: no revenue; visits beside where members stand.
                  ? sideBySide([(3, checkInCard), (2, status)])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (revenue != null) ...[revenue, SizedBox(height: contentWidth >= 640 ? 20 : 16)],
                        status,
                      ],
                    ),
        ),
        const SizedBox(height: 20),
        FadeSlideIn(
          delay: const Duration(milliseconds: 180),
          child: contentWidth >= 900
              ? sideBySide([if (revenue != null) (3, checkInCard) else (3, activity), (2, endingCard)])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (revenue != null || contentWidth < 900) ...[checkInCard, const SizedBox(height: 16)],
                    endingCard,
                  ],
                ),
        ),
        if (revenue != null || contentWidth < 900) ...[
          const SizedBox(height: 20),
          FadeSlideIn(delay: const Duration(milliseconds: 220), child: activity),
        ],
      ],
    );
  }
}

String _daysText(int days) => days == 1 ? 'last day' : '$days days left';

/// The desk's shortcuts, as their role allows: check in, register, a new
/// package, staff.
class _QuickActions extends StatelessWidget {
  final VenueAccess access;

  const _QuickActions({required this.access});

  @override
  Widget build(BuildContext context) {
    final id = access.venue.id;
    final actions = [
      if (access.can(GymPermission.checkIn))
        (Icons.qr_code_scanner_rounded, 'Check in', GymRoutes.checkInFor(id)),
      if (access.can(GymPermission.register))
        (Icons.person_add_alt_1_rounded, 'Register member', GymRoutes.registerMemberFor(id)),
      if (access.can(GymPermission.members)) (Icons.search_rounded, 'Find a member', GymRoutes.membersFor(id)),
      if (access.can(GymPermission.plans)) (Icons.add_card_rounded, 'New package', GymRoutes.newPlanFor(id)),
      if (access.can(VenuePermission.staff)) (Icons.group_add_outlined, 'Add staff', CoreRoutes.venueStaffFor(id)),
    ];
    // The day's main action in orange, the rest quieter; each gives a
    // little under the hand, and they arrive one after another.
    const text = TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14.5);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: staggered(offset: 8, step: const Duration(milliseconds: 45), [
        for (final (i, (icon, label, route)) in actions.indexed)
          Pressable(
            child: i == 0
                ? FilledButton.icon(
                    onPressed: () => context.push(route),
                    style: FilledButton.styleFrom(
                      backgroundColor: context.brand.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      textStyle: text,
                    ),
                    icon: Icon(icon, size: 20),
                    label: Text(label),
                  )
                : OutlinedButton.icon(
                    onPressed: () => context.push(route),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 16), textStyle: text),
                    icon: Icon(icon, size: 20),
                    label: Text(label),
                  ),
          ),
      ]),
    );
  }
}

/// A getting-started step: done (ticked) or the way to do it.
class _Step {
  final bool done;
  final String title;
  final String text;
  final String action;
  final String route;

  const _Step({required this.done, required this.title, required this.text, required this.action, required this.route});
}

/// Get your gym ready: the steps left, how far along, and each one's way in.
class _SetupCard extends StatelessWidget {
  final List<_Step> steps;

  const _SetupCard({required this.steps});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final done = steps.where((s) => s.done).length;
    final next = steps.indexWhere((s) => !s.done);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ink.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.brand.accent.withValues(alpha: 0.35)),
        boxShadow: ink.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.rocket_launch_rounded, color: context.brand.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Get your gym ready',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink.heading)),
              ),
              Text('$done of ${steps.length} done', style: TextStyle(color: context.brand.muted, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: done / steps.length),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                color: context.brand.accent,
                backgroundColor: context.brand.accent.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final (i, s) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: LayoutBuilder(builder: (context, c) {
                // On a phone the button goes under the step, not beside it.
                final narrow = c.maxWidth < 520;
                final Widget? button = s.done
                    ? null
                    : i == next
                        ? FilledButton(
                            onPressed: () => context.push(s.route),
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                            child: Text(s.action),
                          )
                        : TextButton(onPressed: () => context.push(s.route), child: Text(s.action));
                return Row(
                  crossAxisAlignment: narrow ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: s.done ? context.brand.success : Colors.transparent,
                        border: Border.all(color: s.done ? context.brand.success : context.brand.glassBorder, width: 2),
                      ),
                      child: s.done
                          ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                          : Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: ink.body)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: s.done ? context.brand.muted : ink.heading,
                              decoration: s.done ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          if (!s.done) Text(s.text, style: TextStyle(color: context.brand.muted, fontSize: 13)),
                          if (narrow && button != null) ...[const SizedBox(height: 8), button],
                        ],
                      ),
                    ),
                    if (!narrow && button != null) ...[const SizedBox(width: 8), button],
                  ],
                );
              }),
            ),
        ],
      ),
    );
  }
}

/// Something that needs the desk now: a package ending, a member without
/// one, the gym being verified.
class _Alert extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback? onTap;

  const _Alert({required this.icon, required this.color, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: HoverLift(
        enabled: onTap != null,
        radius: 14,
        child: Material(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 10),
                  Flexible(child: Text(text, style: TextStyle(color: ConsoleInk.of(context).body, fontWeight: FontWeight.w600))),
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded, color: color, size: 20),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Check-ins on each of the last 7 days, today marked.
class _CheckInsCard extends StatelessWidget {
  final List<GymCheckIn> checkIns;
  final DateTime today;
  final String venueId;

  const _CheckInsCard({required this.checkIns, required this.today, required this.venueId});

  @override
  Widget build(BuildContext context) {
    final points = visitSeries(checkIns, today, RevenueRange.week);
    final total = points.fold<int>(0, (s, p) => s + p.amount);
    return ConsoleCard(
      icon: Icons.login_rounded,
      title: 'Check-in activity',
      trailing: ConsoleLink(label: 'Scan a card', onPressed: () => context.push(GymRoutes.checkInFor(venueId))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$total check-in${total == 1 ? '' : 's'} in the last 7 days',
              style: TextStyle(fontSize: 13, color: context.brand.muted)),
          const SizedBox(height: 10),
          ConsoleBarChart(
            name: 'Check-ins, last 7 days',
            height: 180,
            color: BrandColors.green,
            highlight: points.length - 1,
            points: [for (final p in points) (label: p.label, value: p.amount)],
            format: (v) => '${v.round()}',
          ),
        ],
      ),
    );
  }
}

// ─── Cards ─────────────────────────────────────────────────────────────────

/// What came in: the total for the range and a line through it.
class _RevenueCard extends StatelessWidget {
  final AsyncValue<List<Payment>> payments;
  final RevenueRange range;
  final DateTime today;
  final bool pickerInHeader;
  final bool fill;
  final ValueChanged<RevenueRange> onRange;

  const _RevenueCard({
    required this.payments,
    required this.range,
    required this.today,
    required this.pickerInHeader,
    required this.fill,
    required this.onRange,
  });

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final picker = ConsoleRangePicker<RevenueRange>(
      values: RevenueRange.values,
      value: range,
      label: (r) => r.label,
      onChanged: onRange,
    );
    final list = payments.valueOrNull;
    final points = revenueSeries(list ?? const [], today, range);
    final total = points.fold<int>(0, (sum, p) => sum + p.amount);
    final Widget chart;
    if (list == null && payments.hasError) {
      chart = Center(child: Text("Couldn't load payments", style: TextStyle(color: context.brand.muted)));
    } else if (list == null) {
      chart = const LoadingSkeleton(semanticsLabel: 'Loading payments');
    } else {
      chart = ConsoleLineChart(
        points: [for (final p in points) (label: p.label, value: p.amount)],
        format: formatNu,
        name: 'Revenue chart',
        noneText: 'no payments',
      );
    }
    return ConsoleCard(
      icon: Icons.bar_chart_rounded,
      title: 'Revenue overview',
      trailing: pickerInHeader ? picker : null,
      fill: fill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!pickerInHeader) ...[picker, const SizedBox(height: 14)],
          // The total glides to the new range's, rather than jumping.
          if (list == null)
            Text('–', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ink.heading, height: 1.1))
          else
            AnimatedCount(
              value: total,
              format: (v) => formatNu(v.round()),
              duration: Motion.count,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ink.heading, height: 1.1),
            ),
          AnimatedSwitcher(
            duration: Motion.of(context, Motion.hover),
            child: Text(
              total == 0 && list != null ? 'No payments in the ${range.description}' : 'Payments, ${range.description}',
              key: ValueKey('$range-${total == 0}'),
              style: TextStyle(fontSize: 13, color: context.brand.muted),
            ),
          ),
          const SizedBox(height: 12),
          if (fill) Expanded(child: chart) else SizedBox(height: 220, child: chart),
        ],
      ),
    );
  }
}

/// Active and expired members as a ring, the total inside.
class _StatusCard extends StatelessWidget {
  final MemberStanding standing;
  final bool fill;

  const _StatusCard({required this.standing, required this.fill});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final total = standing.members;
    String share(int n) => total == 0 ? '0%' : '${(100 * n / total).round()}%';
    final legend = [
      (BrandColors.blue, 'Active', standing.active),
      (BrandColors.orange, 'Expired', standing.expired),
    ];
    return ConsoleCard(
      icon: Icons.donut_large_rounded,
      title: 'Membership status',
      fill: fill,
      child: Column(
        children: [
          ConsoleRing(
            parts: [for (final (color, _, n) in legend) (n, color)],
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedCount(
                  value: total,
                  format: AnimatedCount.whole,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: ink.heading, height: 1),
                ),
                const SizedBox(height: 2),
                Text(total == 1 ? 'member' : 'members', style: TextStyle(fontSize: 12.5, color: context.brand.muted)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          for (final (color, name, n) in legend)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(width: 11, height: 11, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(name, style: TextStyle(fontSize: 14, color: ink.body, fontWeight: FontWeight.w600))),
                  Text(
                    '$n  ·  ${share(n)}',
                    style: TextStyle(fontSize: 13.5, color: ink.heading, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          
        ],
      ),
    );
  }
}

/// The latest check-ins, requests and memberships started.
class _ActivityCard extends StatelessWidget {
  final List<GymActivity> activity;
  final DateTime today;

  const _ActivityCard({required this.activity, required this.today});

  static const _kinds = {
    GymActivityKind.checkIn: ('Check-in', BrandColors.green),
    GymActivityKind.request: ('Request', BrandColors.amber),
    GymActivityKind.joined: ('New member', BrandColors.blue),
    GymActivityKind.renewed: ('Renewal', Color(0xFF7C4DFF)),
  };

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    return ConsoleCard(
      icon: Icons.monitor_heart_outlined,
      title: 'Recent activity',
      child: activity.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Nothing yet. Check-ins, requests and new memberships show up here.',
                style: TextStyle(color: context.brand.muted),
              ),
            )
          : Column(
              children: [
                for (final a in activity)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 66,
                          child: Text(
                            BhutanTime.dateOnly(BhutanTime.toBhutan(a.at)) == today
                                ? formatTime(a.at)
                                : formatShortDate(BhutanTime.toBhutan(a.at)),
                            style: TextStyle(fontSize: 12.5, color: context.brand.muted),
                          ),
                        ),
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(color: _kinds[a.kind]!.$2, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            a.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: ink.body, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: _kinds[a.kind]!.$2.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _kinds[a.kind]!.$1,
                            style: TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.w700, color: context.brand.readable(_kinds[a.kind]!.$2)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Members whose plan ends within 30 days, soonest first.
class _EndingCard extends StatelessWidget {
  final List<GymSubscription> ending;
  final DateTime today;
  final String venueId;

  const _EndingCard({required this.ending, required this.today, required this.venueId});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final brand = context.brand;
    return ConsoleCard(
      icon: Icons.event_busy_rounded,
      title: 'Ending soon',
      trailing: Text('Next 30 days', style: TextStyle(fontSize: 12.5, color: brand.muted)),
      child: ending.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text('No memberships end in the next 30 days.', style: TextStyle(color: brand.muted)),
            )
          : Column(
              children: [
                for (final s in ending.take(6))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: BrandColors.blue.withValues(alpha: 0.12),
                          child: Text(
                            s.memberDisplayName.characters.first.toUpperCase(),
                            style: const TextStyle(color: BrandColors.blue, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.memberDisplayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ink.heading),
                              ),
                              Text(
                                '${s.planName} · until ${formatShortDate(s.endDate!)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: brand.muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        () {
                          final left = s.daysLeftOn(today);
                          final color = left <= 3 ? brand.danger : (left <= 7 ? brand.warning : brand.muted);
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _daysText(left),
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: brand.readable(color)),
                            ),
                          );
                        }(),
                      ],
                    ),
                  ),
                if (ending.length > 6)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => context.push(GymRoutes.membersFor(venueId)),
                      child: Text('See all ${ending.length}'),
                    ),
                  ),
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/dashboard_data.dart';
import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../gym_routes.dart';
import '../widgets/console_kit.dart';
import '../widgets/gym_type.dart';
import '../widgets/gym_widgets.dart';

/// Where a gym's owner, managers and front desk land: today's numbers,
/// revenue (owners and managers: payments are theirs to see), where members
/// stand, what to do next, what just happened and whose membership ends
/// soon. A navy menu down the side of a wide window; a drawer on a phone.
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

/// Widths at which the side menu shows, and the content goes side by side.
const _sideMenuFrom = 1100.0;
const _sideMenuWidth = 260.0;

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
    if (widget.access.canManage) ref.invalidate(venuePaymentsProvider(_paymentsQuery(BhutanTime.today())));
    await ref.read(gymDashboardProvider(_id).future);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= _sideMenuFrom;
    return Scaffold(
      backgroundColor: context.brand.background,
      drawer: wide ? null : Drawer(width: 280, child: _SideNav(access: widget.access, inDrawer: true)),
      body: Row(
        children: [
          if (wide) SizedBox(width: _sideMenuWidth, child: _SideNav(access: widget.access, inDrawer: false)),
          Expanded(
            child: Column(
              children: [
                _TopBar(access: widget.access, showMenu: !wide),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: AsyncValueView<List<GymSubscription>>(
                      value: ref.watch(gymSubscriptionsProvider(_id)),
                      onRetry: () => ref.invalidate(gymSubscriptionsProvider(_id)),
                      data: (subs) => AsyncValueView<GymDashboard>(
                        value: ref.watch(gymDashboardProvider(_id)),
                        onRetry: () => ref.invalidate(gymDashboardProvider(_id)),
                        data: (dash) => _content(context, subs, dash, width - (wide ? _sideMenuWidth : 0)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final payments = access.canManage ? ref.watch(venuePaymentsProvider(_paymentsQuery(today))) : null;
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final ink = ConsoleInk.of(context);

    final kpis = [
      ConsoleKpi(
        icon: Icons.groups_rounded,
        color: BrandColors.blue,
        value: '${standing.members}',
        label: 'Total members',
        note: '${standing.active} active now',
        onTap: () => context.push(GymRoutes.membersFor(_id)),
      ),
      ConsoleKpi(
        icon: Icons.qr_code_scanner_rounded,
        color: BrandColors.green,
        value: '${dash.checkInsToday}',
        label: 'Check-ins today',
        note: 'Since midnight, Bhutan time',
        onTap: () => context.push(GymRoutes.checkInFor(_id)),
      ),
      if (dash.incomeThisMonth != null)
        ConsoleKpi(
          icon: Icons.payments_outlined,
          color: BrandColors.orange,
          value: formatNu(dash.incomeThisMonth!),
          label: 'Income this month',
          note: formatMonth(today),
          onTap: () => context.push(GymRoutes.incomeFor(_id)),
        )
      else
        ConsoleKpi(
          icon: Icons.inbox_outlined,
          color: BrandColors.amber,
          value: '${dash.pending}',
          label: 'Requests waiting',
          note: 'Confirm their payments',
          onTap: () => context.push(GymRoutes.requestsFor(_id)),
        ),
      ConsoleKpi(
        icon: Icons.event_busy_rounded,
        color: const Color(0xFF7C4DFF),
        value: '${ending.length}',
        label: 'Ending in 30 days',
        note: ending.isEmpty
            ? 'No renewals due'
            : 'Next: ${firstName(ending.first.memberDisplayName, fallback: 'a member')}, '
                '${_daysText(ending.first.daysLeftOn(today))}',
        onTap: () => context.push(GymRoutes.membersFor(_id)),
      ),
    ];

    final revenue = payments == null
        ? null
        : _RevenueCard(
            payments: payments,
            range: _range,
            today: today,
            pickerInHeader: contentWidth >= 640,
            fill: contentWidth >= 1000,
            onRange: (r) => setState(() => _range = r),
          );
    final status = _StatusCard(standing: standing, waiting: dash.pending, venueId: _id, fill: contentWidth >= 640);
    final actions = _ActionsCard(access: access, pending: dash.pending, fill: contentWidth >= 640);
    final activity = _ActivityCard(
      activity: recentActivity(subs: subs, checkIns: checkIns, payments: payments?.valueOrNull),
      today: today,
    );
    final endingCard = _EndingCard(ending: ending, today: today, venueId: _id);

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
      padding: EdgeInsets.fromLTRB(pad, 26, pad, 40),
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
        if (!venue.isVerified) ...[
          const SizedBox(height: 16),
          _Notice(
            text: 'SportsHub is still checking ${venue.name}. Members can find it and join once it is verified.',
          ),
        ],
        const SizedBox(height: 24),
        ConsoleCells(columns: contentWidth >= 900 ? 4 : 2, spacing: 16, children: kpis),
        const SizedBox(height: 20),
        if (contentWidth >= 1000)
          sideBySide([if (revenue != null) (5, revenue), (3, status), (3, actions)], height: 410)
        else if (contentWidth >= 640) ...[
          if (revenue != null) ...[revenue, const SizedBox(height: 20)],
          sideBySide([(1, status), (1, actions)], height: 400),
        ] else ...[
          if (revenue != null) ...[revenue, const SizedBox(height: 16)],
          status,
          const SizedBox(height: 16),
          actions,
        ],
        const SizedBox(height: 20),
        if (contentWidth >= 900)
          sideBySide([(3, activity), (2, endingCard)])
        else ...[
          activity,
          const SizedBox(height: 16),
          endingCard,
        ],
      ],
    );
  }
}

String _daysText(int days) => days == 1 ? 'last day' : '$days days left';

// ─── Frame ─────────────────────────────────────────────────────────────────

String _roleLabel(String role) => switch (role) {
      VenueRole.owner => 'Gym owner',
      VenueRole.manager => 'Manager',
      VenueRole.staff => 'Front desk',
      _ => 'SportsHub admin',
    };

/// The gym's menu, on navy: its pages, the gym's own pages, and back to
/// SportsHub.
class _SideNav extends ConsumerWidget {
  final VenueAccess access;

  /// In the phone's drawer, which closes before a page opens.
  final bool inDrawer;

  const _SideNav({required this.access, required this.inDrawer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = access.venue.id;
    final pending = ref.watch(gymDashboardProvider(id)).valueOrNull?.pending ?? 0;
    final profile = ref.watch(myProfileProvider).valueOrNull;
    void open(String route) {
      if (inDrawer) Navigator.of(context).pop();
      context.push(route);
    }

    final name = (profile?.fullName ?? '').trim();
    return ConsoleSideNav(
      items: [
        ConsoleNavItem(
          icon: Icons.space_dashboard_rounded,
          label: 'Dashboard',
          selected: true,
          onTap: () {
            if (inDrawer) Navigator.of(context).pop();
          },
        ),
        ConsoleNavItem(
          icon: Icons.qr_code_scanner_rounded,
          label: 'Check in',
          onTap: () => open(GymRoutes.checkInFor(id)),
        ),
        ConsoleNavItem(
          icon: Icons.inbox_outlined,
          label: 'Requests',
          badge: pending,
          onTap: () => open(GymRoutes.requestsFor(id)),
        ),
        ConsoleNavItem(icon: Icons.groups_rounded, label: 'Members', onTap: () => open(GymRoutes.membersFor(id))),
        if (access.canManage) ...[
          ConsoleNavItem(icon: Icons.sell_outlined, label: 'Plans & prices', onTap: () => open(GymRoutes.plansFor(id))),
          ConsoleNavItem(icon: Icons.payments_outlined, label: 'Income', onTap: () => open(GymRoutes.incomeFor(id))),
          ConsoleNavItem(icon: Icons.badge_outlined, label: 'Staff', onTap: () => open(CoreRoutes.venueStaffFor(id))),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
        ),
        ConsoleNavItem(icon: Icons.storefront_outlined, label: 'Gym page', onTap: () => open(GymRoutes.gymFor(id))),
        ConsoleNavItem(
          icon: Icons.tune_rounded,
          label: 'Gym settings',
          onTap: () => open(CoreRoutes.venueManageFor(id)),
        ),
      ],
      footer: [
        ConsoleNavItem(
          icon: Icons.home_outlined,
          label: 'SportsHub home',
          onTap: () {
            if (inDrawer) Navigator.of(context).pop();
            context.go(CoreRoutes.home);
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: BrandColors.orange,
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'You' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    Text(
                      _roleLabel(access.role),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The menu button (phones), the gym (a switcher for someone at more than
/// one), its public page, notifications and the account.
class _TopBar extends ConsumerWidget {
  final VenueAccess access;
  final bool showMenu;

  const _TopBar({required this.access, required this.showMenu});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = ConsoleInk.of(context);
    final gyms = (ref.watch(myVenuesProvider).valueOrNull ?? const <MyVenue>[])
        .where((v) => v.venue.type == gymVenueType)
        .toList();
    final current = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: BrandColors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.fitness_center_rounded, size: 18, color: BrandColors.orange),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            access.venue.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: ink.heading),
          ),
        ),
        if (gyms.length > 1) Icon(Icons.expand_more_rounded, color: ink.heading),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: ink.card,
        border: Border(bottom: BorderSide(color: context.brand.glassBorder)),
      ),
      child: SafeArea(
        bottom: false,
        left: false,
        child: SizedBox(
          height: 66,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (showMenu)
                  IconButton(
                    tooltip: 'Menu',
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: gyms.length > 1
                        ? PopupMenuButton<String>(
                            tooltip: 'Switch gym',
                            onSelected: (id) => context.pushReplacement(GymRoutes.dashboardFor(id)),
                            itemBuilder: (_) => [
                              for (final g in gyms)
                                PopupMenuItem(
                                  value: g.venue.id,
                                  child: Text(g.venue.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: current),
                          )
                        : current,
                  ),
                ),
                IconButton(
                  tooltip: "The gym's public page",
                  icon: const Icon(Icons.storefront_outlined),
                  onPressed: () => context.push(GymRoutes.gymFor(access.venue.id)),
                ),
                const ThemeModeButton(),
                const NotificationBell(),
                IconButton(
                  tooltip: 'Account',
                  icon: const Icon(Icons.account_circle_outlined),
                  onPressed: () => context.push(CoreRoutes.account),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;

  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    final warning = context.brand.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_top_rounded, color: warning),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: ConsoleInk.of(context).body, height: 1.4))),
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
      chart = const Center(child: CircularProgressIndicator());
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
          Text(
            list == null ? '–' : formatNu(total),
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ink.heading, height: 1.1),
          ),
          Text(
            total == 0 && list != null ? 'No payments in the ${range.description}' : 'Payments, ${range.description}',
            style: TextStyle(fontSize: 13, color: context.brand.muted),
          ),
          const SizedBox(height: 12),
          if (fill) Expanded(child: chart) else SizedBox(height: 220, child: chart),
        ],
      ),
    );
  }
}

/// Active and expired members as a ring, the total inside; requests waiting
/// under it.
class _StatusCard extends StatelessWidget {
  final MemberStanding standing;
  final int waiting;
  final String venueId;
  final bool fill;

  const _StatusCard({required this.standing, required this.waiting, required this.venueId, required this.fill});

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
                Text('$total',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: ink.heading, height: 1)),
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
          if (waiting > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push(GymRoutes.requestsFor(venueId)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                icon: Icon(Icons.hourglass_top_rounded, size: 17, color: context.brand.warning),
                label: Text('$waiting waiting for payment'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Check in first; then the gym's other pages, waiting requests counted.
class _ActionsCard extends StatelessWidget {
  final VenueAccess access;
  final int pending;
  final bool fill;

  const _ActionsCard({required this.access, required this.pending, required this.fill});

  @override
  Widget build(BuildContext context) {
    final id = access.venue.id;
    final tiles = [
      ConsoleActionTile(
        icon: Icons.inbox_outlined,
        label: 'Requests',
        badge: pending,
        onTap: () => context.push(GymRoutes.requestsFor(id)),
      ),
      ConsoleActionTile(
          icon: Icons.groups_rounded, label: 'Members', onTap: () => context.push(GymRoutes.membersFor(id))),
      if (access.canManage) ...[
        ConsoleActionTile(
            icon: Icons.sell_outlined, label: 'Plans & prices', onTap: () => context.push(GymRoutes.plansFor(id))),
        ConsoleActionTile(
            icon: Icons.payments_outlined, label: 'Income', onTap: () => context.push(GymRoutes.incomeFor(id))),
        ConsoleActionTile(
            icon: Icons.badge_outlined, label: 'Staff', onTap: () => context.push(CoreRoutes.venueStaffFor(id))),
      ],
      ConsoleActionTile(
          icon: Icons.storefront_outlined, label: 'Gym page', onTap: () => context.push(GymRoutes.gymFor(id))),
    ];
    return ConsoleCard(
      icon: Icons.bolt_rounded,
      title: 'Quick actions',
      fill: fill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => context.push(GymRoutes.checkInFor(id)),
            style: FilledButton.styleFrom(
              backgroundColor: BrandColors.orange,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              minimumSize: const Size.fromHeight(50),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Check in a member'),
          ),
          const SizedBox(height: 14),
          ConsoleTileGrid(tiles: tiles),
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
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _kinds[a.kind]!.$2),
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
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
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

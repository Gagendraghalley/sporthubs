import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/dashboard_data.dart';
import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../data/member_qr.dart';
import '../gym_routes.dart';
import '../widgets/console_kit.dart';
import '../widgets/gym_art.dart';
import '../widgets/gym_type.dart';

/// The signed-in home while gym membership leads SportsHub, in the console
/// look it shares with the gym dashboard: the navy menu down the side (a
/// drawer on a phone); the greeting over a photo of training, with the
/// member's gym and account across the top; their numbers; their training,
/// membership and shortcuts; what they did lately, their gyms (or the sports
/// to come) and their QR pass; the footer.
///
/// Every number is the member's own, from their records.
class GymHomePage extends ConsumerStatefulWidget {
  const GymHomePage({super.key});

  @override
  ConsumerState<GymHomePage> createState() => _GymHomePageState();
}

/// Widths at which the side menu shows.
const _sideMenuFrom = 1100.0;
const _sideMenuWidth = 260.0;

/// The training chart's periods: the member's check-ins reach back 90 days.
const _visitRanges = [RevenueRange.week, RevenueRange.month, RevenueRange.quarter];

const _purple = Color(0xFF7C4DFF);

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String _daysText(int days) => days == 1 ? 'last day' : '$days days left';

String _visits(int n) => n == 1 ? '1 visit' : '$n visits';

class _GymHomePageState extends ConsumerState<GymHomePage> {
  RevenueRange _range = RevenueRange.week;

  void _refresh() {
    ref.invalidate(mySubscriptionsProvider);
    ref.invalidate(myCheckInsProvider);
    ref.invalidate(myVenuesProvider);
    ref.invalidate(myProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final menu = MediaQuery.sizeOf(context).width >= _sideMenuFrom;
    return GymType(
      child: Scaffold(
        backgroundColor: context.brand.background,
        drawer: menu ? null : const Drawer(width: 280, child: _HomeNav(inDrawer: true)),
        body: Row(
          // Full height: a page shorter than the window starts at its top.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (menu) const SizedBox(width: _sideMenuWidth, child: _HomeNav(inDrawer: false)),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: LayoutBuilder(
                  builder: (context, constraints) => _content(context, constraints.maxWidth, showMenu: !menu),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, double area, {required bool showMenu}) {
    final pad = area >= 900 ? 32.0 : 16.0;
    final content = area - pad * 2;
    final today = BhutanTime.today();
    final subs = ref.watch(mySubscriptionsProvider).valueOrNull ?? const <GymSubscription>[];
    final checkIns = ref.watch(myCheckInsProvider).valueOrNull ?? const <GymCheckIn>[];
    final venues = ref.watch(myVenuesProvider).valueOrNull ?? const <MyVenue>[];
    final isAdmin = ref.watch(myProfileProvider).valueOrNull?.isAdmin ?? false;
    final unread = ref.watch(unreadCountProvider);
    final m = _Membership.of(subs, today);

    final training = _TrainingCard(
      checkIns: checkIns,
      today: today,
      range: _range,
      fill: content >= 1000,
      onRange: (r) => setState(() => _range = r),
    );
    final membership = _MembershipCard(m: m, today: today);
    final actions = _ActionsCard(m: m, venues: venues, unread: unread, isAdmin: isAdmin, fill: content >= 640);
    final activity = _ActivityCard(activity: myActivity(subs: subs, checkIns: checkIns, limit: 6), today: today);
    final places = venues.isEmpty ? const _ExploreCard() : _YourGymsCard(venues: venues);
    final pass = _PassCard(m: m);

    /// Cards in a row: as tall as the tallest, or [height].
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

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(area: area, gutter: pad, m: m, venues: venues, showMenu: showMenu),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 20, pad, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConsoleCells(columns: content >= 1000 ? 4 : 2, children: _numbers(context, m, checkIns, today, unread)),
                const SizedBox(height: 20),
                if (content >= 1000)
                  sideBySide([(4, training), (3, membership), (3, actions)])
                else if (content >= 640) ...[
                  training,
                  const SizedBox(height: 20),
                  sideBySide([(1, membership), (1, actions)]),
                ] else ...[
                  training,
                  const SizedBox(height: 16),
                  membership,
                  const SizedBox(height: 16),
                  actions,
                ],
                const SizedBox(height: 20),
                // The QR code can't be measured ahead, so these rows are set
                // heights rather than as tall as their tallest.
                if (content >= 1000)
                  sideBySide([(1, activity), (1, places), (1, pass)], height: 360)
                else if (content >= 640) ...[
                  sideBySide([(1, activity), (1, places)], height: 360),
                  const SizedBox(height: 20),
                  pass,
                ] else ...[
                  activity,
                  const SizedBox(height: 16),
                  places,
                  const SizedBox(height: 16),
                  pass,
                ],
                if (isAdmin) ...[const SizedBox(height: 20), const _AdminCard()],
              ],
            ),
          ),
          ConsoleFooter(
            gutter: pad,
            links: [
              ('Find a gym', () => context.push(GymRoutes.gyms)),
              ('My gym', () => context.push(GymRoutes.myGym)),
              ('Notifications', () => context.push(CoreRoutes.notifications)),
              ('Account', () => context.push(CoreRoutes.account)),
              ('Register your gym', () => context.push(CoreRoutes.registerVenue)),
            ],
          ),
        ],
      ),
    );
  }

  /// Days left, visits this week, the streak, notifications.
  List<Widget> _numbers(BuildContext context, _Membership m, List<GymCheckIn> checkIns, DateTime today, int unread) {
    final c = m.current;
    final weeks = weeklyVisits(checkIns, today);
    final streak = visitStreak(checkIns, today);
    void myGym() => context.push(GymRoutes.myGym);
    return [
      ConsoleKpi(
        icon: Icons.event_available_rounded,
        color: BrandColors.blue,
        value: c == null ? '–' : '${c.daysLeftOn(today)}',
        label: 'Days left',
        note: c != null
            ? '${c.planName} · ${c.gymName ?? 'your gym'}'
            : m.upcoming != null
                ? 'Starts ${formatShortDate(m.upcoming!.startDate!)}'
                : (m.pending.isNotEmpty ? 'Waiting for payment' : 'No plan yet'),
        trailing: c == null ? null : _PlanLeft(share: 1 - c.progressOn(today)),
        onTap: () => context.push(m.hasPass || m.pending.isNotEmpty ? GymRoutes.myGym : GymRoutes.gyms),
      ),
      ConsoleKpi(
        icon: Icons.directions_run_rounded,
        color: BrandColors.green,
        value: '${weeks.last}',
        label: 'Visits this week',
        note: 'The last 7 days',
        trailing: _Trend(weeks: weeks, color: BrandColors.green),
        onTap: myGym,
      ),
      ConsoleKpi(
        icon: Icons.local_fire_department_rounded,
        color: BrandColors.orange,
        value: '$streak',
        label: 'Day streak',
        note: streak == 0 ? 'Check in to start one' : (streak == 1 ? '1 day in a row' : '$streak days in a row'),
        trailing: _WeekBars(days: visitedDays(checkIns, today)),
        onTap: myGym,
      ),
      ConsoleKpi(
        icon: Icons.notifications_none_rounded,
        color: _purple,
        value: '$unread',
        label: 'Notifications',
        note: unread == 0 ? 'All caught up' : '$unread unread',
        onTap: () => context.push(CoreRoutes.notifications),
      ),
    ];
  }
}

/// Where the member stands: their current membership (soonest ending), a
/// renewal already paid, and requests waiting.
class _Membership {
  final GymSubscription? current;
  final GymSubscription? upcoming;
  final List<GymSubscription> pending;

  const _Membership({this.current, this.upcoming, this.pending = const []});

  factory _Membership.of(List<GymSubscription> subs, DateTime today) {
    final current = subs.where((s) => s.isCurrentOn(today)).toList()..sort((a, b) => a.endDate!.compareTo(b.endDate!));
    final upcoming = subs.where((s) => s.isUpcomingOn(today)).toList()..sort((a, b) => a.startDate!.compareTo(b.startDate!));
    return _Membership(
      current: current.firstOrNull,
      upcoming: upcoming.firstOrNull,
      pending: subs.where((s) => s.isPending).toList(),
    );
  }

  bool get hasPass => current != null || upcoming != null;

  /// One line on where things stand, or what to do first.
  String status(DateTime today) {
    if (current != null) {
      final c = current!;
      return '${c.gymName ?? 'Your gym'} · ${c.planName} · ${_daysText(c.daysLeftOn(today))}';
    }
    if (upcoming != null) {
      final u = upcoming!;
      return 'Your ${u.planName} at ${u.gymName ?? 'your gym'} starts on ${formatDate(u.startDate!)}.';
    }
    if (pending.isNotEmpty) {
      final p = pending.first;
      return 'Waiting for ${p.gymName ?? 'the gym'} to confirm your payment of ${formatNu(p.price)}.';
    }
    return 'Find a gym near you, join a plan and check in with your phone.';
  }
}

String _roleLabel(String role) => switch (role) {
      VenueRole.owner => 'Owner',
      VenueRole.manager => 'Manager',
      VenueRole.staff => 'Front desk',
      _ => 'Admin',
    };

// ─── The side menu ─────────────────────────────────────────────────────────

/// Home, the member's pages, the gyms they run and registering one; a card
/// at the foot.
class _HomeNav extends ConsumerWidget {
  /// In the phone's drawer, which closes before a page opens.
  final bool inDrawer;

  const _HomeNav({required this.inDrawer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(myVenuesProvider).valueOrNull ?? const <MyVenue>[];
    final modules = ref.watch(enabledModulesProvider).valueOrNull ?? const <SportsHubModule>[];
    final unread = ref.watch(unreadCountProvider);
    final isAdmin = ref.watch(myProfileProvider).valueOrNull?.isAdmin ?? false;
    void open(String route) {
      if (inDrawer) Navigator.of(context).pop();
      context.push(route);
    }

    return ConsoleSideNav(
      items: [
        ConsoleNavItem(
          icon: Icons.home_rounded,
          label: 'Home',
          selected: true,
          onTap: () {
            if (inDrawer) Navigator.of(context).pop();
          },
        ),
        ConsoleNavItem(icon: Icons.search_rounded, label: 'Find a gym', onTap: () => open(GymRoutes.gyms)),
        ConsoleNavItem(icon: Icons.qr_code_2_rounded, label: 'My gym', onTap: () => open(GymRoutes.myGym)),
        ConsoleNavItem(
          icon: Icons.notifications_none_rounded,
          label: 'Notifications',
          badge: unread,
          onTap: () => open(CoreRoutes.notifications),
        ),
        ConsoleNavItem(icon: Icons.person_outline_rounded, label: 'Account', onTap: () => open(CoreRoutes.account)),
        if (venues.isNotEmpty) ...[
          const ConsoleNavHeading('Your gyms'),
          for (final v in venues)
            ConsoleNavItem(
              icon: Icons.fitness_center_rounded,
              label: v.venue.name,
              onTap: () => open(venueHomeRoute(modules, v.venue)),
            ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
        ),
        ConsoleNavItem(
          icon: Icons.add_business_outlined,
          label: 'Register a gym',
          onTap: () => open(CoreRoutes.registerVenue),
        ),
        if (isAdmin)
          ConsoleNavItem(
            icon: Icons.admin_panel_settings_outlined,
            label: 'SportsHub admin',
            onTap: () => open(CoreRoutes.admin),
          ),
      ],
      footer: [
        const SizedBox(height: 12),
        _SidePromo(
          runsAGym: venues.isNotEmpty,
          onPressed: () => open(venues.isNotEmpty ? GymRoutes.gyms : CoreRoutes.registerVenue),
        ),
      ],
    );
  }
}

/// At the menu's foot, on a photo: putting a gym on SportsHub, or (for
/// someone running one already) the community.
class _SidePromo extends StatelessWidget {
  final bool runsAGym;
  final VoidCallback onPressed;

  const _SidePromo({required this.runsAGym, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          const Positioned.fill(child: GymPhoto('about')),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xF5071229), Color(0xB30A1C45)],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  runsAGym ? 'Stronger together' : 'Put your gym on SportsHub',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16.5, height: 1.2),
                ),
                const SizedBox(height: 6),
                Text(
                  runsAGym
                      ? 'Build a healthier, happier community.'
                      : 'Plans, payments, QR check-in and members in one dashboard.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                _PromoButton(label: runsAGym ? 'Explore gyms' : 'Register', onPressed: onPressed, small: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── The top ───────────────────────────────────────────────────────────────

/// The gym switcher and the account across the top; the date, the greeting
/// and where the membership stands; a photo of training fading into the page
/// on the right (under it on a phone), "Stay Fit. Stay Healthy." on navy in
/// its corner.
class _Hero extends ConsumerWidget {
  final double area;
  final double gutter;
  final _Membership m;
  final List<MyVenue> venues;
  final bool showMenu;

  const _Hero({required this.area, required this.gutter, required this.m, required this.venues, required this.showMenu});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = ConsoleInk.of(context);
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final name = (profile?.fullName ?? '').trim();
    final today = BhutanTime.today();
    final top = MediaQuery.paddingOf(context).top;
    final wide = area >= 900;
    final role = venues.any((v) => v.role == VenueRole.owner)
        ? 'Gym owner'
        : venues.isNotEmpty
            ? 'Gym staff'
            : ((profile?.isAdmin ?? false) ? 'Admin' : 'Member');

    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${_weekdays[today.weekday - 1]}, ${formatShortDate(today)} · Bhutan time',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.brand.muted),
        ),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${greetingAt(BhutanTime.now())}, ${firstName(name)}! '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Icon(Icons.waving_hand_rounded, color: const Color(0xFFF5B43C), size: wide ? 32 : 26),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: wide ? 34 : 26,
            fontWeight: FontWeight.w800,
            color: ink.heading,
            height: 1.15,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(m.status(today), style: TextStyle(fontSize: wide ? 16.5 : 15, color: ink.body, height: 1.5)),
      ],
    );

    if (wide) {
      return SizedBox(
        height: 300 + top,
        child: Stack(
          children: [
            Positioned(top: 0, right: 0, bottom: 0, width: area * 0.56, child: _FadingPhoto(dark: ink.dark)),
            Positioned(right: 0, bottom: 0, width: math.min(340, area * 0.3), height: 168, child: const _Tagline()),
            Positioned(top: top, right: 0, child: _AccountPanel(name: name, role: role)),
            Positioned(
              top: top + 22,
              left: gutter,
              // Clear of the account panel.
              right: 430,
              child: Row(
                children: [
                  if (showMenu) ...[const _MenuButton(), const SizedBox(width: 8)],
                  Flexible(child: _GymPill(m: m, venues: venues)),
                ],
              ),
            ),
            Positioned(left: gutter, top: top + 100, width: area * 0.5, child: words),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, top + 10, gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (showMenu) const _MenuButton(),
              const SizedBox(width: 6),
              const SportsHubLogo(height: 34, markOnly: true),
              const Spacer(),
              const ThemeModeButton(),
              const NotificationBell(),
              IconButton(
                tooltip: 'Account',
                onPressed: () => context.push(CoreRoutes.account),
                icon: _Avatar(name: name, radius: 15),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(alignment: Alignment.centerLeft, child: _GymPill(m: m, venues: venues)),
          const SizedBox(height: 18),
          words,
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 180,
              child: Stack(
                children: [
                  const Positioned.fill(child: GymPhoto('hero', alignment: Alignment(0.35, -0.35))),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    width: math.min(250, area * 0.66),
                    height: 112,
                    child: const _Tagline(compact: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Menu',
      color: ConsoleInk.of(context).heading,
      icon: const Icon(Icons.menu_rounded),
      onPressed: () => Scaffold.of(context).openDrawer(),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final double radius;

  const _Avatar({required this.name, required this.radius});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: BrandColors.orange,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: radius * 0.9),
      ),
    );
  }
}

/// The photo, fading in from the page on its left and at its foot.
class _FadingPhoto extends StatelessWidget {
  final bool dark;

  const _FadingPhoto({required this.dark});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        stops: [0, 0.82, 1],
      ).createShader(rect),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          colors: [Color(0x00000000), Color(0xFF000000)],
          stops: [0, 0.45],
        ).createShader(rect),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const GymPhoto('hero', alignment: Alignment(0.35, -0.35)),
            if (dark) const ColoredBox(color: Color(0x40000000)),
          ],
        ),
      ),
    );
  }
}

/// "Stay Fit. Stay Healthy." on a navy slant, an orange stroke under it.
class _Tagline extends StatelessWidget {
  final bool compact;

  const _Tagline({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _Slant(),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xE60A1C45), Color(0xF7071229)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(compact ? 56 : 80, compact ? 14 : 22, compact ? 18 : 30, compact ? 12 : 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Transform.rotate(
                    angle: -0.06,
                    child: Text(
                      'Stay Fit.\nStay Healthy.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 20 : 28,
                        fontWeight: FontWeight.w800,
                        fontStyle: FontStyle.italic,
                        height: 1.1,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: compact ? 6 : 10),
              CustomPaint(size: Size(compact ? 110 : 160, compact ? 10 : 14), painter: const _Swoosh()),
            ],
          ),
        ),
      ),
    );
  }
}

/// A box with its left edge slanting in towards the top.
class _Slant extends CustomClipper<Path> {
  const _Slant();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * 0.24, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(_Slant oldClipper) => false;
}

/// An orange brush stroke, rising to the right.
class _Swoosh extends CustomPainter {
  const _Swoosh();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.9)
      ..quadraticBezierTo(size.width * 0.55, size.height * 0.05, size.width, size.height * 0.3);
    canvas.drawPath(
      path,
      Paint()
        ..color = BrandColors.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Swoosh oldDelegate) => false;
}

/// Light or dark, notifications and the account, on a card hanging from the
/// top right.
class _AccountPanel extends StatelessWidget {
  final String name;
  final String role;

  const _AccountPanel({required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    const shape = BorderRadius.only(bottomLeft: Radius.circular(28));
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: ink.shadow),
      child: Material(
        color: ink.card,
        borderRadius: shape,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ThemeModeButton(),
              const NotificationBell(),
              Container(
                width: 1,
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: context.brand.glassBorder,
              ),
              Semantics(
                button: true,
                label: 'Account',
                child: InkWell(
                  onTap: () => context.push(CoreRoutes.account),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Avatar(name: name, radius: 20),
                        const SizedBox(width: 10),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 170),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name.isEmpty ? 'You' : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: ink.heading),
                              ),
                              Text(role, style: TextStyle(fontSize: 12.5, color: context.brand.muted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.expand_more_rounded, color: ink.heading),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The member's gym on a white pill; it opens My gym, the gyms they run, or
/// Find a gym.
class _GymPill extends ConsumerWidget {
  final _Membership m;
  final List<MyVenue> venues;

  const _GymPill({required this.m, required this.venues});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = ConsoleInk.of(context);
    final modules = ref.watch(enabledModulesProvider).valueOrNull ?? const <SportsHubModule>[];
    final name = m.current?.gymName ?? m.upcoming?.gymName ?? m.pending.firstOrNull?.gymName ?? venues.firstOrNull?.venue.name;
    final choices = <(IconData, String, String)>[
      if (m.hasPass || m.pending.isNotEmpty) (Icons.qr_code_2_rounded, 'My gym & QR pass', GymRoutes.myGym),
      for (final v in venues) (Icons.space_dashboard_outlined, '${v.venue.name}: dashboard', venueHomeRoute(modules, v.venue)),
      (Icons.search_rounded, 'Find a gym', GymRoutes.gyms),
    ];
    final pill = Container(
      padding: const EdgeInsets.fromLTRB(7, 7, 12, 7),
      decoration: BoxDecoration(
        color: ink.card,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: context.brand.glassBorder),
        boxShadow: ink.shadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: BrandColors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(name == null ? Icons.search_rounded : Icons.apartment_rounded, size: 20, color: BrandColors.orange),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                name ?? 'Find a gym',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: ink.heading),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(choices.length > 1 ? Icons.expand_more_rounded : Icons.arrow_forward_rounded, size: 20, color: ink.heading),
        ],
      ),
    );
    if (choices.length == 1) {
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => context.push(GymRoutes.gyms),
          borderRadius: BorderRadius.circular(30),
          child: pill,
        ),
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Your gyms',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (route) => context.push(route),
      itemBuilder: (_) => [
        for (final (icon, label, route) in choices)
          PopupMenuItem(
            value: route,
            child: Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 12),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
      child: pill,
    );
  }
}

// ─── The numbers' trends ───────────────────────────────────────────────────

/// How much of the plan is left, as a small ring.
class _PlanLeft extends StatelessWidget {
  final double share;

  const _PlanLeft({required this.share});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 42,
      child: CircularProgressIndicator(
        value: share.clamp(0.0, 1.0),
        strokeWidth: 5,
        strokeCap: StrokeCap.round,
        color: BrandColors.blue,
        backgroundColor: context.brand.glassBorder,
        semanticsLabel: 'Plan left',
        semanticsValue: '${(share.clamp(0.0, 1.0) * 100).round()}%',
      ),
    );
  }
}

/// Visits week by week as a line, and the change on the week before.
class _Trend extends StatelessWidget {
  final List<int> weeks;
  final Color color;

  const _Trend({required this.weeks, required this.color});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final change = weeks.last - weeks[weeks.length - 2];
    final (icon, tone) = change > 0
        ? (Icons.arrow_upward_rounded, brand.success)
        : change < 0
            ? (Icons.arrow_downward_rounded, brand.danger)
            : (Icons.remove_rounded, brand.muted);
    return Semantics(
      label: change == 0 ? 'Same as the week before' : '${change.abs()} ${change > 0 ? 'more' : 'fewer'} than the week before',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConsoleSparkline(values: weeks, color: color),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: tone),
              const SizedBox(width: 2),
              Text(
                change == 0 ? 'same' : '${change.abs()}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tone),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The last 7 days, a bar for each: orange where the member checked in.
class _WeekBars extends StatelessWidget {
  final List<bool> days;

  const _WeekBars({required this.days});

  @override
  Widget build(BuildContext context) {
    final n = days.where((d) => d).length;
    return Semantics(
      label: 'Checked in on $n of the last ${days.length} days',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < days.length; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Container(
                  width: 8,
                  height: 20,
                  decoration: BoxDecoration(
                    color: days[i] ? BrandColors.orange : context.brand.glassBorder,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$n of ${days.length} days',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.brand.muted),
          ),
        ],
      ),
    );
  }
}

// ─── Training, membership, shortcuts ───────────────────────────────────────

/// The member's visits as a line: by day over 7 or 30 days, by week over 90.
class _TrainingCard extends StatelessWidget {
  final List<GymCheckIn> checkIns;
  final DateTime today;
  final RevenueRange range;
  final bool fill;
  final ValueChanged<RevenueRange> onRange;

  const _TrainingCard({
    required this.checkIns,
    required this.today,
    required this.range,
    required this.fill,
    required this.onRange,
  });

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final points = visitSeries(checkIns, today, range);
    final total = points.fold<int>(0, (sum, p) => sum + p.amount);
    final chart = ConsoleLineChart(
      points: [for (final p in points) (label: p.label, value: p.amount)],
      format: _visits,
      whole: true,
      name: 'Visits chart',
      noneText: 'no visits',
    );
    return ConsoleCard(
      icon: Icons.insights_rounded,
      title: 'Your training',
      fill: fill,
      trailing: ConsoleRangePicker<RevenueRange>(
        values: _visitRanges,
        value: range,
        label: (r) => r.label,
        onChanged: onRange,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _visits(total),
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ink.heading, height: 1.1),
          ),
          Text(
            total == 0 ? 'No check-ins in the ${range.description}' : 'Check-ins, ${range.description}',
            style: TextStyle(fontSize: 13, color: context.brand.muted),
          ),
          const SizedBox(height: 12),
          if (fill)
            Expanded(child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 220), child: chart))
          else
            SizedBox(height: 240, child: chart),
        ],
      ),
    );
  }
}

/// The current membership as a ring of days left, with its gym and plan; a
/// renewal already paid, and requests waiting; or, with none, how to start.
class _MembershipCard extends StatelessWidget {
  final _Membership m;
  final DateTime today;

  const _MembershipCard({required this.m, required this.today});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final brand = context.brand;
    final c = m.current;

    Widget chip(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        );

    final children = <Widget>[];
    if (c != null) {
      final left = c.daysLeftOn(today);
      final used = math.max(0, c.endDate!.difference(c.startDate!).inDays + 1 - left);
      children.addAll([
        Center(
          child: ConsoleRing(
            size: 150,
            stroke: 16,
            parts: [(left, left <= 7 ? brand.warning : BrandColors.blue), (used, brand.glassBorder)],
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$left', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: ink.heading, height: 1)),
                const SizedBox(height: 2),
                Text(left == 1 ? 'day left' : 'days left', style: TextStyle(fontSize: 12.5, color: brand.muted)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          c.gymName ?? 'Your gym',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink.heading),
        ),
        const SizedBox(height: 2),
        Text(
          '${c.planName} · until ${formatDate(c.endDate!)}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: brand.muted),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            chip('Active', brand.success),
            if (m.upcoming != null)
              chip('Renewed from ${formatShortDate(m.upcoming!.startDate!)}', BrandColors.blue)
            else if (left <= 7)
              chip('Ends soon: renew at the desk', brand.warning),
          ],
        ),
      ]);
    } else if (m.upcoming != null) {
      final u = m.upcoming!;
      children.add(Text(
        'Your ${u.planName} at ${u.gymName ?? 'your gym'} starts on ${formatDate(u.startDate!)}.',
        style: TextStyle(fontSize: 15, color: ink.body, height: 1.5),
      ));
    }
    for (final p in m.pending.take(2)) {
      if (children.isNotEmpty) children.add(Divider(height: 28, color: brand.glassBorder));
      children.add(Row(
        children: [
          Icon(Icons.hourglass_top_rounded, color: brand.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting for ${p.gymName ?? 'the gym'}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink.heading),
                ),
                Text(
                  '${p.planName}: pay ${formatNu(p.price)} at the gym and they will start it.',
                  style: TextStyle(fontSize: 13, color: brand.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ));
    }
    if (children.isEmpty) {
      children.addAll([
        Text('No membership yet', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: ink.heading)),
        const SizedBox(height: 4),
        Text(
          'Join a gym to get your member pass and check in with your phone.',
          style: TextStyle(fontSize: 14, color: ink.body, height: 1.5),
        ),
        const SizedBox(height: 16),
        for (final (i, step) in const ['Find a gym and pick a plan', 'Pay at the gym: cash or mBoB', 'Check in with your QR code'].indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: BrandColors.orange.withValues(alpha: 0.14),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(color: BrandColors.orange, fontWeight: FontWeight.w800, fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(step, style: TextStyle(fontSize: 14, color: ink.body))),
              ],
            ),
          ),
      ]);
    }
    final started = m.hasPass || m.pending.isNotEmpty;
    return ConsoleCard(
      icon: Icons.card_membership_rounded,
      title: 'Your membership',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...children,
          const SizedBox(height: 12),
          Align(
            alignment: c != null ? Alignment.center : Alignment.centerLeft,
            child: ConsoleLink(
              label: started ? 'Open My gym' : 'Find a gym',
              onPressed: () => context.push(started ? GymRoutes.myGym : GymRoutes.gyms),
            ),
          ),
        ],
      ),
    );
  }
}

/// Six shortcuts, and the pass (or Find a gym) on the orange button.
class _ActionsCard extends ConsumerWidget {
  final _Membership m;
  final List<MyVenue> venues;
  final int unread;
  final bool isAdmin;

  /// Pushes the button to the card's foot (the card has a height).
  final bool fill;

  const _ActionsCard({required this.m, required this.venues, required this.unread, required this.isAdmin, required this.fill});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(enabledModulesProvider).valueOrNull ?? const <SportsHubModule>[];
    void go(String route) => context.push(route);
    final tiles = [
      ConsoleActionTile(icon: Icons.search_rounded, label: 'Find a gym', onTap: () => go(GymRoutes.gyms)),
      ConsoleActionTile(icon: Icons.qr_code_2_rounded, label: 'My gym', onTap: () => go(GymRoutes.myGym)),
      // One-word names where a tile is narrow: a long word would break.
      ConsoleActionTile(
        icon: Icons.notifications_none_rounded,
        label: 'Alerts',
        badge: unread,
        onTap: () => go(CoreRoutes.notifications),
      ),
      ConsoleActionTile(icon: Icons.edit_outlined, label: 'Edit profile', onTap: () => go(CoreRoutes.editProfile)),
      if (venues.isEmpty)
        ConsoleActionTile(icon: Icons.add_business_outlined, label: 'Register a gym', onTap: () => go(CoreRoutes.registerVenue))
      else
        ConsoleActionTile(
          icon: Icons.space_dashboard_outlined,
          label: 'Dashboard',
          onTap: () => go(venueHomeRoute(modules, venues.first.venue)),
        ),
      if (isAdmin)
        ConsoleActionTile(icon: Icons.admin_panel_settings_outlined, label: 'Admin', onTap: () => go(CoreRoutes.admin))
      else
        ConsoleActionTile(icon: Icons.person_outline_rounded, label: 'Account', onTap: () => go(CoreRoutes.account)),
    ];
    return ConsoleCard(
      icon: Icons.bolt_rounded,
      title: 'Quick actions',
      fill: fill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConsoleTileGrid(tiles: tiles),
          if (fill) const Spacer(),
          const SizedBox(height: 16),
          ConsoleGlowButton(
            label: m.hasPass ? 'Show my QR pass' : 'Find a gym',
            icon: m.hasPass ? Icons.qr_code_2_rounded : Icons.arrow_forward_rounded,
            onPressed: () => go(m.hasPass ? GymRoutes.myGym : GymRoutes.gyms),
          ),
        ],
      ),
    );
  }
}

// ─── Lately, places, the pass ──────────────────────────────────────────────

/// The member's latest check-ins, requests and memberships, on a timeline.
class _ActivityCard extends StatelessWidget {
  final List<GymActivity> activity;
  final DateTime today;

  const _ActivityCard({required this.activity, required this.today});

  static const _colors = {
    GymActivityKind.checkIn: BrandColors.green,
    GymActivityKind.request: BrandColors.amber,
    GymActivityKind.joined: BrandColors.blue,
    GymActivityKind.renewed: _purple,
  };

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final brand = context.brand;
    String when(DateTime at) {
      final day = BhutanTime.dateOnly(BhutanTime.toBhutan(at));
      if (day == today) return formatTime(at);
      if (day == DateTime(today.year, today.month, today.day - 1)) return 'Yesterday';
      return formatShortDate(day);
    }

    return ConsoleCard(
      icon: Icons.format_list_bulleted_rounded,
      title: 'Recent activity',
      trailing: ConsoleLink(label: 'View all', onPressed: () => context.push(GymRoutes.myGym)),
      child: activity.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Your check-ins and memberships show up here once you join a gym.',
                style: TextStyle(fontSize: 14, color: brand.muted, height: 1.5),
              ),
            )
          : Column(
              children: [
                for (final a in activity)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 76,
                          child: Text(when(a.at), style: TextStyle(fontSize: 12.5, color: brand.muted)),
                        ),
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(color: _colors[a.kind], shape: BoxShape.circle),
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
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// A place on its photo (or [icon] on a soft tile), with a word on where it
/// stands: at the row's end, or under its name where the card is narrow.
class _PlaceRow extends StatelessWidget {
  final String? photo;
  final IconData? icon;
  final String title;
  final String subtitle;
  final (String, Color)? chip;
  final VoidCallback? onTap;

  const _PlaceRow({this.photo, this.icon, required this.title, required this.subtitle, this.chip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    final badge = chip == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: chip!.$2.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(chip!.$1, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: chip!.$2)),
          );
    final picture = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 72,
        height: 56,
        child: photo != null
            ? GymPhoto(photo!)
            : ColoredBox(color: ink.tint, child: Icon(icon, color: BrandColors.orange, size: 26)),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final under = constraints.maxWidth < 400;
                return Row(
                  children: [
                    picture,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink.heading),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: context.brand.muted),
                          ),
                          if (under && badge != null) ...[const SizedBox(height: 6), badge],
                        ],
                      ),
                    ),
                    if (!under && badge != null) ...[const SizedBox(width: 8), badge],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The gyms they run (three of them), each opening its dashboard; with room,
/// registering another.
class _YourGymsCard extends ConsumerWidget {
  final List<MyVenue> venues;

  const _YourGymsCard({required this.venues});

  static const _photos = ['gym', 'indoor', 'about'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final modules = ref.watch(enabledModulesProvider).valueOrNull ?? const <SportsHubModule>[];
    return ConsoleCard(
      icon: Icons.storefront_outlined,
      title: 'Your gyms',
      trailing: venues.length > 3 ? ConsoleLink(label: 'View all', onPressed: () => context.push(CoreRoutes.manage)) : null,
      child: Column(
        children: [
          for (final (i, v) in venues.take(3).indexed)
            _PlaceRow(
              photo: _photos[i % _photos.length],
              title: v.venue.name,
              subtitle: '${_roleLabel(v.role)} · ${v.venue.place}',
              chip: v.venue.isVerified ? ('Verified', brand.success) : ('Being checked', brand.warning),
              onTap: () => context.push(venueHomeRoute(modules, v.venue)),
            ),
          if (venues.length < 3)
            _PlaceRow(
              icon: Icons.add_business_outlined,
              title: 'Register another gym',
              subtitle: 'Run it from the same account',
              onTap: () => context.push(CoreRoutes.registerVenue),
            ),
        ],
      ),
    );
  }
}

/// Gyms now, and the sports on their way.
class _ExploreCard extends StatelessWidget {
  const _ExploreCard();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return ConsoleCard(
      icon: Icons.explore_outlined,
      title: 'Explore SportsHub',
      trailing: ConsoleLink(label: 'Find a gym', onPressed: () => context.push(GymRoutes.gyms)),
      child: Column(
        children: [
          _PlaceRow(
            photo: 'gym',
            title: 'Gym & Fitness',
            subtitle: 'Join a plan, check in by QR',
            chip: ('Open now', brand.success),
            onTap: () => context.push(GymRoutes.gyms),
          ),
          const _PlaceRow(
            photo: 'yoga',
            title: 'Yoga & Wellness',
            subtitle: 'On its way to SportsHub',
            chip: ('Coming soon', BrandColors.blue),
          ),
          const _PlaceRow(
            photo: 'swimming',
            title: 'Swimming',
            subtitle: 'On its way to SportsHub',
            chip: ('Coming soon', BrandColors.blue),
          ),
        ],
      ),
    );
  }
}

/// On a dark photo: the member's QR pass; or, without one, what's next.
class _PassCard extends ConsumerWidget {
  final _Membership m;

  const _PassCard({required this.m});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final userId = ref.watch(currentUserIdProvider);
    final pending = m.pending.firstOrNull;
    final Widget content;
    if (m.hasPass && userId != null) {
      final s = m.current ?? m.upcoming!;
      final code = profile?.memberCode ?? '';
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Member pass', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            '${s.gymName ?? 'Your gym'} · show this at the desk',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: QrImageView(
                  data: MemberQr.encode(userId),
                  size: 116,
                  padding: EdgeInsets.zero,
                  semanticsLabel: 'Your member QR code',
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: BrandColors.navy),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: BrandColors.navy),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'MEMBER CODE',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        code.isEmpty ? '–' : code,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 5),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _PromoButton(label: 'Open My gym', onPressed: () => context.push(GymRoutes.myGym), small: true),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    } else if (pending != null) {
      content = _Promo(
        title: const [TextSpan(text: 'Almost '), TextSpan(text: 'there', style: TextStyle(color: Color(0xFFFF8A3D)))],
        text: 'Pay ${formatNu(pending.price)} at ${pending.gymName ?? 'the gym'} and they will start your ${pending.planName}.',
        button: 'Open My gym',
        onPressed: () => context.push(GymRoutes.myGym),
      );
    } else {
      content = _Promo(
        title: const [
          TextSpan(text: 'Achieve your\n'),
          TextSpan(text: 'fitness goals', style: TextStyle(color: Color(0xFFFF8A3D))),
        ],
        text: 'Join a gym on SportsHub and become the best version of yourself.',
        button: 'Join now',
        onPressed: () => context.push(GymRoutes.gyms),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          const Positioned.fill(child: GymPhoto('indoor', alignment: Alignment.centerRight)),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFA0A1C45), Color(0xE00A1C45), Color(0x660A1C45)],
                  stops: [0, 0.55, 1],
                ),
              ),
            ),
          ),
          const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: GymStripesPainter()))),
          Padding(padding: const EdgeInsets.all(24), child: content),
        ],
      ),
    );
  }
}

/// A headline (part of it orange), a line under it and a button, on dark.
class _Promo extends StatelessWidget {
  final List<TextSpan> title;
  final String text;
  final String button;
  final VoidCallback onPressed;

  const _Promo({required this.title, required this.text, required this.button, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(children: title),
          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.4),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 14.5, height: 1.5)),
        ),
        const SizedBox(height: 18),
        _PromoButton(label: button, onPressed: onPressed),
      ],
    );
  }
}

class _PromoButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool small;

  const _PromoButton({required this.label, required this.onPressed, this.small = false});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: BrandColors.orange,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        minimumSize: Size(0, small ? 36 : 44),
        padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20, vertical: small ? 8 : 12),
        textStyle: TextStyle(fontSize: small ? 13 : 14.5, fontWeight: FontWeight.w700, fontFamily: gymFont),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward_rounded, size: small ? 16 : 18),
        ],
      ),
    );
  }
}

/// SportsHub admin, for admins: venues to verify and modules.
class _AdminCard extends StatelessWidget {
  const _AdminCard();

  @override
  Widget build(BuildContext context) {
    final ink = ConsoleInk.of(context);
    return Material(
      color: ink.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => context.push(CoreRoutes.admin),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: BrandColors.orange.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: BrandColors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.admin_panel_settings_outlined, color: BrandColors.orange),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SportsHub admin', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink.heading)),
                    Text(
                      'Verify new venues, and turn modules on or off',
                      style: TextStyle(fontSize: 13, color: context.brand.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: ink.heading),
            ],
          ),
        ),
      ),
    );
  }
}

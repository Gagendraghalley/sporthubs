import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_repository.dart';
import '../gym_permissions.dart';
import '../gym_routes.dart';
import 'current_gym.dart';

/// The gym being worked at, from a page's [path]: a gym page
/// (`/gyms/<id>/manage/...`) or one of the core's pages for it
/// (`/manage/<id>/staff`, `/manage/<id>/edit`).
String? gymIdInPath(String path) =>
    GymRoutes.gymIdIn(path) ?? RegExp(r'^/manage/([0-9a-fA-F-]{36})(/|$)').firstMatch(path)?.group(1);

/// Gym management's section of the side menu: the gym (with a switcher for
/// someone at several), then its pages as their role there allows, under
/// Front desk, Business and Manage; and its shortcuts. For someone with no
/// gym yet, the way to set one up.
ServiceNav gymNavigation(WidgetRef ref, String location,
    {required String name, required IconData icon, required Color color}) {
  final gyms = ref.watch(myGymsProvider).valueOrNull ?? const <MyVenue>[];
  final gym = currentGym(gyms, pathGymId: gymIdInPath(location), remembered: ref.watch(rememberedGymProvider));
  final setUp = CoreRoutes.registerVenueFor(gymVenueType);
  if (gym == null) {
    return ServiceNav(
      key: gymModuleKey,
      name: name,
      icon: icon,
      color: color,
      tagline: 'Not set up yet',
      isSetUp: false,
      homeRoute: setUp,
      sections: [
        NavSection(items: [NavDestination(label: 'Set up your gym', icon: Icons.rocket_launch_outlined, route: setUp)]),
      ],
      actions: [
        ServiceAction(label: 'Set up your gym', icon: Icons.add_business_rounded, route: setUp, hint: 'Then packages, staff and members'),
      ],
    );
  }

  final id = gym.venue.id;
  final a = gym.access;
  final register = GymRoutes.registerMemberFor(id);
  final sections = [
    NavSection(items: [
      NavDestination(label: 'Dashboard', icon: Icons.space_dashboard_outlined, route: GymRoutes.dashboardFor(id), exact: true),
    ]),
    NavSection(title: 'Front desk', items: [
      if (a.can(GymPermission.checkIn))
        NavDestination(label: 'Check-in', icon: Icons.qr_code_scanner_rounded, route: GymRoutes.checkInFor(id)),
      if (a.can(GymPermission.members))
        NavDestination(label: 'Members', icon: Icons.groups_outlined, route: GymRoutes.membersFor(id), notUnder: [register]),
      if (a.can(GymPermission.register))
        NavDestination(label: 'Register member', icon: Icons.person_add_alt_1_outlined, route: register),
    ]),
    NavSection(title: 'Business', items: [
      if (a.can(GymPermission.plans))
        NavDestination(label: 'Memberships & packages', icon: Icons.sell_outlined, route: GymRoutes.plansFor(id)),
      if (a.can(VenuePermission.income))
        NavDestination(label: 'Payments & income', icon: Icons.payments_outlined, route: GymRoutes.incomeFor(id)),
      if (a.can(GymPermission.members))
        NavDestination(label: 'Reports & analytics', icon: Icons.insights_rounded, route: GymRoutes.reportsFor(id)),
    ]),
    NavSection(title: 'Manage', items: [
      if (a.can(VenuePermission.staff))
        NavDestination(label: 'Staff', icon: Icons.badge_outlined, route: CoreRoutes.venueStaffFor(id)),
      if (a.can(VenuePermission.edit))
        NavDestination(label: 'Gym settings', icon: Icons.tune_rounded, route: CoreRoutes.editVenueFor(id)),
    ]),
  ];
  return ServiceNav(
    key: gymModuleKey,
    name: name,
    icon: icon,
    color: color,
    tagline: gym.roleName,
    homeRoute: GymRoutes.dashboardFor(id),
    scope: ServiceScope(
      currentId: id,
      label: gym.venue.name,
      detail: gym.venue.place,
      options: [for (final g in gyms) ServiceScopeOption(id: g.venue.id, label: g.venue.name, detail: g.venue.place)],
      onSelect: (gymId) {
        ref.read(rememberedGymProvider.notifier).state = gymId;
        return GymRoutes.dashboardFor(gymId);
      },
      addLabel: 'Register another gym',
      addRoute: setUp,
    ),
    sections: [for (final s in sections) if (s.items.isNotEmpty) s],
    actions: [
      if (a.can(GymPermission.checkIn))
        ServiceAction(
            label: 'Check in a member', icon: Icons.qr_code_scanner_rounded, route: GymRoutes.checkInFor(id), hint: 'Scan their QR card'),
      if (a.can(GymPermission.register))
        ServiceAction(label: 'Register a member', icon: Icons.person_add_alt_1_rounded, route: register, hint: 'Details, photo and package'),
      if (a.can(GymPermission.plans))
        ServiceAction(
            label: 'New package', icon: Icons.add_card_rounded, route: GymRoutes.newPlanFor(id), hint: 'What the desk sells'),
      if (a.can(VenuePermission.staff))
        ServiceAction(
            label: 'Add staff', icon: Icons.group_add_outlined, route: CoreRoutes.venueStaffFor(id), hint: 'And choose their role'),
    ],
  );
}

/// Gym management's card on Overview and My services: the gym, its numbers
/// today, and the way in; for someone with no gym, how to start.
class GymOverviewCard extends ConsumerWidget {
  final String name;
  final IconData icon;
  final Color color;

  const GymOverviewCard({super.key, required this.name, required this.icon, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gyms = ref.watch(myGymsProvider).valueOrNull ?? const <MyVenue>[];
    final gym = currentGym(gyms, remembered: ref.watch(rememberedGymProvider));
    if (gym == null) return _start(context);
    final id = gym.venue.id;
    final a = gym.access;
    final dash = ref.watch(gymDashboardProvider(id)).valueOrNull;
    final more = gyms.length - 1;
    return ServiceCard(
      icon: icon,
      color: color,
      name: name,
      subtitle: '${gym.venue.name} · ${gym.roleName}${more > 0 ? ' · +$more more' : ''}',
      status: gym.venue.isVerified
          ? null
          : StatusChip(label: 'Being verified', color: context.brand.warning, icon: Icons.hourglass_top_rounded),
      onOpen: () => context.go(GymRoutes.dashboardFor(id)),
      actions: [
        FilledButton.icon(
          onPressed: () => context.go(GymRoutes.dashboardFor(id)),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.space_dashboard_outlined, size: 18),
          label: const Text('Open dashboard'),
        ),
        if (a.can(GymPermission.checkIn))
          OutlinedButton.icon(
            onPressed: () => context.go(GymRoutes.checkInFor(id)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
            label: const Text('Check in'),
          ),
        if (a.can(GymPermission.register))
          OutlinedButton.icon(
            onPressed: () => context.go(GymRoutes.registerMemberFor(id)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Register member'),
          ),
      ],
      child: dash == null
          ? const Shimmer(
              child: Row(children: [
                Expanded(child: SkeletonBox(height: 64, radius: 14)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 64, radius: 14)),
              ]),
            )
          : ServiceStats(stats: [
              ServiceStat(label: 'Active members', value: dash.active, color: BrandColors.blue),
              ServiceStat(label: 'Check-ins today', value: dash.checkInsToday, color: BrandColors.green),
              ServiceStat(label: 'Ending this week', value: dash.expiringSoon, color: BrandColors.amber),
              if (dash.incomeThisMonth != null)
                ServiceStat(
                  label: 'Income this month',
                  value: dash.incomeThisMonth!,
                  format: (v) => formatNu(v.round()),
                  color: BrandColors.orange,
                ),
            ]),
    );
  }

  /// No gym yet: the three steps, and the way in.
  Widget _start(BuildContext context) {
    final muted = context.brand.muted;
    Widget step(int n, String title, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Text('$n', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$title  ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: text, style: TextStyle(color: muted)),
                ])),
              ),
            ],
          ),
        );
    return ServiceCard(
      icon: icon,
      color: color,
      name: name,
      subtitle: 'Run your gym on SportsHub',
      status: StatusChip(label: 'Not set up', color: context.colors.tertiary),
      onOpen: () => context.go(CoreRoutes.registerVenueFor(gymVenueType)),
      actions: [
        FilledButton.icon(
          onPressed: () => context.go(CoreRoutes.registerVenueFor(gymVenueType)),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.rocket_launch_outlined, size: 18),
          label: const Text('Set up your gym'),
        ),
        Text(
          'Work at a gym? Its owner adds you on its Staff page; it shows here as soon as they do.',
          style: TextStyle(color: muted, fontSize: 12.5),
        ),
      ],
      child: Column(
        children: [
          step(1, 'Register your gym.', 'Its name, place and how members pay.'),
          step(2, 'Add your packages.', 'What the front desk sells, and the prices.'),
          step(3, 'Register members.', 'Photo, package and a QR card they show at the counter.'),
        ],
      ),
    );
  }
}

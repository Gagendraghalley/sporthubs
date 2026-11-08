import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportshub_core/sportshub_core.dart';

import 'dashboard/gym_dashboard_page.dart';
import 'data/gym_repository.dart';
import 'gym_permissions.dart';
import 'gym_routes.dart';
import 'screens/check_in_screen.dart';
import 'screens/member_registered_screen.dart';
import 'screens/members_screens.dart';
import 'screens/public_screens.dart';
import 'screens/reports_screen.dart';
import 'screens/staff_screens.dart';
import 'shell/gym_navigation.dart';
import 'welcome/gym_welcome_page.dart';

/// Gym management, the platform's first service. A gym's front desk
/// registers members (details, webcam photo, package for a number of
/// months), gives them a QR card (sent on WhatsApp) and checks them in with
/// it; owners set packages and prices, see income and reports, and choose
/// their staff's roles. Visitors see the public Welcome page and the gyms'
/// public pages.
class GymModule extends SportsHubModule {
  const GymModule();

  @override
  String get key => gymModuleKey;

  @override
  String get name => 'Gym management';

  @override
  String get description => 'Register members, sell packages and check them in with a QR card.';

  @override
  IconData get icon => Icons.fitness_center_rounded;

  @override
  Color get color => BrandColors.orange;

  @override
  List<String> get basePaths => const [GymRoutes.gyms];

  @override
  List<String> get publicPaths => const [GymRoutes.gyms, GymRoutes.gym];

  @override
  List<VenueKind> get venueKinds => const [
        VenueKind(
          key: gymVenueType,
          label: 'Gym',
          description: 'A gym or fitness centre with membership packages',
          icon: Icons.fitness_center_rounded,
        ),
      ];

  /// Every page in the platform's frame. The register's 'new' comes before
  /// ':memberId', so it isn't taken for a member.
  @override
  List<RouteBase> get routes => [
        GoRoute(path: GymRoutes.gyms, builder: (_, __) => const GymListScreen()),
        GoRoute(path: GymRoutes.gym, builder: (_, s) => GymDetailsScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.dashboard, builder: (_, s) => GymDashboardPage(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.checkIn, builder: (_, s) => CheckInScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.members, builder: (_, s) => MembersScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.registerMember, builder: (_, s) => RegisterMemberScreen(venueId: s.pathParameters['id']!)),
        GoRoute(
          path: GymRoutes.editMember,
          builder: (_, s) => RegisterMemberScreen(venueId: s.pathParameters['id']!, memberId: s.pathParameters['memberId']),
        ),
        GoRoute(
          path: GymRoutes.memberRegistered,
          builder: (_, s) => MemberRegisteredScreen(venueId: s.pathParameters['id']!, memberId: s.pathParameters['memberId']!),
        ),
        GoRoute(
          path: GymRoutes.member,
          builder: (_, s) => GymMemberScreen(venueId: s.pathParameters['id']!, memberId: s.pathParameters['memberId']!),
        ),
        GoRoute(
          path: GymRoutes.plans,
          builder: (_, s) => PlansScreen(venueId: s.pathParameters['id']!, openNew: s.uri.queryParameters['new'] == '1'),
        ),
        GoRoute(path: GymRoutes.income, builder: (_, s) => IncomeScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.reports, builder: (_, s) => ReportsScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.requests, redirect: (_, s) => GymRoutes.membersFor(s.pathParameters['id']!)),
      ];

  @override
  ServiceNav? navigation(WidgetRef ref, String location) =>
      gymNavigation(ref, location, name: name, icon: icon, color: color);

  @override
  Widget? buildOverviewCard(BuildContext context) => GymOverviewCard(name: name, icon: icon, color: color);

  /// For the core's pages that list a venue's pages.
  @override
  List<ModuleMenuItem> managerMenuItems(Venue venue, VenueAccess access) => [
        ModuleMenuItem(
          title: 'Dashboard',
          subtitle: 'Today, revenue, members and what just happened',
          icon: Icons.space_dashboard_rounded,
          route: GymRoutes.dashboardFor(venue.id),
        ),
        if (access.can(GymPermission.checkIn))
          ModuleMenuItem(
            title: 'Check-in',
            subtitle: 'Scan their QR card or type their member code',
            icon: Icons.qr_code_scanner_rounded,
            route: GymRoutes.checkInFor(venue.id),
          ),
        if (access.can(GymPermission.members))
          ModuleMenuItem(
            title: 'Members',
            subtitle: 'The register: packages, cards and visits',
            icon: Icons.groups_rounded,
            route: GymRoutes.membersFor(venue.id),
          ),
        if (access.can(GymPermission.register))
          ModuleMenuItem(
            title: 'Register member',
            subtitle: 'Details, photo and package',
            icon: Icons.person_add_alt_1_rounded,
            route: GymRoutes.registerMemberFor(venue.id),
          ),
        if (access.can(GymPermission.plans))
          ModuleMenuItem(
            title: 'Memberships & packages',
            subtitle: 'What the front desk sells, and the prices',
            icon: Icons.sell_outlined,
            route: GymRoutes.plansFor(venue.id),
          ),
        if (access.can(VenuePermission.income))
          ModuleMenuItem(
            title: 'Payments & income',
            subtitle: 'Payments month by month',
            icon: Icons.payments_outlined,
            route: GymRoutes.incomeFor(venue.id),
          ),
        if (access.can(GymPermission.members))
          ModuleMenuItem(
            title: 'Reports & analytics',
            subtitle: 'Members, visits, packages and revenue over time',
            icon: Icons.insights_rounded,
            route: GymRoutes.reportsFor(venue.id),
          ),
      ];

  @override
  Widget? buildWelcome(BuildContext context) => const GymWelcomePage();

  @override
  String? managerHomeRoute(Venue venue) => GymRoutes.dashboardFor(venue.id);
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sportshub_core/sportshub_core.dart';

import 'dashboard/gym_dashboard_page.dart';
import 'data/gym_repository.dart';
import 'home/gym_home_page.dart';
import 'gym_routes.dart';
import 'screens/check_in_screen.dart';
import 'screens/member_screens.dart';
import 'screens/staff_screens.dart';
import 'welcome/gym_welcome_page.dart';
import 'widgets/gym_widgets.dart';

/// Module 2: gym membership. Members find a gym, ask for a plan, pay the gym
/// (mBoB or cash), and check in with their QR code; the gym's staff confirm
/// payments and check members in; owners set plans and see income.
class GymModule extends SportsHubModule {
  const GymModule();

  @override
  String get key => gymModuleKey;

  @override
  String get name => 'Gym membership';

  @override
  String get description => 'Find a gym, join a plan and check in with your phone.';

  @override
  IconData get icon => Icons.fitness_center_rounded;

  @override
  List<String> get basePaths => const [GymRoutes.gyms, GymRoutes.myGym];

  @override
  List<String> get publicPaths => const [GymRoutes.gyms, GymRoutes.gym];

  @override
  List<VenueKind> get venueKinds => const [
        VenueKind(
          key: gymVenueType,
          label: 'Gym',
          description: 'A gym or fitness centre with membership plans',
          icon: Icons.fitness_center_rounded,
        ),
      ];

  @override
  List<RouteBase> get routes => [
        GoRoute(path: GymRoutes.gyms, builder: (_, __) => const GymListScreen()),
        GoRoute(path: GymRoutes.myGym, builder: (_, __) => const MyGymScreen()),
        GoRoute(path: GymRoutes.gym, builder: (_, s) => GymDetailsScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.dashboard, builder: (_, s) => GymDashboardPage(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.checkIn, builder: (_, s) => CheckInScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.requests, builder: (_, s) => RequestsScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.members, builder: (_, s) => MembersScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.plans, builder: (_, s) => PlansScreen(venueId: s.pathParameters['id']!)),
        GoRoute(path: GymRoutes.income, builder: (_, s) => IncomeScreen(venueId: s.pathParameters['id']!)),
      ];

  @override
  List<ModuleMenuItem> playerMenuItems() => const [
        ModuleMenuItem(
          title: 'Find a gym',
          subtitle: 'Plans and prices near you',
          icon: Icons.fitness_center_rounded,
          route: GymRoutes.gyms,
        ),
        ModuleMenuItem(
          title: 'My gym',
          subtitle: 'Your membership card, days left and check-ins',
          icon: Icons.qr_code_2_rounded,
          route: GymRoutes.myGym,
        ),
      ];

  @override
  List<ModuleMenuItem> managerMenuItems(Venue venue, String role) => [
        ModuleMenuItem(
          title: 'Dashboard',
          subtitle: 'Today, revenue, members and what just happened',
          icon: Icons.space_dashboard_rounded,
          route: GymRoutes.dashboardFor(venue.id),
        ),
        ModuleMenuItem(
          title: 'Check in members',
          subtitle: 'Scan their QR code or type their code',
          icon: Icons.qr_code_scanner_rounded,
          route: GymRoutes.checkInFor(venue.id),
        ),
        ModuleMenuItem(
          title: 'Membership requests',
          subtitle: 'Confirm payments to activate memberships',
          icon: Icons.inbox_outlined,
          route: GymRoutes.requestsFor(venue.id),
        ),
        ModuleMenuItem(
          title: 'Members',
          subtitle: 'Active, ending soon and past members',
          icon: Icons.groups_rounded,
          route: GymRoutes.membersFor(venue.id),
        ),
        if (VenueRole.canManage(role)) ...[
          ModuleMenuItem(
            title: 'Plans and prices',
            subtitle: 'What members can buy',
            icon: Icons.sell_outlined,
            route: GymRoutes.plansFor(venue.id),
          ),
          ModuleMenuItem(
            title: 'Income',
            subtitle: 'Payments month by month',
            icon: Icons.payments_outlined,
            route: GymRoutes.incomeFor(venue.id),
          ),
        ],
        ModuleMenuItem(
          title: "The gym's public page",
          subtitle: 'What members see',
          icon: Icons.storefront_outlined,
          route: GymRoutes.gymFor(venue.id),
        ),
      ];

  @override
  Widget? buildHomeSection(BuildContext context) => const GymHomeSection();

  @override
  Widget? buildWelcome(BuildContext context) => const GymWelcomePage();

  @override
  Widget? buildHome(BuildContext context) => const GymHomePage();

  @override
  String? managerHomeRoute(Venue venue) => GymRoutes.dashboardFor(venue.id);

  @override
  Widget? buildManagerSection(BuildContext context, Venue venue, String role) =>
      GymManagerStats(venueId: venue.id, showIncome: VenueRole.canManage(role));
}

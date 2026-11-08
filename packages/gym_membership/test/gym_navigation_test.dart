import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:sportshub_core/sportshub_core.dart';

const gymId = '0f8e3a1c-2b4d-4e5f-8a9b-0c1d2e3f4a5b';
const otherId = '1f8e3a1c-2b4d-4e5f-8a9b-0c1d2e3f4a5c';

Venue venue(String id, String name) => Venue.fromJson({
      'id': id,
      'type': 'gym',
      'name': name,
      'dzongkhag': 'Thimphu',
      'verification_status': 'verified',
      'created_at': '2026-11-01T00:00:00Z',
    });

/// Who is signed in: the gyms they run (role and its permissions) and
/// whether they're on the SportsHub team.
List<Override> person({List<MyVenue> gyms = const [], bool team = false}) => [
      currentUserIdProvider.overrideWithValue('u1'),
      myProfileProvider.overrideWith((ref) async => Profile.fromJson({'id': 'u1', 'full_name': 'Gagendra Ghalley'})),
      myAccessProvider.overrideWith((ref) async => PlatformAccess(isSuperAdmin: team, isActive: true, permissions: const {})),
      myVenuesProvider.overrideWith((ref) async => gyms),
      enabledModulesProvider.overrideWith((ref) async => const [GymModule()]),
      pendingVenuesProvider.overrideWith((ref) async => const []),
      unreadCountProvider.overrideWithValue(2),
    ];

final owner = [MyVenue(venue(gymId, 'Druk Fitness Club'), VenueRole.owner), MyVenue(venue(otherId, 'Paro Power Gym'), VenueRole.owner)];
final frontDesk = [
  MyVenue(venue(gymId, 'Druk Fitness Club'), VenueRole.staff,
      roleName: 'Front desk',
      permissions: const {GymPermission.register, GymPermission.members, GymPermission.payments, GymPermission.checkIn}),
];

/// The platform's frame (the gym is one service in it) with a stand-in for
/// each page.
Future<GoRouter> showApp(WidgetTester tester, Size size, List<Override> who,
    {bool dark = false, String at = '/gyms/$gymId/manage'}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget page(String name) => AppPage(title: name, body: Center(child: Text('Page: $name')));
  final router = GoRouter(
    initialLocation: at,
    routes: [
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          for (final (path, name) in [
            (CoreRoutes.home, 'Overview'),
            (CoreRoutes.services, 'My services'),
            (CoreRoutes.account, 'Account'),
            (CoreRoutes.notifications, 'Notifications'),
            (CoreRoutes.admin, 'Admin'),
            (CoreRoutes.registerVenue, 'Register a venue'),
            (CoreRoutes.registerVenueForm, 'Register a gym'),
            (CoreRoutes.venueStaff, 'Staff'),
            (CoreRoutes.editVenue, 'Gym settings'),
            (GymRoutes.dashboard, 'Dashboard'),
            (GymRoutes.checkIn, 'Check-in'),
            (GymRoutes.members, 'Members'),
            (GymRoutes.registerMember, 'Register member'),
            (GymRoutes.plans, 'Packages'),
            (GymRoutes.income, 'Income'),
            (GymRoutes.reports, 'Reports'),
          ])
            GoRoute(path: path, builder: (_, __) => page(name)),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: who,
    child: MaterialApp.router(theme: dark ? AppTheme.dark : AppTheme.light, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

Finder inMenu(String label) => find.descendant(of: find.byType(PlatformSidebar), matching: find.text(label));

bool selected(WidgetTester tester, String label) =>
    tester.widget<SideNavTile>(find.ancestor(of: inMenu(label), matching: find.byType(SideNavTile))).selected;

void main() {
  const computer = Size(1440, 1000);
  const phone = Size(390, 844);

  testWidgets("an owner's menu: the platform, then Gym management with their gym and its pages, grouped", (tester) async {
    final router = await showApp(tester, computer, person(gyms: owner));
    for (final label in ['Overview', 'My services', 'Notifications', 'Gym management', 'Druk Fitness Club']) {
      expect(inMenu(label), findsOneWidget, reason: label);
    }
    for (final label in [
      'Dashboard', 'Check-in', 'Members', 'Register member', 'Memberships & packages', 'Payments & income',
      'Reports & analytics', 'Staff', 'Gym settings',
    ]) {
      expect(inMenu(label), findsOneWidget, reason: label);
    }
    for (final heading in ['Front desk', 'Business', 'Manage']) {
      expect(inMenu(heading), findsOneWidget, reason: heading);
    }
    expect(inMenu('ADMINISTRATION'), findsNothing);
    expect(selected(tester, 'Dashboard'), isTrue);

    await tester.tap(inMenu('Members'));
    await tester.pumpAndSettle();
    expect(find.text('Page: Members'), findsOneWidget);
    expect(selected(tester, 'Members'), isTrue);
    expect(selected(tester, 'Dashboard'), isFalse);
    expect(router.routerDelegate.currentConfiguration.uri.path, GymRoutes.membersFor(gymId));
    // The page says whose it is: the service and the gym, over its title.
    expect(find.text('Gym management · Druk Fitness Club'), findsOneWidget);
    expect(find.byTooltip('Menu'), findsNothing);
  });

  testWidgets("the core's pages for the gym (Staff, Gym settings) are the gym's in the menu", (tester) async {
    await showApp(tester, computer, person(gyms: owner), at: CoreRoutes.venueStaffFor(otherId));
    expect(selected(tester, 'Staff'), isTrue);
    expect(inMenu('Paro Power Gym'), findsOneWidget, reason: 'the gym in the address');
  });

  testWidgets('the front desk sees only what its role allows', (tester) async {
    await showApp(tester, computer, person(gyms: frontDesk));
    for (final label in ['Check-in', 'Members', 'Register member', 'Reports & analytics']) {
      expect(inMenu(label), findsOneWidget, reason: label);
    }
    for (final hidden in ['Memberships & packages', 'Payments & income', 'Staff', 'Gym settings', 'Manage']) {
      expect(inMenu(hidden), findsNothing, reason: hidden);
    }
    expect(inMenu('Front desk'), findsWidgets, reason: 'their role, and the heading');
  });

  testWidgets('no gym yet: the service offers setting one up; the team get Administration', (tester) async {
    await showApp(tester, computer, person(team: true), at: CoreRoutes.home);
    // The only service: open from the start.
    expect(inMenu('Set up your gym'), findsOneWidget);
    expect(inMenu('Not set up yet'), findsOneWidget);
    expect(inMenu('Dashboard'), findsNothing);
    expect(inMenu('ADMINISTRATION'), findsOneWidget);
  });

  testWidgets('switching gyms, and registering another, from the gym at the top of its section', (tester) async {
    final router = await showApp(tester, computer, person(gyms: owner));
    await tester.tap(inMenu('Druk Fitness Club'));
    await tester.pumpAndSettle();
    expect(find.text('Register another gym'), findsOneWidget);
    await tester.tap(find.text('Paro Power Gym').last);
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, GymRoutes.dashboardFor(otherId));
    expect(inMenu('Paro Power Gym'), findsOneWidget);
  });

  testWidgets('the New menu has the gym shortcuts the role allows', (tester) async {
    await showApp(tester, computer, person(gyms: frontDesk));
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    expect(find.text('Check in a member'), findsOneWidget);
    expect(find.text('Register a member'), findsOneWidget);
    expect(find.text('New package'), findsNothing);
  });

  testWidgets('the menu folds to its icons and opens out again', (tester) async {
    await showApp(tester, computer, person(gyms: owner));
    expect(tester.getSize(find.byType(PlatformSidebar)).width, sideMenuWidth);
    await tester.tap(find.byTooltip('Collapse menu'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PlatformSidebar)).width, sideMenuFoldedWidth);
    await tester.tap(find.byTooltip('Expand menu'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(PlatformSidebar)).width, sideMenuWidth);
  });

  testWidgets("on a phone the menu is a drawer, opened from the page's bar", (tester) async {
    await showApp(tester, phone, person(gyms: owner));
    expect(find.byType(PlatformSidebar), findsNothing);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Collapse menu'), findsNothing);
    await tester.tap(inMenu('Check-in'));
    await tester.pumpAndSettle();
    expect(find.text('Page: Check-in'), findsOneWidget);
    expect(find.byType(PlatformSidebar), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('the frame fits a laptop, open and folded, ${dark ? 'dark' : 'light'}', (tester) async {
      await showApp(tester, const Size(1280, 800), person(gyms: owner, team: true), dark: dark);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Collapse menu'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

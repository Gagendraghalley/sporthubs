import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sportshub_core/sportshub_core.dart';

/// A stand-in service: its pages under `/<key>`, a heading over the second.
class _Service extends SportsHubModule {
  @override
  final String key;
  @override
  final String name;

  const _Service(this.key, this.name);

  @override
  String get description => 'The $name service';
  @override
  IconData get icon => Icons.storefront_rounded;
  @override
  List<String> get basePaths => ['/$key'];

  @override
  ServiceNav? navigation(WidgetRef ref, String location) => ServiceNav(
        key: key,
        name: name,
        icon: icon,
        color: BrandColors.green,
        tagline: 'Owner',
        homeRoute: '/$key',
        sections: [
          NavSection(items: [NavDestination(label: '$name home', icon: Icons.home_rounded, route: '/$key', exact: true)]),
          NavSection(title: 'Work', items: [NavDestination(label: '$name orders', icon: Icons.list_rounded, route: '/$key/orders')]),
        ],
        actions: [ServiceAction(label: 'New $name order', icon: Icons.add_rounded, route: '/$key/orders')],
      );
}

/// The platform's frame with [services], a stand-in page at every path.
Future<GoRouter> showShell(WidgetTester tester, List<SportsHubModule> services,
    {String at = '/home', Size size = const Size(1440, 1000), bool team = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: at,
    routes: [
      ShellRoute(
        builder: (_, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/:a', builder: (_, s) => AppPage(title: 'Page ${s.uri.path}', body: const SizedBox())),
          GoRoute(path: '/:a/:b', builder: (_, s) => AppPage(title: 'Page ${s.uri.path}', body: const SizedBox())),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('u1'),
      enabledModulesProvider.overrideWith((ref) async => services),
      myProfileProvider.overrideWith((ref) async => Profile.fromJson({'id': 'u1', 'full_name': 'Pema Dorji'})),
      myAccessProvider.overrideWith((ref) async => PlatformAccess(isSuperAdmin: team, isActive: true, permissions: const {})),
      pendingVenuesProvider.overrideWith((ref) async => const []),
      unreadCountProvider.overrideWithValue(3),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

Finder inMenu(String text) => find.descendant(of: find.byType(PlatformSidebar), matching: find.text(text));

bool selected(WidgetTester tester, String label) =>
    tester.widget<SideNavTile>(find.ancestor(of: inMenu(label), matching: find.byType(SideNavTile))).selected;

void main() {
  const shop = _Service('shop', 'Shop');
  const cafe = _Service('cafe', 'Cafe');

  testWidgets('signed in, a page sits in the frame: the platform, then each service', (tester) async {
    await showShell(tester, const [shop, cafe]);
    for (final label in ['Overview', 'My services', 'Notifications', 'SERVICES', 'Shop', 'Cafe']) {
      expect(inMenu(label), findsOneWidget, reason: label);
    }
    expect(selected(tester, 'Overview'), isTrue);
    expect(inMenu('Administration'.toUpperCase()), findsNothing, reason: 'not on the team');
  });

  testWidgets('visitors get the page alone', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [currentUserIdProvider.overrideWithValue(null)],
      child: const MaterialApp(home: AppShell(location: '/home', child: Text('the page'))),
    ));
    expect(find.byType(PlatformSidebar), findsNothing);
    expect(find.text('the page'), findsOneWidget);
  });

  testWidgets("the open page's service is open, its page marked; the others fold to one line", (tester) async {
    await showShell(tester, const [shop, cafe], at: '/cafe/orders');
    expect(selected(tester, 'Cafe orders'), isTrue);
    expect(selected(tester, 'Cafe home'), isFalse, reason: 'exact: the home is only its own page');
    expect(inMenu('Shop orders'), findsNothing, reason: 'folded away, not just hidden');
    // The page knows its service: its name over the title, its shortcuts.
    expect(find.text('Cafe'), findsWidgets);
    expect(find.text('New'), findsOneWidget);
  });

  testWidgets('a service opens from its line, and the one open closes', (tester) async {
    await showShell(tester, const [shop, cafe], at: '/cafe');
    await tester.tap(inMenu('Shop'));
    await tester.pumpAndSettle();
    expect(inMenu('Shop orders'), findsOneWidget);
    expect(inMenu('Cafe orders'), findsNothing);
    await tester.tap(inMenu('Shop orders'));
    await tester.pumpAndSettle();
    expect(selected(tester, 'Shop orders'), isTrue);
  });

  testWidgets('twenty services stay one short list, with a box to find one', (tester) async {
    final many = [for (var i = 1; i <= 20; i++) _Service('s$i', 'Service $i')];
    await showShell(tester, many, at: '/s7/orders');
    expect(find.text('20'), findsOneWidget, reason: 'how many, by the heading');
    expect(inMenu('Service 7 orders'), findsOneWidget);
    expect(find.descendant(of: find.byType(PlatformSidebar), matching: find.textContaining('orders')), findsOneWidget,
        reason: "only the open service's pages");
    await tester.enterText(find.widgetWithText(TextField, 'Find a service'), 'service 1');
    await tester.pumpAndSettle();
    expect(inMenu('Service 12'), findsOneWidget);
    expect(inMenu('Service 7'), findsNothing);
  });

  testWidgets('folded, the menu is icons; a service opens its pages beside it', (tester) async {
    await showShell(tester, const [shop, cafe], at: '/shop');
    await tester.tap(find.byTooltip('Collapse menu'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PlatformSidebar)).width, sideMenuFoldedWidth);
    expect(inMenu('Overview'), findsNothing);
    await tester.tap(find.byTooltip('Cafe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cafe orders').last);
    await tester.pumpAndSettle();
    expect(find.text('Page /cafe/orders'), findsOneWidget);
    await tester.tap(find.byTooltip('Expand menu'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PlatformSidebar)).width, sideMenuWidth);
  });

  testWidgets("the SportsHub team get Administration, as a section like a service's", (tester) async {
    await showShell(tester, const [shop], at: '/admin', team: true);
    expect(inMenu('ADMINISTRATION'), findsOneWidget);
    expect(selected(tester, 'Admin home'), isTrue);
    expect(inMenu('Users'), findsOneWidget);
  });

  testWidgets('on a phone the menu is a drawer, opened from the page bar', (tester) async {
    await showShell(tester, const [shop], at: '/shop', size: const Size(390, 844));
    expect(find.byType(PlatformSidebar), findsNothing);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(inMenu('Shop orders'), findsOneWidget);
    await tester.tap(inMenu('Shop orders'));
    await tester.pumpAndSettle();
    expect(find.text('Page /shop/orders'), findsOneWidget);
    expect(find.byType(PlatformSidebar), findsNothing, reason: 'the drawer closed');
  });

  testWidgets('a page in the frame on a phone opens the menu from its bar', (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: AppShellScope(openMenu: () => opened++, child: const AppPage(title: 'Page', body: SizedBox())),
    ));
    await tester.tap(find.byTooltip('Menu'));
    expect(opened, 1);
  });

  testWidgets('a page with somewhere to go back to keeps its back button', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AppShellScope(
        openMenu: () {},
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AppPage(title: 'Deeper', body: SizedBox())),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byTooltip('Menu'), findsNothing);
  });

  test('a page is open at its route, under it, but not under what it excludes', () {
    const members = NavDestination(label: 'Members', icon: Icons.groups, route: '/g/members', notUnder: ['/g/members/new']);
    expect(members.isOpenAt('/g/members'), isTrue);
    expect(members.isOpenAt('/g/members/abc'), isTrue);
    expect(members.isOpenAt('/g/members/new'), isFalse);
    expect(members.isOpenAt('/g/membership'), isFalse);
    const staff = NavDestination(label: 'Staff', icon: Icons.badge, route: '/manage/g/staff', alsoUnder: ['/g/staff']);
    expect(staff.isOpenAt('/g/staff/x'), isTrue);
  });
}

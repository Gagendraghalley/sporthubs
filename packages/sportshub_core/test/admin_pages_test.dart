import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportshub_core/sportshub_core.dart';
import 'package:sportshub_core/src/access/organisation_screens.dart';
import 'package:sportshub_core/src/access/role_screens.dart';
import 'package:sportshub_core/src/access/user_screens.dart';
import 'package:sportshub_core/src/masters/master_screens.dart';
import 'package:sportshub_core/src/venues/venue_staff_screen.dart';

final gym = Venue.fromJson({
  'id': 'g1',
  'type': 'gym',
  'name': 'Peak Fitness Changzamtok',
  'dzongkhag': 'Thimphu',
  'verification_status': 'verified',
  'created_at': '2026-11-01T00:00:00Z',
});

const permissions = [
  AppPermission(key: 'users.manage', scope: 'platform', name: 'Users', description: 'Make accounts, give roles', sortOrder: 10),
  AppPermission(key: 'masters.manage', scope: 'platform', name: 'Master data', description: 'Dzongkhags, gewogs and villages', sortOrder: 30),
  AppPermission(key: 'venue.edit', scope: 'venue', name: 'Venue details', description: 'Change details and photos', sortOrder: 10),
  AppPermission(key: 'venue.staff', scope: 'venue', name: 'Staff', sortOrder: 20),
  AppPermission(key: 'gym.members', scope: 'venue', moduleKey: 'gym_membership', name: 'Members', sortOrder: 110),
  AppPermission(key: 'gym.check_in', scope: 'venue', moduleKey: 'gym_membership', name: 'Check-in', sortOrder: 130),
];

final roles = [
  const AppRole(id: 'r-admin', key: 'platform_admin', scope: 'platform', name: 'Administrator', isSystem: true,
      description: 'Runs SportsHub day to day: users, roles, masters, venues and modules',
      permissions: {'users.manage', 'masters.manage'}),
  const AppRole(id: 'r-masters', key: 'masters_officer', scope: 'platform', name: 'Masters officer', permissions: {'masters.manage'}),
  const AppRole(id: 'r-owner', key: 'owner', scope: 'venue', name: 'Owner', isSystem: true, permissions: {}),
  const AppRole(id: 'r-staff', key: 'staff', scope: 'venue', name: 'Front desk', isSystem: true,
      description: 'Registers members, takes payments and checks people in', permissions: {'gym.members', 'gym.check_in'}),
  const AppRole(id: 'r-cashier', key: 'cashier', scope: 'venue', name: 'Cashier with a rather long role name', isActive: false,
      permissions: {}),
];

/// Peak Fitness Pvt Ltd: Trainer changed (plans added), Front desk as
/// SportsHub has it, Owner, and its own Till operator.
OrganisationRoles chainRoles({bool canManage = true}) => OrganisationRoles(
      organisationId: 'o1',
      organisationName: 'Peak Fitness Pvt Ltd',
      canManage: canManage,
      grantable: {'venue.edit', 'gym.members', 'gym.check_in'},
      roles: const [
        AppRole(id: 'r-owner', key: 'owner', scope: 'venue', name: 'Owner', isSystem: true, people: 1,
            permissions: {'venue.edit', 'venue.staff', 'gym.members', 'gym.check_in'}),
        AppRole(id: 'r-staff', key: 'staff', scope: 'venue', name: 'Front desk', isSystem: true, people: 3,
            permissions: {'gym.members', 'gym.check_in'}, defaultPermissions: {'gym.members', 'gym.check_in'}),
        AppRole(id: 'r-trainer', key: 'trainer', scope: 'venue', name: 'Trainer', isSystem: true, isCustomised: true,
            permissions: {'gym.members', 'gym.check_in', 'venue.edit'}, defaultPermissions: {'gym.members', 'gym.check_in'}),
        AppRole(id: 'r-till', key: 'till_operator', scope: 'venue', organisationId: 'o1', name: 'Till operator',
            description: 'Takes payments at the till', permissions: {'gym.check_in'}, defaultPermissions: {'gym.check_in'}),
      ],
    );

final users = [
  const ManagedUser(id: 'me', fullName: 'Gagendra Ghalley', email: 'gagendra.ghalley@sportshub.bt', phone: '+97517123456',
      isSuperAdmin: true, isActive: true, memberCode: '4K7P9Q', platformRoleIds: {}, venueRoles: []),
  const ManagedUser(id: 'u2', fullName: 'Karma Choden Wangmo Dorji', email: 'karma.choden.wangmo.dorji@example.bt',
      isSuperAdmin: false, isActive: false, memberCode: 'ABCDEF', platformRoleIds: {'r-masters'},
      venueRoles: [UserVenueRole(venueId: 'g1', venueName: 'Peak Fitness Changzamtok', role: 'staff', organisationId: 'o1')]),
];

List<Override> overrides() => [
      currentUserIdProvider.overrideWithValue('me'),
      myAccessProvider.overrideWith((ref) async => const PlatformAccess(isSuperAdmin: true, isActive: true, permissions: {})),
      rolesProvider.overrideWith((ref) async => roles),
      permissionsProvider.overrideWith((ref) async => permissions),
      // As the database would: with an organisation, only who works at its venues.
      managedUsersProvider.overrideWith((ref, q) async => [
            for (final u in users)
              if (q.organisationId == null || u.venueRoles.any((v) => v.organisationId == q.organisationId)) u,
          ]),
      managedUserProvider.overrideWith((ref, id) async => users.firstWhere((u) => u.id == id)),
      allVenuesProvider.overrideWith((ref) async => [gym]),
      masterListProvider.overrideWith((ref, q) async => [
            for (var i = 0; i < 30; i++)
              LocationItem(
                id: i + 1,
                level: q.level,
                name: i == 0 ? 'Dzongdra Chetoekha Tashigang Goenpa Lhakhang' : '${q.level.label} $i',
                isActive: i != 3,
                parentName: q.level == LocationLevel.dzongkhag ? null : 'Chokhor',
                grandparentName: q.level == LocationLevel.village ? 'Bumthang' : null,
                kind: q.level == LocationLevel.gewog && i.isOdd ? GewogKind.thromde : null,
                code: q.level == LocationLevel.village ? '0101${(i + 1).toString().padLeft(3, '0')}' : null,
              ),
          ]),
      venueAccessProvider.overrideWith((ref, id) async => VenueAccess(gym, VenueRole.owner)),
      organisationsProvider.overrideWith((ref) async => const [
            Organisation(id: 'o1', name: 'Peak Fitness Pvt Ltd', description: 'Two gyms in Thimphu', venueCount: 1),
            Organisation(id: 'o2', name: 'Druk Wellness Cooperative of Eastern Bhutan', venueCount: 0),
          ]),
      organisationRolesProvider.overrideWith((ref, id) async => chainRoles()),
      organisationVenuesProvider.overrideWith((ref, id) async => [gym]),
      venueStaffProvider.overrideWith((ref, id) async => [
            VenueStaffMember(venueId: 'g1', userId: 'me', role: 'owner', name: 'Gagendra Ghalley', email: 'g@x.bt'),
            VenueStaffMember(venueId: 'g1', userId: 'u2', role: 'staff', name: 'Karma Choden Wangmo Dorji',
                roleName: 'Front desk', email: 'karma.choden.wangmo.dorji@example.bt'),
          ]),
    ];

Future<void> show(WidgetTester tester, Widget page, Size size, {List<Override> extra = const []}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(overrides: [...overrides(), ...extra], child: MaterialApp(home: page)));
  await tester.pumpAndSettle();
}

/// Brings [finder] to the middle of its list, clear of the bars and buttons.
Future<void> centre(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

const phone = Size(360, 780);
const laptop = Size(1280, 800);

void main() {
  for (final size in [phone, laptop]) {
    final at = size == phone ? 'phone' : 'laptop';

    testWidgets('Users list fits a $at', (tester) async {
      await show(tester, const AdminUsersScreen(), size);
      expect(find.text('Karma Choden Wangmo Dorji'), findsOneWidget);
      expect(find.text('Super admin'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      await tester.tap(find.text('Turned off'));
      await tester.pumpAndSettle();
      expect(find.text('Gagendra Ghalley'), findsNothing);
    });

    testWidgets('Users narrow to one organisation\'s people on a $at', (tester) async {
      await show(tester, const AdminUsersScreen(), size);
      expect(find.text('Gagendra Ghalley'), findsOneWidget);
      await tester.tap(find.widgetWithText(SearchableDropdown<String>, 'Organisation'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byKey(SearchableDropdown.menuKey), matching: find.text('Peak Fitness Pvt Ltd')));
      await tester.pumpAndSettle();
      expect(find.text('Gagendra Ghalley'), findsNothing, reason: 'works at no venue of it');
      expect(find.text('Karma Choden Wangmo Dorji'), findsOneWidget);
      // From the organisation's page, it starts there; an organisation nobody works at says so.
      await show(tester, const AdminUsersScreen(organisationId: 'o2'), size);
      expect(find.textContaining("Nobody works at Druk Wellness Cooperative of Eastern Bhutan's venues"), findsOneWidget);
    });

    testWidgets('a user fits a $at', (tester) async {
      await show(tester, const AdminUserScreen(userId: 'u2'), size);
      expect(find.text('Account on'), findsOneWidget);
      expect(find.text('Super admin'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Peak Fitness Changzamtok'), 200);
      expect(find.text('Front desk'), findsOneWidget);
    });

    testWidgets('roles and the role editor fit a $at', (tester) async {
      await show(tester, const AdminRolesScreen(), size);
      expect(find.text('Administrator'), findsOneWidget);
      await show(tester, const RoleEditorScreen(roleId: 'r-staff'), size);
      expect(find.text('Gym membership').evaluate().isEmpty, isTrue, reason: 'no module registered: its key shows');
      expect(find.text('Check-in'), findsOneWidget);
      final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
      expect(save.bottom, greaterThan(size.height - 80), reason: 'the Save bar sits at the bottom, not over the page');
      expect(find.byType(TextFormField).first.hitTestable(), findsOneWidget, reason: 'the form shows above it');
      await show(tester, const RoleEditorScreen(roleId: 'r-owner'), size);
      expect(find.textContaining("can't be changed"), findsOneWidget);
    });

    testWidgets('master data fits a $at, every level', (tester) async {
      await show(tester, const AdminMastersScreen(), size);
      expect(find.text('Dzongdra Chetoekha Tashigang Goenpa Lhakhang'), findsOneWidget);
      for (final level in ['Gewogs', 'Villages']) {
        await tester.tap(find.text(level));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('0101001'), findsOneWidget);
      await centre(tester, find.text('Village 2'));
      await tester.tap(find.text('Village 2'));
      await tester.pumpAndSettle();
      expect(find.text('Change village'), findsOneWidget);
    });

    testWidgets("an organisation's roles fit a $at", (tester) async {
      await show(tester, const AdminRolesScreen(organisationId: 'o1'), size);
      expect(find.text("Peak Fitness Pvt Ltd's own roles"), findsOneWidget);
      expect(find.text('Till operator'), findsOneWidget);
      if (size == laptop) {
        expect(find.text('Changed here'), findsOneWidget);
        expect(find.text('Own role'), findsOneWidget);
      }
      expect(find.text('New own role'), findsOneWidget);
    });

    testWidgets('a SportsHub role, changed for an organisation, fits a $at; back to SportsHub\'s in one tap', (tester) async {
      await show(tester, const RoleEditorScreen(organisationId: 'o1', roleId: 'r-trainer'), size);
      expect(find.text('On at Peak Fitness Pvt Ltd'), findsOneWidget);
      expect(find.textContaining("won't reach it"), findsOneWidget);
      final save = tester.getRect(find.widgetWithText(FilledButton, 'Save'));
      expect(save.bottom, greaterThan(size.height - 80), reason: 'the Save bar sits at the bottom');
      await centre(tester, find.text("Use SportsHub's"));
      await tester.tap(find.text("Use SportsHub's"));
      await tester.pumpAndSettle();
      expect(find.textContaining('it changes here too'), findsOneWidget);
      expect(find.text("Use SportsHub's"), findsNothing);
    });

    testWidgets("an organisation's own role is only seen by staff who can't manage its roles, on a $at", (tester) async {
      await show(tester, const RoleEditorScreen(organisationId: 'o1', roleId: 'r-till'), size, extra: [
        organisationRolesProvider.overrideWith((ref, id) async => chainRoles(canManage: false)),
      ]);
      expect(find.textContaining("Only people who manage this organisation's roles"), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
      expect(find.byTooltip('Delete role'), findsNothing);
    });

    testWidgets('organisations and one organisation fit a $at', (tester) async {
      await show(tester, const AdminOrganisationsScreen(), size);
      expect(find.text('Druk Wellness Cooperative of Eastern Bhutan'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'druk');
      await tester.pumpAndSettle();
      expect(find.text('Peak Fitness Pvt Ltd'), findsNothing);
      await show(tester, const AdminOrganisationScreen(organisationId: 'o1'), size);
      expect(find.text('Peak Fitness Changzamtok'), findsOneWidget);
      expect(find.text('Add a venue'), findsOneWidget);
      expect(find.byTooltip('Delete organisation'), findsNothing, reason: 'it still has a venue');
      await centre(tester, find.text('Roles and permissions'));
      expect(find.text('Roles and permissions'), findsOneWidget);
      expect(find.text('Its people'), findsOneWidget);
    });

    testWidgets("a venue's Roles & permissions fits a $at", (tester) async {
      final gymOfChain = Venue.fromJson({
        'id': 'g1',
        'type': 'gym',
        'name': 'Peak Fitness Changzamtok',
        'dzongkhag': 'Thimphu',
        'verification_status': 'verified',
        'created_at': '2026-11-01T00:00:00Z',
        'organisation_id': 'o1',
      });
      await show(tester, const VenueRolesScreen(venueId: 'g1'), size, extra: [
        myAccessProvider.overrideWith((ref) async => const PlatformAccess(isSuperAdmin: false, isActive: true, permissions: {})),
        venueAccessProvider.overrideWith((ref, id) async => VenueAccess(gymOfChain, VenueRole.owner)),
      ]);
      expect(find.text('Front desk'), findsOneWidget);
      expect(find.text('New own role'), findsOneWidget);
    });

    testWidgets("a venue's staff page fits a $at, and its add dialog", (tester) async {
      // The venue's owner, not on the SportsHub team.
      await show(tester, const VenueStaffScreen(venueId: 'g1'), size, extra: [
        myAccessProvider.overrideWith((ref) async => const PlatformAccess(isSuperAdmin: false, isActive: true, permissions: {})),
      ]);
      expect(find.text('Gagendra Ghalley (you)'), findsOneWidget);
      await tester.tap(find.text('Add staff'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make their account'));
      await tester.pumpAndSettle();
      expect(find.text('Full name *'), findsOneWidget);
      // Owner can't be given from a venue; turned-off roles aren't offered.
      await tester.tap(find.widgetWithText(SearchableDropdown<String>, 'Role *'));
      await tester.pumpAndSettle();
      // Among the dropdown's choices (the staff table shows the owner's role).
      Finder offered(String role) => find.descendant(of: find.byKey(SearchableDropdown.menuKey), matching: find.text(role));
      expect(offered('Front desk'), findsWidgets, reason: 'the choices are open');
      expect(offered('Owner'), findsNothing);
      expect(offered('Cashier with a rather long role name'), findsNothing);
    });
  }
}

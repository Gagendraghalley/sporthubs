import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportshub_core/sportshub_core.dart';
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

final users = [
  const ManagedUser(id: 'me', fullName: 'Gagendra Ghalley', email: 'gagendra.ghalley@sportshub.bt', phone: '+97517123456',
      isSuperAdmin: true, isActive: true, memberCode: '4K7P9Q', platformRoleIds: {}, venueRoles: []),
  const ManagedUser(id: 'u2', fullName: 'Karma Choden Wangmo Dorji', email: 'karma.choden.wangmo.dorji@example.bt',
      isSuperAdmin: false, isActive: false, memberCode: 'ABCDEF', platformRoleIds: {'r-masters'},
      venueRoles: [UserVenueRole(venueId: 'g1', venueName: 'Peak Fitness Changzamtok', role: 'staff')]),
];

List<Override> overrides() => [
      currentUserIdProvider.overrideWithValue('me'),
      myAccessProvider.overrideWith((ref) async => const PlatformAccess(isSuperAdmin: true, isActive: true, permissions: {})),
      rolesProvider.overrideWith((ref) async => roles),
      permissionsProvider.overrideWith((ref) async => permissions),
      managedUsersProvider.overrideWith((ref, search) async => users),
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
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Role *'));
      await tester.pumpAndSettle();
      expect(find.text('Owner'), findsNothing);
      expect(find.text('Cashier with a rather long role name'), findsNothing);
    });
  }
}

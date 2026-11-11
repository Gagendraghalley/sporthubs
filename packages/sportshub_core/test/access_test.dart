import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportshub_core/sportshub_core.dart';
import 'package:sportshub_core/src/access/user_screens.dart' show UserFilter;
import 'package:sportshub_core/src/admin/admin_screens.dart';
import 'package:sportshub_core/src/venues/venue_staff_screen.dart' show givableVenueRoles;

final gym = Venue.fromJson({
  'id': 'g1',
  'type': 'gym',
  'name': 'Peak Fitness',
  'dzongkhag': 'Thimphu',
  'verification_status': 'verified',
  'created_at': '2026-11-01T00:00:00Z',
});

AppRole role(String key, Set<String> permissions, {String scope = RoleScope.venue, bool active = true}) =>
    AppRole(id: 'id-$key', key: key, scope: scope, name: key, permissions: permissions, isActive: active);

void main() {
  group('PlatformAccess', () {
    test('super admins can do everything; others what their roles give', () {
      const boss = PlatformAccess(isSuperAdmin: true, isActive: true, permissions: {});
      const officer = PlatformAccess(isSuperAdmin: false, isActive: true, permissions: {PlatformPermission.masters});
      expect(PlatformPermission.all.every(boss.can), isTrue);
      expect(officer.can(PlatformPermission.masters), isTrue);
      expect(officer.can(PlatformPermission.users), isFalse);
      expect(officer.isTeam, isTrue);
      expect(PlatformAccess.none.isTeam, isFalse);
    });

    test('a turned-off account can do nothing, super admin or not', () {
      const off = PlatformAccess(isSuperAdmin: true, isActive: false, permissions: {PlatformPermission.users});
      expect(off.can(PlatformPermission.users), isFalse);
      expect(off.isTeam, isFalse);
    });

    test('reads my_access()', () {
      final a = PlatformAccess.fromJson({
        'is_super_admin': false,
        'is_active': true,
        'permissions': ['users.manage', 'masters.manage'],
      });
      expect(a.permissions, {PlatformPermission.users, PlatformPermission.masters});
    });
  });

  group('VenueAccess', () {
    test('owners and super admins have everything; other roles exactly theirs', () {
      expect(VenueAccess(gym, VenueRole.owner).can('gym.plans'), isTrue);
      expect(VenueAccess(gym, VenueRole.admin).can(VenuePermission.staff), isTrue);
      final cashier = VenueAccess(gym, 'cashier', roleName: 'Cashier', permissions: {'gym.payments'});
      expect(cashier.can('gym.payments'), isTrue);
      expect(cashier.can('gym.check_in'), isFalse);
      expect(cashier.roleName, 'Cashier');
    });

    test('one of my_venues(): the venue, its organisation, the role and what it allows there', () {
      final mine = MyVenue.fromJson({
        'role': 'cashier',
        'role_name': 'Cashier',
        'venue': {
          'id': 'g1',
          'type': 'gym',
          'name': 'Peak Fitness',
          'dzongkhag': 'Thimphu',
          'verification_status': 'verified',
          'created_at': '2026-11-01T00:00:00Z',
          'organisation_id': 'o1',
        },
        'organisation': {'id': 'o1', 'name': 'Peak Fitness Pvt Ltd'},
        'permissions': ['gym.payments'],
      });
      expect(mine.roleName, 'Cashier');
      expect(mine.organisationName, 'Peak Fitness Pvt Ltd');
      expect(mine.venue.organisationId, 'o1');
      expect(mine.access.can('gym.payments'), isTrue);
      expect(mine.access.can('gym.members'), isFalse);
    });
  });

  group('organisations', () {
    test('a role from the table is as SportsHub has it', () {
      final r = AppRole.fromJson({
        'id': 'r1',
        'key': 'staff',
        'scope': 'venue',
        'name': 'Front desk',
        'organisation_id': null,
        'is_system': true,
        'role_permissions': [
          {'permission_key': 'gym.members'},
        ],
      });
      expect(r.isShared, isTrue);
      expect(r.permissions, {'gym.members'});
      expect(r.defaultPermissions, isNull);
    });

    test('organisation_roles(): roles as its venues have them, what it changed, and who may change them', () {
      final org = OrganisationRoles.fromJson({
        'organisation': {'id': 'o1', 'name': 'Chain Fitness'},
        'can_manage': true,
        'grantable': ['gym.members', 'gym.plans'],
        'roles': [
          {
            'id': 'r-trainer',
            'key': 'trainer',
            'scope': 'venue',
            'organisation_id': null,
            'name': 'Trainer',
            'is_system': true,
            'is_active': true,
            'off_here': false,
            'custom_permissions': true,
            'permissions': ['gym.check_in', 'gym.members', 'gym.plans'],
            'default_permissions': ['gym.check_in', 'gym.members'],
            'people': 2,
          },
          {
            'id': 'r-till',
            'key': 'till_operator',
            'scope': 'venue',
            'organisation_id': 'o1',
            'name': 'Till operator',
            'is_active': false,
            'off_here': false,
            'custom_permissions': false,
            'permissions': ['gym.payments'],
            'default_permissions': ['gym.payments'],
            'people': 0,
          },
        ],
      });
      expect(org.organisationName, 'Chain Fitness');
      expect(org.canManage, isTrue);
      expect(org.grantable, {'gym.members', 'gym.plans'});
      final trainer = org.roles.first;
      expect(trainer.isShared && trainer.isCustomised, isTrue);
      expect(trainer.permissions.difference(trainer.defaultPermissions!), {'gym.plans'});
      expect(trainer.people, 2);
      final till = org.roles.last;
      expect(till.isShared, isFalse);
      expect(till.isActive, isFalse);
    });

    test('an organisation with its venues counted', () {
      final o = Organisation.fromJson({
        'id': 'o1',
        'name': 'Chain Fitness',
        'description': null,
        'venues': [
          {'count': 3},
        ],
      });
      expect(o.venueCount, 3);
      expect(Organisation.fromJson({'id': 'o2', 'name': 'Empty'}).venueCount, 0);
    });
  });

  group('giving roles', () {
    final owner = role(VenueRole.owner, {});
    final manager = role(VenueRole.manager, {VenuePermission.edit, VenuePermission.income, 'gym.plans'});
    final frontDesk = role(VenueRole.staff, {'gym.members', 'gym.payments', 'gym.check_in'});
    final viewer = role('viewer', {'gym.members'});
    final all = [owner, manager, frontDesk, viewer];
    const member = PlatformAccess(isSuperAdmin: false, isActive: true, permissions: {});

    test('a venue owner gives any role but Owner', () {
      expect(givableVenueRoles(all, VenueAccess(gym, VenueRole.owner), member), [manager, frontDesk, viewer]);
    });

    test('someone who manages staff gives only roles within their own permissions', () {
      final supervisor = VenueAccess(gym, 'supervisor', permissions: {VenuePermission.staff, 'gym.members'});
      expect(givableVenueRoles(all, supervisor, member), [viewer]);
    });

    test('without the staff permission, nothing', () {
      expect(givableVenueRoles(all, VenueAccess(gym, VenueRole.staff, permissions: frontDesk.permissions), member), isEmpty);
    });

    test("SportsHub's user managers give any role, Owner too", () {
      const users = PlatformAccess(isSuperAdmin: false, isActive: true, permissions: {PlatformPermission.users});
      expect(givableVenueRoles(all, null, users), all);
    });

    test('team roles: only those whose permissions you have, unless super admin', () {
      final masters = role('masters_officer', {PlatformPermission.masters}, scope: RoleScope.platform);
      final admin = role('platform_admin', PlatformPermission.all.toSet(), scope: RoleScope.platform);
      const userDesk = PlatformAccess(
          isSuperAdmin: false, isActive: true, permissions: {PlatformPermission.users, PlatformPermission.masters});
      expect(canGiveRole(userDesk, masters), isTrue);
      expect(canGiveRole(userDesk, admin), isFalse);
      expect(canGiveRole(const PlatformAccess(isSuperAdmin: true, isActive: true, permissions: {}), admin), isTrue);
    });
  });

  test('permissions group as the core first, then each module, in their order', () {
    const perms = [
      AppPermission(key: 'gym.plans', scope: 'venue', name: 'Plans', moduleKey: 'gym_membership', sortOrder: 140),
      AppPermission(key: 'venue.income', scope: 'venue', name: 'Income', sortOrder: 30),
      AppPermission(key: 'gym.members', scope: 'venue', name: 'Members', moduleKey: 'gym_membership', sortOrder: 110),
      AppPermission(key: 'venue.edit', scope: 'venue', name: 'Details', sortOrder: 10),
    ];
    final groups = groupPermissions(perms);
    expect(groups.keys, [null, 'gym_membership']);
    expect(groups[null]!.map((p) => p.key), ['venue.edit', 'venue.income']);
    expect(groups['gym_membership']!.map((p) => p.key), ['gym.members', 'gym.plans']);
  });

  test('a search keeps what people type but not what would change the filter', () {
    expect(userSearchPattern(' pema, (dorji)* '), 'pema   dorji');
    expect(userSearchPattern('17123456'), '17123456');
  });

  test('user filters', () {
    ManagedUser u({bool admin = false, bool active = true, Set<String> roles = const {}, bool staff = false}) => ManagedUser(
          id: 'u',
          fullName: 'U',
          isSuperAdmin: admin,
          isActive: active,
          memberCode: 'AAAAAA',
          platformRoleIds: roles,
          venueRoles: staff ? const [UserVenueRole(venueId: 'g1', venueName: 'Gym', role: 'staff')] : const [],
        );
    expect(UserFilter.team.matches(u(roles: {'r1'})), isTrue);
    expect(UserFilter.team.matches(u(admin: true)), isTrue);
    expect(UserFilter.team.matches(u()), isFalse);
    expect(UserFilter.venueStaff.matches(u(staff: true)), isTrue);
    expect(UserFilter.off.matches(u(active: false)), isTrue);
  });

  group('SportsHub admin', () {
    Future<void> showAdmin(WidgetTester tester, PlatformAccess access) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          myAccessProvider.overrideWith((ref) async => access),
          pendingVenuesProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: AdminScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows what your permissions open', (tester) async {
      await showAdmin(tester, const PlatformAccess(isSuperAdmin: false, isActive: true, permissions: {PlatformPermission.masters}));
      expect(find.text('Master data'), findsOneWidget);
      expect(find.text('Users'), findsNothing);
      expect(find.text('Modules'), findsNothing);
    });

    testWidgets('super admins see everything', (tester) async {
      await showAdmin(tester, const PlatformAccess(isSuperAdmin: true, isActive: true, permissions: {}));
      for (final t in ['Users', 'Roles and permissions', 'Organisations', 'Master data', 'Venues to verify', 'Modules']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('members get a lock', (tester) async {
      await showAdmin(tester, const PlatformAccess(isSuperAdmin: false, isActive: true, permissions: {}));
      expect(find.text('For the SportsHub team only'), findsOneWidget);
    });
  });
}

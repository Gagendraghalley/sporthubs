/// What the database lets people do. The keys match the permissions table:
/// the database functions check them, the app only uses them to decide what
/// to show.
abstract final class PlatformPermission {
  /// Make accounts, give roles, turn people off.
  static const users = 'users.manage';

  /// Make roles and choose their permissions.
  static const roles = 'roles.manage';

  /// Dzongkhags, gewogs and villages.
  static const masters = 'masters.manage';

  /// See every venue; verify new ones or send them back.
  static const venuesVerify = 'venues.verify';

  /// Turn modules on and off.
  static const modules = 'modules.manage';

  /// Make organisations and choose which venues belong to each.
  static const organisations = 'organisations.manage';

  static const all = [users, roles, masters, venuesVerify, modules, organisations];
}

/// Running one venue (the core's; modules add their own, e.g. gym.check_in).
abstract final class VenuePermission {
  /// Details, photos and how to pay.
  static const edit = 'venue.edit';

  /// Add staff, make their accounts and choose their roles.
  static const staff = 'venue.staff';

  /// The organisation's own roles, and what each role may do there. To
  /// change them it's needed at every one of the organisation's venues.
  static const roles = 'venue.roles';

  /// Payments and income.
  static const income = 'venue.income';
}

/// roles.scope: a role for the SportsHub team, or for running a venue.
abstract final class RoleScope {
  static const platform = 'platform';
  static const venue = 'venue';

  static String label(String scope) => scope == platform ? 'SportsHub team' : 'Venue staff';
}

/// What the signed-in user may do across SportsHub (my_access()).
class PlatformAccess {
  /// profiles.role = 'admin': everything, everywhere.
  final bool isSuperAdmin;

  /// False once someone turned their account off: no roles count.
  final bool isActive;
  final Set<String> permissions;

  const PlatformAccess({required this.isSuperAdmin, required this.isActive, required this.permissions});

  static const none = PlatformAccess(isSuperAdmin: false, isActive: false, permissions: {});

  bool can(String permission) => isActive && (isSuperAdmin || permissions.contains(permission));

  /// Opens SportsHub admin: any of the team's permissions.
  bool get isTeam => isActive && (isSuperAdmin || permissions.isNotEmpty);

  factory PlatformAccess.fromJson(Map<String, dynamic> json) => PlatformAccess(
        isSuperAdmin: json['is_super_admin'] as bool? ?? false,
        isActive: json['is_active'] as bool? ?? false,
        permissions: {for (final p in (json['permissions'] as List? ?? const [])) p as String},
      );
}

/// A row of permissions: something a role can allow.
class AppPermission {
  final String key;
  final String scope;

  /// The module it belongs to (app_modules.key); null for the core's.
  final String? moduleKey;
  final String name;
  final String? description;
  final int sortOrder;

  const AppPermission({
    required this.key,
    required this.scope,
    required this.name,
    this.moduleKey,
    this.description,
    this.sortOrder = 100,
  });

  factory AppPermission.fromJson(Map<String, dynamic> json) => AppPermission(
        key: json['key'] as String,
        scope: json['scope'] as String,
        moduleKey: json['module_key'] as String?,
        name: json['name'] as String,
        description: json['description'] as String?,
        sortOrder: json['sort_order'] as int? ?? 100,
      );
}

/// A row of roles, with the permissions it gives. Read from the table, a
/// role is as SportsHub has it; read for an organisation
/// (organisation_roles()), it is as that organisation's venues have it.
class AppRole {
  final String id;

  /// What venue_staff.role holds; made from the name and never changed.
  final String key;
  final String scope;
  final String name;
  final String? description;

  /// The organisation whose own role it is; null for SportsHub-wide roles,
  /// which every organisation has.
  final String? organisationId;

  /// Comes with SportsHub: can't be deleted (turn it off instead).
  final bool isSystem;

  /// On (for an organisation: on there).
  final bool isActive;
  final Set<String> permissions;

  /// For an organisation: SportsHub's own permissions for the role, when the
  /// organisation changed them ([permissions] are then the organisation's).
  final Set<String>? defaultPermissions;

  /// For an organisation: it changed what this SportsHub-wide role allows.
  final bool isCustomised;

  /// For an organisation: it turned this SportsHub-wide role off for itself.
  final bool isOffHere;

  /// For an organisation: how many people have the role at its venues.
  final int? people;

  const AppRole({
    required this.id,
    required this.key,
    required this.scope,
    required this.name,
    required this.permissions,
    this.description,
    this.organisationId,
    this.isSystem = false,
    this.isActive = true,
    this.defaultPermissions,
    this.isCustomised = false,
    this.isOffHere = false,
    this.people,
  });

  /// The venue Owner always has every permission and can't be changed.
  bool get isLocked => key == 'owner';

  bool get isPlatform => scope == RoleScope.platform;

  /// Every organisation has it (it isn't one organisation's own).
  bool get isShared => organisationId == null;

  /// A row of roles with `role_permissions(permission_key)`, or a role from
  /// organisation_roles() (`permissions` and `default_permissions` as keys).
  factory AppRole.fromJson(Map<String, dynamic> json) {
    Set<String> keys(Object? list) => {
          for (final p in (list as List? ?? const []))
            p is Map ? p['permission_key'] as String : p as String,
        };
    return AppRole(
      id: json['id'] as String,
      key: json['key'] as String,
      scope: json['scope'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      organisationId: json['organisation_id'] as String?,
      isSystem: json['is_system'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      permissions: keys(json['permissions'] ?? json['role_permissions']),
      defaultPermissions: json.containsKey('default_permissions') ? keys(json['default_permissions']) : null,
      isCustomised: json['custom_permissions'] as bool? ?? false,
      isOffHere: json['off_here'] as bool? ?? false,
      people: (json['people'] as num?)?.toInt(),
    );
  }
}

/// A business on SportsHub that runs one or more venues (its branches).
class Organisation {
  final String id;
  final String name;
  final String? description;

  /// How many venues belong to it (when read with them).
  final int venueCount;

  const Organisation({required this.id, required this.name, this.description, this.venueCount = 0});

  /// A row of organisations, with `venues(count)` when counted.
  factory Organisation.fromJson(Map<String, dynamic> json) => Organisation(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        venueCount: switch (json['venues']) {
          [Map<String, dynamic> c, ...] => (c['count'] as num?)?.toInt() ?? 0,
          _ => 0,
        },
      );
}

/// An organisation's venue roles as its venues have them (organisation_roles()):
/// SportsHub-wide ones first, with its changes, then its own.
class OrganisationRoles {
  final String organisationId;
  final String organisationName;

  /// The signed-in user may make and change them.
  final bool canManage;

  /// The venue permissions they may give or take away here.
  final Set<String> grantable;
  final List<AppRole> roles;

  const OrganisationRoles({
    required this.organisationId,
    required this.organisationName,
    required this.canManage,
    required this.grantable,
    required this.roles,
  });

  factory OrganisationRoles.fromJson(Map<String, dynamic> json) {
    final organisation = json['organisation'] as Map<String, dynamic>;
    return OrganisationRoles(
      organisationId: organisation['id'] as String,
      organisationName: organisation['name'] as String,
      canManage: json['can_manage'] as bool? ?? false,
      grantable: {for (final k in (json['grantable'] as List? ?? const [])) k as String},
      roles: [for (final r in (json['roles'] as List? ?? const [])) AppRole.fromJson(r as Map<String, dynamic>)],
    );
  }
}

/// [permissions] grouped for a checklist: the core's first, then each
/// module's, each in sort order. Keys are module keys (null: the core).
Map<String?, List<AppPermission>> groupPermissions(Iterable<AppPermission> permissions) {
  final sorted = permissions.toList()
    ..sort((a, b) {
      if ((a.moduleKey == null) != (b.moduleKey == null)) return a.moduleKey == null ? -1 : 1;
      final byModule = (a.moduleKey ?? '').compareTo(b.moduleKey ?? '');
      return byModule != 0 ? byModule : a.sortOrder.compareTo(b.sortOrder);
    });
  final groups = <String?, List<AppPermission>>{};
  for (final p in sorted) {
    groups.putIfAbsent(p.moduleKey, () => []).add(p);
  }
  return groups;
}

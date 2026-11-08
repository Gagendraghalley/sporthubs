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

  static const all = [users, roles, masters, venuesVerify, modules];
}

/// Running one venue (the core's; modules add their own, e.g. gym.check_in).
abstract final class VenuePermission {
  /// Details, photos and how to pay.
  static const edit = 'venue.edit';

  /// Add staff, make their accounts and choose their roles.
  static const staff = 'venue.staff';

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

/// A row of roles, with the permissions it gives.
class AppRole {
  final String id;

  /// What venue_staff.role holds; made from the name and never changed.
  final String key;
  final String scope;
  final String name;
  final String? description;

  /// Comes with SportsHub: can't be deleted (turn it off instead).
  final bool isSystem;
  final bool isActive;
  final Set<String> permissions;

  const AppRole({
    required this.id,
    required this.key,
    required this.scope,
    required this.name,
    required this.permissions,
    this.description,
    this.isSystem = false,
    this.isActive = true,
  });

  /// The venue Owner always has every permission and can't be changed.
  bool get isLocked => key == 'owner';

  bool get isPlatform => scope == RoleScope.platform;

  factory AppRole.fromJson(Map<String, dynamic> json) => AppRole(
        id: json['id'] as String,
        key: json['key'] as String,
        scope: json['scope'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        isSystem: json['is_system'] as bool? ?? false,
        isActive: json['is_active'] as bool? ?? true,
        permissions: {
          for (final p in (json['role_permissions'] as List? ?? const []))
            (p as Map<String, dynamic>)['permission_key'] as String,
        },
      );
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

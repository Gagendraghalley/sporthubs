import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_repository.dart';
import '../supabase/supabase_provider.dart';
import '../venues/venue.dart';
import 'access.dart';

final accessRepositoryProvider = Provider<AccessRepository>((ref) => AccessRepository(ref.watch(supabaseProvider)));

/// What the signed-in user may do across SportsHub; [PlatformAccess.none]
/// when nobody is signed in.
final myAccessProvider = FutureProvider<PlatformAccess>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return PlatformAccess.none;
  return ref.watch(accessRepositoryProvider).myAccess();
});

/// Every permission there is, in sort order.
final permissionsProvider =
    FutureProvider<List<AppPermission>>((ref) => ref.watch(accessRepositoryProvider).permissions());

/// Every role, turned off ones too: the team's first, then venues'.
final rolesProvider = FutureProvider<List<AppRole>>((ref) => ref.watch(accessRepositoryProvider).roles());

/// The venue roles that can be given now (turned on), Owner first.
final venueRolesProvider = FutureProvider<List<AppRole>>((ref) async {
  final roles = await ref.watch(rolesProvider.future);
  return roles.where((r) => r.scope == RoleScope.venue && r.isActive).toList();
});

/// Accounts matching [search] (name, email or phone), newest first.
final managedUsersProvider = FutureProvider.autoDispose.family<List<ManagedUser>, String>(
  (ref, search) => ref.watch(accessRepositoryProvider).users(search: search),
);

final managedUserProvider = FutureProvider.autoDispose.family<ManagedUser?, String>(
  (ref, id) => ref.watch(accessRepositoryProvider).user(id),
);

/// Every venue, for giving someone a role at one (user managers see all).
final allVenuesProvider =
    FutureProvider.autoDispose<List<Venue>>((ref) => ref.watch(accessRepositoryProvider).allVenues());

/// An account, as people who manage users see it.
class ManagedUser {
  final String id;
  final String fullName;
  final String? email;
  final String? phone;
  final bool isSuperAdmin;
  final bool isActive;
  final String memberCode;
  final DateTime? createdAt;
  final Set<String> platformRoleIds;
  final List<UserVenueRole> venueRoles;

  const ManagedUser({
    required this.id,
    required this.fullName,
    required this.isSuperAdmin,
    required this.isActive,
    required this.memberCode,
    required this.platformRoleIds,
    required this.venueRoles,
    this.email,
    this.phone,
    this.createdAt,
  });

  String get displayName => fullName.trim().isEmpty ? (email ?? 'SportsHub member') : fullName.trim();

  bool get isTeam => isSuperAdmin || platformRoleIds.isNotEmpty;

  factory ManagedUser.fromJson(Map<String, dynamic> json) => ManagedUser(
        id: json['id'] as String,
        fullName: json['full_name'] as String? ?? '',
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        isSuperAdmin: json['role'] == 'admin',
        isActive: json['is_active'] as bool? ?? true,
        memberCode: json['member_code'] as String? ?? '',
        createdAt: json['created_at'] == null ? null : DateTime.parse(json['created_at'] as String),
        platformRoleIds: {
          for (final r in (json['user_roles'] as List? ?? const [])) (r as Map<String, dynamic>)['role_id'] as String,
        },
        venueRoles: [
          for (final s in (json['venue_staff'] as List? ?? const []))
            if ((s as Map<String, dynamic>)['venue'] != null)
              UserVenueRole(
                venueId: (s['venue'] as Map<String, dynamic>)['id'] as String,
                venueName: (s['venue'] as Map<String, dynamic>)['name'] as String,
                role: s['role'] as String,
              ),
        ]..sort((a, b) => a.venueName.toLowerCase().compareTo(b.venueName.toLowerCase())),
      );
}

/// Someone's role at one venue.
class UserVenueRole {
  final String venueId;
  final String venueName;
  final String role;

  const UserVenueRole({required this.venueId, required this.venueName, required this.role});
}

/// What the admin-users Edge Function made.
class CreatedUser {
  final String userId;

  /// The email already had an account: it only got the roles.
  final bool existed;

  const CreatedUser(this.userId, {required this.existed});
}

/// Text for a PostgREST `or` filter: what people type, without the
/// characters that would change the filter.
String userSearchPattern(String search) => search.replaceAll(RegExp(r'[,()*%\\]'), ' ').trim();

class AccessRepository {
  AccessRepository(this._client);
  final SupabaseClient _client;

  static const _userColumns = 'id, full_name, email, phone, role, is_active, member_code, created_at, '
      'user_roles!user_roles_user_id_fkey(role_id), '
      'venue_staff!venue_staff_user_id_fkey(role, venue:venues(id, name))';

  Future<PlatformAccess> myAccess() async =>
      PlatformAccess.fromJson(await _client.rpc('my_access') as Map<String, dynamic>);

  Future<List<AppPermission>> permissions() async {
    final rows = await _client.from('permissions').select().order('scope').order('sort_order');
    return rows.map(AppPermission.fromJson).toList();
  }

  Future<List<AppRole>> roles() async {
    final rows = await _client
        .from('roles')
        .select('id, key, scope, name, description, is_system, is_active, sort_order, role_permissions(permission_key)')
        .order('scope')
        .order('sort_order')
        .order('name');
    return rows.map(AppRole.fromJson).toList();
  }

  /// A new role ([roleId] null) or changes to one, with exactly
  /// [permissionKeys]. Returns its id.
  Future<String> saveRole({
    String? roleId,
    required String scope,
    required String name,
    String? description,
    required bool active,
    required Set<String> permissionKeys,
  }) async =>
      await _client.rpc('save_role', params: {
        'role_id': roleId,
        'scope': scope,
        'name': name.trim(),
        'description': description,
        'active': active,
        'permission_keys': permissionKeys.toList()..sort(),
      }) as String;

  Future<void> deleteRole(String roleId) => _client.rpc('delete_role', params: {'role_id': roleId});

  Future<List<ManagedUser>> users({String search = '', int limit = 200}) async {
    var query = _client.from('profiles').select(_userColumns);
    final pattern = userSearchPattern(search);
    if (pattern.isNotEmpty) {
      query = query
          .or('full_name.ilike.%$pattern%,email.ilike.%$pattern%,phone.ilike.%$pattern%,member_code.ilike.%$pattern%');
    }
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return rows.map(ManagedUser.fromJson).toList();
  }

  Future<ManagedUser?> user(String id) async {
    final row = await _client.from('profiles').select(_userColumns).eq('id', id).maybeSingle();
    return row == null ? null : ManagedUser.fromJson(row);
  }

  Future<List<Venue>> allVenues() async {
    final rows = await _client.from('venues').select().order('name');
    return rows.map(Venue.fromJson).toList();
  }

  Future<void> setPlatformRoles(String userId, Set<String> roleIds) =>
      _client.rpc('set_user_platform_roles', params: {'user_id': userId, 'role_ids': roleIds.toList()});

  Future<void> setSuperAdmin(String userId, bool make) =>
      _client.rpc('set_user_super_admin', params: {'user_id': userId, 'make': make});

  /// Turns the account off (no roles count, and they can't sign in) or on.
  Future<void> setActive(String userId, bool active) =>
      _invoke({'action': 'set_active', 'user_id': userId, 'active': active});

  /// Makes an account (they sign in with the emailed code) and gives it
  /// roles: a venue role at [venueId], and/or SportsHub team roles. An email
  /// that already has an account just gets the roles.
  Future<CreatedUser> createUser({
    required String email,
    required String fullName,
    String? phone,
    String? venueId,
    String? venueRole,
    Set<String> platformRoleIds = const {},
  }) async {
    final data = await _invoke({
      'action': 'create',
      'email': email.trim().toLowerCase(),
      'full_name': fullName.trim(),
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (venueId != null) 'venue_id': venueId,
      if (venueRole != null) 'venue_role': venueRole,
      if (platformRoleIds.isNotEmpty) 'platform_role_ids': platformRoleIds.toList(),
    });
    return CreatedUser(data['user_id'] as String, existed: data['existed'] as bool? ?? false);
  }

  /// Calls the admin-users Edge Function; its own error messages (what the
  /// database said) become a [StateError], which the app shows as it is.
  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke('admin-users', body: body);
      return (response.data as Map?)?.cast<String, dynamic>() ?? const {};
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      if (message != null) throw StateError(message);
      rethrow;
    }
  }
}

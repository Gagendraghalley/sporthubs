import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_repository.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../utils/formatters.dart';
import '../utils/validators.dart';
import '../venues/venue.dart';
import '../venues/venue_repository.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/feedback.dart';
import '../widgets/form_fields.dart';
import '../widgets/responsive.dart';
import '../widgets/searchable_dropdown.dart';

import 'access.dart';
import 'access_repository.dart';
import 'permission_gate.dart';

/// Which accounts Admin -> Users shows.
enum UserFilter {
  all('All'),
  team('SportsHub team'),
  venueStaff('Venue staff'),
  off('Turned off');

  const UserFilter(this.label);
  final String label;

  bool matches(ManagedUser u) => switch (this) {
        all => true,
        team => u.isTeam,
        venueStaff => u.venueRoles.isNotEmpty,
        off => !u.isActive,
      };
}

/// Roles [access] could give: super admins any; others only roles whose
/// every permission they have (the database checks the same).
bool canGiveRole(PlatformAccess access, AppRole role) =>
    access.isSuperAdmin || (!role.isLocked && role.permissions.every(access.can));

/// Admin -> Users: every account, to find someone and change their roles.
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _searchField = TextEditingController();
  String _search = '';
  UserFilter _filter = UserFilter.all;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      title: 'Users',
      permission: PlatformPermission.users,
      builder: (context, access) {
        final users = ref.watch(managedUsersProvider(_search));
        final roles = ref.watch(rolesProvider).valueOrNull ?? const <AppRole>[];
        final roleNames = {for (final r in roles) r.id: r.name};
        // A venue role is kept by its key ('staff'); shown by its name.
        final venueRoleNames = {for (final r in roles) if (r.scope == 'venue') r.key: r.name};
        return AppPage(
          title: 'Users',
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _create(access),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('New user'),
          ),
          body: RefreshIndicator(
            onRefresh: () async => ref.invalidate(managedUsersProvider(_search)),
            child: ListView(
              padding: pagePadding(context, bottom: 96),
              children: [
                ResponsiveColumns(
                  breakpoint: 980,
                  flex: (3, 2),
                  spacing: 16,
                  first: [
                    TextField(
                      controller: _searchField,
                      textInputAction: TextInputAction.search,
                      onChanged: (text) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 350), () {
                          if (mounted) setState(() => _search = text.trim());
                        });
                      },
                      decoration: const InputDecoration(
                        hintText: 'Search name, email, phone or member code',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ],
                  second: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final f in UserFilter.values)
                            ChoiceChip(
                                label: Text(f.label), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AsyncValueView<List<ManagedUser>>(
                  value: users,
                  onRetry: () => ref.invalidate(managedUsersProvider(_search)),
                  data: (all) {
                    final shown = all.where(_filter.matches).toList();
                    if (shown.isEmpty) {
                      return const EmptyState(icon: Icons.person_search_rounded, title: 'Nobody here');
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (all.length >= 200)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                            child: FormHint(
                                'The 200 newest accounts${_search.isEmpty ? '' : ' that match'}. Search to find others.'),
                          ),
                        _UsersTable(users: shown, roleNames: roleNames, venueRoleNames: venueRoleNames),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _create(PlatformAccess access) async {
    final made = await showAppDialog<CreatedUser>(context: context, builder: (_) => NewUserDialog(access: access));
    if (made == null || !mounted) return;
    ref.invalidate(managedUsersProvider);
    context.push(CoreRoutes.adminUserFor(made.userId));
  }
}

/// Every account as a table: who, phone, member code, the team's roles,
/// their venues, on or off, and when they joined; tap a row to open it.
/// On a narrow window the extra columns step aside and the person's cell
/// carries their roles.
class _UsersTable extends StatelessWidget {
  final List<ManagedUser> users;
  final Map<String, String> roleNames;
  final Map<String, String> venueRoleNames;

  const _UsersTable({required this.users, required this.roleNames, required this.venueRoleNames});

  List<String> _roles(ManagedUser u) => [
        for (final id in u.platformRoleIds)
          if (roleNames[id] != null) roleNames[id]!,
      ];

  @override
  Widget build(BuildContext context) {
    String lower(String? s) => (s ?? '').toLowerCase();
    return DataGrid<ManagedUser>(
      rows: users,
      noun: 'accounts',
      rowLabel: (u) => 'Open ${u.displayName}',
      onRowTap: (u) => context.push(CoreRoutes.adminUserFor(u.id)),
      columns: [
        GridColumn(
          key: 'user',
          label: 'User',
          flex: 5,
          sortBy: (u) => lower(u.displayName),
          cell: (context, u) => _UserCell(user: u, roles: _roles(u)),
        ),
        GridColumn(
          key: 'phone',
          label: 'Phone',
          flex: 3,
          showFrom: 1150,
          sortBy: (u) => u.phone ?? '',
          cell: (context, u) => _Plain(u.phone),
        ),
        GridColumn(
          key: 'code',
          label: 'Member code',
          flex: 3,
          showFrom: 1000,
          sortBy: (u) => u.memberCode,
          cell: (context, u) => _Plain(u.memberCode, spaced: true),
        ),
        GridColumn(
          key: 'roles',
          label: 'Roles',
          flex: 4,
          showFrom: 640,
          // Super admins first, then the team, then everyone else.
          sortBy: (u) => '${u.isSuperAdmin ? 0 : (u.platformRoleIds.isEmpty ? 2 : 1)}${lower(_roles(u).join())}',
          cell: (context, u) => _RolesCell(user: u, roles: _roles(u)),
        ),
        GridColumn(
          key: 'venues',
          label: 'Venues',
          flex: 4,
          showFrom: 860,
          sortBy: (u) => u.venueRoles.length,
          cell: (context, u) => _VenuesCell(user: u, venueRoleNames: venueRoleNames),
        ),
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 112,
          showFrom: 480,
          sortBy: (u) => u.isActive ? 0 : 1,
          cell: (context, u) => u.isActive
              ? StatusChip(label: 'Active', color: context.brand.success)
              : StatusChip(label: 'Off', color: context.brand.danger),
        ),
        GridColumn(
          key: 'joined',
          label: 'Joined',
          flex: 2,
          showFrom: 1250,
          sortBy: (u) => u.createdAt ?? DateTime(0),
          cell: (context, u) => _Plain(u.createdAt == null ? null : formatDate(u.createdAt!.toLocal())),
        ),
        GridColumn(
          key: 'open',
          label: '',
          width: 40,
          alignEnd: true,
          cell: (context, u) => Icon(Icons.chevron_right_rounded, color: context.brand.muted),
        ),
      ],
    );
  }
}

/// Their initials, name and email; with the Roles column away (a narrow
/// window), their roles too, and with Status away (a phone), 'Off' when
/// they're turned off.
class _UserCell extends StatelessWidget {
  final ManagedUser user;
  final List<String> roles;

  const _UserCell({required this.user, required this.roles});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final carryRoles = !DataGrid.shows(context, 'roles');
    final carryOff = !user.isActive && !DataGrid.shows(context, 'status');
    final badges = [
      if (carryRoles && user.isSuperAdmin) StatusChip(label: 'Super admin', color: context.colors.tertiary),
      if (carryOff) StatusChip(label: 'Off', color: brand.danger),
    ];
    return Row(
      children: [
        _Initials(name: user.displayName, dim: !user.isActive),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(user.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
              if (user.email != null)
                Text(user.email!,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13.5)),
              if (carryRoles && !user.isSuperAdmin && roles.isNotEmpty)
                Text(roles.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
              if (badges.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 6, runSpacing: 4, children: badges),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Super admin, and the team's roles, as chips; 'Member' with none.
class _RolesCell extends StatelessWidget {
  final ManagedUser user;
  final List<String> roles;

  const _RolesCell({required this.user, required this.roles});

  @override
  Widget build(BuildContext context) {
    if (!user.isSuperAdmin && roles.isEmpty) return _Plain('Member', quiet: true);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (user.isSuperAdmin) StatusChip(label: 'Super admin', color: context.colors.tertiary),
        for (final r in roles) StatusChip(label: r, color: context.colors.primary),
      ],
    );
  }
}

/// The first venue they work at and their role there; how many more.
class _VenuesCell extends StatelessWidget {
  final ManagedUser user;
  final Map<String, String> venueRoleNames;

  const _VenuesCell({required this.user, required this.venueRoleNames});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (user.venueRoles.isEmpty) return const _Plain(null);
    final first = user.venueRoles.first;
    final more = user.venueRoles.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(first.venueName,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink)),
        Text(
          [venueRoleNames[first.role] ?? first.role, if (more > 0) '+$more more'].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: brand.muted, fontSize: 13),
        ),
      ],
    );
  }
}

/// A cell's text, or a dash with nothing to say.
class _Plain extends StatelessWidget {
  final String? text;
  final bool spaced;
  final bool quiet;

  const _Plain(this.text, {this.spaced = false, this.quiet = false});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final empty = text == null || text!.trim().isEmpty;
    return Text(
      empty ? '—' : text!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: empty || quiet ? brand.muted : brand.body,
        letterSpacing: spaced && !empty ? 1 : null,
        fontWeight: spaced && !empty ? FontWeight.w600 : null,
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;
  final bool dim;

  const _Initials({required this.name, this.dim = false});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
    final color = dim ? context.brand.muted : context.colors.primary;
    return CircleAvatar(
      radius: 20,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    );
  }
}

/// One account: on or off, super admin, the team's roles, venue roles.
class AdminUserScreen extends ConsumerWidget {
  final String userId;

  const AdminUserScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PermissionGate(
      title: 'User',
      permission: PlatformPermission.users,
      builder: (context, access) {
        final user = ref.watch(managedUserProvider(userId));
        return AppPage(
          title: user.valueOrNull?.displayName ?? 'User',
          body: AsyncValueView<ManagedUser?>(
            value: user,
            onRetry: () => ref.invalidate(managedUserProvider(userId)),
            data: (u) => u == null
                ? const EmptyState(icon: Icons.person_off_outlined, title: 'This account no longer exists')
                : RefreshIndicator(
                    onRefresh: () async => _refresh(ref),
                    child: ListView(
                      padding: pagePadding(context),
                      children: [
                        ResponsiveColumns(
                          first: [
                            const SectionTitle('Profile'),
                            _UserHeader(user: u),
                            _AccountSection(user: u, access: access),
                          ],
                          second: [
                            _TeamRolesSection(key: ValueKey(u.platformRoleIds.join(',')), user: u, access: access),
                            _VenueRolesSection(user: u),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(managedUserProvider(userId));
    ref.invalidate(managedUsersProvider);
  }
}

void _refreshUser(WidgetRef ref, String userId) {
  ref.invalidate(managedUserProvider(userId));
  ref.invalidate(managedUsersProvider);
  // Their own menus, if they changed themselves.
  ref.invalidate(myAccessProvider);
  ref.invalidate(myVenuesProvider);
}

class _UserHeader extends StatelessWidget {
  final ManagedUser user;

  const _UserHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Initials(name: user.displayName, dim: !user.isActive),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName, style: context.text.titleMedium),
                const SizedBox(height: 4),
                if (user.email != null) InfoRow(icon: Icons.mail_outline_rounded, text: user.email!),
                if (user.phone != null) InfoRow(icon: Icons.call_outlined, text: user.phone!),
                InfoRow(icon: Icons.qr_code_2_rounded, text: 'Member code ${user.memberCode}'),
                if (user.createdAt != null)
                  InfoRow(icon: Icons.schedule_rounded, text: 'Joined ${formatMoment(user.createdAt!)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountSection extends ConsumerWidget {
  final ManagedUser user;
  final PlatformAccess access;

  const _AccountSection({required this.user, required this.access});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final isMe = user.id == me;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Account'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SwitchListTile(
                secondary: Icon(user.isActive ? Icons.toggle_on_outlined : Icons.block_rounded),
                title: const Text('Account on', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(isMe
                    ? "You can't turn your own account off"
                    : user.isActive
                        ? 'They can sign in and use their roles'
                        : "Off: they can't sign in, and none of their roles count"),
                value: user.isActive,
                onChanged: isMe || (user.isSuperAdmin && !access.isSuperAdmin)
                    ? null
                    : (on) async {
                        if (!on) {
                          final sure = await confirmAction(
                            context,
                            title: 'Turn ${user.displayName} off?',
                            message: "They are signed out, can't sign in again, and lose every role until you turn "
                                'them on. Their memberships and history stay.',
                            confirmLabel: 'Turn off',
                            destructive: true,
                          );
                          if (!sure || !context.mounted) return;
                        }
                        final ok = await runAction(
                          context,
                          () => ref.read(accessRepositoryProvider).setActive(user.id, on),
                          success: on ? '${user.displayName} is on again' : '${user.displayName} is turned off',
                        );
                        if (ok) _refreshUser(ref, user.id);
                      },
              ),
              if (access.isSuperAdmin) ...[
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.shield_outlined),
                  title: const Text('Super admin', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle:
                      Text(isMe ? 'Another super admin can change this for you' : 'Can do everything, everywhere'),
                  value: user.isSuperAdmin,
                  onChanged: isMe
                      ? null
                      : (make) async {
                          if (make) {
                            final sure = await confirmAction(
                              context,
                              title: 'Make ${user.displayName} a super admin?',
                              message:
                                  'They will be able to do everything on SportsHub, including making other super admins.',
                              confirmLabel: 'Make super admin',
                            );
                            if (!sure || !context.mounted) return;
                          }
                          final ok = await runAction(
                            context,
                            () => ref.read(accessRepositoryProvider).setSuperAdmin(user.id, make),
                            success: make
                                ? '${user.displayName} is a super admin'
                                : '${user.displayName} is no longer a super admin',
                          );
                          if (ok) _refreshUser(ref, user.id);
                        },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The SportsHub team's roles: ticked ones are theirs; Save gives them
/// exactly those.
class _TeamRolesSection extends ConsumerStatefulWidget {
  final ManagedUser user;
  final PlatformAccess access;

  const _TeamRolesSection({super.key, required this.user, required this.access});

  @override
  ConsumerState<_TeamRolesSection> createState() => _TeamRolesSectionState();
}

class _TeamRolesSectionState extends ConsumerState<_TeamRolesSection> {
  late final Set<String> _chosen = {...widget.user.platformRoleIds};
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final roles = (ref.watch(rolesProvider).valueOrNull ?? const <AppRole>[])
        .where((r) => r.isPlatform && (r.isActive || widget.user.platformRoleIds.contains(r.id)))
        .toList();
    final changed = !_sameSet(_chosen, widget.user.platformRoleIds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'SportsHub team roles',
          trailing: changed ? FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')) : null,
        ),
        if (widget.user.isSuperAdmin)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: FormHint('As a super admin they can already do everything; these roles add nothing.'),
          ),
        if (roles.isEmpty)
          const FormHint('No team roles yet. Make one under Roles and permissions.')
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, r) in roles.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  CheckboxListTile(
                    value: _chosen.contains(r.id),
                    title: Text(r.isActive ? r.name : '${r.name} (turned off)'),
                    subtitle: r.description == null ? null : Text(r.description!),
                    onChanged: canGiveRole(widget.access, r)
                        ? (on) => setState(() => on == true ? _chosen.add(r.id) : _chosen.remove(r.id))
                        : null,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      () => ref.read(accessRepositoryProvider).setPlatformRoles(widget.user.id, _chosen),
      success: 'Roles saved',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) _refreshUser(ref, widget.user.id);
  }
}

bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

/// Their roles at venues: change one, take one away, or add one.
class _VenueRolesSection extends ConsumerWidget {
  final ManagedUser user;

  const _VenueRolesSection({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(rolesProvider).valueOrNull ?? const <AppRole>[];
    String roleName(String key) => roles.where((r) => r.key == key).firstOrNull?.name ?? VenueRole.label(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Venues',
          trailing: TextButton.icon(
            onPressed: () => _give(context, ref, null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add to a venue'),
          ),
        ),
        if (user.venueRoles.isEmpty)
          const FormHint("They don't run any venue.")
        else
          for (final v in user.venueRoles)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MenuTile(
                icon: v.role == VenueRole.owner ? Icons.workspace_premium_outlined : Icons.badge_outlined,
                title: v.venueName,
                subtitle: roleName(v.role),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Change',
                  onSelected: (action) => action == 'change' ? _give(context, ref, v) : _remove(context, ref, v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'change', child: Text('Change role')),
                    PopupMenuItem(value: 'remove', child: Text('Take off this venue')),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _give(BuildContext context, WidgetRef ref, UserVenueRole? current) async {
    final result = await showAppDialog<({String venueId, String role})>(
      context: context,
      builder: (_) => _VenueRoleDialog(current: current, exclude: {for (final v in user.venueRoles) v.venueId}),
    );
    if (result == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(venueRepositoryProvider).setStaffRole(result.venueId, user.id, result.role),
      success: 'Saved',
    );
    if (ok) {
      _refreshUser(ref, user.id);
      ref.invalidate(venueStaffProvider(result.venueId));
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, UserVenueRole v) async {
    final sure = await confirmAction(
      context,
      title: 'Take ${user.displayName} off ${v.venueName}?',
      confirmLabel: 'Take off',
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(venueRepositoryProvider).removeStaff(v.venueId, user.id));
    if (ok) {
      _refreshUser(ref, user.id);
      ref.invalidate(venueStaffProvider(v.venueId));
    }
  }
}

/// A venue and a role there. Changing [current] keeps its venue.
class _VenueRoleDialog extends ConsumerStatefulWidget {
  final UserVenueRole? current;

  /// Venues they already have a role at (changed from their own row).
  final Set<String> exclude;

  const _VenueRoleDialog({required this.current, required this.exclude});

  @override
  ConsumerState<_VenueRoleDialog> createState() => _VenueRoleDialogState();
}

class _VenueRoleDialogState extends ConsumerState<_VenueRoleDialog> {
  final _form = GlobalKey<FormState>();
  late String? _venueId = widget.current?.venueId;
  late String? _role = widget.current?.role;

  @override
  Widget build(BuildContext context) {
    final venues = ref.watch(allVenuesProvider).valueOrNull ?? const <Venue>[];
    final roles = ref.watch(venueRolesProvider).valueOrNull ?? const <AppRole>[];
    final choosable = widget.current != null ? venues : venues.where((v) => !widget.exclude.contains(v.id)).toList();
    return AlertDialog(
      title: Text(widget.current == null ? 'Add to a venue' : 'Role at ${widget.current!.venueName}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.current == null) ...[
                SearchableDropdown<String>(
                  value: _venueId,
                  decoration: const InputDecoration(labelText: 'Venue *'),
                  options: [for (final v in choosable) DropdownOption(v.id, '${v.name} · ${v.place}')],
                  onChanged: (id) => setState(() => _venueId = id),
                  validator: (id) => id == null ? 'Choose the venue' : null,
                ),
                const SizedBox(height: 14),
              ],
              VenueRoleField(
                roles: roles,
                value: _role,
                onChanged: (r) => setState(() => _role = r),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) Navigator.pop(context, (venueId: _venueId!, role: _role!));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Choose a venue role, each with what it lets them do.
class VenueRoleField extends StatelessWidget {
  final List<AppRole> roles;
  final String? value;
  final ValueChanged<String?> onChanged;

  const VenueRoleField({super.key, required this.roles, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SearchableDropdown<String>(
      value: roles.any((r) => r.key == value) ? value : null,
      decoration: const InputDecoration(labelText: 'Role *'),
      options: [for (final r in roles) DropdownOption(r.key, r.name, detail: r.description)],
      onChanged: onChanged,
      validator: (r) => r == null ? 'Choose the role' : null,
    );
  }
}

/// Makes an account for someone (they sign in with the emailed code) and
/// gives it team roles. Pops the [CreatedUser].
class NewUserDialog extends ConsumerStatefulWidget {
  final PlatformAccess access;

  const NewUserDialog({super.key, required this.access});

  @override
  ConsumerState<NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends ConsumerState<NewUserDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _roles = <String>{};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teamRoles = (ref.watch(rolesProvider).valueOrNull ?? const <AppRole>[])
        .where((r) => r.isPlatform && r.isActive && canGiveRole(widget.access, r))
        .toList();
    return AlertDialog(
      title: const Text('New user'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FormHint('They sign in with this email and the 6-digit code SportsHub sends them; no password.'),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name *'),
                  validator: (v) => Validators.required(v, 'Name'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email *'),
                  validator: Validators.email,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone', hintText: '17123456'),
                  validator: Validators.phone,
                ),
                if (teamRoles.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text('SportsHub team roles', style: context.text.titleSmall),
                  const SizedBox(height: 4),
                  const FormHint(
                      'Leave all unticked for someone who only runs a venue; add them to it from their page.'),
                  for (final r in teamRoles)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _roles.contains(r.id),
                      title: Text(r.name),
                      subtitle: r.description == null ? null : Text(r.description!),
                      onChanged: (on) => setState(() => on == true ? _roles.add(r.id) : _roles.remove(r.id)),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Make account'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    CreatedUser? made;
    final ok = await runAction(context, () async {
      made = await ref.read(accessRepositoryProvider).createUser(
            email: _email.text,
            fullName: _name.text,
            phone: Validators.normalizePhone(_phone.text),
            platformRoleIds: _roles,
          );
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok && made != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(made!.existed
            ? 'That email already had an account; it got the roles.'
            : 'Account made. They can sign in with ${_email.text.trim().toLowerCase()}.'),
      ));
      Navigator.pop(context, made);
    }
  }
}

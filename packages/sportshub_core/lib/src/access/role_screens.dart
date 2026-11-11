import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../module/module_providers.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
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

/// Admin -> Roles and permissions: the SportsHub team's roles and the
/// SportsHub-wide venue roles every organisation has; or, with
/// [organisationId], one organisation's venue roles as its venues have them.
class AdminRolesScreen extends ConsumerWidget {
  final String? organisationId;

  const AdminRolesScreen({super.key, this.organisationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PermissionGate(
      title: 'Roles and permissions',
      permission: PlatformPermission.roles,
      builder: (context, access) {
        final org = organisationId;
        final whose = _WhoseRoles(organisationId: org);
        return AppPage(
          title: 'Roles and permissions',
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => org == null
                ? _newRole(context)
                : context.push(CoreRoutes.adminRoleNewFor(RoleScope.venue, organisation: org)),
            icon: const Icon(Icons.add_moderator_outlined),
            label: Text(org == null ? 'New role' : 'New own role'),
          ),
          body: org != null
              ? OrganisationRolesView(
                  organisationId: org,
                  header: whose,
                  roleRoute: (r) => CoreRoutes.adminRoleFor(r.id, organisation: org),
                )
              : AsyncValueView<List<AppRole>>(
                  value: ref.watch(rolesProvider),
                  onRetry: () => ref.invalidate(rolesProvider),
                  data: (roles) => RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(rolesProvider);
                      ref.invalidate(permissionsProvider);
                      ref.invalidate(organisationsProvider);
                    },
                    child: ListView(
                      padding: pagePadding(context, bottom: 96),
                      children: [
                        whose,
                        const SizedBox(height: 12),
                        const FormHint(
                          'A role is a set of permissions. Super admins have every permission; everyone else gets what '
                          'their roles allow. Turning a role off takes its permissions away from everyone who has it.',
                        ),
                        for (final scope in const [RoleScope.platform, RoleScope.venue]) ...[
                          SectionTitle(scope == RoleScope.platform ? 'SportsHub team' : 'Venue staff, SportsHub-wide'),
                          if (scope == RoleScope.venue)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                              child: FormHint(
                                'Every organisation has these, with the same permissions, unless it changes them for '
                                'itself. Choose an organisation above to see its own roles and what it changed.',
                              ),
                            ),
                          _RolesTable(
                            roles: [for (final r in roles) if (r.scope == scope && r.isShared) r],
                            onOpen: (r) => context.push(CoreRoutes.adminRoleFor(r.id)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Future<void> _newRole(BuildContext context) async {
    final scope = await showAppDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('A role for'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, RoleScope.platform),
            child: const ListTile(
              leading: Icon(Icons.admin_panel_settings_outlined),
              title: Text('The SportsHub team'),
              subtitle: Text('Users, roles, master data, organisations, venues, modules'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, RoleScope.venue),
            child: const ListTile(
              leading: Icon(Icons.badge_outlined),
              title: Text('Venue staff, at every organisation'),
              subtitle: Text('Members, payments, check-in, plans, income'),
            ),
          ),
        ],
      ),
    );
    if (scope != null && context.mounted) context.push(CoreRoutes.adminRoleNewFor(scope));
  }
}

/// The value of [_WhoseRoles] for SportsHub-wide roles.
const _everyone = '';

/// Whose roles Roles and permissions shows: SportsHub-wide ones, or one
/// organisation's.
class _WhoseRoles extends ConsumerWidget {
  final String? organisationId;

  const _WhoseRoles({required this.organisationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final organisations = ref.watch(organisationsProvider).valueOrNull ?? const <Organisation>[];
    final current = organisationId ?? _everyone;
    return SearchableDropdown<String>(
      value: current,
      decoration: const InputDecoration(labelText: 'Whose roles', prefixIcon: Icon(Icons.apartment_rounded)),
      searchHint: 'Find an organisation',
      options: [
        const DropdownOption(_everyone, 'SportsHub-wide', detail: 'The team, and what every organisation starts with'),
        for (final o in organisations)
          DropdownOption(o.id, o.name, detail: o.venueCount == 1 ? '1 venue' : '${o.venueCount} venues'),
      ],
      onChanged: (id) {
        if (id == null || id == current) return;
        context.replace(CoreRoutes.adminRolesFor(id == _everyone ? null : id));
      },
    );
  }
}

/// An organisation's venue roles as its venues have them: SportsHub-wide
/// ones (with what it changed) and its own. For the team (Roles and
/// permissions) and the organisation's people (a venue's Roles page); a row
/// opens [roleRoute].
class OrganisationRolesView extends ConsumerWidget {
  final String organisationId;
  final String Function(AppRole role) roleRoute;

  /// Above the roles (the team's choice of organisation).
  final Widget? header;

  const OrganisationRolesView({super.key, required this.organisationId, required this.roleRoute, this.header});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void refresh() {
      ref.invalidate(organisationRolesProvider(organisationId));
      ref.invalidate(permissionsProvider);
    }

    return AsyncValueView<OrganisationRoles>(
      value: ref.watch(organisationRolesProvider(organisationId)),
      onRetry: refresh,
      data: (org) {
        final shared = [for (final r in org.roles) if (r.isShared) r];
        final own = [for (final r in org.roles) if (!r.isShared) r];
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: ListView(
            padding: pagePadding(context, bottom: 96),
            children: [
              if (header != null) ...[header!, const SizedBox(height: 12)],
              FormHint(org.canManage
                  ? 'These are the roles at ${org.organisationName}\'s venues. Change what a SportsHub role allows '
                      'here, or turn it off here: other organisations keep it as it is. Or make roles of your own.'
                  : 'These are the roles at ${org.organisationName}\'s venues and what each allows. Only people who '
                      'manage its roles at all of its venues can change them.'),
              const SectionTitle('SportsHub roles'),
              _RolesTable(roles: shared, organisation: true, onOpen: (r) => context.push(roleRoute(r))),
              SectionTitle('${org.organisationName}\'s own roles'),
              if (own.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: FormHint(org.canManage
                      ? 'None yet. Make one (New own role) when SportsHub\'s don\'t fit, e.g. a cashier who only takes '
                          'payments. Only this organisation\'s venues can give it.'
                      : 'None.'),
                )
              else
                _RolesTable(roles: own, organisation: true, onOpen: (r) => context.push(roleRoute(r))),
            ],
          ),
        );
      },
    );
  }
}

/// Roles as a table: the role, what it's for, how many permissions, where
/// it comes from, on or off; a row opens the role. For an [organisation],
/// as its venues have them, with how many people have each there. On a
/// narrow window the role's cell carries what the hidden columns said.
class _RolesTable extends StatelessWidget {
  final List<AppRole> roles;
  final ValueChanged<AppRole> onOpen;

  /// Read for an organisation (organisation_roles()).
  final bool organisation;

  const _RolesTable({required this.roles, required this.onOpen, this.organisation = false});

  static int _count(AppRole r) => r.isLocked ? 1 << 20 : r.permissions.length;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return DataGrid<AppRole>(
      rows: roles,
      noun: 'roles',
      rowLabel: (r) => 'Open ${r.name}',
      dimmed: (r) => !r.isActive,
      onRowTap: onOpen,
      columns: [
        GridColumn(
          key: 'role',
          label: 'Role',
          flex: 4,
          sortBy: (r) => r.name.toLowerCase(),
          cell: (context, r) => _RoleCell(role: r, organisation: organisation),
        ),
        GridColumn(
          key: 'about',
          label: "What it's for",
          flex: 6,
          showFrom: 820,
          cell: (context, r) => Text(
            r.description ?? '—',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: r.description == null ? brand.muted : brand.body, height: 1.35),
          ),
        ),
        GridColumn(
          key: 'permissions',
          label: 'Permissions',
          flex: 2,
          showFrom: 560,
          sortBy: _count,
          cell: (context, r) => _Count(role: r),
        ),
        if (organisation)
          GridColumn(
            key: 'people',
            label: 'People',
            width: 88,
            showFrom: 980,
            alignEnd: true,
            sortBy: (r) => r.people ?? 0,
            cell: (context, r) => Text('${r.people ?? 0}', style: TextStyle(color: brand.body, fontWeight: FontWeight.w600)),
          ),
        GridColumn(
          key: 'type',
          label: organisation ? 'From' : 'Type',
          width: organisation ? 136 : 120,
          showFrom: 700,
          sortBy: (r) => _typeRank(r, organisation),
          cell: (context, r) => _TypeChip(role: r, organisation: organisation),
        ),
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 104,
          showFrom: 480,
          sortBy: (r) => r.isActive ? 0 : 1,
          cell: (context, r) => _StatusChip(role: r),
        ),
        GridColumn(
          key: 'open',
          label: '',
          width: 40,
          alignEnd: true,
          cell: (context, r) => Icon(Icons.chevron_right_rounded, color: brand.muted),
        ),
      ],
    );
  }
}

int _typeRank(AppRole r, bool organisation) =>
    organisation ? (!r.isShared ? 2 : (r.isCustomised ? 1 : 0)) : (r.isSystem ? 0 : 1);

/// Where a role comes from: built into SportsHub or made by the team; for
/// an organisation, SportsHub's as it is, SportsHub's changed there, or
/// its own.
class _TypeChip extends StatelessWidget {
  final AppRole role;
  final bool organisation;

  const _TypeChip({required this.role, required this.organisation});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (!organisation) {
      return role.isSystem
          ? StatusChip(label: 'Built in', color: context.colors.tertiary)
          : StatusChip(label: 'Custom', color: brand.muted);
    }
    if (!role.isShared) return StatusChip(label: 'Own role', color: brand.accent);
    if (role.isCustomised) return StatusChip(label: 'Changed here', color: brand.warning);
    return StatusChip(label: 'SportsHub', color: context.colors.tertiary);
  }
}

/// On, off, or (for an organisation) turned off there only.
class _StatusChip extends StatelessWidget {
  final AppRole role;

  const _StatusChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (role.isActive) return StatusChip(label: 'Active', color: brand.success);
    return StatusChip(label: role.isOffHere ? 'Off here' : 'Off', color: brand.danger);
  }
}

/// '5 permissions', the number bold; 'Every permission' for one that has all.
class _Count extends StatelessWidget {
  final AppRole role;

  const _Count({required this.role});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (role.isLocked) {
      return Text('Every permission', style: TextStyle(fontWeight: FontWeight.w600, color: brand.ink));
    }
    final n = role.permissions.length;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '$n', style: TextStyle(fontWeight: FontWeight.w800, color: brand.ink)),
        TextSpan(text: n == 1 ? ' permission' : ' permissions', style: TextStyle(color: brand.muted)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The role's icon and name; what the hidden columns would say, under it.
class _RoleCell extends StatelessWidget {
  final AppRole role;
  final bool organisation;

  const _RoleCell({required this.role, required this.organisation});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = role.isActive ? context.colors.primary : brand.muted;
    final count = role.isLocked
        ? 'Every permission'
        : '${role.permissions.length} permission${role.permissions.length == 1 ? '' : 's'}';
    final people = role.people ?? 0;
    final carry = [
      if (!DataGrid.shows(context, 'permissions')) count,
      if (organisation && !DataGrid.shows(context, 'people') && people > 0) people == 1 ? '1 person' : '$people people',
      if (!DataGrid.shows(context, 'about') && role.description != null) role.description!,
    ];
    final badges = [
      if (!DataGrid.shows(context, 'type') && (organisation ? _typeRank(role, true) > 0 : role.isSystem))
        _TypeChip(role: role, organisation: organisation),
      if (!DataGrid.shows(context, 'status') && !role.isActive) _StatusChip(role: role),
    ];
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
          child: Icon(role.isPlatform ? Icons.admin_panel_settings_outlined : Icons.badge_outlined, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(role.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
              if (carry.isNotEmpty)
                Text(carry.join(' · '),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13)),
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

/// A role's name, whether it's on, and its permissions.
///   * SportsHub-wide ([organisationId] null), for the team: a new one of
///     [scope], or the role [roleId].
///   * For organisation [organisationId]: a new role of its own, one of its
///     own [roleId], or what the SportsHub role [roleId] allows there.
class RoleEditorScreen extends ConsumerWidget {
  final String? roleId;
  final String? scope;
  final String? organisationId;

  const RoleEditorScreen({super.key, this.roleId, this.scope, this.organisationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (organisationId case final org?) return _OrganisationRoleEditor(organisationId: org, roleId: roleId);
    return PermissionGate(
      title: 'Role',
      permission: PlatformPermission.roles,
      builder: (context, access) {
        final roles = ref.watch(rolesProvider);
        final permissions = ref.watch(permissionsProvider);
        return AsyncValueView<List<AppRole>>(
          value: roles,
          onRetry: () => ref.invalidate(rolesProvider),
          data: (all) => AsyncValueView<List<AppPermission>>(
            value: permissions,
            onRetry: () => ref.invalidate(permissionsProvider),
            data: (perms) {
              final role = roleId == null ? null : all.where((r) => r.id == roleId).firstOrNull;
              if (roleId != null && role == null) return const _RoleGone();
              // One organisation's own role: as that organisation has it.
              if (role?.organisationId case final org?) return _OrganisationRoleEditor(organisationId: org, roleId: role!.id);
              final s = role?.scope ?? (scope == RoleScope.platform ? RoleScope.platform : RoleScope.venue);
              return _RoleForm(
                key: ValueKey(role?.id ?? 'new-$s'),
                role: role,
                scope: s,
                permissions: perms.where((p) => p.scope == s).toList(),
                // Only super admins give team permissions they don't have themselves.
                canTick: (p) => s == RoleScope.venue || access.isSuperAdmin || access.can(p.key),
              );
            },
          ),
        );
      },
    );
  }
}

class _RoleGone extends StatelessWidget {
  const _RoleGone();

  @override
  Widget build(BuildContext context) =>
      const AppPage(title: 'Role', body: EmptyState(icon: Icons.search_off_rounded, title: 'This role no longer exists'));
}

/// A role as organisation [organisationId] has it: a new or existing role of
/// its own, or a SportsHub role. Read-only for those who can't change the
/// organisation's roles.
class _OrganisationRoleEditor extends ConsumerWidget {
  final String organisationId;
  final String? roleId;

  const _OrganisationRoleEditor({required this.organisationId, required this.roleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<OrganisationRoles>(
      value: ref.watch(organisationRolesProvider(organisationId)),
      onRetry: () => ref.invalidate(organisationRolesProvider(organisationId)),
      data: (org) => AsyncValueView<List<AppPermission>>(
        value: ref.watch(permissionsProvider),
        onRetry: () => ref.invalidate(permissionsProvider),
        data: (perms) {
          final role = roleId == null ? null : org.roles.where((r) => r.id == roleId).firstOrNull;
          if (roleId != null && role == null) return const _RoleGone();
          final venuePermissions = perms.where((p) => p.scope == RoleScope.venue).toList();
          bool canTick(AppPermission p) => org.canManage && org.grantable.contains(p.key);
          if (role != null && role.isShared) {
            return _SharedRoleForm(
              key: ValueKey('${org.organisationId}-${role.id}'),
              role: role,
              organisation: org,
              permissions: venuePermissions,
              canTick: canTick,
            );
          }
          return _RoleForm(
            key: ValueKey(role?.id ?? 'new-${org.organisationId}'),
            role: role,
            scope: RoleScope.venue,
            permissions: venuePermissions,
            canTick: canTick,
            organisation: org,
          );
        },
      ),
    );
  }
}

class _RoleForm extends ConsumerStatefulWidget {
  final AppRole? role;
  final String scope;
  final List<AppPermission> permissions;

  /// Whether the signed-in user may tick or untick [AppPermission].
  final bool Function(AppPermission) canTick;

  /// Set: one of this organisation's own roles (or a new one).
  final OrganisationRoles? organisation;

  const _RoleForm({
    super.key,
    required this.role,
    required this.scope,
    required this.permissions,
    required this.canTick,
    this.organisation,
  });

  @override
  ConsumerState<_RoleForm> createState() => _RoleFormState();
}

class _RoleFormState extends ConsumerState<_RoleForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.role?.name ?? '');
  late final _description = TextEditingController(text: widget.role?.description ?? '');
  late bool _active = widget.role?.isActive ?? true;
  late final Set<String> _chosen = {...?widget.role?.permissions};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _locked => widget.role?.isLocked ?? false;

  /// They may see it but not change it (another's organisation's role).
  bool get _readOnly => _locked || !(widget.organisation?.canManage ?? true);

  @override
  Widget build(BuildContext context) {
    final role = widget.role;
    final org = widget.organisation;
    final moduleNames = {for (final m in ref.watch(registeredModulesProvider)) m.key: m.name};
    final groups = groupPermissions(widget.permissions);
    return AppPage(
      title: role != null
          ? role.name
          : (org == null ? 'New ${RoleScope.label(widget.scope).toLowerCase()} role' : 'New role for ${org.organisationName}'),
      actions: [
        if (role != null && !role.isSystem && !_readOnly)
          IconButton(tooltip: 'Delete role', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
      ],
      bottomBar: _readOnly ? null : _SaveBar(label: role == null ? 'Make role' : 'Save', onPressed: _saving ? null : _save),
      body: Form(
        key: _form,
        child: ListView(
          padding: pagePadding(context, bottom: 110),
          children: [
            ResponsiveColumns(
              flex: (2, 3),
              first: [
            const SectionTitle('Role'),
            if (_locked)
              const _Notice(icon: Icons.lock_outline_rounded, text: "A venue's Owner can always do everything there. This role can't be changed.")
            else if (_readOnly)
              const _Notice(
                  icon: Icons.visibility_outlined,
                  text: "Only people who manage this organisation's roles at all of its venues can change it."),
            if (org != null && !_locked)
              _Notice(
                icon: Icons.apartment_rounded,
                text: '${org.organisationName}\'s own role: only its venues can give it'
                    '${(role?.people ?? 0) > 0 ? ', and ${role!.people == 1 ? '1 person has' : '${role.people} people have'} it' : ''}.',
              ),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    enabled: !_readOnly,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Name *', hintText: 'e.g. Cashier'),
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the role\'s name' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _description,
                    enabled: !_readOnly,
                    maxLength: 300,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'What it is for'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('On'),
                    subtitle:
                        Text(_active ? 'People with this role get its permissions' : 'Nobody gets its permissions'),
                    value: _active,
                    onChanged: _readOnly ? null : (v) => setState(() => _active = v),
                  ),
                ],
              ),
            ),
              ],
              second: [
            for (final entry in groups.entries)
              _PermissionGroup(
                title: _groupTitle(entry.key, widget.scope, moduleNames),
                permissions: entry.value,
                ticked: (p) => _locked || _chosen.contains(p.key),
                note: (p) => !_readOnly && !widget.canTick(p) ? "You don't have this one" : null,
                onChanged: (p) => _readOnly || !widget.canTick(p)
                    ? null
                    : (on) => setState(() => on ? _chosen.add(p.key) : _chosen.remove(p.key)),
              ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_chosen.isEmpty && _active) {
      final sure = await confirmAction(
        context,
        title: 'No permissions?',
        message: 'People with this role will be able to do nothing extra.',
        confirmLabel: 'Save anyway',
      );
      if (!sure || !mounted) return;
    }
    setState(() => _saving = true);
    final ok = await runAction(
      context,
      () => ref.read(accessRepositoryProvider).saveRole(
            roleId: widget.role?.id,
            scope: widget.scope,
            name: _name.text,
            description: _description.text.trim().isEmpty ? null : _description.text.trim(),
            active: _active,
            permissionKeys: _chosen,
            organisationId: widget.role == null ? widget.organisation?.organisationId : null,
          ),
      success: widget.role == null ? 'Role made' : 'Saved',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      refreshRoles(ref, organisationId: widget.organisation?.organisationId);
      context.pop();
    }
  }

  Future<void> _delete() async {
    final sure = await confirmAction(
      context,
      title: 'Delete ${widget.role!.name}?',
      message: 'Only a role nobody has can be deleted.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!sure || !mounted) return;
    final ok = await runAction(context, () => ref.read(accessRepositoryProvider).deleteRole(widget.role!.id),
        success: 'Deleted');
    if (ok && mounted) {
      refreshRoles(ref, organisationId: widget.organisation?.organisationId);
      context.pop();
    }
  }
}

/// What a SportsHub role allows at one organisation's venues: on or off
/// there, and its permissions there, as SportsHub has them (following
/// SportsHub's later changes) or as the organisation chose.
class _SharedRoleForm extends ConsumerStatefulWidget {
  /// As the organisation has it.
  final AppRole role;
  final OrganisationRoles organisation;
  final List<AppPermission> permissions;
  final bool Function(AppPermission) canTick;

  const _SharedRoleForm({
    super.key,
    required this.role,
    required this.organisation,
    required this.permissions,
    required this.canTick,
  });

  @override
  ConsumerState<_SharedRoleForm> createState() => _SharedRoleFormState();
}

class _SharedRoleFormState extends ConsumerState<_SharedRoleForm> {
  late bool _onHere = !widget.role.isOffHere;
  late final Set<String> _chosen = {...widget.role.permissions};
  bool _saving = false;

  AppRole get _role => widget.role;
  Set<String> get _defaults => _role.defaultPermissions ?? _role.permissions;

  /// Ticked exactly as SportsHub has it: kept as SportsHub's, so its later
  /// changes reach this organisation too.
  bool get _asSportsHub => _sameSet(_chosen, _defaults);
  bool get _readOnly => _role.isLocked || !widget.organisation.canManage;
  bool get _changed => _onHere == _role.isOffHere || !_sameSet(_chosen, _role.permissions);

  @override
  Widget build(BuildContext context) {
    final org = widget.organisation;
    final brand = context.brand;
    final moduleNames = {for (final m in ref.watch(registeredModulesProvider)) m.key: m.name};
    final groups = groupPermissions(widget.permissions);
    final people = _role.people ?? 0;
    return AppPage(
      title: _role.name,
      bottomBar: _readOnly ? null : _SaveBar(label: 'Save', onPressed: _saving || !_changed ? null : _save),
      body: ListView(
        padding: pagePadding(context, bottom: 110),
        children: [
          ResponsiveColumns(
            flex: (2, 3),
            first: [
              SectionTitle('At ${org.organisationName}'),
              if (_role.isLocked)
                const _Notice(icon: Icons.lock_outline_rounded, text: "A venue's Owner can always do everything there. This role can't be changed.")
              else if (_readOnly)
                const _Notice(
                    icon: Icons.visibility_outlined,
                    text: "Only people who manage this organisation's roles at all of its venues can change it."),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(_role.name, style: context.text.titleMedium)),
                        StatusChip(label: 'SportsHub role', color: context.colors.tertiary),
                      ],
                    ),
                    if (_role.description != null) ...[
                      const SizedBox(height: 4),
                      Text(_role.description!, style: TextStyle(color: brand.body)),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Every organisation has this role. What you choose here applies only at ${org.organisationName}\'s '
                      'venues${people > 0 ? ' (${people == 1 ? '1 person has' : '$people people have'} it there)' : ''}.',
                      style: TextStyle(color: brand.muted, fontSize: 13),
                    ),
                    if (!_role.isLocked)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('On at ${org.organisationName}'),
                        subtitle: Text(_onHere
                            ? 'People with this role there get its permissions'
                            : 'Nobody there gets its permissions'),
                        value: _onHere,
                        onChanged: _readOnly ? null : (v) => setState(() => _onHere = v),
                      ),
                    if (!_role.isActive && !_role.isOffHere)
                      Text('SportsHub has turned this role off everywhere.', style: TextStyle(color: brand.danger)),
                  ],
                ),
              ),
              if (!_role.isLocked) ...[
                const SizedBox(height: 12),
                _Notice(
                  icon: _asSportsHub ? Icons.sync_rounded : Icons.tune_rounded,
                  text: _asSportsHub
                      ? 'Permissions as SportsHub has them: when SportsHub changes this role, it changes here too.'
                      : 'Permissions changed for ${org.organisationName}: SportsHub\'s later changes to this role '
                          'won\'t reach it.',
                  action: _asSportsHub || _readOnly
                      ? null
                      : TextButton.icon(
                          onPressed: () => setState(() => _chosen
                            ..clear()
                            ..addAll(_defaults)),
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: const Text("Use SportsHub's"),
                        ),
                ),
              ],
            ],
            second: [
              for (final entry in groups.entries)
                _PermissionGroup(
                  title: _groupTitle(entry.key, RoleScope.venue, moduleNames),
                  permissions: entry.value,
                  ticked: (p) => _role.isLocked || _chosen.contains(p.key),
                  note: (p) {
                    if (_role.isLocked) return null;
                    final notes = [
                      if (_chosen.contains(p.key) != _defaults.contains(p.key))
                        _defaults.contains(p.key) ? "SportsHub's has it" : "Not in SportsHub's",
                      if (!_readOnly && !widget.canTick(p)) "You don't have this one",
                    ];
                    return notes.isEmpty ? null : notes.join(' · ');
                  },
                  onChanged: (p) => _readOnly || !widget.canTick(p)
                      ? null
                      : (on) => setState(() => on ? _chosen.add(p.key) : _chosen.remove(p.key)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final org = widget.organisation;
    final ok = await runAction(
      context,
      () => ref.read(accessRepositoryProvider).setOrganisationRole(
            organisationId: org.organisationId,
            roleId: _role.id,
            active: _onHere,
            permissionKeys: _asSportsHub ? null : _chosen,
          ),
      success: 'Saved for ${org.organisationName}',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      refreshRoles(ref, organisationId: org.organisationId);
      context.pop();
    }
  }
}

/// After a role changes: the lists of roles, the choices when giving one,
/// and the signed-in user's own menus (if one of their roles changed).
void refreshRoles(WidgetRef ref, {String? organisationId}) {
  ref.invalidate(rolesProvider);
  if (organisationId != null) ref.invalidate(organisationRolesProvider(organisationId));
  ref.invalidate(venueRoleChoicesProvider);
  ref.invalidate(myAccessProvider);
  ref.invalidate(myVenuesProvider);
}

bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

/// A group of permissions' heading: the core's, or the module's name.
String _groupTitle(String? moduleKey, String scope, Map<String, String> moduleNames) => moduleKey == null
    ? (scope == RoleScope.venue ? 'Venue' : 'SportsHub')
    : (moduleNames[moduleKey] ?? moduleKey);

/// One group of permissions as ticks, each with what it allows.
class _PermissionGroup extends StatelessWidget {
  final String title;
  final List<AppPermission> permissions;
  final bool Function(AppPermission) ticked;

  /// Said after its description, if anything.
  final String? Function(AppPermission) note;

  /// Null: it can't be changed.
  final ValueChanged<bool>? Function(AppPermission) onChanged;

  const _PermissionGroup({
    required this.title,
    required this.permissions,
    required this.ticked,
    required this.note,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, p) in permissions.indexed) ...[
                if (i > 0) const Divider(height: 1),
                CheckboxListTile(
                  value: ticked(p),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([if (p.description != null) p.description!, if (note(p) case final n?) n].join(' · ')),
                  onChanged: switch (onChanged(p)) {
                    final change? => (on) => change(on == true),
                    null => null,
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

/// A line of explanation in a card, with an icon and, maybe, an action.
class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Notice({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: context.colors.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(text)),
              ],
            ),
            if (action != null) Align(alignment: Alignment.centerRight, child: action!),
          ],
        ),
      ),
    );
  }
}

/// The page's Save button: as wide as its words on a wide screen, the whole
/// width on a phone. heightFactor 1: the bar is only as tall as the button
/// (a Scaffold's bottom bar may take the whole height, and the page body
/// would get none).
class _SaveBar extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _SaveBar({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: LayoutBuilder(
        builder: (context, c) => Align(
          alignment: Alignment.centerRight,
          heightFactor: 1,
          child: SizedBox(
            width: c.maxWidth >= 700 ? 260 : c.maxWidth,
            child: FilledButton(onPressed: onPressed, child: Text(label)),
          ),
        ),
      ),
    );
  }
}

/// A venue's Roles & permissions: its organisation's roles as its venues
/// have them. Whoever may change them (Roles at all of its venues) does it
/// here; other staff see them.
class VenueRolesScreen extends ConsumerWidget {
  final String venueId;

  const VenueRolesScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _WithOrganisation(
      venueId: venueId,
      title: 'Roles & permissions',
      builder: (organisationId) {
        final canManage = ref.watch(organisationRolesProvider(organisationId)).valueOrNull?.canManage ?? false;
        return AppPage(
          title: 'Roles & permissions',
          floatingActionButton: canManage
              ? FloatingActionButton.extended(
                  onPressed: () => context.push(CoreRoutes.venueRoleNewFor(venueId)),
                  icon: const Icon(Icons.add_moderator_outlined),
                  label: const Text('New own role'),
                )
              : null,
          body: OrganisationRolesView(
            organisationId: organisationId,
            roleRoute: (r) => CoreRoutes.venueRoleFor(venueId, r.id),
          ),
        );
      },
    );
  }
}

/// A role from a venue's Roles & permissions, as the venue's organisation
/// has it; a new role of its own when [roleId] is null.
class VenueRoleEditorScreen extends ConsumerWidget {
  final String venueId;
  final String? roleId;

  const VenueRoleEditorScreen({super.key, required this.venueId, this.roleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _WithOrganisation(
        venueId: venueId,
        title: 'Role',
        builder: (organisationId) => RoleEditorScreen(organisationId: organisationId, roleId: roleId),
      );
}

/// The organisation of a venue the signed-in user runs (or any venue, for
/// super admins), for [builder]; a lock for anyone else.
class _WithOrganisation extends ConsumerWidget {
  final String venueId;
  final String title;
  final Widget Function(String organisationId) builder;

  const _WithOrganisation({required this.venueId, required this.title, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<VenueAccess?>(
      value: ref.watch(venueAccessProvider(venueId)),
      onRetry: () => ref.invalidate(myVenuesProvider),
      data: (access) => switch (access?.venue.organisationId) {
        final organisationId? => builder(organisationId),
        null => AppPage(
            title: title,
            body: const EmptyState(icon: Icons.lock_outline_rounded, title: "You don't run this venue"),
          ),
      },
    );
  }
}

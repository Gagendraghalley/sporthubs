import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../module/module_providers.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../venues/venue_repository.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/feedback.dart';
import '../widgets/form_fields.dart';
import '../widgets/responsive.dart';

import 'access.dart';
import 'access_repository.dart';
import 'permission_gate.dart';

/// Admin -> Roles and permissions: the SportsHub team's roles and the venue
/// roles every venue chooses from.
class AdminRolesScreen extends ConsumerWidget {
  const AdminRolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PermissionGate(
      title: 'Roles and permissions',
      permission: PlatformPermission.roles,
      builder: (context, access) => AppPage(
        title: 'Roles and permissions',
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _newRole(context),
          icon: const Icon(Icons.add_moderator_outlined),
          label: const Text('New role'),
        ),
        body: AsyncValueView<List<AppRole>>(
          value: ref.watch(rolesProvider),
          onRetry: () => ref.invalidate(rolesProvider),
          data: (roles) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(rolesProvider);
              ref.invalidate(permissionsProvider);
            },
            child: ListView(
              padding: pagePadding(context, bottom: 96),
              children: [
                const FormHint(
                  'A role is a set of permissions. Super admins have every permission; everyone else gets what '
                  'their roles allow. Turning a role off takes its permissions away from everyone who has it.',
                ),
                for (final scope in const [RoleScope.platform, RoleScope.venue]) ...[
                  SectionTitle(scope == RoleScope.platform ? 'SportsHub team' : 'Venue staff'),
                  if (scope == RoleScope.venue)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: FormHint('Every venue chooses its staff\'s roles from these.'),
                    ),
                  _RolesTable(roles: [for (final r in roles) if (r.scope == scope) r]),
                ],
              ],
            ),
          ),
        ),
      ),
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
              subtitle: Text('Users, roles, master data, venues, modules'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, RoleScope.venue),
            child: const ListTile(
              leading: Icon(Icons.badge_outlined),
              title: Text('Venue staff'),
              subtitle: Text('Members, payments, check-in, plans, income'),
            ),
          ),
        ],
      ),
    );
    if (scope != null && context.mounted) context.push(CoreRoutes.adminRoleNewFor(scope));
  }
}

/// One group's roles as a table: the role, what it's for, how many
/// permissions, built in or made here, on or off; a row opens the role.
/// On a narrow window the role's cell carries what the hidden columns said.
class _RolesTable extends StatelessWidget {
  final List<AppRole> roles;

  const _RolesTable({required this.roles});

  static int _count(AppRole r) => r.isLocked ? 1 << 20 : r.permissions.length;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return DataGrid<AppRole>(
      rows: roles,
      noun: 'roles',
      rowLabel: (r) => 'Open ${r.name}',
      dimmed: (r) => !r.isActive,
      onRowTap: (r) => context.push(CoreRoutes.adminRoleFor(r.id)),
      columns: [
        GridColumn(
          key: 'role',
          label: 'Role',
          flex: 4,
          sortBy: (r) => r.name.toLowerCase(),
          cell: (context, r) => _RoleCell(role: r),
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
        GridColumn(
          key: 'type',
          label: 'Type',
          width: 120,
          showFrom: 700,
          sortBy: (r) => r.isSystem ? 0 : 1,
          cell: (context, r) => r.isSystem
              ? StatusChip(label: 'Built in', color: context.colors.tertiary)
              : StatusChip(label: 'Custom', color: brand.muted),
        ),
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 104,
          showFrom: 480,
          sortBy: (r) => r.isActive ? 0 : 1,
          cell: (context, r) => r.isActive
              ? StatusChip(label: 'Active', color: brand.success)
              : StatusChip(label: 'Off', color: brand.danger),
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

  const _RoleCell({required this.role});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = role.isActive ? context.colors.primary : brand.muted;
    final count = role.isLocked
        ? 'Every permission'
        : '${role.permissions.length} permission${role.permissions.length == 1 ? '' : 's'}';
    final carry = [
      if (!DataGrid.shows(context, 'permissions')) count,
      if (!DataGrid.shows(context, 'about') && role.description != null) role.description!,
    ];
    final badges = [
      if (!DataGrid.shows(context, 'type') && role.isSystem) StatusChip(label: 'Built in', color: context.colors.tertiary),
      if (!DataGrid.shows(context, 'status') && !role.isActive) StatusChip(label: 'Off', color: brand.danger),
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

/// A role's name, whether it's on, and its permissions: a new one of
/// [scope], or the role [roleId].
class RoleEditorScreen extends ConsumerWidget {
  final String? roleId;
  final String? scope;

  const RoleEditorScreen({super.key, this.roleId, this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              if (roleId != null && role == null) {
                return const AppPage(
                    title: 'Role',
                    body: EmptyState(icon: Icons.search_off_rounded, title: 'This role no longer exists'));
              }
              final s = role?.scope ?? (scope == RoleScope.platform ? RoleScope.platform : RoleScope.venue);
              return _RoleForm(
                key: ValueKey(role?.id ?? 'new-$s'),
                role: role,
                scope: s,
                permissions: perms.where((p) => p.scope == s).toList(),
                access: access,
              );
            },
          ),
        );
      },
    );
  }
}

class _RoleForm extends ConsumerStatefulWidget {
  final AppRole? role;
  final String scope;
  final List<AppPermission> permissions;
  final PlatformAccess access;

  const _RoleForm(
      {super.key, required this.role, required this.scope, required this.permissions, required this.access});

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

  /// Only super admins give team permissions they don't have themselves.
  bool _canTick(AppPermission p) =>
      !_locked && (widget.scope == RoleScope.venue || widget.access.isSuperAdmin || widget.access.can(p.key));

  @override
  Widget build(BuildContext context) {
    final role = widget.role;
    final moduleNames = {for (final m in ref.watch(registeredModulesProvider)) m.key: m.name};
    final groups = groupPermissions(widget.permissions);
    return AppPage(
      title: role == null ? 'New ${RoleScope.label(widget.scope).toLowerCase()} role' : role.name,
      actions: [
        if (role != null && !role.isSystem)
          IconButton(tooltip: 'Delete role', icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
      ],
      bottomBar: _locked
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: LayoutBuilder(
                // A button that fits its words on a wide screen; the whole
                // width on a phone. heightFactor 1: the bar is only as tall
                // as the button (a Scaffold's bottom bar may take the whole
                // height, and the page body would get none).
                builder: (context, c) => Align(
                  alignment: Alignment.centerRight,
                  heightFactor: 1,
                  child: SizedBox(
                    width: c.maxWidth >= 700 ? 260 : c.maxWidth,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(role == null ? 'Make role' : 'Save'),
                    ),
                  ),
                ),
              ),
            ),
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
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SectionCard(
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, color: context.colors.primary),
                      const SizedBox(width: 12),
                      const Expanded(
                          child: Text("A venue's Owner can always do everything there. This role can't be changed.")),
                    ],
                  ),
                ),
              ),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    enabled: !_locked,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Name *', hintText: 'e.g. Cashier'),
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the role\'s name' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _description,
                    enabled: !_locked,
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
                    onChanged: _locked ? null : (v) => setState(() => _active = v),
                  ),
                ],
              ),
            ),
              ],
              second: [
            for (final entry in groups.entries) ...[
              SectionTitle(entry.key == null
                  ? (widget.scope == RoleScope.venue ? 'Venue' : 'SportsHub')
                  : (moduleNames[entry.key] ?? entry.key!)),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (i, p) in entry.value.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      CheckboxListTile(
                        value: _locked || _chosen.contains(p.key),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          [
                            if (p.description != null) p.description!,
                            if (!_locked && !_canTick(p)) "You don't have this one"
                          ].join(' · '),
                        ),
                        onChanged: _canTick(p)
                            ? (on) => setState(() => on == true ? _chosen.add(p.key) : _chosen.remove(p.key))
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            ],
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
          ),
      success: widget.role == null ? 'Role made' : 'Saved',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _refresh();
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
      _refresh();
      context.pop();
    }
  }

  void _refresh() {
    ref.invalidate(rolesProvider);
    // Their own menus, if one of their roles changed.
    ref.invalidate(myAccessProvider);
    ref.invalidate(myVenuesProvider);
  }
}

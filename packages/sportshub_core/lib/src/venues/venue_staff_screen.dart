import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../access/access.dart';
import '../access/access_repository.dart';
import '../access/user_screens.dart' show VenueRoleField;
import '../auth/auth_repository.dart';
import '../theme/brand.dart';
import '../utils/validators.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/feedback.dart';
import '../widgets/form_fields.dart';
import '../widgets/responsive.dart';

import 'venue.dart';
import 'venue_repository.dart';

/// The venue roles [venue] lets someone give: SportsHub's user managers any
/// (Owner too); at the venue, roles whose every permission they have
/// themselves, never Owner. The database checks the same.
List<AppRole> givableVenueRoles(List<AppRole> roles, VenueAccess? venue, PlatformAccess platform) {
  if (platform.can(PlatformPermission.users)) return roles;
  if (venue == null || !venue.can(VenuePermission.staff)) return const [];
  return [
    for (final r in roles)
      if (!r.isLocked && r.permissions.every(venue.can)) r,
  ];
}

/// Who runs a venue. Whoever may manage its staff adds people (by their
/// SportsHub account, or making one), changes their roles and removes them.
class VenueStaffScreen extends ConsumerWidget {
  final String venueId;

  const VenueStaffScreen({super.key, required this.venueId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(venueAccessProvider(venueId)).valueOrNull;
    final platform = ref.watch(myAccessProvider).valueOrNull ?? PlatformAccess.none;
    final roles = givableVenueRoles(ref.watch(venueRolesProvider).valueOrNull ?? const [], access, platform);
    final canEdit = roles.isNotEmpty;
    final me = ref.watch(currentUserIdProvider);
    return AppPage(
      title: 'Staff',
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _add(context, ref, roles),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add staff'),
            )
          : null,
      body: AsyncValueView<List<VenueStaffMember>>(
        value: ref.watch(venueStaffProvider(venueId)),
        onRetry: () => ref.invalidate(venueStaffProvider(venueId)),
        data: (staff) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(venueStaffProvider(venueId)),
          child: ListView(
            padding: pagePadding(context, bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: FormHint(canEdit
                    ? 'Each role decides what its people can do here. Add someone who already has a SportsHub '
                        'account by their email, or make their account: they sign in with the code SportsHub emails them.'
                    : 'Who runs this venue.'),
              ),
              ResponsiveGrid(
                minItemWidth: 360,
                maxColumns: 3,
                children: [
                  for (final s in staff)
                    MenuTile(
                      icon: s.role == VenueRole.owner ? Icons.workspace_premium_outlined : Icons.badge_outlined,
                      title: s.userId == me ? '${s.name} (you)' : s.name,
                      subtitle: [s.roleName, if (s.email != null) s.email!].join(' · '),
                      onTap: _canChange(s, roles, me) ? () => _change(context, ref, s, roles) : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Not the owner (unless they may give Owner), not themselves, and only
  /// people whose role they could give.
  bool _canChange(VenueStaffMember s, List<AppRole> roles, String? me) {
    if (s.userId == me) return false;
    return roles.any((r) => r.key == s.role);
  }

  Future<void> _add(BuildContext context, WidgetRef ref, List<AppRole> roles) async {
    final result = await showDialog<_NewStaff>(context: context, builder: (_) => _AddStaffDialog(roles: roles));
    if (result == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () async {
        if (result.newAccount) {
          await ref.read(accessRepositoryProvider).createUser(
                email: result.email,
                fullName: result.name!,
                phone: result.phone,
                venueId: venueId,
                venueRole: result.role,
              );
        } else {
          await ref.read(venueRepositoryProvider).addStaff(venueId, result.email, result.role);
        }
      },
      success: result.newAccount ? 'Account made and added' : 'Added',
    );
    if (ok) ref.invalidate(venueStaffProvider(venueId));
  }

  Future<void> _change(BuildContext context, WidgetRef ref, VenueStaffMember s, List<AppRole> roles) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(s.name, style: context.text.titleMedium), subtitle: Text(s.roleName)),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Change role'),
              onTap: () => Navigator.pop(context, 'role'),
            ),
            ListTile(
              leading: Icon(Icons.person_remove_outlined, color: context.brand.danger),
              title: Text('Remove from staff', style: TextStyle(color: context.brand.danger)),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'remove') {
      final sure = await confirmAction(context, title: 'Remove ${s.name}?', confirmLabel: 'Remove', destructive: true);
      if (!sure || !context.mounted) return;
      final ok = await runAction(context, () => ref.read(venueRepositoryProvider).removeStaff(venueId, s.userId));
      if (ok) ref.invalidate(venueStaffProvider(venueId));
      return;
    }
    final role = await showDialog<String>(
        context: context, builder: (_) => _RoleDialog(name: s.name, roles: roles, current: s.role));
    if (role == null || role == s.role || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(venueRepositoryProvider).setStaffRole(venueId, s.userId, role),
      success: 'Role changed',
    );
    if (ok) ref.invalidate(venueStaffProvider(venueId));
  }
}

class _NewStaff {
  final bool newAccount;
  final String email;
  final String? name;
  final String? phone;
  final String role;

  const _NewStaff({required this.newAccount, required this.email, required this.role, this.name, this.phone});
}

class _AddStaffDialog extends StatefulWidget {
  final List<AppRole> roles;

  const _AddStaffDialog({required this.roles});

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _newAccount = false;
  late String? _role = widget.roles.where((r) => r.key == VenueRole.staff).firstOrNull?.key;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add staff'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Has an account')),
                    ButtonSegment(value: true, label: Text('Make their account')),
                  ],
                  selected: {_newAccount},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _newAccount = s.first),
                ),
                const SizedBox(height: 16),
                if (_newAccount) ...[
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Full name *'),
                    validator: (v) => Validators.required(v, 'Name'),
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _email,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: _newAccount ? 'Email *' : 'Their SportsHub email *'),
                  validator: Validators.email,
                ),
                if (_newAccount) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone', hintText: '17123456'),
                    validator: Validators.phone,
                  ),
                ],
                const SizedBox(height: 14),
                VenueRoleField(roles: widget.roles, value: _role, onChanged: (r) => setState(() => _role = r)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              _NewStaff(
                newAccount: _newAccount,
                email: _email.text.trim(),
                name: _newAccount ? _name.text.trim() : null,
                phone: _newAccount ? Validators.normalizePhone(_phone.text) : null,
                role: _role!,
              ),
            );
          },
          child: Text(_newAccount ? 'Make account' : 'Add'),
        ),
      ],
    );
  }
}

class _RoleDialog extends StatefulWidget {
  final String name;
  final List<AppRole> roles;
  final String current;

  const _RoleDialog({required this.name, required this.roles, required this.current});

  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<_RoleDialog> {
  late String? _role = widget.current;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("${widget.name}'s role"),
      content: SizedBox(
        width: 420,
        child: VenueRoleField(roles: widget.roles, value: _role, onChanged: (r) => setState(() => _role = r)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _role == null ? null : () => Navigator.pop(context, _role), child: const Text('Save')),
      ],
    );
  }
}

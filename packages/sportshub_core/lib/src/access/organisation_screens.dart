import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../venues/venue.dart';
import '../venues/venue_repository.dart';
import '../venues/venue_widgets.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/feedback.dart';
import '../widgets/form_fields.dart';
import '../widgets/motion.dart';
import '../widgets/searchable_dropdown.dart';

import 'access.dart';
import 'access_repository.dart';
import 'permission_gate.dart';
import 'role_screens.dart' show refreshRoles;

/// Admin -> Organisations: the businesses on SportsHub. Every venue belongs
/// to one; put a business's branches in one organisation, and its roles and
/// permissions are the same at all of them.
class AdminOrganisationsScreen extends ConsumerStatefulWidget {
  const AdminOrganisationsScreen({super.key});

  @override
  ConsumerState<AdminOrganisationsScreen> createState() => _AdminOrganisationsScreenState();
}

class _AdminOrganisationsScreenState extends ConsumerState<AdminOrganisationsScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      title: 'Organisations',
      permission: PlatformPermission.organisations,
      builder: (context, access) => AppPage(
        title: 'Organisations',
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _new,
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('New organisation'),
        ),
        body: AsyncValueView<List<Organisation>>(
          value: ref.watch(organisationsProvider),
          onRetry: () => ref.invalidate(organisationsProvider),
          data: (all) {
            final words = _search.toLowerCase();
            final shown = words.isEmpty
                ? all
                : [for (final o in all) if ('${o.name} ${o.description ?? ''}'.toLowerCase().contains(words)) o];
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(organisationsProvider),
              child: ListView(
                padding: pagePadding(context, bottom: 96),
                children: [
                  const FormHint(
                    'Every venue belongs to an organisation: the business that runs it. A new venue gets one of its '
                    'own, named after it. Put a business\'s branches in one organisation, and its roles and '
                    'permissions are the same at all of them.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded), hintText: 'Find an organisation'),
                    onChanged: (v) => setState(() => _search = v.trim()),
                  ),
                  const SizedBox(height: 12),
                  if (shown.isEmpty)
                    EmptyState(
                      icon: Icons.apartment_rounded,
                      title: all.isEmpty ? 'No organisations yet' : 'None match "$_search"',
                    )
                  else
                    _OrganisationsTable(
                      organisations: shown,
                      onOpen: (o) => context.push(CoreRoutes.adminOrganisationFor(o.id)),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _new() async {
    final draft = await showAppDialog<_OrganisationDraft>(context: context, builder: (_) => const _OrganisationDialog());
    if (draft == null || !mounted) return;
    String? id;
    final ok = await runAction(context, () async {
      id = await ref.read(accessRepositoryProvider).saveOrganisation(name: draft.name, description: draft.description);
    }, success: 'Organisation made');
    if (!ok || !mounted) return;
    ref.invalidate(organisationsProvider);
    context.push(CoreRoutes.adminOrganisationFor(id!));
  }
}

/// Organisations as a table: the organisation and how many venues it runs.
class _OrganisationsTable extends StatelessWidget {
  final List<Organisation> organisations;
  final ValueChanged<Organisation> onOpen;

  const _OrganisationsTable({required this.organisations, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    String venues(Organisation o) => o.venueCount == 1 ? '1 venue' : '${o.venueCount} venues';
    return DataGrid<Organisation>(
      rows: organisations,
      noun: 'organisations',
      rowLabel: (o) => 'Open ${o.name}',
      dimmed: (o) => o.venueCount == 0,
      onRowTap: onOpen,
      columns: [
        GridColumn(
          key: 'organisation',
          label: 'Organisation',
          flex: 5,
          sortBy: (o) => o.name.toLowerCase(),
          cell: (context, o) {
            final tint = context.colors.primary;
            final carry = [
              if (!DataGrid.shows(context, 'venues')) venues(o),
              if (o.description != null) o.description!,
            ];
            return Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: tint.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
                  child: Icon(Icons.apartment_rounded, color: tint, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(o.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                      if (carry.isNotEmpty)
                        Text(carry.join(' · '),
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        GridColumn(
          key: 'venues',
          label: 'Venues',
          width: 110,
          showFrom: 560,
          alignEnd: true,
          sortBy: (o) => o.venueCount,
          cell: (context, o) => Text(venues(o), style: TextStyle(color: brand.body, fontWeight: FontWeight.w600)),
        ),
        GridColumn(
          key: 'open',
          label: '',
          width: 40,
          alignEnd: true,
          cell: (context, o) => Icon(Icons.chevron_right_rounded, color: brand.muted),
        ),
      ],
    );
  }
}

/// One organisation: its name, its venues (bring one in, or move one to
/// another organisation), and the way to its roles.
class AdminOrganisationScreen extends ConsumerWidget {
  final String organisationId;

  const AdminOrganisationScreen({super.key, required this.organisationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PermissionGate(
      title: 'Organisation',
      permission: PlatformPermission.organisations,
      builder: (context, access) => AsyncValueView<List<Organisation>>(
        value: ref.watch(organisationsProvider),
        onRetry: () => ref.invalidate(organisationsProvider),
        data: (all) {
          final org = all.where((o) => o.id == organisationId).firstOrNull;
          if (org == null) {
            return const AppPage(
              title: 'Organisation',
              body: EmptyState(icon: Icons.search_off_rounded, title: 'This organisation no longer exists'),
            );
          }
          final venues = ref.watch(organisationVenuesProvider(org.id));
          return AppPage(
            title: org.name,
            actions: [
              IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(context, ref, org)),
              if (org.venueCount == 0)
                IconButton(
                  tooltip: 'Delete organisation',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => _delete(context, ref, org),
                ),
            ],
            body: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(organisationsProvider);
                ref.invalidate(organisationVenuesProvider(org.id));
              },
              child: ListView(
                padding: pagePadding(context, bottom: 48),
                children: [
                  SectionCard(
                    child: Row(
                      children: [
                        Icon(Icons.apartment_rounded, color: context.colors.primary, size: 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(org.name, style: context.text.titleLarge),
                              if (org.description != null) Text(org.description!, style: TextStyle(color: context.brand.body)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SectionTitle(
                    'Venues',
                    trailing: TextButton.icon(
                      onPressed: () => _bringIn(context, ref, org),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add a venue'),
                    ),
                  ),
                  AsyncValueView<List<Venue>>(
                    value: venues,
                    loading: const LoadingSkeleton.rows(),
                    onRetry: () => ref.invalidate(organisationVenuesProvider(org.id)),
                    data: (list) => list.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                            child: FormHint('No venues. Add one: it leaves the organisation it is in now.'),
                          )
                        : _VenuesTable(venues: list, onMove: (v) => _moveOut(context, ref, org, v)),
                  ),
                  if (access.can(PlatformPermission.users) || access.can(PlatformPermission.roles))
                    const SectionTitle('People and roles'),
                  if (access.can(PlatformPermission.users))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: MenuTile(
                        icon: Icons.people_alt_outlined,
                        title: 'Its people',
                        subtitle: 'Everyone who works at its venues, and their roles',
                        onTap: () => context.push(CoreRoutes.adminUsersFor(org.id)),
                      ),
                    ),
                  if (access.can(PlatformPermission.roles))
                    MenuTile(
                      icon: Icons.verified_user_outlined,
                      title: 'Roles and permissions',
                      subtitle: "Its own roles, and what SportsHub's roles allow at its venues",
                      onTap: () => context.push(CoreRoutes.adminRolesFor(org.id)),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Organisation org) async {
    final draft = await showAppDialog<_OrganisationDraft>(context: context, builder: (_) => _OrganisationDialog(current: org));
    if (draft == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref
          .read(accessRepositoryProvider)
          .saveOrganisation(organisationId: org.id, name: draft.name, description: draft.description),
      success: 'Saved',
    );
    if (ok) {
      ref.invalidate(organisationsProvider);
      ref.invalidate(organisationRolesProvider(org.id));
      ref.invalidate(myVenuesProvider);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Organisation org) async {
    final sure = await confirmAction(
      context,
      title: 'Delete ${org.name}?',
      message: 'Its own roles, and what it changed in SportsHub\'s, go with it.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!sure || !context.mounted) return;
    final ok = await runAction(context, () => ref.read(accessRepositoryProvider).deleteOrganisation(org.id),
        success: 'Deleted');
    if (ok && context.mounted) {
      ref.invalidate(organisationsProvider);
      context.pop();
    }
  }

  /// Brings a venue in from another organisation.
  Future<void> _bringIn(BuildContext context, WidgetRef ref, Organisation org) async {
    final venueId = await showAppDialog<String>(
      context: context,
      builder: (_) => _ChooseDialog(
        title: 'Add a venue to ${org.name}',
        label: 'Venue',
        hint: 'It leaves the organisation it is in now. Its staff keep SportsHub roles, as ${org.name} has them; '
            'staff on its old organisation\'s own roles need other roles first.',
        options: (ref) => [
          for (final v in ref.watch(allVenuesProvider).valueOrNull ?? const <Venue>[])
            if (v.organisationId != org.id) DropdownOption(v.id, v.name, detail: v.place),
        ],
        confirmLabel: 'Add',
      ),
    );
    if (venueId == null || !context.mounted) return;
    await _move(context, ref, venueId, org.id, success: 'Added to ${org.name}');
  }

  /// Moves [venue] to another organisation.
  Future<void> _moveOut(BuildContext context, WidgetRef ref, Organisation org, Venue venue) async {
    final target = await showAppDialog<String>(
      context: context,
      builder: (_) => _ChooseDialog(
        title: 'Move ${venue.name}',
        label: 'To organisation',
        hint: 'Its roles become as the new organisation has them.',
        options: (ref) => [
          for (final o in ref.watch(organisationsProvider).valueOrNull ?? const <Organisation>[])
            if (o.id != org.id) DropdownOption(o.id, o.name, detail: o.venueCount == 1 ? '1 venue' : '${o.venueCount} venues'),
        ],
        confirmLabel: 'Move',
      ),
    );
    if (target == null || !context.mounted) return;
    await _move(context, ref, venue.id, target, success: 'Moved');
  }

  Future<void> _move(BuildContext context, WidgetRef ref, String venueId, String organisationId,
      {required String success}) async {
    final ok = await runAction(
      context,
      () => ref.read(accessRepositoryProvider).setVenueOrganisation(venueId, organisationId),
      success: success,
    );
    if (!ok) return;
    ref.invalidate(organisationsProvider);
    ref.invalidate(organisationVenuesProvider);
    ref.invalidate(allVenuesProvider);
    ref.invalidate(organisationRolesProvider);
    ref.invalidate(venueProvider(venueId));
    refreshRoles(ref);
  }
}

/// An organisation's venues: the venue, where, and whether it's verified;
/// each can move to another organisation.
class _VenuesTable extends StatelessWidget {
  final List<Venue> venues;
  final ValueChanged<Venue> onMove;

  const _VenuesTable({required this.venues, required this.onMove});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return DataGrid<Venue>(
      rows: venues,
      noun: 'venues',
      columns: [
        GridColumn(
          key: 'venue',
          label: 'Venue',
          flex: 4,
          sortBy: (v) => v.name.toLowerCase(),
          cell: (context, v) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(v.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
              if (!DataGrid.shows(context, 'place'))
                Text(v.place, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13)),
              if (!DataGrid.shows(context, 'status'))
                Padding(padding: const EdgeInsets.only(top: 4), child: VerificationChip(status: v.verificationStatus)),
            ],
          ),
        ),
        GridColumn(
          key: 'place',
          label: 'Where',
          flex: 3,
          showFrom: 700,
          sortBy: (v) => v.place.toLowerCase(),
          cell: (context, v) => Text(v.place, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 136,
          showFrom: 520,
          sortBy: (v) => v.verificationStatus,
          cell: (context, v) => VerificationChip(status: v.verificationStatus),
        ),
        GridColumn(
          key: 'move',
          label: '',
          width: 48,
          alignEnd: true,
          cell: (context, v) => IconButton(
            tooltip: 'Move to another organisation',
            icon: Icon(Icons.drive_file_move_outline, color: brand.muted),
            onPressed: () => onMove(v),
          ),
        ),
      ],
    );
  }
}

class _OrganisationDraft {
  final String name;
  final String? description;

  const _OrganisationDraft(this.name, this.description);
}

/// An organisation's name and what it is.
class _OrganisationDialog extends StatefulWidget {
  final Organisation? current;

  const _OrganisationDialog({this.current});

  @override
  State<_OrganisationDialog> createState() => _OrganisationDialogState();
}

class _OrganisationDialogState extends State<_OrganisationDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.current?.name ?? '');
  late final _description = TextEditingController(text: widget.current?.description ?? '');

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.current == null ? 'New organisation' : 'Rename organisation'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Name *', hintText: 'e.g. Druk Fitness Pvt Ltd'),
                validator: (v) => (v ?? '').trim().length < 2 ? "Enter the organisation's name" : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _description,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'About it'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final about = _description.text.trim();
            Navigator.pop(context, _OrganisationDraft(_name.text.trim(), about.isEmpty ? null : about));
          },
          child: Text(widget.current == null ? 'Make' : 'Save'),
        ),
      ],
    );
  }
}

/// Choose one of [options] (read as they load); pops its value.
class _ChooseDialog extends ConsumerStatefulWidget {
  final String title;
  final String label;
  final String hint;
  final List<DropdownOption<String>> Function(WidgetRef ref) options;
  final String confirmLabel;

  const _ChooseDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.options,
    required this.confirmLabel,
  });

  @override
  ConsumerState<_ChooseDialog> createState() => _ChooseDialogState();
}

class _ChooseDialogState extends ConsumerState<_ChooseDialog> {
  final _form = GlobalKey<FormState>();
  String? _value;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormHint(widget.hint),
              const SizedBox(height: 14),
              SearchableDropdown<String>(
                value: _value,
                decoration: InputDecoration(labelText: '${widget.label} *'),
                options: widget.options(ref),
                onChanged: (v) => setState(() => _value = v),
                validator: (v) => v == null ? 'Choose one' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) Navigator.pop(context, _value);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

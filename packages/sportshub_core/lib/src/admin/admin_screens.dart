import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../access/access.dart';
import '../access/permission_gate.dart';
import '../module/app_module_row.dart';
import '../module/module_providers.dart';
import '../module/sportshub_module.dart';
import '../router/core_routes.dart';
import '../shell/platform_shell.dart' show ServiceIconTile;
import '../theme/brand.dart';
import '../utils/formatters.dart';
import '../venues/venue.dart';
import '../venues/venue_widgets.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/data_grid.dart';
import '../widgets/feedback.dart';
import '../widgets/responsive.dart';
import 'admin_repository.dart';

/// SportsHub admin: what the signed-in member of the team may open, by
/// their permissions (super admins see everything).
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PermissionGate(
      title: 'Admin',
      builder: (context, access) {
        final pending = access.can(PlatformPermission.venuesVerify) ? ref.watch(pendingVenuesProvider).valueOrNull?.length : null;
        final tiles = [
          if (access.can(PlatformPermission.users))
            MenuTile(
              icon: Icons.manage_accounts_outlined,
              title: 'Users',
              subtitle: 'Make accounts, give roles, turn people off',
              onTap: () => context.push(CoreRoutes.adminUsers),
            ),
          if (access.can(PlatformPermission.roles))
            MenuTile(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Roles and permissions',
              subtitle: "The team's roles, and venue roles: SportsHub-wide or an organisation's own",
              onTap: () => context.push(CoreRoutes.adminRoles),
            ),
          if (access.can(PlatformPermission.organisations))
            MenuTile(
              icon: Icons.apartment_rounded,
              title: 'Organisations',
              subtitle: 'The businesses that run venues, and their branches',
              onTap: () => context.push(CoreRoutes.adminOrganisations),
            ),
          if (access.can(PlatformPermission.masters))
            MenuTile(
              icon: Icons.map_outlined,
              title: 'Master data',
              subtitle: 'Dzongkhags, gewogs and villages',
              onTap: () => context.push(CoreRoutes.adminMasters),
            ),
          if (access.can(PlatformPermission.venuesVerify))
            MenuTile(
              icon: Icons.verified_outlined,
              title: 'Venues to verify',
              subtitle: pending == null ? null : (pending == 0 ? 'None waiting' : '$pending waiting'),
              onTap: () => context.push(CoreRoutes.adminVenues),
            ),
          if (access.can(PlatformPermission.modules))
            MenuTile(
              icon: Icons.extension_outlined,
              title: 'Modules',
              subtitle: 'Turn gym membership and others on or off',
              onTap: () => context.push(CoreRoutes.adminModules),
            ),
        ];
        return AppPage(
          title: 'SportsHub admin',
          body: ListView(
            padding: pagePadding(context),
            children: [ResponsiveGrid(minItemWidth: 360, maxColumns: 3, children: tiles)],
          ),
        );
      },
    );
  }
}

class AdminVenuesScreen extends ConsumerWidget {
  const AdminVenuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PermissionGate(
      title: 'Venues to verify',
      permission: PlatformPermission.venuesVerify,
      builder: (context, _) => AppPage(
        title: 'Venues to verify',
        body: AsyncValueView<List<Venue>>(
          value: ref.watch(pendingVenuesProvider),
          onRetry: () => ref.invalidate(pendingVenuesProvider),
          data: (venues) => venues.isEmpty
              ? const EmptyState(icon: Icons.task_alt_rounded, title: 'All caught up', message: 'No venues are waiting.')
              : ListView(
                  padding: pagePadding(context),
                  children: [_PendingVenuesTable(venues: venues)],
                ),
        ),
      ),
    );
  }
}

/// Sends [venue] back (asking why) or verifies it (asking first); true when
/// it was done.
Future<bool> _reviewVenue(BuildContext context, WidgetRef ref, Venue venue, {required bool approve}) async {
  String? note;
  if (!approve) {
    note = await askText(context, title: 'Why is it sent back?', hint: 'The owner sees this', required: true);
    if (note == null) return false;
  } else {
    final sure =
        await confirmAction(context, title: 'Verify ${venue.name}?', message: 'It goes live for everyone.', confirmLabel: 'Verify');
    if (!sure) return false;
  }
  if (!context.mounted) return false;
  final ok = await runAction(
    context,
    () => ref.read(adminRepositoryProvider).reviewVenue(venue.id, approve: approve, note: note),
    success: approve ? '${venue.name} is live' : 'Sent back to the owner',
  );
  if (ok) ref.invalidate(pendingVenuesProvider);
  return ok;
}

/// The venues waiting, as a table: the venue, where, its phone, when it was
/// sent, and Send back / Verify. A row opens it in full (photos and all)
/// to review.
class _PendingVenuesTable extends ConsumerWidget {
  final List<Venue> venues;

  const _PendingVenuesTable({required this.venues});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    return DataGrid<Venue>(
      rows: venues,
      noun: 'venues',
      rowLabel: (v) => 'Review ${v.name}',
      onRowTap: (v) => showAppDialog<void>(context: context, builder: (_) => _ReviewVenueDialog(venue: v)),
      columns: [
        GridColumn(
          key: 'venue',
          label: 'Venue',
          flex: 4,
          sortBy: (v) => v.name.toLowerCase(),
          cell: (context, v) => Row(
            children: [
              _VenueThumb(venue: v),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(v.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                    Text(
                      DataGrid.shows(context, 'place') ? _typeLabel(v.type) : '${_typeLabel(v.type)} · ${v.place}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: brand.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        GridColumn(
          key: 'place',
          label: 'Where',
          flex: 3,
          showFrom: 720,
          sortBy: (v) => v.place.toLowerCase(),
          cell: (context, v) => Text(v.place, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'phone',
          label: 'Phone',
          flex: 2,
          showFrom: 1050,
          cell: (context, v) => Text(v.phone ?? '—', style: TextStyle(color: v.phone == null ? brand.muted : brand.body)),
        ),
        GridColumn(
          key: 'sent',
          label: 'Sent',
          flex: 2,
          showFrom: 880,
          sortBy: (v) => v.createdAt,
          cell: (context, v) => Text(formatMoment(v.createdAt), style: TextStyle(color: brand.body)),
        ),
        GridColumn(
          key: 'actions',
          label: '',
          width: 236,
          showFrom: 640,
          alignEnd: true,
          cell: (context, v) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: () => _reviewVenue(context, ref, v, approve: false),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14)),
                child: const Text('Send back'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _reviewVenue(context, ref, v, approve: true),
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14)),
                child: const Text('Verify'),
              ),
            ],
          ),
        ),
        GridColumn(
          key: 'open',
          label: '',
          width: 40,
          alignEnd: true,
          cell: (context, v) => Icon(Icons.chevron_right_rounded, color: brand.muted),
        ),
      ],
    );
  }
}

/// 'gym' -> 'Gym'.
String _typeLabel(String type) => type.isEmpty ? type : type[0].toUpperCase() + type.substring(1).replaceAll('_', ' ');

/// The venue's first photo, small; its icon without one.
class _VenueThumb extends StatelessWidget {
  final Venue venue;

  const _VenueThumb({required this.venue});

  @override
  Widget build(BuildContext context) {
    final tint = context.colors.tertiary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 44,
        height: 44,
        child: venue.photos.isEmpty
            ? ColoredBox(color: tint.withValues(alpha: 0.12), child: Icon(Icons.storefront_rounded, color: tint, size: 22))
            : Image.network(
                venue.photos.first,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    ColoredBox(color: tint.withValues(alpha: 0.12), child: Icon(Icons.storefront_rounded, color: tint, size: 22)),
              ),
      ),
    );
  }
}

/// One waiting venue in full, to review: its photos and details, and Send
/// back or Verify.
class _ReviewVenueDialog extends ConsumerWidget {
  final Venue venue;

  const _ReviewVenueDialog({required this.venue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> review(bool approve) async {
      final done = await _reviewVenue(context, ref, venue, approve: approve);
      if (done && context.mounted) Navigator.of(context).pop();
    }

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(venue.name)),
          StatusChip(label: _typeLabel(venue.type), color: context.colors.tertiary),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (venue.photos.isNotEmpty) ...[VenuePhotoCarousel(photos: venue.photos), const SizedBox(height: 12)],
              InfoRow(icon: Icons.place_outlined, text: [venue.place, if (venue.address != null) venue.address!].join(' · ')),
              if (venue.phone != null) InfoRow(icon: Icons.call_outlined, text: venue.phone!),
              if (venue.description != null) InfoRow(icon: Icons.notes_rounded, text: venue.description!),
              InfoRow(icon: Icons.schedule_rounded, text: 'Sent ${formatMoment(venue.createdAt)}'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        OutlinedButton(onPressed: () => review(false), child: const Text('Send back')),
        FilledButton(onPressed: () => review(true), child: const Text('Verify')),
      ],
    );
  }
}

class AdminModulesScreen extends ConsumerWidget {
  const AdminModulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registered = {for (final m in ref.watch(registeredModulesProvider)) m.key: m};
    return PermissionGate(
      title: 'Modules',
      permission: PlatformPermission.modules,
      builder: (context, _) => AppPage(
        title: 'Modules',
        body: AsyncValueView<List<AppModuleRow>>(
          value: ref.watch(appModulesProvider),
          onRetry: () => ref.invalidate(appModulesProvider),
          data: (rows) => ListView(
            padding: pagePadding(context),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  'A module that is off is hidden from everyone but admins, so you can try it first.',
                  style: TextStyle(color: context.brand.muted),
                ),
              ),
              _ModulesTable(rows: rows, registered: registered),
            ],
          ),
        ),
      ),
    );
  }
}

/// The modules as a table: the service, what it does, on or off, and its
/// switch; tapping a row flips it too. A module this version of the app
/// doesn't have says so.
class _ModulesTable extends ConsumerWidget {
  final List<AppModuleRow> rows;
  final Map<String, SportsHubModule> registered;

  const _ModulesTable({required this.rows, required this.registered});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    Future<void> toggle(AppModuleRow row, bool on) async {
      final ok = await runAction(
        context,
        () => ref.read(adminRepositoryProvider).setModuleEnabled(row.key, on),
        success: '${row.name} is ${on ? 'on' : 'off'}',
      );
      if (ok) ref.invalidate(appModulesProvider);
    }

    String about(AppModuleRow row) => registered[row.key]?.description ?? 'Not in this version of the app';
    return DataGrid<AppModuleRow>(
      rows: rows,
      noun: 'modules',
      rowLabel: (r) => 'Turn ${r.name} ${r.isEnabled ? 'off' : 'on'}',
      dimmed: (r) => !r.isEnabled,
      onRowTap: (r) => toggle(r, !r.isEnabled),
      columns: [
        GridColumn(
          key: 'module',
          label: 'Service',
          flex: 3,
          sortBy: (r) => r.name.toLowerCase(),
          cell: (context, r) {
            final module = registered[r.key];
            final color = module?.color ?? brand.muted;
            return Row(
              children: [
                ServiceIconTile(icon: module?.icon ?? Icons.extension_outlined, color: color, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink)),
                      if (!DataGrid.shows(context, 'about'))
                        Text(about(r),
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: brand.muted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        GridColumn(
          key: 'about',
          label: 'What it does',
          flex: 5,
          showFrom: 720,
          cell: (context, r) => Text(about(r),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: registered[r.key] == null ? brand.muted : brand.body, height: 1.35)),
        ),
        GridColumn(
          key: 'status',
          label: 'Status',
          width: 104,
          showFrom: 520,
          sortBy: (r) => r.isEnabled ? 0 : 1,
          cell: (context, r) => r.isEnabled
              ? StatusChip(label: 'On', color: brand.success)
              : StatusChip(label: 'Off', color: brand.muted),
        ),
        GridColumn(
          key: 'switch',
          label: '',
          width: 72,
          alignEnd: true,
          cell: (context, r) => Switch(value: r.isEnabled, onChanged: (on) => toggle(r, on)),
        ),
      ],
    );
  }
}

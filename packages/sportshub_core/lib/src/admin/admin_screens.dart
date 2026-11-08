import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../access/access.dart';
import '../access/permission_gate.dart';
import '../module/app_module_row.dart';
import '../module/module_providers.dart';
import '../module/sportshub_module.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../utils/formatters.dart';
import '../venues/venue.dart';
import '../venues/venue_widgets.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
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
              subtitle: "The team's roles and the venue roles staff get",
              onTap: () => context.push(CoreRoutes.adminRoles),
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
                  children: [
                    ResponsiveGrid(
                      minItemWidth: 420,
                      maxColumns: 3,
                      equalHeight: false,
                      children: [for (final v in venues) _PendingVenueCard(venue: v)],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PendingVenueCard extends ConsumerWidget {
  final Venue venue;

  const _PendingVenueCard({required this.venue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (venue.photos.isNotEmpty) ...[VenuePhotoCarousel(photos: venue.photos), const SizedBox(height: 12)],
          Row(
            children: [
              Expanded(child: Text(venue.name, style: context.text.titleMedium)),
              StatusChip(label: venue.type, color: context.colors.tertiary),
            ],
          ),
          const SizedBox(height: 6),
          InfoRow(icon: Icons.place_outlined, text: [venue.place, if (venue.address != null) venue.address!].join(' · ')),
          if (venue.phone != null) InfoRow(icon: Icons.call_outlined, text: venue.phone!),
          if (venue.description != null) InfoRow(icon: Icons.notes_rounded, text: venue.description!),
          InfoRow(icon: Icons.schedule_rounded, text: 'Sent ${formatMoment(venue.createdAt)}'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _review(context, ref, approve: false),
                  child: const Text('Send back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => _review(context, ref, approve: true),
                  child: const Text('Verify'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _review(BuildContext context, WidgetRef ref, {required bool approve}) async {
    String? note;
    if (!approve) {
      note = await askText(context, title: 'Why is it sent back?', hint: 'The owner sees this', required: true);
      if (note == null) return;
    } else {
      final sure = await confirmAction(context, title: 'Verify ${venue.name}?', message: 'It goes live for everyone.', confirmLabel: 'Verify');
      if (!sure) return;
    }
    if (!context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(adminRepositoryProvider).reviewVenue(venue.id, approve: approve, note: note),
      success: approve ? '${venue.name} is live' : 'Sent back to the owner',
    );
    if (ok) ref.invalidate(pendingVenuesProvider);
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
              ResponsiveGrid(
                minItemWidth: 340,
                maxColumns: 3,
                children: [
                  for (final row in rows) _ModuleTile(row: row, module: registered[row.key]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One module with its switch; tapping anywhere on the card flips it.
/// [module] is null for a module this version of the app doesn't have.
class _ModuleTile extends ConsumerWidget {
  final AppModuleRow row;
  final SportsHubModule? module;

  const _ModuleTile({required this.row, required this.module});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> toggle(bool on) async {
      final ok = await runAction(
        context,
        () => ref.read(adminRepositoryProvider).setModuleEnabled(row.key, on),
        success: '${row.name} is ${on ? 'on' : 'off'}',
      );
      if (ok) ref.invalidate(appModulesProvider);
    }

    return MenuTile(
      icon: module?.icon ?? Icons.extension_outlined,
      iconColor: module?.color ?? context.brand.muted,
      title: row.name,
      subtitle: module?.description ?? 'Not in this version of the app',
      trailing: Switch(value: row.isEnabled, onChanged: toggle),
      onTap: () => toggle(!row.isEnabled),
    );
  }
}

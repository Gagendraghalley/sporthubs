import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../module/app_module_row.dart';
import '../module/module_providers.dart';
import '../profiles/profile.dart';
import '../profiles/profile_repository.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../utils/formatters.dart';
import '../venues/venue.dart';
import '../venues/venue_widgets.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/feedback.dart';
import 'admin_repository.dart';

/// Only for the SportsHub team (profiles.role = 'admin'); the database
/// refuses anyone else whatever the app shows.
class _AdminOnly extends ConsumerWidget {
  final String title;
  final Widget Function(BuildContext context) builder;

  const _AdminOnly({required this.title, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<Profile?>(
      value: ref.watch(myProfileProvider),
      data: (p) => (p?.isAdmin ?? false)
          ? builder(context)
          : AppPage(title: title, body: const EmptyState(icon: Icons.lock_outline_rounded, title: 'For the SportsHub team only')),
    );
  }
}

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingVenuesProvider).valueOrNull?.length;
    return _AdminOnly(
      title: 'Admin',
      builder: (context) => AppPage(
        title: 'SportsHub admin',
        body: ListView(
          padding: pagePadding(context),
          children: [
            MenuTile(
              icon: Icons.verified_outlined,
              title: 'Venues to verify',
              subtitle: pending == null ? null : (pending == 0 ? 'None waiting' : '$pending waiting'),
              onTap: () => context.push(CoreRoutes.adminVenues),
            ),
            const SizedBox(height: 10),
            MenuTile(
              icon: Icons.extension_outlined,
              title: 'Modules',
              subtitle: 'Turn gym membership and others on or off',
              onTap: () => context.push(CoreRoutes.adminModules),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminVenuesScreen extends ConsumerWidget {
  const AdminVenuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AdminOnly(
      title: 'Venues to verify',
      builder: (context) => AppPage(
        title: 'Venues to verify',
        body: AsyncValueView<List<Venue>>(
          value: ref.watch(pendingVenuesProvider),
          onRetry: () => ref.invalidate(pendingVenuesProvider),
          data: (venues) => venues.isEmpty
              ? const EmptyState(icon: Icons.task_alt_rounded, title: 'All caught up', message: 'No venues are waiting.')
              : ListView.separated(
                  padding: pagePadding(context),
                  itemCount: venues.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _PendingVenueCard(venue: venues[i]),
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
    return _AdminOnly(
      title: 'Modules',
      builder: (context) => AppPage(
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
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: SwitchListTile(
                      secondary: Icon(registered[row.key]?.icon ?? Icons.extension_outlined),
                      title: Text(row.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(registered.containsKey(row.key)
                          ? registered[row.key]!.description
                          : 'Not in this version of the app'),
                      value: row.isEnabled,
                      onChanged: (on) async {
                        final ok = await runAction(
                          context,
                          () => ref.read(adminRepositoryProvider).setModuleEnabled(row.key, on),
                          success: '${row.name} is ${on ? 'on' : 'off'}',
                        );
                        if (ok) ref.invalidate(appModulesProvider);
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

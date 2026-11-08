import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../access/access.dart';
import '../access/access_repository.dart';
import '../module/module_providers.dart';
import '../module/sportshub_module.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/responsive.dart';
import '../widgets/service_cards.dart';
import 'service_nav.dart';

/// My services: every service on SportsHub, the ones they use (open them)
/// and the ones they could start (set them up). The same card for each, so
/// a tenth service sits beside the first.
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(myAccessProvider).valueOrNull ?? PlatformAccess.none;
    return AppPage(
      title: 'My services',
      actions: [
        if (access.can(PlatformPermission.modules))
          TextButton.icon(
            onPressed: () => context.go(CoreRoutes.adminModules),
            icon: const Icon(Icons.toggle_on_outlined),
            label: const Text('Turn services on or off'),
          ),
      ],
      body: AsyncValueView<List<SportsHubModule>>(
        value: ref.watch(enabledModulesProvider),
        onRetry: () => ref.invalidate(appModulesProvider),
        data: (modules) {
          final navs = {for (final s in serviceNavs(ref, CoreRoutes.services)) s.module.key: s.nav};
          final rows = {for (final r in ref.watch(appModulesProvider).valueOrNull ?? const []) r.key: r};
          final inUse = [for (final m in modules) if (navs[m.key]?.isSetUp ?? false) m];
          final others = [for (final m in modules) if (!(navs[m.key]?.isSetUp ?? false)) m];
          Widget grid(List<SportsHubModule> list) => ResponsiveGrid(
                minItemWidth: 320,
                maxColumns: 3,
                spacing: 16,
                runSpacing: 16,
                children: staggered([
                  for (final m in list) _ServiceTile(module: m, nav: navs[m.key], off: rows[m.key]?.isEnabled == false),
                ]),
              );
          return ListView(
            padding: pagePadding(context, bottom: 40),
            children: [
              Text(
                'Each service runs one side of your business, with its own pages, staff and roles. '
                'Switch between them from the menu.',
                style: TextStyle(color: context.brand.muted, fontSize: 15, height: 1.45),
              ),
              if (inUse.isNotEmpty) ...[SectionTitle('In use (${inUse.length})'), grid(inUse)],
              if (others.isNotEmpty) ...[SectionTitle(inUse.isEmpty ? 'Services' : 'More services'), grid(others)],
              if (modules.isEmpty)
                const EmptyState(icon: Icons.apps_rounded, title: 'No services yet', message: 'They appear here as SportsHub turns them on.'),
            ],
          );
        },
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final SportsHubModule module;
  final ServiceNav? nav;

  /// Turned off for users; admins still see it.
  final bool off;

  const _ServiceTile({required this.module, required this.nav, required this.off});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final nav = this.nav;
    final home = nav?.homeRoute;
    final setUp = nav?.isSetUp ?? false;
    final pages = [for (final d in nav?.destinations ?? const <NavDestination>[]) if (!d.isExternal) d];
    final links = module.playerMenuItems();
    final Widget status = off
        ? StatusChip(label: 'Admins only', color: brand.warning, icon: Icons.visibility_off_outlined)
        : setUp
            ? StatusChip(label: 'In use', color: brand.success, icon: Icons.check_circle_rounded)
            : StatusChip(label: nav == null ? 'Available' : 'Not set up', color: context.colors.tertiary);
    return ServiceCard(
      icon: module.icon,
      color: module.color,
      name: nav?.name ?? module.name,
      subtitle: nav?.scope?.label ?? nav?.tagline,
      status: status,
      onOpen: home == null ? null : () => context.go(home),
      actions: [
        if (home != null)
          FilledButton.icon(
            onPressed: () => context.go(home),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: Icon(setUp ? Icons.arrow_forward_rounded : Icons.rocket_launch_outlined, size: 18),
            label: Text(setUp ? 'Open' : 'Set up'),
          ),
        for (final item in links)
          OutlinedButton.icon(
            onPressed: () => item.open(context),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: Icon(item.isExternal ? Icons.open_in_new_rounded : item.icon, size: 18),
            label: Text(item.title),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(module.description, style: TextStyle(color: brand.muted, height: 1.4)),
          if (pages.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in pages.take(6))
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(d.icon, size: 16, color: module.color),
                    label: Text(d.label, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

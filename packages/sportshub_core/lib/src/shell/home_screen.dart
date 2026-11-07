import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../module/module_providers.dart';
import '../module/sportshub_module.dart';
import '../notifications/notifications_screen.dart';
import '../profiles/profile_repository.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../theme/theme_mode.dart';
import '../utils/formatters.dart';
import '../venues/venue_repository.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';

/// The signed-in home: the lead module's own (SportsHubModule.buildHome) or
/// a section for each enabled module, then the user's venues and registering
/// one.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(enabledModulesProvider);
    // Just the background while the modules load, rather than flashing the
    // plain home before a module's own.
    if (enabled.isLoading && !enabled.hasValue) return const Scaffold(body: BrandBackdrop(child: SizedBox.expand()));
    for (final m in enabled.valueOrNull ?? const <SportsHubModule>[]) {
      final page = m.buildHome(context);
      if (page != null) return page;
    }
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final myVenues = ref.watch(myVenuesProvider).valueOrNull ?? const [];
    final rows = {for (final r in ref.watch(appModulesProvider).valueOrNull ?? const []) r.key: r};
    return AppPage(
      titleWidget: const SportsHubLogo(height: 40, markOnly: true),
      actions: [
        const ThemeModeButton(),
        const NotificationBell(),
        IconButton(
          tooltip: 'Account',
          icon: const Icon(Icons.account_circle_outlined),
          onPressed: () => context.push(CoreRoutes.account),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(appModulesProvider);
          ref.invalidate(myProfileProvider);
          ref.invalidate(myVenuesProvider);
        },
        child: AsyncValueView<List<SportsHubModule>>(
          value: ref.watch(enabledModulesProvider),
          onRetry: () => ref.invalidate(appModulesProvider),
          data: (modules) => ListView(
            padding: pagePadding(context),
            children: [
              Text('Hello, ${firstName(profile?.fullName ?? '')}', style: context.text.headlineSmall),
              const SizedBox(height: 2),
              Text('Play · Train · Book · Connect', style: TextStyle(color: context.brand.muted)),
              for (final m in modules) ...[
                if (rows[m.key]?.isEnabled == false)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: StatusChip(
                      label: '${m.name} is off for users: only admins see it',
                      color: context.brand.warning,
                      icon: Icons.visibility_off_outlined,
                    ),
                  ),
                m.buildHomeSection(context) ?? ModuleHomeSection(module: m),
              ],
              const SectionTitle('Run a venue'),
              if (myVenues.isNotEmpty) ...[
                MenuTile(
                  icon: Icons.storefront_rounded,
                  title: 'Your venues',
                  subtitle: myVenues.length == 1 ? myVenues.first.venue.name : '${myVenues.length} venues',
                  onTap: () => context.push(
                      myVenues.length == 1 ? venueHomeRoute(modules, myVenues.first.venue) : CoreRoutes.manage),
                ),
                const SizedBox(height: 10),
              ],
              MenuTile(
                icon: Icons.add_business_outlined,
                title: 'Register your venue',
                subtitle: 'List your gym or ground on SportsHub',
                onTap: () => context.push(CoreRoutes.registerVenue),
              ),
              if (profile?.isAdmin ?? false) ...[
                const SizedBox(height: 10),
                MenuTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'SportsHub admin',
                  iconColor: context.colors.secondary,
                  onTap: () => context.push(CoreRoutes.admin),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A module's home section when it has none of its own: its name and its
/// menu for players.
class ModuleHomeSection extends StatelessWidget {
  final SportsHubModule module;

  const ModuleHomeSection({super.key, required this.module});

  @override
  Widget build(BuildContext context) {
    final items = module.playerMenuItems();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(module.name),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MenuTile(
              icon: item.icon,
              title: item.title,
              subtitle: item.subtitle,
              trailing: item.isExternal ? const Icon(Icons.open_in_new_rounded, size: 20) : null,
              onTap: () => item.open(context),
            ),
          ),
      ],
    );
  }
}

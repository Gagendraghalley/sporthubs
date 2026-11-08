import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../access/access.dart';
import '../access/access_repository.dart';
import '../admin/admin_repository.dart';
import '../module/module_providers.dart';
import '../module/sportshub_module.dart';
import '../notifications/app_notification.dart';
import '../notifications/notification_repository.dart';
import '../profiles/profile_repository.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../utils/bhutan_time.dart';
import '../utils/formatters.dart';
import '../venues/venue_repository.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/responsive.dart';
import '../widgets/service_cards.dart';
import 'service_nav.dart';

/// Overview, the platform's home: a welcome, every service's shortcuts,
/// each service's card (how things stand, the way in), what needs attention
/// (notifications, venues to verify) and starting another business.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppPage(
      title: 'Overview',
      body: AsyncValueView<List<SportsHubModule>>(
        value: ref.watch(enabledModulesProvider),
        onRetry: () => ref.invalidate(appModulesProvider),
        data: (modules) => _Overview(modules: modules),
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  final List<SportsHubModule> modules;

  const _Overview({required this.modules});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = serviceNavs(ref, CoreRoutes.home);
    final navByKey = {for (final s in services) s.module.key: s.nav};
    final rows = {for (final r in ref.watch(appModulesProvider).valueOrNull ?? const []) r.key: r};
    final access = ref.watch(myAccessProvider).valueOrNull ?? PlatformAccess.none;
    final actions = [
      for (final s in services)
        for (final a in s.nav.actions) (action: a, nav: s.nav),
    ];

    final cards = [
      for (final m in modules)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            m.buildOverviewCard(context) ?? DefaultServiceCard(module: m, nav: navByKey[m.key]),
            if (rows[m.key]?.isEnabled == false)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: StatusChip(
                  label: '${m.name} is off for users: only admins see it',
                  color: context.brand.warning,
                  icon: Icons.visibility_off_outlined,
                ),
              ),
          ],
        ),
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(appModulesProvider);
        ref.invalidate(myProfileProvider);
        ref.invalidate(myVenuesProvider);
      },
      child: ListView(
        padding: pagePadding(context, bottom: 40),
        children: [
          FadeSlideIn(child: _Welcome(serviceCount: services.length, actions: actions)),
          if (actions.isNotEmpty) ...[
            const SectionTitle('Quick actions'),
            ResponsiveGrid(
              minItemWidth: 230,
              maxColumns: 4,
              spacing: 12,
              runSpacing: 12,
              children: staggered([
                for (final a in actions)
                  QuickActionTile(
                    action: a.action,
                    color: a.nav.color,
                    service: a.nav.name,
                    onTap: () => context.go(a.action.route),
                  ),
              ]),
            ),
          ],
          SectionTitle(
            'Your services',
            trailing: TextButton.icon(
              onPressed: () => context.go(CoreRoutes.services),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('All services'),
            ),
          ),
          if (cards.isEmpty)
            const EmptyState(icon: Icons.apps_rounded, title: 'No services yet', message: 'They appear here as SportsHub turns them on.')
          else
            ResponsiveGrid(minItemWidth: 380, maxColumns: 2, spacing: 16, runSpacing: 16, equalHeight: false, children: staggered(cards)),
          const SizedBox(height: 8),
          ResponsiveColumns(
            breakpoint: 900,
            first: [const SectionTitle('Needs your attention'), const FadeSlideIn(child: _Attention())],
            second: [
              const SectionTitle('Grow'),
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: _Tile(
                  icon: Icons.add_business_rounded,
                  color: BrandColors.orange,
                  title: 'Run another business on SportsHub',
                  message: 'Register a gym or another venue: each gets its own dashboard, staff and roles.',
                  action: 'Register a venue',
                  onTap: () => context.go(CoreRoutes.registerVenue),
                ),
              ),
              if (access.isTeam) ...[
                const SizedBox(height: 12),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 140),
                  child: _Tile(
                    icon: Icons.admin_panel_settings_rounded,
                    color: BrandColors.blue,
                    title: 'SportsHub admin',
                    message: 'Users, roles, master data, venues to verify and which services are on.',
                    action: 'Open admin',
                    onTap: () => context.go(CoreRoutes.admin),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The welcome: good morning, the date in Bhutan, and the first shortcuts.
class _Welcome extends ConsumerWidget {
  final int serviceCount;
  final List<({ServiceAction action, ServiceNav nav})> actions;

  const _Welcome({required this.serviceCount, required this.actions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final unread = ref.watch(unreadCountProvider);
    final now = BhutanTime.now();
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final facts = [
      '${weekdays[now.weekday - 1]}, ${formatDate(now)}',
      serviceCount == 1 ? '1 service' : '$serviceCount services',
      if (unread > 0) unread == 1 ? '1 new notification' : '$unread new notifications',
    ];
    return Container(
      padding: EdgeInsets.all(wide ? 28 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF12306E), BrandColors.navy, BrandColors.night],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: BrandColors.navy.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 14))],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // A soft orange glow in the corner.
          Positioned(
            right: -60,
            top: -80,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                      colors: [BrandColors.orange.withValues(alpha: 0.35), BrandColors.orange.withValues(alpha: 0)]),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${greeting(now)}, ${firstName(profile?.fullName ?? '')}',
                style: TextStyle(color: Colors.white, fontSize: wide ? 30 : 24, fontWeight: FontWeight.w800, letterSpacing: -0.4),
              ),
              const SizedBox(height: 6),
              Text(facts.join('  ·  '), style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 14)),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (i, a) in actions.take(2).indexed)
                      FilledButton.icon(
                        onPressed: () => context.go(a.action.route),
                        style: FilledButton.styleFrom(
                          backgroundColor: i == 0 ? BrandColors.orange : Colors.white.withValues(alpha: 0.12),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 46),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        icon: Icon(a.action.icon, size: 20),
                        label: Text(a.action.label),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// What needs them: unread notifications, and venues waiting to be verified
/// (for those who verify); all caught up otherwise.
class _Attention extends ConsumerWidget {
  const _Attention();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(myAccessProvider).valueOrNull ?? PlatformAccess.none;
    final pending = access.can(PlatformPermission.venuesVerify) ? ref.watch(pendingVenuesProvider).valueOrNull ?? const [] : const [];
    final all = ref.watch(notificationsProvider).valueOrNull ?? const <AppNotification>[];
    final unread = all.where((n) => !n.isRead).take(5).toList();
    final brand = context.brand;
    return SectionCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pending.isNotEmpty)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: brand.warning.withValues(alpha: 0.15),
                child: Icon(Icons.fact_check_outlined, color: brand.warning),
              ),
              title: Text(pending.length == 1 ? '1 venue waiting to be verified' : '${pending.length} venues waiting to be verified'),
              subtitle: const Text('They show on SportsHub once verified'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.go(CoreRoutes.adminVenues),
            ),
          for (final n in unread)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: context.colors.tertiary.withValues(alpha: 0.12),
                child: Icon(Icons.notifications_active_outlined, color: context.colors.tertiary, size: 20),
              ),
              title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [if (n.body != null) n.body!, timeAgo(n.createdAt)].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => context.go(n.link ?? CoreRoutes.notifications),
            ),
          if (pending.isEmpty && unread.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.task_alt_rounded, color: brand.success, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(child: Text("You're all caught up. New notifications show here.")),
                ],
              ),
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => context.go(CoreRoutes.notifications), child: const Text('All notifications')),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String action;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(message, style: TextStyle(color: context.brand.muted, height: 1.4)),
                const SizedBox(height: 8),
                Text(action, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A service's card when it has none of its own: its name and description,
/// and its pages ([nav]) or, for a service on another website, its links.
class DefaultServiceCard extends StatelessWidget {
  final SportsHubModule module;
  final ServiceNav? nav;

  const DefaultServiceCard({super.key, required this.module, this.nav});

  @override
  Widget build(BuildContext context) {
    final links = module.playerMenuItems();
    final home = nav?.homeRoute;
    return ServiceCard(
      icon: module.icon,
      color: module.color,
      name: nav?.name ?? module.name,
      subtitle: nav?.tagline ?? module.description,
      onOpen: home == null ? null : () => context.go(home),
      actions: [
        if (home != null)
          FilledButton.tonal(onPressed: () => context.go(home), child: Text(nav!.isSetUp ? 'Open' : 'Set up')),
        for (final item in links)
          OutlinedButton.icon(
            onPressed: () => item.open(context),
            icon: Icon(item.isExternal ? Icons.open_in_new_rounded : item.icon, size: 18),
            label: Text(item.title),
          ),
      ],
    );
  }
}

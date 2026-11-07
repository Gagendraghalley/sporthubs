import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../gym_routes.dart';

/// A plan with its price, and a button to join (or renew).
class PlanCard extends StatelessWidget {
  final GymPlan plan;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  const PlanCard({super.key, required this.plan, this.actionLabel, this.onAction, this.trailing});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name, style: context.text.titleMedium),
                const SizedBox(height: 2),
                Text(formatDuration(plan.durationDays), style: TextStyle(color: context.brand.muted)),
                if (plan.description != null && plan.description!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(plan.description!),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                plan.price == 0 ? 'Free' : formatNu(plan.price),
                style: context.text.titleLarge?.copyWith(color: context.brand.accent),
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
              if (trailing != null) trailing!,
            ],
          ),
        ],
      ),
    );
  }
}

/// A membership's state in words and colour.
class SubscriptionStatusChip extends StatelessWidget {
  final GymSubscription subscription;

  const SubscriptionStatusChip({super.key, required this.subscription});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final today = BhutanTime.today();
    final s = subscription;
    if (s.isCurrentOn(today)) {
      final left = s.daysLeftOn(today);
      return StatusChip(
        label: left == 1 ? 'Last day' : '$left days left',
        color: left <= 3 ? brand.warning : brand.success,
        icon: Icons.check_circle_rounded,
      );
    }
    if (s.isUpcomingOn(today)) {
      return StatusChip(label: 'Starts ${formatShortDate(s.startDate!)}', color: context.colors.tertiary, icon: Icons.event_rounded);
    }
    return switch (s.status) {
      SubscriptionStatus.pending =>
        StatusChip(label: 'Waiting for payment', color: brand.warning, icon: Icons.hourglass_top_rounded),
      SubscriptionStatus.cancelled => StatusChip(label: 'Cancelled', color: brand.muted, icon: Icons.block_rounded),
      _ => StatusChip(label: 'Ended', color: brand.muted, icon: Icons.history_rounded),
    };
  }
}

/// On the home page: the member's current gym at a glance, and the way in.
class GymHomeSection extends ConsumerWidget {
  const GymHomeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(mySubscriptionsProvider).valueOrNull ?? const <GymSubscription>[];
    final today = BhutanTime.today();
    final current = subs.where((s) => s.isCurrentOn(today)).toList()
      ..sort((a, b) => a.endDate!.compareTo(b.endDate!));
    final pending = subs.where((s) => s.isPending).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Gym'),
        for (final s in current.take(2))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CurrentMembershipCard(subscription: s),
          ),
        for (final s in pending.take(2))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MenuTile(
              icon: Icons.hourglass_top_rounded,
              iconColor: context.brand.warning,
              title: 'Waiting for ${s.gymName ?? 'the gym'}',
              subtitle: '${s.planName}: pay ${formatNu(s.price)} at the gym and they will activate it',
              onTap: () => context.push(GymRoutes.myGym),
            ),
          ),
        MenuTile(
          icon: Icons.fitness_center_rounded,
          title: 'Find a gym',
          subtitle: 'Plans and prices near you',
          onTap: () => context.push(GymRoutes.gyms),
        ),
        if (current.isEmpty) ...[
          const SizedBox(height: 10),
          MenuTile(
            icon: Icons.qr_code_2_rounded,
            title: 'My gym',
            subtitle: 'Your membership card, days left and check-ins',
            onTap: () => context.push(GymRoutes.myGym),
          ),
        ],
      ],
    );
  }
}

class _CurrentMembershipCard extends StatelessWidget {
  final GymSubscription subscription;

  const _CurrentMembershipCard({required this.subscription});

  @override
  Widget build(BuildContext context) {
    final today = BhutanTime.today();
    final left = subscription.daysLeftOn(today);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(GymRoutes.myGym),
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [BrandColors.navy, BrandColors.blue], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subscription.gymName ?? 'Your gym',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      '${subscription.planName} · until ${formatDate(subscription.endDate!)}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: subscription.progressOn(today),
                        minHeight: 6,
                        color: BrandColors.orange,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(
                children: [
                  Text('$left', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                  Text(left == 1 ? 'day left' : 'days left', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 6),
                  const Icon(Icons.qr_code_2_rounded, color: Colors.white),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A gym's numbers on its Manage page; each opens its page.
class GymManagerStats extends ConsumerWidget {
  final String venueId;
  final bool showIncome;

  const GymManagerStats({super.key, required this.venueId, required this.showIncome});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    return AsyncValueView<GymDashboard>(
      value: ref.watch(gymDashboardProvider(venueId)),
      onRetry: () => ref.invalidate(gymDashboardProvider(venueId)),
      data: (d) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth > 560 ? 3 : 2;
          final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
          final tiles = [
            StatTile(
              label: 'Requests waiting',
              value: '${d.pending}',
              icon: Icons.hourglass_top_rounded,
              color: d.pending > 0 ? brand.warning : null,
              onTap: () => context.push(GymRoutes.requestsFor(venueId)),
            ),
            StatTile(
              label: 'Active members',
              value: '${d.active}',
              icon: Icons.groups_rounded,
              onTap: () => context.push(GymRoutes.membersFor(venueId)),
            ),
            StatTile(
              label: 'Ending in 7 days',
              value: '${d.expiringSoon}',
              icon: Icons.event_busy_rounded,
              color: d.expiringSoon > 0 ? brand.accent : null,
              onTap: () => context.push(GymRoutes.membersFor(venueId)),
            ),
            StatTile(
              label: 'Check-ins today',
              value: '${d.checkInsToday}',
              icon: Icons.qr_code_scanner_rounded,
              onTap: () => context.push(GymRoutes.checkInFor(venueId)),
            ),
            if (showIncome && d.incomeThisMonth != null)
              StatTile(
                label: 'Income this month',
                value: formatNu(d.incomeThisMonth!),
                icon: Icons.payments_outlined,
                color: brand.success,
                onTap: () => context.push(GymRoutes.incomeFor(venueId)),
              ),
          ];
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final t in tiles) SizedBox(width: width, child: t)],
          );
        },
      ),
    );
  }
}

/// A gym page only its staff may open ([managersOnly]: owners and managers).
class GymStaffPage extends ConsumerWidget {
  final String venueId;
  final String title;
  final bool managersOnly;
  final Widget Function(BuildContext context, VenueAccess access) builder;

  const GymStaffPage({super.key, required this.venueId, required this.title, required this.builder, this.managersOnly = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<VenueAccess?>(
      value: ref.watch(venueAccessProvider(venueId)),
      onRetry: () => ref.invalidate(myVenuesProvider),
      data: (access) {
        if (access == null || access.venue.type != gymVenueType || (managersOnly && !access.canManage)) {
          return AppPage(
            title: title,
            body: EmptyState(
              icon: Icons.lock_outline_rounded,
              title: managersOnly ? "Only the gym's owner and managers can open this" : "You don't work at this gym",
            ),
          );
        }
        return builder(context, access);
      },
    );
  }
}

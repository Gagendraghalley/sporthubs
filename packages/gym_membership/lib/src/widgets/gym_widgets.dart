import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportshub_core/sportshub_core.dart';

import '../data/gym_models.dart';
import '../data/gym_repository.dart';
import '../shell/current_gym.dart';

/// A package with its price (and an optional button).
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

/// A gym page only its staff may open: those whose role there has
/// [permission] (any of its staff, when null).
class GymStaffPage extends ConsumerWidget {
  final String venueId;
  final String title;
  final String? permission;
  final Widget Function(BuildContext context, VenueAccess access) builder;

  const GymStaffPage({super.key, required this.venueId, required this.title, required this.builder, this.permission});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<VenueAccess?>(
      value: ref.watch(venueAccessProvider(venueId)),
      onRetry: () => ref.invalidate(myVenuesProvider),
      data: (access) {
        final works = access != null && access.venue.type == gymVenueType;
        if (!works || (permission != null && !access.can(permission!))) {
          return AppPage(
            title: title,
            body: EmptyState(
              icon: Icons.lock_outline_rounded,
              title: works ? "Your role here doesn't include this" : "You don't work at this gym",
              message: works ? 'Ask the gym\'s owner if you need it.' : null,
            ),
          );
        }
        // A gym's page was opened: the menu, Overview and the switcher stay
        // on this gym.
        if (ref.read(rememberedGymProvider) != venueId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) ref.read(rememberedGymProvider.notifier).state = venueId;
          });
        }
        return builder(context, access);
      },
    );
  }
}

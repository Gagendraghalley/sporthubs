import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../utils/formatters.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/feedback.dart';
import '../widgets/motion.dart';
import 'app_notification.dart';
import 'notification_repository.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return AppPage(
      title: 'Notifications',
      actions: [
        if (unread > 0)
          TextButton(
            onPressed: () => runAction(context, () => ref.read(notificationRepositoryProvider).markAllRead()),
            child: const Text('Mark all read'),
          ),
      ],
      body: AsyncValueView<List<AppNotification>>(
        value: ref.watch(notificationsProvider),
        onRetry: () => ref.invalidate(notificationsProvider),
        data: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'Nothing yet',
                message: "We'll tell you here when something happens, like your membership being activated.",
              )
            : ListView.separated(
                padding: pagePadding(context),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _NotificationTile(item: items[i]),
              ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final AppNotification item;

  const _NotificationTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = item.isRead ? context.brand.muted : context.colors.secondary;
    return SectionCard(
      padding: const EdgeInsets.all(14),
      onTap: () {
        if (!item.isRead) ref.read(notificationRepositoryProvider).markRead(item.id).ignore();
        final link = item.link;
        if (link != null && link.startsWith('/')) context.push(link);
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(item.isRead ? Icons.circle_outlined : Icons.circle, size: 10, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w800, fontSize: 15.5),
                ),
                if (item.body != null) ...[const SizedBox(height: 2), Text(item.body!)],
                const SizedBox(height: 6),
                Text(formatMoment(item.createdAt), style: context.text.bodySmall?.copyWith(color: context.brand.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The bell in app bars, with the number unread.
/// The bell at the top right, with how many are unread. When a new one
/// comes in, the bell rings once (a short swing) and the count pops: you
/// notice it, and it's still after that.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadCountProvider);
    ref.listen<int>(unreadCountProvider, (before, now) {
      if (now > (before ?? 0) && !reduceMotion(context)) _ring.forward(from: 0);
    });
    return IconButton(
      tooltip: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      onPressed: () => context.push(CoreRoutes.notifications),
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: context.colors.secondary,
        label: AnimatedSwitcher(
          duration: Motion.of(context, Motion.press),
          transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
          child: Text(unread > 9 ? '9+' : '$unread', key: ValueKey(unread)),
        ),
        child: AnimatedBuilder(
          animation: _ring,
          // A swing that dies away: three beats, smaller each time.
          builder: (context, child) {
            final t = _ring.value;
            final angle = t == 0 || t == 1 ? 0.0 : 0.32 * (1 - t) * math.sin(t * 6 * math.pi);
            return Transform.rotate(angle: angle, alignment: Alignment.topCenter, child: child);
          },
          child: const Icon(Icons.notifications_none_rounded),
        ),
      ),
    );
  }
}

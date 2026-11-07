import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../utils/formatters.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/feedback.dart';
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
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return IconButton(
      tooltip: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      onPressed: () => context.push(CoreRoutes.notifications),
      icon: Badge(
        isLabelVisible: unread > 0,
        backgroundColor: context.colors.secondary,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

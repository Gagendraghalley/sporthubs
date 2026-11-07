import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_repository.dart';
import '../supabase/supabase_provider.dart';
import 'app_notification.dart';

final notificationRepositoryProvider =
    Provider<NotificationRepository>((ref) => NotificationRepository(ref.watch(supabaseProvider)));

/// The signed-in user's notifications, newest first, live (Supabase Realtime).
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watch(userId);
});

/// How many are unread, for the bell.
final unreadCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).valueOrNull?.where((n) => !n.isRead).length ?? 0,
);

class NotificationRepository {
  NotificationRepository(this._client);
  final SupabaseClient _client;

  Stream<List<AppNotification>> watch(String userId) => _client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) => rows.map(AppNotification.fromJson).toList());

  Future<void> markRead(String id) =>
      _client.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);

  Future<void> markAllRead() => _client.rpc('mark_all_notifications_read');
}

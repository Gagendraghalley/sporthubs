import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportshub_core/sportshub_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gym_models.dart';
import 'member_qr.dart';

/// venue_types.key for gyms.
const gymVenueType = 'gym';

/// app_modules.key and payments.module_key.
const gymModuleKey = 'gym_membership';

final gymRepositoryProvider = Provider<GymRepository>((ref) => GymRepository(ref.watch(supabaseProvider)));

/// A gym's plans: those on sale ([all] false, for members) or every one
/// (for its owner and managers).
final gymPlansProvider = FutureProvider.family<List<GymPlan>, ({String venueId, bool all})>(
  (ref, q) => ref.watch(gymRepositoryProvider).plans(q.venueId, includeInactive: q.all),
);

/// The signed-in member's memberships and requests, at every gym.
final mySubscriptionsProvider = FutureProvider<List<GymSubscription>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  return ref.watch(gymRepositoryProvider).mySubscriptions(userId);
});

final myCheckInsProvider = FutureProvider<List<GymCheckIn>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  return ref.watch(gymRepositoryProvider).myCheckIns(userId);
});

/// Every membership and request at a gym, for its staff.
final gymSubscriptionsProvider = FutureProvider.family<List<GymSubscription>, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).venueSubscriptions(venueId),
);

/// Today's check-ins at a gym (Bhutan time), newest first.
final gymCheckInsTodayProvider = FutureProvider.family<List<GymCheckIn>, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).venueCheckIns(venueId, since: bhutanMidnightUtc(BhutanTime.today())),
);

/// The past week's check-ins at a gym (today and the 6 days before),
/// newest first, for the dashboard's Recent activity.
final gymRecentCheckInsProvider = FutureProvider.family<List<GymCheckIn>, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).venueCheckIns(
        venueId,
        since: bhutanMidnightUtc(BhutanTime.today().subtract(const Duration(days: 6))),
      ),
);

final gymDashboardProvider = FutureProvider.family<GymDashboard, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).dashboard(venueId),
);

/// The moment Bhutan's [date] begins, in UTC.
DateTime bhutanMidnightUtc(DateTime date) => DateTime.utc(date.year, date.month, date.day).subtract(BhutanTime.offset);

/// After a change to a gym's memberships: everything that shows them.
void refreshGym(WidgetRef ref, String venueId) {
  ref.invalidate(gymSubscriptionsProvider(venueId));
  ref.invalidate(gymDashboardProvider(venueId));
  ref.invalidate(gymCheckInsTodayProvider(venueId));
  ref.invalidate(gymRecentCheckInsProvider(venueId));
}

/// Gym data. Plans, memberships and check-ins change only through the
/// database's gym_* functions, which check who is calling.
class GymRepository {
  GymRepository(this._client);
  final SupabaseClient _client;

  static const _memberFields = 'full_name, phone, member_code';

  Future<List<GymPlan>> plans(String venueId, {bool includeInactive = false}) async {
    var query = _client.from('gym_plans').select().eq('venue_id', venueId);
    if (!includeInactive) query = query.eq('is_active', true);
    final rows = await query.order('sort_order').order('price');
    return rows.map(GymPlan.fromJson).toList();
  }

  /// A new plan ([planId] null) or changes to one; owners and managers only.
  Future<String> savePlan({
    required String venueId,
    String? planId,
    required String name,
    String? description,
    required int durationDays,
    required int price,
    bool isActive = true,
  }) async =>
      await _client.rpc('gym_save_plan', params: {
        'venue_id': venueId,
        'plan_id': planId,
        'name': name.trim(),
        'description': (description == null || description.trim().isEmpty) ? null : description.trim(),
        'duration_days': durationDays,
        'price': price,
        'is_active': isActive,
      }) as String;

  /// The member asks for [planId]; the gym confirms once they've paid.
  Future<String> requestSubscription(String planId) async =>
      await _client.rpc('gym_request_subscription', params: {'plan_id': planId}) as String;

  /// Calls off a pending request: the member, or the gym's staff.
  Future<void> cancelSubscription(String subscriptionId) =>
      _client.rpc('gym_cancel_subscription', params: {'subscription_id': subscriptionId});

  /// Staff confirm the payment: the membership starts (the day after the
  /// current one ends, for a renewal) and the payment is recorded.
  Future<void> activateSubscription(String subscriptionId,
          {required int amount, required PaymentMethod method, String? reference}) =>
      _client.rpc('gym_activate_subscription', params: {
        'subscription_id': subscriptionId,
        'amount': amount,
        'method': method.value,
        'reference': (reference == null || reference.trim().isEmpty) ? null : reference.trim(),
      });

  Future<List<GymSubscription>> mySubscriptions(String userId) async {
    final rows = await _client
        .from('gym_subscriptions')
        .select('*, gym:venues(name)')
        .eq('member_id', userId)
        .order('requested_at', ascending: false);
    return rows.map(GymSubscription.fromJson).toList();
  }

  Future<List<GymCheckIn>> myCheckIns(String userId) async {
    final rows = await _client
        .from('gym_check_ins')
        .select('*, gym:venues(name)')
        .eq('member_id', userId)
        .order('checked_in_at', ascending: false)
        // Enough for the home's 90-day chart, even training most days.
        .limit(120);
    return rows.map(GymCheckIn.fromJson).toList();
  }

  Future<List<GymSubscription>> venueSubscriptions(String venueId) async {
    final rows = await _client
        .from('gym_subscriptions')
        .select('*, member:profiles!gym_subscriptions_member_id_fkey($_memberFields)')
        .eq('venue_id', venueId)
        .order('requested_at', ascending: false)
        .limit(1000);
    return rows.map(GymSubscription.fromJson).toList();
  }

  Future<List<GymCheckIn>> venueCheckIns(String venueId, {required DateTime since}) async {
    final rows = await _client
        .from('gym_check_ins')
        .select('*, member:profiles!gym_check_ins_member_id_fkey(full_name)')
        .eq('venue_id', venueId)
        .gte('checked_in_at', since.toUtc().toIso8601String())
        .order('checked_in_at', ascending: false)
        .limit(200);
    return rows.map(GymCheckIn.fromJson).toList();
  }

  /// Checks a member in; fails (with the reason) unless they have a
  /// membership at this gym covering today.
  Future<CheckInResult> checkIn(String venueId, MemberRef member) async {
    final result = member.id != null
        ? await _client.rpc('gym_check_in', params: {'venue_id': venueId, 'member_id': member.id})
        : await _client.rpc('gym_check_in_by_code', params: {'venue_id': venueId, 'code': member.code});
    return CheckInResult.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<GymDashboard> dashboard(String venueId) async {
    final result = await _client.rpc('gym_dashboard', params: {'venue_id': venueId});
    return GymDashboard.fromJson(Map<String, dynamic>.from(result as Map));
  }
}

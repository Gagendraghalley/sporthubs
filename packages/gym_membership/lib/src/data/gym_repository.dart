import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportshub_core/sportshub_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:typed_data';

import 'gym_models.dart';
import 'member_qr.dart';
import 'registered_member.dart';

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

/// Every membership at a gym, for its staff.
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

/// A gym's check-ins since a Bhutan date (up to 5,000), for its reports.
final gymCheckInsSinceProvider = FutureProvider.family<List<GymCheckIn>, ({String venueId, DateTime since})>(
  (ref, q) => ref.watch(gymRepositoryProvider).venueCheckIns(q.venueId, since: bhutanMidnightUtc(q.since), limit: 5000),
);

final gymDashboardProvider = FutureProvider.family<GymDashboard, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).dashboard(venueId),
);

/// The members a gym registered at its front desk, by name.
final gymMembersProvider = FutureProvider.family<List<GymMember>, String>(
  (ref, venueId) => ref.watch(gymRepositoryProvider).registeredMembers(venueId),
);

/// One registered member, with their place's names.
final gymMemberProvider = FutureProvider.autoDispose.family<GymMember?, String>(
  (ref, id) => ref.watch(gymRepositoryProvider).registeredMember(id),
);

/// A registered member's visits, newest first.
final gymMemberCheckInsProvider = FutureProvider.autoDispose.family<List<GymCheckIn>, String>(
  (ref, id) => ref.watch(gymRepositoryProvider).registeredMemberCheckIns(id),
);

/// A member's photo (private: only the gym's staff may see it), kept while
/// the app runs.
final gymMemberPhotoProvider = FutureProvider.family<Uint8List?, String>(
  (ref, path) => ref.watch(gymRepositoryProvider).memberPhoto(path),
);

/// The moment Bhutan's [date] begins, in UTC.
DateTime bhutanMidnightUtc(DateTime date) => DateTime.utc(date.year, date.month, date.day).subtract(BhutanTime.offset);

/// After a change to a gym's memberships: everything that shows them.
void refreshGym(WidgetRef ref, String venueId) {
  ref.invalidate(gymMembersProvider(venueId));
  ref.invalidate(gymSubscriptionsProvider(venueId));
  ref.invalidate(gymDashboardProvider(venueId));
  ref.invalidate(gymCheckInsTodayProvider(venueId));
  ref.invalidate(gymRecentCheckInsProvider(venueId));
  ref.invalidate(gymCheckInsSinceProvider);
}

/// Gym data. Plans, memberships and check-ins change only through the
/// database's gym_* functions, which check who is calling.
class GymRepository {
  GymRepository(this._client);
  final SupabaseClient _client;

  static const _memberFields = 'full_name, phone, member_code';
  static const _registeredFields = 'full_name, phone, code';
  static const _gymMemberColumns = '*, village:villages(name), gewog:gewogs(name), dzongkhag:dzongkhags(name)';

  /// Members' photos: private, in a folder per gym.
  static const photoBucket = 'gym-member-photos';

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

  Future<List<GymSubscription>> venueSubscriptions(String venueId) async {
    final rows = await _client
        .from('gym_subscriptions')
        .select('*, member:profiles!gym_subscriptions_member_id_fkey($_memberFields), '
            'registered:gym_members!gym_subscriptions_gym_member_id_fkey($_registeredFields)')
        .eq('venue_id', venueId)
        .order('requested_at', ascending: false)
        .limit(1000);
    return rows.map(GymSubscription.fromJson).toList();
  }

  Future<List<GymCheckIn>> venueCheckIns(String venueId, {required DateTime since, int limit = 200}) async {
    final rows = await _client
        .from('gym_check_ins')
        .select('*, member:profiles!gym_check_ins_member_id_fkey(full_name), '
            'registered:gym_members!gym_check_ins_gym_member_id_fkey(full_name)')
        .eq('venue_id', venueId)
        .gte('checked_in_at', since.toUtc().toIso8601String())
        .order('checked_in_at', ascending: false)
        .limit(limit);
    return rows.map(GymCheckIn.fromJson).toList();
  }

  /// Checks a member in; fails (with the reason) unless they have a
  /// membership at this gym covering today.
  Future<CheckInResult> checkIn(String venueId, MemberRef member) async {
    final result = member.id != null
        ? await _client.rpc('gym_check_in', params: {'venue_id': venueId, 'member_id': member.id})
        : member.cardToken != null
            ? await _client.rpc('gym_check_in_member', params: {'venue_id': venueId, 'qr_token': member.cardToken})
            : await _client.rpc('gym_check_in_by_code', params: {'venue_id': venueId, 'code': member.code});
    return CheckInResult.fromJson(Map<String, dynamic>.from(result as Map));
  }

  Future<GymDashboard> dashboard(String venueId) async {
    final result = await _client.rpc('gym_dashboard', params: {'venue_id': venueId});
    return GymDashboard.fromJson(Map<String, dynamic>.from(result as Map));
  }

  // ─── Members registered at the front desk ─────────────────────────────

  Future<List<GymMember>> registeredMembers(String venueId) async {
    final rows = await _client.from('gym_members').select(_gymMemberColumns).eq('venue_id', venueId).order('full_name');
    return rows.map(GymMember.fromJson).toList();
  }

  Future<GymMember?> registeredMember(String id) async {
    final row = await _client.from('gym_members').select(_gymMemberColumns).eq('id', id).maybeSingle();
    return row == null ? null : GymMember.fromJson(row);
  }

  /// The registered member whose card holds [qrToken], if this gym's.
  Future<GymMember?> registeredMemberByCard(String venueId, String qrToken) async {
    final row = await _client
        .from('gym_members')
        .select(_gymMemberColumns)
        .eq('venue_id', venueId)
        .eq('qr_token', qrToken)
        .maybeSingle();
    return row == null ? null : GymMember.fromJson(row);
  }

  Future<List<GymCheckIn>> registeredMemberCheckIns(String gymMemberId) async {
    final rows = await _client
        .from('gym_check_ins')
        .select()
        .eq('gym_member_id', gymMemberId)
        .order('checked_in_at', ascending: false)
        .limit(120);
    return rows.map(GymCheckIn.fromJson).toList();
  }

  /// Registers a member, and sells them [sale] (from their date of joining)
  /// if given. Returns their id.
  Future<String> registerMember(String venueId, MemberDetails details, {PackageSale? sale}) async {
    final result = await _client.rpc('gym_register_member', params: {
      'venue_id': venueId,
      'details': details.toJson(),
      'plan_id': sale?.plan.id,
      'months': sale?.months,
      'amount': sale?.amount ?? 0,
      'method': sale?.method?.value,
      'reference': _clean(sale?.reference),
    });
    return (result as Map)['gym_member_id'] as String;
  }

  Future<void> updateMember(String gymMemberId, MemberDetails details) =>
      _client.rpc('gym_update_member', params: {'gym_member_id': gymMemberId, 'details': details.toJson()});

  /// Sells a registered member another package: from the day after their
  /// current one ends, or today.
  Future<void> renewMember(String gymMemberId, PackageSale sale) => _client.rpc('gym_renew_member', params: {
        'gym_member_id': gymMemberId,
        'plan_id': sale.plan.id,
        'months': sale.months,
        'amount': sale.amount,
        'method': sale.method?.value,
        'reference': _clean(sale.reference),
      });

  /// A new QR card for them; the old one stops working.
  Future<String> reissueCard(String gymMemberId) async =>
      await _client.rpc('gym_reissue_member_qr', params: {'gym_member_id': gymMemberId}) as String;

  /// Uploads [bytes] as the photo of member [memberId] of gym [venueId] and
  /// makes it theirs; their [oldPath] one is removed. Returns its path.
  Future<String> setMemberPhoto({
    required String venueId,
    required String memberId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
    String? oldPath,
  }) async {
    final ext = switch (contentType) { 'image/png' => 'png', 'image/webp' => 'webp', _ => 'jpg' };
    final path = '$venueId/$memberId-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage
        .from(photoBucket)
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: true));
    await _client.rpc('gym_set_member_photo', params: {'gym_member_id': memberId, 'photo_path': path});
    if (oldPath != null && oldPath != path) {
      try {
        await _client.storage.from(photoBucket).remove([oldPath]);
      } catch (_) {
        // A leftover file is harmless; the member points at the new one.
      }
    }
    return path;
  }

  Future<Uint8List?> memberPhoto(String path) async {
    try {
      return await _client.storage.from(photoBucket).download(path);
    } on StorageException {
      return null;
    }
  }

  static String? _clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
}

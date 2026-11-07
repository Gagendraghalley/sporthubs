import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_provider.dart';
import '../venues/venue.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) => AdminRepository(ref.watch(supabaseProvider)));

/// Venues waiting for the SportsHub team, oldest first.
final pendingVenuesProvider = FutureProvider<List<Venue>>((ref) => ref.watch(adminRepositoryProvider).pendingVenues());

/// Admin-only actions; the database checks profiles.role = 'admin'.
class AdminRepository {
  AdminRepository(this._client);
  final SupabaseClient _client;

  Future<List<Venue>> pendingVenues() async {
    final rows = await _client
        .from('venues')
        .select()
        .eq('verification_status', VerificationStatus.pending)
        .order('created_at');
    return rows.map(Venue.fromJson).toList();
  }

  /// Verifies the venue (it goes live) or sends it back with [note].
  Future<void> reviewVenue(String venueId, {required bool approve, String? note}) =>
      _client.rpc('review_venue', params: {'venue_id': venueId, 'approve': approve, 'note': note});

  Future<void> setModuleEnabled(String key, bool enabled) =>
      _client.rpc('set_module_enabled', params: {'module_key': key, 'enabled': enabled});
}

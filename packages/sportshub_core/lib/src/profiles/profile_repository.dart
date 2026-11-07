import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_repository.dart';
import '../supabase/supabase_provider.dart';
import 'profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(supabaseProvider)));

/// The signed-in user's profile; null when nobody is signed in.
final myProfileProvider = FutureProvider<Profile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(profileRepositoryProvider).get(userId);
});

class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  Future<Profile?> get(String userId) async {
    final row = await _client.from('profiles').select().eq('id', userId).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  /// Only these can be changed by the user (the role can't).
  Future<void> update(String userId, {required String fullName, String? phone, String? dzongkhag}) =>
      _client.from('profiles').update({
        'full_name': fullName.trim(),
        'phone': phone,
        'dzongkhag': dzongkhag,
      }).eq('id', userId);
}

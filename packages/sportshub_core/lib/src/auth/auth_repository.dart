import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_provider.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(supabaseProvider)));

/// Every sign-in, sign-out and token refresh.
final authChangesProvider = StreamProvider<void>((ref) => ref.watch(authRepositoryProvider).changes);

/// The signed-in user's id, or null. Whatever watches it rebuilds when
/// someone signs in or out (not on token refreshes).
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authChangesProvider);
  return ref.watch(authRepositoryProvider).userId;
});

/// One account for the website and the apps: email and password, with
/// 6-digit email codes to sign up, sign in without a password, or reset it.
/// (Supabase -> Authentication -> Email templates must include {{ .Token }}:
/// see the README.)
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  bool get isLoggedIn => _auth.currentSession != null;
  String? get userId => _auth.currentUser?.id;
  String? get email => _auth.currentUser?.email;

  Stream<void> get changes => _auth.onAuthStateChange.map((_) {});

  Future<void> signIn({required String email, required String password}) =>
      _auth.signInWithPassword(email: email.trim().toLowerCase(), password: password);

  /// Emails a code that makes the account when it's entered.
  Future<void> sendSignUpCode({required String email, required String fullName, String? phone}) =>
      _auth.signInWithOtp(
        email: email.trim().toLowerCase(),
        shouldCreateUser: true,
        data: {'full_name': fullName.trim(), if (phone != null) 'phone': phone},
      );

  /// Emails a code to sign in (or to reset the password); no new account.
  Future<void> sendLoginCode(String email) =>
      _auth.signInWithOtp(email: email.trim().toLowerCase(), shouldCreateUser: false);

  /// Signs in with the emailed code.
  Future<void> verifyCode({required String email, required String code}) =>
      _auth.verifyOTP(email: email.trim().toLowerCase(), token: code.trim(), type: OtpType.email);

  Future<void> setPassword(String password) => _auth.updateUser(UserAttributes(password: password));

  Future<void> signOut() => _auth.signOut();

  /// The delete-account Edge Function removes the login and everything that
  /// is only theirs (supabase/functions/delete-account).
  Future<void> deleteAccount() async {
    await _client.functions.invoke('delete-account');
    await _auth.signOut();
  }
}

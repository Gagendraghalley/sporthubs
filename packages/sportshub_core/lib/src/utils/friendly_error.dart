import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// A message to show people for [error].
///
/// The database functions raise their own messages for what people can fix
/// ('This plan is no longer offered'); those are shown as they are. Anything
/// else gets a plain sentence instead of a stack of technical words.
String friendlyError(Object error) {
  if (error is PostgrestException) {
    // Our functions' own messages (raise exception '...').
    if (error.code == 'P0001' || error.code == 'SH001') return error.message;
    if (error.code == '23505') return 'That already exists.';
    if (error.code == '42501') return "You don't have permission to do that.";
    if (error.code == 'PGRST301' || error.message.contains('JWT')) return 'Please sign in again.';
    return 'Something went wrong. Please try again.';
  }
  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login credentials')) return 'Wrong email or password.';
    if (m.contains('token has expired') || m.contains('otp') && m.contains('invalid')) {
      return 'That code is wrong or has expired. Ask for a new one.';
    }
    if (m.contains('rate limit') || error.statusCode == '429') return 'Too many tries. Wait a minute and try again.';
    if (m.contains('signups not allowed') || m.contains('user not found')) return 'No account uses that email.';
    return error.message;
  }
  if (error is StorageException) return 'The photo could not be uploaded. Please try again.';
  if (error is FunctionException) return 'Something went wrong. Please try again.';
  if (error is TimeoutException) return 'This is taking too long. Check your connection and try again.';
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('ClientException') || text.contains('Failed host lookup')) {
    return 'No internet connection. Check it and try again.';
  }
  if (error is StateError) return error.message;
  return 'Something went wrong. Please try again.';
}

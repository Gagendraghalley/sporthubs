/// Settings passed at build time:
///   flutter run --dart-define-from-file=env.json
/// (apps/sportshub_app/env.example.json lists them).
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// The project's anon (publishable) key. Never the service-role key: that
  /// one stays in Supabase Edge Functions.
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// What's wrong with the settings, or null when the app can start.
  static String? get problem {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      return 'Missing Supabase settings.\n\nRun the app with\n--dart-define-from-file=env.json\n'
          '(copy env.example.json to env.json and fill it in).';
    }
    if (supabaseUrl.contains('YOUR-PROJECT') || supabaseAnonKey.startsWith('YOUR-')) {
      return 'env.json still has the example values.\n\n'
          'Put in your Supabase project URL and anon key.';
    }
    return null;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Supabase client, set up in main.dart. Repositories take it from here,
/// so tests can replace them without a network.
final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

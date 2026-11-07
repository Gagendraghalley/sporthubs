import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:sportshub_core/sportshub_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every module in this build. Adding a service: its package, one line here,
/// and its migration (supabase/migrations). Admins turn each on and off in
/// app_modules (Admin -> Modules).
///
/// Gym membership only for now. Ground booking (packages/ground_booking)
/// comes back with `GroundBookingModule(),` here and its import.
const modules = <SportsHubModule>[
  GymModule(),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final problem = Env.problem;
  if (problem != null) {
    runApp(StartupProblemApp(problem));
    return;
  }
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  final themeMode = await ThemeModeController.saved();
  runApp(
    ProviderScope(
      overrides: [
        registeredModulesProvider.overrideWithValue(modules),
        themeModeProvider.overrideWith(() => ThemeModeController(themeMode)),
      ],
      child: const SportsHubApp(),
    ),
  );
}

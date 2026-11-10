import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ground_booking/ground_booking.dart';
import 'package:gym_membership/gym_membership.dart';
import 'package:sportshub_core/sportshub_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every module in this build. Adding a service: its package, one line here,
/// and its migration (supabase/migrations). Admins turn each on and off in
/// app_modules (Admin -> Modules).
const modules = <SportsHubModule>[
  GroundBookingModule(),
  GymModule(),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final problem = Env.problem;
  if (problem != null) {
    runApp(StartupProblemApp(problem));
    return;
  }
  // The splash's logo is read while Supabase starts, so the first frame
  // shows it and the launch screen hands over without a blink.
  final splashLogo = SportsHubSplash.precacheLogo();
  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
  final themeMode = await ThemeModeController.saved();
  await splashLogo;
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

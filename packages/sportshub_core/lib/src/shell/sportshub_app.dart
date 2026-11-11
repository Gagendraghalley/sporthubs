import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../router/app_router.dart';
import '../theme/app_theme.dart';
import '../theme/theme_mode.dart';
import '../widgets/motion.dart';

/// The app, the same on the web, Android and iOS. main.dart wraps it in a
/// ProviderScope that registers the modules.
class SportsHubApp extends ConsumerWidget {
  const SportsHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lessMotion = ref.watch(reduceMotionProvider);
    return MaterialApp.router(
      title: 'SportsHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      // Light and dark cross-fade: every colour (and the side menu's and
      // cards' own, through Brand.darkness) glides to its other self.
      themeAnimationDuration: lessMotion ? Duration.zero : Motion.theme,
      themeAnimationCurve: Motion.easeInOut,
      // Their own Reduce motion joins the device's: everything that asks
      // reduceMotion(context) stands still.
      builder: (context, child) {
        if (!lessMotion) return child!;
        return MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!);
      },
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}

/// Shown instead of the app when it can't start (e.g. missing settings).
class StartupProblemApp extends StatelessWidget {
  final String message;

  const StartupProblemApp(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
          ),
        ),
      ),
    );
  }
}

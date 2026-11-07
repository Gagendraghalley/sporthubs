import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../admin/admin_screens.dart';
import '../auth/auth_repository.dart';
import '../auth/auth_screens.dart';
import '../module/module_providers.dart';
import '../notifications/notifications_screen.dart';
import '../profiles/account_screens.dart';
import '../shell/home_screen.dart';
import '../shell/not_found_screen.dart';
import '../venues/venue_screens.dart';
import 'core_routes.dart';
import 'route_guard.dart';

/// The app's router: the core's pages and every registered module's. Hash
/// URLs on the web (/#/gyms), so links work on any static host.
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final modules = ref.watch(registeredModulesProvider);
  final refresh = _RouterRefresh(auth.changes);
  ref.onDispose(refresh.dispose);
  ref.listen(
    enabledModulesProvider,
    (_, next) => refresh.enabledKeys = next.valueOrNull?.map((m) => m.key).toSet(),
    fireImmediately: true,
  );

  final publicPatterns = {...CoreRoutes.publicPaths, for (final m in modules) ...m.publicPaths};

  return GoRouter(
    initialLocation: CoreRoutes.root,
    refreshListenable: refresh,
    redirect: (context, state) {
      String? moduleKey;
      for (final m in modules) {
        if (m.ownsPath(state.uri.path)) moduleKey = m.key;
      }
      return guardRoute(
        uri: state.uri,
        pattern: state.fullPath ?? state.uri.path,
        signedIn: auth.isLoggedIn,
        publicPatterns: publicPatterns,
        moduleKey: moduleKey,
        enabledModuleKeys: refresh.enabledKeys,
      );
    },
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      GoRoute(path: CoreRoutes.root, builder: (_, __) => const NotFoundScreen()),
      GoRoute(path: CoreRoutes.welcome, builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: CoreRoutes.signIn, builder: (_, s) => SignInScreen(next: safeNext(s.uri.queryParameters['next']))),
      GoRoute(path: CoreRoutes.signUp, builder: (_, s) => SignUpScreen(next: safeNext(s.uri.queryParameters['next']))),
      GoRoute(path: CoreRoutes.verify, builder: (_, __) => const VerifyCodeScreen()),
      GoRoute(
        path: CoreRoutes.setPassword,
        builder: (_, s) => SetPasswordScreen(next: safeNext(s.uri.queryParameters['next'])),
      ),
      GoRoute(path: CoreRoutes.home, builder: (_, __) => const HomeScreen()),
      GoRoute(path: CoreRoutes.account, builder: (_, __) => const AccountScreen()),
      GoRoute(path: CoreRoutes.editProfile, builder: (_, __) => const EditProfileScreen()),
      GoRoute(path: CoreRoutes.notifications, builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: CoreRoutes.registerVenue, builder: (_, __) => const RegisterVenueScreen()),
      GoRoute(
        path: CoreRoutes.registerVenueForm,
        builder: (_, s) => VenueFormScreen(type: s.pathParameters['type']),
      ),
      GoRoute(path: CoreRoutes.manage, builder: (_, __) => const MyVenuesScreen()),
      GoRoute(path: CoreRoutes.venueManage, builder: (_, s) => VenueManageScreen(venueId: s.pathParameters['id']!)),
      GoRoute(path: CoreRoutes.editVenue, builder: (_, s) => VenueFormScreen(venueId: s.pathParameters['id'])),
      GoRoute(path: CoreRoutes.venueStaff, builder: (_, s) => VenueStaffScreen(venueId: s.pathParameters['id']!)),
      GoRoute(path: CoreRoutes.admin, builder: (_, __) => const AdminScreen()),
      GoRoute(path: CoreRoutes.adminVenues, builder: (_, __) => const AdminVenuesScreen()),
      GoRoute(path: CoreRoutes.adminModules, builder: (_, __) => const AdminModulesScreen()),
      for (final m in modules) ...m.routes,
    ],
  );
});

/// Tells the router to check its redirect again: on every sign-in and
/// sign-out, and when the enabled modules change.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Stream<void> authChanges) {
    _subscription = authChanges.listen((_) => notifyListeners());
  }

  late final StreamSubscription<void> _subscription;
  Set<String>? _enabledKeys;

  Set<String>? get enabledKeys => _enabledKeys;
  set enabledKeys(Set<String>? keys) {
    if (setEquals(keys, _enabledKeys)) return;
    _enabledKeys = keys;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

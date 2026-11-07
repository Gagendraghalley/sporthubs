import 'core_routes.dart';

/// Where to send someone opening [uri] instead, or null to let them in.
///
/// - '/' is home for signed-in users and Welcome for visitors.
/// - A module's pages are closed while it's turned off ([moduleKey] not in
///   [enabledModuleKeys]; null while app_modules is still loading).
/// - Sign-in pages send signed-in users on (to ?next= when it's one of ours).
/// - Everything not in [publicPatterns] needs an account: visitors sign in
///   first and come back.
///
/// [pattern] is the matched route's pattern ('/gyms/:id'), so public pages
/// with ids match.
String? guardRoute({
  required Uri uri,
  required String pattern,
  required bool signedIn,
  required Set<String> publicPatterns,
  String? moduleKey,
  Set<String>? enabledModuleKeys,
}) {
  final start = signedIn ? CoreRoutes.home : CoreRoutes.welcome;
  if (uri.path == CoreRoutes.root || uri.path.isEmpty) return start;
  if (moduleKey != null && enabledModuleKeys != null && !enabledModuleKeys.contains(moduleKey)) return start;
  if (signedIn && CoreRoutes.signedOutOnly.contains(pattern)) {
    return safeNext(uri.queryParameters['next']) ?? CoreRoutes.home;
  }
  if (!signedIn && !publicPatterns.contains(pattern)) return CoreRoutes.signInFor(uri.toString());
  return null;
}

/// [next] when it's a page of this app ('/gyms/1'), not another site.
String? safeNext(String? next) =>
    next != null && next.startsWith('/') && !next.startsWith('//') && !next.contains('://') ? next : null;

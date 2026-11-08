import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../access/access.dart';
import '../access/access_repository.dart';
import '../module/module_providers.dart';
import '../router/core_routes.dart';
import '../venues/venue_repository.dart';
import '../widgets/motion.dart';
import 'platform_shell.dart';
import 'service_nav.dart';

// The platform's own pages (Overview, My services, Notifications) are the
// super admin's. Everyone else has only what they've been given: the
// services they work in, and Administration if they're on the team.

/// Whether the platform's own pages are [access]'s.
bool hasPlatformPages(PlatformAccess access) => access.isActive && access.isSuperAdmin;

/// Where someone starts who isn't the super admin: the first page they've
/// been given (a service they work in, then Administration), or their
/// account when they've been given none. Null while that's still loading.
String? assignedStart(WidgetRef ref) {
  final access = ref.watch(myAccessProvider);
  final venues = ref.watch(myVenuesProvider);
  final modules = ref.watch(enabledModulesProvider);
  if ([access, venues, modules].any((v) => v.isLoading && !v.hasValue)) return null;
  for (final s in serviceNavs(ref, CoreRoutes.home)) {
    if (s.nav.isSetUp && s.nav.homeRoute != null) return s.nav.homeRoute;
  }
  return adminNav(access.valueOrNull ?? PlatformAccess.none)?.homeRoute ?? CoreRoutes.account;
}

/// One of the platform's own pages: the super admin sees [child]; anyone
/// else goes on to their first page ([assignedStart]).
class PlatformPage extends ConsumerWidget {
  final Widget child;

  const PlatformPage({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(myAccessProvider);
    if (access.valueOrNull case final a? when hasPlatformPages(a)) return child;
    final start = access.isLoading && !access.hasValue ? null : assignedStart(ref);
    if (start != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(start);
      });
    }
    return const Scaffold(body: LoadingSkeleton());
  }
}

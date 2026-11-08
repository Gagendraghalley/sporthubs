import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/app_page.dart';
import '../widgets/common.dart';
import 'access.dart';
import 'access_repository.dart';

/// A SportsHub admin page: shown to people with [permission] (any of the
/// team's, when null), a lock to everyone else. The database refuses them
/// whatever the app shows; this only keeps the page tidy.
class PermissionGate extends ConsumerWidget {
  final String title;
  final String? permission;
  final Widget Function(BuildContext context, PlatformAccess access) builder;

  const PermissionGate({super.key, required this.title, required this.builder, this.permission});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<PlatformAccess>(
      value: ref.watch(myAccessProvider),
      onRetry: () => ref.invalidate(myAccessProvider),
      data: (access) {
        final allowed = permission == null ? access.isTeam : access.can(permission!);
        if (allowed) return builder(context, access);
        return AppPage(
          title: title,
          body: EmptyState(
            icon: Icons.lock_outline_rounded,
            title: access.isTeam ? "Your role doesn't include this" : 'For the SportsHub team only',
            message: access.isTeam ? 'Ask a SportsHub admin if you need it.' : null,
          ),
        );
      },
    );
  }
}

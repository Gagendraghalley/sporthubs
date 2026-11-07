import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router/core_routes.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      body: EmptyState(
        icon: Icons.explore_off_outlined,
        title: "This page isn't here",
        message: 'The link may be old, or the page has moved.',
        actionLabel: 'Go home',
        onAction: () => context.go(CoreRoutes.root),
      ),
    );
  }
}

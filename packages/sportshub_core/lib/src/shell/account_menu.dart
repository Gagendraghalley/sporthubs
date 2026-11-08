import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_repository.dart';
import '../profiles/profile_repository.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../theme/theme_mode.dart';

// The account menu (their account, light or dark, sign out): at the top
// right of every signed-in page, and under the side menu.

/// The account menu's choices.
List<PopupMenuEntry<String>> accountMenuEntries(ThemeMode mode) => [
      const PopupMenuItem(
        value: 'account',
        child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.person_outline_rounded), title: Text('Account')),
      ),
      const PopupMenuDivider(),
      for (final (value, label, m) in [('light', 'Light', ThemeMode.light), ('dark', 'Dark', ThemeMode.dark), ('system', 'Match device', ThemeMode.system)])
        CheckedPopupMenuItem(value: value, checked: mode == m, child: Text(label)),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'out',
        child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.logout_rounded), title: Text('Sign out')),
      ),
    ];

/// Does what [value], one of [accountMenuEntries], says.
Future<void> chooseFromAccountMenu(BuildContext context, WidgetRef ref, String value) async {
  switch (value) {
    case 'account':
      context.go(CoreRoutes.account);
    case 'light':
      await ref.read(themeModeProvider.notifier).set(ThemeMode.light);
    case 'dark':
      await ref.read(themeModeProvider.notifier).set(ThemeMode.dark);
    case 'system':
      await ref.read(themeModeProvider.notifier).set(ThemeMode.system);
    case 'out':
      await ref.read(authRepositoryProvider).signOut();
      if (context.mounted) context.go(CoreRoutes.welcome);
  }
}

/// Their initial in an orange circle.
class AccountAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const AccountAvatar({super.key, required this.name, this.radius = 17});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: BrandColors.orange,
      child: Text(initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: radius * 0.85)),
    );
  }
}

/// Top right of a signed-in page: their initial, opening the account menu
/// under who is signed in.
class AccountButton extends ConsumerWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final mode = ref.watch(themeModeProvider);
    final name = (profile?.fullName ?? '').trim();
    final email = (profile?.email ?? '').trim();
    return PopupMenuButton<String>(
      tooltip: 'Account and settings',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      onSelected: (value) => chooseFromAccountMenu(context, ref, value),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name.isEmpty ? 'You' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
              if (email.isNotEmpty)
                Text(email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.brand.muted, fontSize: 12.5)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        ...accountMenuEntries(mode),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: AccountAvatar(name: name, radius: 16),
      ),
    );
  }
}

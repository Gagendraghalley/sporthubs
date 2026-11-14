import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../assistant/assistant_chat.dart';
import '../auth/auth_repository.dart';
import '../module/module_providers.dart';
import '../widgets/splash.dart';
import 'platform_shell.dart';
import 'service_nav.dart';

/// The frame around a signed-in user's pages: the platform's
/// ([PlatformShell]), its side menu made of the services. Visitors get the
/// page alone.
class AppShell extends ConsumerWidget {
  /// The page's path, for the menu to mark where you are.
  final String location;
  final Widget child;

  const AppShell({super.key, required this.location, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The floating Ask AI button over every page, for visitors too.
    if (ref.watch(currentUserIdProvider) == null) return AssistantFrame(location: location, child: child);
    final enabled = ref.watch(enabledModulesProvider);
    // The splash while the services load, rather than the page flashing up
    // without its frame.
    return SplashGate(
      ready: enabled.hasValue || !enabled.isLoading,
      builder: (context) => AssistantFrame(location: location, child: PlatformShell(location: location, child: child)),
    );
  }
}

/// What the frame tells the page inside it.
class AppShellScope extends InheritedWidget {
  /// Opens the menu where it's a drawer (a phone); null where it shows beside
  /// the page. Pages put a menu button in their bar for it.
  final VoidCallback? openMenu;

  /// The service the page belongs to, if any: its name over the page's
  /// title, its shortcuts in the bar.
  final ServiceNav? service;

  const AppShellScope({super.key, required this.openMenu, this.service, required super.child});

  static AppShellScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppShellScope>();

  @override
  bool updateShouldNotify(AppShellScope oldWidget) =>
      (oldWidget.openMenu == null) != (openMenu == null) || oldWidget.service?.key != service?.key ||
      oldWidget.service?.actions.length != service?.actions.length;
}

/// Whether the side menu is folded to its icons. Kept on the device.
final sideMenuCollapsedProvider = NotifierProvider<SideMenuCollapsed, bool>(SideMenuCollapsed.new);

class SideMenuCollapsed extends Notifier<bool> {
  static const _key = 'side_menu_collapsed';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getBool(_key);
      if (saved != null && saved != state) state = saved;
    } catch (_) {
      // Not kept on this device: it opens unfolded.
    }
  }

  Future<void> toggle() async {
    state = !state;
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, state);
    } catch (_) {
      // Not kept on this device; it still applies until the app closes.
    }
  }
}

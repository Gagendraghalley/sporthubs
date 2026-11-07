import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light, dark, or as the phone is set (Account -> Appearance). Kept on the
/// device.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  /// Read before the first frame (main.dart), so the app doesn't flash.
  static Future<ThemeMode> saved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ThemeMode.values.asNameMap()[prefs.getString(_key)] ?? ThemeMode.system;
    } catch (_) {
      return ThemeMode.system;
    }
  }

  ThemeModeController([this._initial = ThemeMode.system]);
  final ThemeMode _initial;

  @override
  ThemeMode build() => _initial;

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // Not kept on this device; it still applies until the app closes.
    }
  }
}

/// Light or dark at a tap, for the top bars. It flips what shows now (the
/// phone's own setting, under Auto); Account -> Appearance has Auto back.
class ThemeModeButton extends ConsumerWidget {
  /// The icon's colour; the bar's own when null.
  final Color? color;

  const ThemeModeButton({super.key, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
      color: color,
      onPressed: () => ref.read(themeModeProvider.notifier).set(dark ? ThemeMode.light : ThemeMode.dark),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => RotationTransition(
          turns: Tween(begin: 0.75, end: 1.0).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, key: ValueKey(dark)),
      ),
    );
  }
}

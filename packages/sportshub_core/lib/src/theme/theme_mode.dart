import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light or dark (the bar's switch, or Account -> Appearance); light until
/// they choose, whatever the phone is set to. Kept on the device.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  /// Before they've chosen: the light theme.
  static const initial = ThemeMode.light;

  /// Read before the first frame (main.dart), so the app doesn't flash.
  static Future<ThemeMode> saved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ThemeMode.values.asNameMap()[prefs.getString(_key)] ?? initial;
    } catch (_) {
      return initial;
    }
  }

  ThemeModeController([this._initial = initial]);
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

/// Less motion (Account -> Appearance): the decorative animations stand
/// still, on top of the device's own reduce-motion setting. Kept on the
/// device.
final reduceMotionProvider = NotifierProvider<ReduceMotionController, bool>(ReduceMotionController.new);

class ReduceMotionController extends Notifier<bool> {
  static const _key = 'reduce_motion';

  /// Read before the first frame (main.dart), with the theme.
  static Future<bool> saved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  ReduceMotionController([this._initial = false]);
  final bool _initial;

  @override
  bool build() => _initial;

  Future<void> set(bool reduce) async {
    state = reduce;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, reduce);
    } catch (_) {
      // Not kept on this device; it still applies until the app closes.
    }
  }
}

/// Light or dark at a tap, for the top bars. It flips what shows now: before
/// they've chosen, the phone's own setting.
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

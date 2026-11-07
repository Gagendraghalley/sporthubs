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

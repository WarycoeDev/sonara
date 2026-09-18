import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static const String _themeKey = 'theme_mode';
  static const String _colorThemeKey = 'color_theme';

  static Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themeKey);

    switch (savedTheme) {
      case 'light':
        return ThemeMode.light;

      case 'dark':
        return ThemeMode.dark;

      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> saveThemeMode(ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();

    final value = switch (themeMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

    await prefs.setString(_themeKey, value);
  }

  static Future<String> loadColorTheme() async {
    final prefs = await SharedPreferences.getInstance();

    final savedTheme = prefs.getString(_colorThemeKey);

    if (savedTheme == null) {
      return 'sonara';
    }

    return savedTheme;
  }

  static Future<void> saveColorTheme(String colorTheme) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_colorThemeKey, colorTheme);
  }
}

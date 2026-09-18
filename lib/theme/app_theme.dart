import 'package:flutter/material.dart';

class AppTheme {
  static const String defaultColorTheme = 'sonara';

  static const Map<String, Color> colorThemes = {
    'sonara': Color.fromARGB(255, 58, 91, 183),
    'violeta': Color(0xFF7E57C2),
    'esmeralda': Color(0xFF26A69A),
    'naranja': Color(0xFFFF8A65),
    'rojo': Color(0xFFEF5350),
    'rosa': Color(0xFFEC407A),
    'cian': Color(0xFF26A6C9),
  };

  static const Map<String, String> colorThemeNames = {
    'sonara': 'Sonara',
    'violeta': 'Violeta',
    'esmeralda': 'Esmeralda',
    'naranja': 'Naranja',
    'rojo': 'Rojo',
    'rosa': 'Rosa',
    'cian': 'Cian',
  };

  static ThemeData lightTheme(String colorTheme) {
    final seedColor =
        colorThemes[colorTheme] ?? colorThemes[defaultColorTheme]!;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.light,
      ),
    );
  }

  static ThemeData darkTheme(String colorTheme) {
    final seedColor =
        colorThemes[colorTheme] ?? colorThemes[defaultColorTheme]!;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
      ),
    );
  }
}

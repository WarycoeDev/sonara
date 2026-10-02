import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sonara/core/services/sonara_storage_service.dart';

class ThemeService {
  ThemeService._();

  static const String _fileName = 'theme_settings.json';

  static const String _themeKey = 'theme_mode';
  static const String _colorThemeKey = 'color_theme';

  /// Obtiene la referencia al archivo JSON de configuración de tema en la carpeta `files`.
  static Future<File> _getStorageFile() async {
    final filesDirectory = await SonaraStorageService.getFilesDirectory();
    return File(p.join(filesDirectory.path, _fileName));
  }

  /// Carga todo el mapa de configuraciones guardado en el archivo JSON.
  static Future<Map<String, dynamic>> _readSettings() async {
    try {
      final file = await _getStorageFile();

      if (!await file.exists()) {
        return <String, dynamic>{};
      }

      final content = await file.readAsString(encoding: utf8);

      if (content.isEmpty) {
        return <String, dynamic>{};
      }

      final decoded = jsonDecode(content);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return <String, dynamic>{};
    } catch (error) {
      debugPrint('[ThemeService] Error al leer configuración: $error');
      return <String, dynamic>{};
    }
  }

  /// Escribe de forma atómica actualizando las claves del archivo JSON.
  static Future<void> _writeSettings(Map<String, dynamic> newSettings) async {
    try {
      final currentSettings = await _readSettings();
      currentSettings.addAll(newSettings);

      final file = await _getStorageFile();

      await file.writeAsString(
        jsonEncode(currentSettings),
        encoding: utf8,
        flush: true,
      );
    } catch (error) {
      debugPrint('[ThemeService] Error al guardar configuración: $error');
    }
  }

  static Future<ThemeMode> loadThemeMode() async {
    final settings = await _readSettings();
    final savedTheme = settings[_themeKey];

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
    final value = switch (themeMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

    await _writeSettings({_themeKey: value});
  }

  static Future<String> loadColorTheme() async {
    final settings = await _readSettings();
    final savedTheme = settings[_colorThemeKey];

    if (savedTheme is String && savedTheme.isNotEmpty) {
      return savedTheme;
    }

    return 'sonara';
  }

  static Future<void> saveColorTheme(String colorTheme) async {
    await _writeSettings({_colorThemeKey: colorTheme});
  }
}

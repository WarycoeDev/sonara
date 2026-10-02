import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sonara/core/services/sonara_storage_service.dart';

class LocaleService {
  LocaleService._();

  static const String _fileName = 'locale_settings.json';

  /// Obtiene la referencia al archivo JSON de idioma en la carpeta `files`.
  static Future<File> _getStorageFile() async {
    final filesDirectory = await SonaraStorageService.getFilesDirectory();
    return File(p.join(filesDirectory.path, _fileName));
  }

  static Future<Locale?> loadLocale() async {
    try {
      final file = await _getStorageFile();

      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString(encoding: utf8);

      if (content.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(content);

      if (decoded is Map<String, dynamic>) {
        final languageCode = decoded['language_code'];

        if (languageCode is String && languageCode.isNotEmpty) {
          return Locale(languageCode);
        }
      }

      return null;
    } catch (error) {
      debugPrint('[LocaleService] Error al cargar idioma: $error');
      return null;
    }
  }

  static Future<void> saveLocale(Locale locale) async {
    try {
      final file = await _getStorageFile();

      final data = {'language_code': locale.languageCode};

      await file.writeAsString(jsonEncode(data), encoding: utf8, flush: true);
    } catch (error) {
      debugPrint('[LocaleService] Error al guardar idioma: $error');
    }
  }

  static Future<void> clearLocale() async {
    try {
      final file = await _getStorageFile();

      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      debugPrint('[LocaleService] Error al borrar idioma: $error');
    }
  }
}

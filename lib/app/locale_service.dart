import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleService {
  LocaleService._();

  static const String _key = 'sonara_locale';

  static Future<Locale?> loadLocale() async {
    final prefs = await SharedPreferences.getInstance();

    final languageCode = prefs.getString(_key);

    if (languageCode == null || languageCode.isEmpty) {
      return null;
    }

    return Locale(languageCode);
  }

  static Future<void> saveLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_key, locale.languageCode);
  }

  static Future<void> clearLocale() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_key);
  }
}

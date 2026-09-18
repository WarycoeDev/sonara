import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesRepository extends ChangeNotifier {
  static const String _storageKey = 'sonara_favorites';

  static final FavoritesRepository _instance = FavoritesRepository._internal();

  factory FavoritesRepository() {
    return _instance;
  }

  FavoritesRepository._internal();

  List<String> _favoriteIds = [];

  bool _initialized = false;

  /// Propiedad opcional para indicar que este repositorio soporta reordenamiento explícito
  bool get hasReorderSupport => true;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();

    final rawData = preferences.getString(_storageKey);

    if (rawData != null && rawData.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawData);

        if (decoded is List) {
          _favoriteIds = decoded.whereType<String>().toList();
        }
      } catch (_) {
        _favoriteIds = [];
      }
    }

    _initialized = true;
  }

  List<String> get favoriteIds {
    return List.unmodifiable(_favoriteIds);
  }

  bool isFavorite(String songId) {
    return _favoriteIds.contains(songId);
  }

  /// Reemplaza la lista completa de IDs (para reordenamientos) y la persiste localmente.
  Future<void> saveFavorites(List<String> newFavoriteIds) async {
    await initialize();

    _favoriteIds = List.from(newFavoriteIds);

    await _save();

    notifyListeners();
  }

  /// Método alias para soportar invocaciones con reorderFavorites.
  Future<void> reorderFavorites(List<String> newFavoriteIds) async {
    await saveFavorites(newFavoriteIds);
  }

  Future<void> addFavorite(String songId) async {
    await initialize();

    if (_favoriteIds.contains(songId)) {
      return;
    }

    _favoriteIds.add(songId);

    await _save();

    notifyListeners();
  }

  Future<void> removeFavorite(String songId) async {
    await initialize();

    final removed = _favoriteIds.remove(songId);

    if (!removed) {
      return;
    }

    await _save();

    notifyListeners();
  }

  Future<bool> toggleFavorite(String songId) async {
    await initialize();

    final isFavorite = _favoriteIds.contains(songId);

    if (isFavorite) {
      _favoriteIds.remove(songId);
    } else {
      _favoriteIds.add(songId);
    }

    await _save();

    notifyListeners();

    return !isFavorite;
  }

  Future<void> clear() async {
    await initialize();

    _favoriteIds.clear();

    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_storageKey);

    notifyListeners();
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(_storageKey, jsonEncode(_favoriteIds));
  }
}

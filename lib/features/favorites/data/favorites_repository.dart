import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sonara/core/services/sonara_storage_service.dart';

class FavoritesRepository extends ChangeNotifier {
  static const String _fileName = 'favorites.json';

  static final FavoritesRepository _instance = FavoritesRepository._internal();

  factory FavoritesRepository() {
    return _instance;
  }

  FavoritesRepository._internal();

  List<String> _favoriteIds = [];

  bool _initialized = false;
  Future<void>? _initializeFuture;

  /// Propiedad opcional para indicar que este repositorio soporta reordenamiento explícito
  bool get hasReorderSupport => true;

  /// Obtiene la referencia al archivo JSON en el directorio de la biblioteca.
  Future<File> _getStorageFile() async {
    final libraryDirectory =
        await SonaraStorageService.getLibraryCacheDirectory();
    return File(p.join(libraryDirectory.path, _fileName));
  }

  Future<void> initialize() {
    if (_initialized) {
      return Future<void>.value();
    }

    final currentInitialization = _initializeFuture;

    if (currentInitialization != null) {
      return currentInitialization;
    }

    final initialization = _performInitialize();

    _initializeFuture = initialization;

    return initialization.whenComplete(() {
      if (identical(_initializeFuture, initialization)) {
        _initializeFuture = null;
      }
    });
  }

  Future<void> _performInitialize() async {
    try {
      final file = await _getStorageFile();

      if (await file.exists()) {
        try {
          final content = await file.readAsString(encoding: utf8);

          if (content.isNotEmpty) {
            final decoded = jsonDecode(content);

            if (decoded is List) {
              _favoriteIds = decoded.whereType<String>().toList();
            }
          }
        } catch (_) {
          _favoriteIds = [];
        }
      }

      _initialized = true;

      notifyListeners();
    } catch (_) {
      _initialized = false;
      rethrow;
    }
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

    final file = await _getStorageFile();

    if (await file.exists()) {
      await file.delete();
    }

    notifyListeners();
  }

  Future<void> _save() async {
    final file = await _getStorageFile();

    await file.writeAsString(
      jsonEncode(_favoriteIds),
      encoding: utf8,
      flush: true,
    );
  }
}

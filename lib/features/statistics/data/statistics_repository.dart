import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sonara/core/services/sonara_storage_service.dart';

import '../domain/models/song_statistics.dart';

class StatisticsRepository extends ChangeNotifier {
  static const String _fileName = 'statistics.json';

  static final StatisticsRepository _instance =
      StatisticsRepository._internal();

  factory StatisticsRepository() {
    return _instance;
  }

  StatisticsRepository._internal();

  Map<String, SongStatistics> _statistics = {};

  bool _initialized = false;

  Future<void>? _initializeFuture;

  /// Obtiene la referencia al archivo JSON de estadísticas en el directorio `files/library`.
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

            if (decoded is Map<String, dynamic>) {
              _statistics = decoded.map((key, value) {
                return MapEntry(
                  key,
                  SongStatistics.fromJson(
                    Map<String, dynamic>.from(value as Map),
                  ),
                );
              });
            }
          }
        } catch (_) {
          _statistics = {};
        }
      }

      _initialized = true;

      notifyListeners();
    } catch (_) {
      _initialized = false;
      rethrow;
    }
  }

  Future<SongStatistics> registerPlay(String songId) async {
    await initialize();

    final current = _statistics[songId] ?? SongStatistics(songId: songId);

    final updated = current.copyWith(
      playCount: current.playCount + 1,
      lastPlayed: DateTime.now(),
    );

    _statistics[songId] = updated;

    await _save();

    notifyListeners();

    return updated;
  }

  SongStatistics? getStatistics(String songId) {
    return _statistics[songId];
  }

  List<SongStatistics> getAllStatistics() {
    return List.unmodifiable(_statistics.values);
  }

  List<SongStatistics> getMostPlayed({int limit = 10}) {
    final list = List<SongStatistics>.from(_statistics.values);

    list.sort((a, b) {
      final countComparison = b.playCount.compareTo(a.playCount);

      if (countComparison != 0) {
        return countComparison;
      }

      final aDate = a.lastPlayed;
      final bDate = b.lastPlayed;

      if (aDate == null && bDate == null) {
        return 0;
      }

      if (aDate == null) {
        return 1;
      }

      if (bDate == null) {
        return -1;
      }

      return bDate.compareTo(aDate);
    });

    if (list.length <= limit) {
      return list;
    }

    return list.take(limit).toList();
  }

  Future<void> addListenTime(String songId, Duration duration) async {
    if (duration <= Duration.zero) {
      return;
    }

    await initialize();

    final current = _statistics[songId] ?? SongStatistics(songId: songId);

    final updated = current.copyWith(
      totalListenTime: current.totalListenTime + duration,
    );

    _statistics[songId] = updated;

    await _save();

    notifyListeners();
  }

  Future<void> clear() async {
    await initialize();

    _statistics.clear();

    final file = await _getStorageFile();

    if (await file.exists()) {
      await file.delete();
    }

    notifyListeners();
  }

  Future<void> _save() async {
    final file = await _getStorageFile();

    final encoded = jsonEncode(
      _statistics.map((key, value) {
        return MapEntry(key, value.toJson());
      }),
    );

    await file.writeAsString(encoded, encoding: utf8, flush: true);
  }
}

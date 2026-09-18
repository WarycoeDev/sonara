import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/song_statistics.dart';

class StatisticsRepository extends ChangeNotifier {
  static const String _storageKey = 'sonara_song_statistics';

  static final StatisticsRepository _instance =
      StatisticsRepository._internal();

  factory StatisticsRepository() {
    return _instance;
  }

  StatisticsRepository._internal();

  Map<String, SongStatistics> _statistics = {};

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();

    final rawData = preferences.getString(_storageKey);

    if (rawData != null && rawData.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawData);

        if (decoded is Map<String, dynamic>) {
          _statistics = decoded.map((key, value) {
            return MapEntry(
              key,
              SongStatistics.fromJson(Map<String, dynamic>.from(value as Map)),
            );
          });
        }
      } catch (_) {
        _statistics = {};
      }
    }

    _initialized = true;
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

    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_storageKey);

    notifyListeners();
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();

    final encoded = jsonEncode(
      _statistics.map((key, value) {
        return MapEntry(key, value.toJson());
      }),
    );

    await preferences.setString(_storageKey, encoded);
  }
}

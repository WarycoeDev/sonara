import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/playlist.dart';

class PlaylistsRepository extends ChangeNotifier {
  static const String _storageKey = 'sonara_playlists';

  static const String playlistFileFormat = 'sonara_playlist';
  static const int playlistFileVersion = 1;

  static final PlaylistsRepository _instance = PlaylistsRepository._internal();

  factory PlaylistsRepository() {
    return _instance;
  }

  PlaylistsRepository._internal() {
    initialize();
  }

  final List<Playlist> _playlists = <Playlist>[];

  bool _initialized = false;

  Future<void>? _initializeFuture;

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
      final preferences = await SharedPreferences.getInstance();

      final rawData = preferences.getString(_storageKey);

      final loadedPlaylists = <Playlist>[];

      if (rawData != null && rawData.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawData);

          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                loadedPlaylists.add(
                  Playlist.fromJson(Map<String, dynamic>.from(item)),
                );
              }
            }
          }
        } catch (_) {
          loadedPlaylists.clear();
        }
      }

      _playlists
        ..clear()
        ..addAll(loadedPlaylists);

      _initialized = true;

      notifyListeners();
    } catch (_) {
      _initialized = false;

      rethrow;
    }
  }

  List<Playlist> get playlists {
    return List<Playlist>.unmodifiable(_playlists);
  }

  Playlist? getPlaylist(String playlistId) {
    for (final playlist in _playlists) {
      if (playlist.id == playlistId) {
        return playlist;
      }
    }

    return null;
  }

  Future<Playlist?> createPlaylist(
    String name, {
    List<String> songIds = const <String>[],
  }) async {
    await initialize();

    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      return null;
    }

    final playlist = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmedName,
      songIds: List<String>.unmodifiable(songIds),
      dateCreated: DateTime.now(),
    );

    _playlists.add(playlist);

    await _save();

    notifyListeners();

    return playlist;
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    await initialize();

    final trimmedName = name.trim();

    if (trimmedName.isEmpty) {
      return;
    }

    final index = _playlists.indexWhere(
      (playlist) => playlist.id == playlistId,
    );

    if (index == -1) {
      return;
    }

    _playlists[index] = _playlists[index].copyWith(name: trimmedName);

    await _save();

    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    await initialize();

    final index = _playlists.indexWhere(
      (playlist) => playlist.id == playlistId,
    );

    if (index == -1) {
      return;
    }

    _playlists.removeAt(index);

    await _save();

    notifyListeners();
  }

  Future<bool> addSongToPlaylist(String playlistId, String songId) async {
    await initialize();

    final index = _playlists.indexWhere(
      (playlist) => playlist.id == playlistId,
    );

    if (index == -1) {
      return false;
    }

    final playlist = _playlists[index];

    if (playlist.songIds.contains(songId)) {
      return false;
    }

    _playlists[index] = playlist.copyWith(
      songIds: <String>[...playlist.songIds, songId],
    );

    await _save();

    notifyListeners();

    return true;
  }

  Future<bool> removeSongFromPlaylist(String playlistId, String songId) async {
    await initialize();

    final index = _playlists.indexWhere(
      (playlist) => playlist.id == playlistId,
    );

    if (index == -1) {
      return false;
    }

    final playlist = _playlists[index];

    if (!playlist.songIds.contains(songId)) {
      return false;
    }

    _playlists[index] = playlist.copyWith(
      songIds: playlist.songIds
          .where((id) => id != songId)
          .toList(growable: false),
    );

    await _save();

    notifyListeners();

    return true;
  }

  Future<void> reorderSongs(String playlistId, List<String> newSongIds) async {
    await initialize();

    final index = _playlists.indexWhere(
      (playlist) => playlist.id == playlistId,
    );

    if (index == -1) {
      return;
    }

    _playlists[index] = _playlists[index].copyWith(
      songIds: List<String>.unmodifiable(newSongIds),
    );

    await _save();

    notifyListeners();
  }

  // ===========================================================================
  // EXPORTAR PLAYLIST
  // ===========================================================================

  Future<bool> exportPlaylist(String playlistId) async {
    await initialize();

    final playlist = getPlaylist(playlistId);

    if (playlist == null) {
      return false;
    }

    try {
      final exportData = <String, dynamic>{
        'format': playlistFileFormat,
        'version': playlistFileVersion,
        'playlist': <String, dynamic>{
          'name': playlist.name,
          'songIds': playlist.songIds,
          'dateCreated': playlist.dateCreated.toIso8601String(),
        },
      };

      final jsonData = const JsonEncoder.withIndent('  ').convert(exportData);

      final filePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Exportar playlist',
        fileName: '${_sanitizeFileName(playlist.name)}.sonara',
        type: FileType.custom,
        allowedExtensions: const ['sonara'],
        bytes: utf8.encode(jsonData),
      );

      return filePath != null && filePath.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ===========================================================================
  // IMPORTAR PLAYLIST
  // ===========================================================================

  Future<Playlist?> importPlaylist() async {
    await initialize();

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Importar playlist',
      type: FileType.custom,
      allowedExtensions: const ['sonara'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final platformFile = result.files.single;

    final path = platformFile.path;

    if (path == null || path.isEmpty) {
      return null;
    }

    final file = File(path);

    if (!await file.exists()) {
      return null;
    }

    final content = await file.readAsString(encoding: utf8);

    final decoded = jsonDecode(content);

    if (decoded is! Map) {
      return null;
    }

    final data = Map<String, dynamic>.from(decoded);

    if (data['format'] != playlistFileFormat) {
      return null;
    }

    final version = data['version'];

    if (version is! int || version != playlistFileVersion) {
      return null;
    }

    final rawPlaylist = data['playlist'];

    if (rawPlaylist is! Map) {
      return null;
    }

    final playlistData = Map<String, dynamic>.from(rawPlaylist);

    final name = playlistData['name'];

    if (name is! String || name.trim().isEmpty) {
      return null;
    }

    final rawSongIds = playlistData['songIds'];

    final songIds = rawSongIds is List
        ? rawSongIds.whereType<String>().toList(growable: false)
        : <String>[];

    final rawDateCreated = playlistData['dateCreated'];

    final dateCreated = rawDateCreated is String
        ? DateTime.tryParse(rawDateCreated) ?? DateTime.now()
        : DateTime.now();

    final playlist = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      songIds: List<String>.unmodifiable(songIds),
      dateCreated: dateCreated,
    );

    _playlists.add(playlist);

    await _save();

    notifyListeners();

    return playlist;
  }

  // ===========================================================================
  // LIMPIAR NOMBRE DE ARCHIVO
  // ===========================================================================

  String _sanitizeFileName(String name) {
    final sanitized = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    if (sanitized.isEmpty) {
      return 'playlist';
    }

    return sanitized;
  }

  Future<void> clear() async {
    await initialize();

    _playlists.clear();

    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_storageKey);

    notifyListeners();
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();

    final data = _playlists
        .map((playlist) => playlist.toJson())
        .toList(growable: false);

    await preferences.setString(_storageKey, jsonEncode(data));
  }
}

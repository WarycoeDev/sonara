import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/models/song.dart';
import 'android_artwork_service.dart';

class AndroidMusicService {
  static const MethodChannel _channel = MethodChannel('com.sonara/music');

  final AndroidArtworkService _artworkService = AndroidArtworkService();

  Future<List<Song>>? _loadingFuture;

  // ACTUALIZAR BIBLIOTECA

  Future<List<Song>> refreshLibrary(List<Song> cachedSongs) async {
    if (!Platform.isAndroid) {
      return const <Song>[];
    }

    final currentLoading = _loadingFuture;

    if (currentLoading != null) {
      return currentLoading;
    }

    final future = _refreshLibraryInternal(cachedSongs);

    _loadingFuture = future;

    try {
      return await future;
    } finally {
      _loadingFuture = null;
    }
  }

  Future<List<Song>> _refreshLibraryInternal(List<Song> cachedSongs) async {
    final hasPermission = await _requestAudioPermission();

    if (!hasPermission) {
      return cachedSongs;
    }

    final cachedByPath = <String, Song>{
      for (final song in cachedSongs) song.filePath: song,
    };

    final filesData = await _channel.invokeMethod<List<dynamic>>(
      'getLibraryFiles',
    );

    if (filesData == null) {
      return cachedSongs;
    }

    final files = filesData
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    final updatedSongs = <Song>[];

    for (final data in files) {
      final filePath = data['filePath']?.toString() ?? '';

      if (filePath.isEmpty) {
        continue;
      }

      final lastModified = _readInt(data['lastModified']);

      final fileSize = _readInt(data['fileSize']);

      final cachedSong = cachedByPath[filePath];

      if (_isSameFile(cachedSong, lastModified, fileSize)) {
        updatedSongs.add(cachedSong!);

        continue;
      }

      final song = await _loadSongMetadata(
        filePath: filePath,
        lastModified: lastModified,
        fileSize: fileSize,
        previousSong: cachedSong,
      );

      updatedSongs.add(song);
    }

    return List<Song>.unmodifiable(updatedSongs);
  }

  bool _isSameFile(Song? song, int? lastModified, int? fileSize) {
    if (song == null ||
        lastModified == null ||
        fileSize == null ||
        song.fileLastModified == null ||
        song.fileSize == null) {
      return false;
    }

    return song.fileLastModified == lastModified && song.fileSize == fileSize;
  }

  // PERMISO

  Future<bool> _requestAudioPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestAudioPermission',
      );

      return result == true;
    } on PlatformException catch (error) {
      print(
        '[SONARA ANDROID] '
        'Error solicitando permiso: '
        '${error.message ?? error.code}',
      );

      return false;
    }
  }

  // LEER METADATOS

  Future<Song> _loadSongMetadata({
    required String filePath,
    required int? lastModified,
    required int? fileSize,
    Song? previousSong,
  }) async {
    try {
      final rawData = await _channel.invokeMethod<dynamic>(
        'getSongMetadata',
        <String, dynamic>{'filePath': filePath},
      );

      if (rawData is! Map) {
        throw Exception('Respuesta de metadatos inválida.');
      }

      final data = Map<String, dynamic>.from(rawData);

      final id = data['id']?.toString() ?? filePath;

      final coverPath = await _getCover(
        filePath: filePath,
        songId: id,
        previousSong: previousSong,
      );

      return Song(
        id: id,
        filePath: filePath,
        title: data['title']?.toString() ?? _titleFromPath(filePath),
        artist: data['artist'] as String?,
        album: data['album'] as String?,
        duration: Duration(milliseconds: _readInt(data['duration']) ?? 0),
        coverPath: coverPath,
        dateAdded: DateTime.fromMillisecondsSinceEpoch(
          _readInt(data['dateAdded']) ??
              lastModified ??
              DateTime.now().millisecondsSinceEpoch,
        ),
        source: SongSource.local,
        isFavorite: previousSong?.isFavorite ?? false,
        fileLastModified: lastModified,
        fileSize: fileSize,

        // IMPORTANTE:
        //
        // ReplayGain se recalcula después en LocalLibraryRepository si el
        // archivo cambió.
        volumeGain: null,
      );
    } catch (error) {
      print(
        '[SONARA ANDROID] '
        'Error leyendo metadatos '
        '$filePath: '
        '$error',
      );

      return Song(
        id: filePath,
        filePath: filePath,
        title: _titleFromPath(filePath),
        duration: Duration.zero,
        dateAdded: DateTime.fromMillisecondsSinceEpoch(
          lastModified ?? DateTime.now().millisecondsSinceEpoch,
        ),
        source: SongSource.local,
        isFavorite: previousSong?.isFavorite ?? false,
        fileLastModified: lastModified,
        fileSize: fileSize,
        volumeGain: null,
      );
    }
  }

  // REPLAYGAIN

  Future<double?> calculateTrackGain(String filePath) async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final result = await _channel.invokeMethod<dynamic>(
        'calculateTrackGain',
        <String, dynamic>{'filePath': filePath},
      );

      if (result is num) {
        final gain = result.toDouble();

        if (gain.isNaN || gain.isInfinite) {
          return null;
        }

        return gain;
      }

      return null;
    } on PlatformException catch (error) {
      print(
        '[SONARA ANDROID] '
        'Error calculando ReplayGain de '
        '$filePath: '
        '${error.message ?? error.code}',
      );

      return null;
    } on MissingPluginException {
      print(
        '[SONARA ANDROID] '
        'El método calculateTrackGain '
        'no está disponible.',
      );

      return null;
    } catch (error) {
      print(
        '[SONARA ANDROID] '
        'Error inesperado calculando ReplayGain: '
        '$error',
      );

      return null;
    }
  }

  // CARÁTULA

  Future<String?> _getCover({
    required String filePath,
    required String songId,
    required Song? previousSong,
  }) async {
    final previousCoverPath = previousSong?.coverPath;

    if (previousCoverPath != null && previousCoverPath.isNotEmpty) {
      final previousCover = File(previousCoverPath);

      if (await previousCover.exists()) {
        try {
          if (await previousCover.length() > 0) {
            return previousCoverPath;
          }
        } catch (_) {}
      }
    }

    return _artworkService.extractCover(filePath: filePath, songId: songId);
  }

  // UTILIDADES

  int? _readInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }

  String _titleFromPath(String path) {
    final fileName = path.split(Platform.pathSeparator).last;

    final lastDot = fileName.lastIndexOf('.');

    if (lastDot <= 0) {
      return fileName;
    }

    return fileName.substring(0, lastDot);
  }
}

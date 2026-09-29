import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/models/song.dart';
import 'android_artwork_service.dart';

class AndroidMusicService {
  static const MethodChannel _channel = MethodChannel('com.sonara/music');

  final AndroidArtworkService _artworkService = AndroidArtworkService();

  Future<List<Song>>? _loadingFuture;

  // ============================================================
  // ACTUALIZAR BIBLIOTECA
  // ============================================================

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

      final isSameFile = _isSameFile(cachedSong, lastModified, fileSize);

      if (isSameFile) {
        final songWithValidCover = await _ensureCachedCoverExists(cachedSong!);

        updatedSongs.add(songWithValidCover);

        print(
          '[SONARA ANDROID SCAN] '
          'Sin cambios: $filePath',
        );

        continue;
      }

      print(
        '[SONARA ANDROID SCAN] '
        '${cachedSong == null ? 'Archivo nuevo' : 'Archivo modificado'}: '
        '$filePath',
      );

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

  // ============================================================
  // VERIFICAR CARÁTULA CACHEADA
  // ============================================================

  Future<Song> _ensureCachedCoverExists(Song song) async {
    final coverPath = song.coverPath;

    if (coverPath == null || coverPath.isEmpty) {
      print(
        '[SONARA ANDROID COVER] '
        'La canción no tiene portada. '
        'Regenerando: ${song.filePath}',
      );

      final newCover = await _artworkService.extractCover(
        filePath: song.filePath,
        songId: song.id,
        fileSize: song.fileSize,
        fileLastModified: song.fileLastModified,
        forceRefresh: true,
      );

      return song.copyWith(coverPath: newCover);
    }

    final isRemoteCover =
        coverPath.startsWith('content://') ||
        coverPath.startsWith('http://') ||
        coverPath.startsWith('https://');

    if (isRemoteCover) {
      return song;
    }

    final coverFile = File(coverPath);

    if (await coverFile.exists()) {
      try {
        final length = await coverFile.length();

        if (length > 0) {
          return song;
        }
      } catch (_) {}
    }

    print(
      '[SONARA ANDROID COVER] '
      'La portada cacheada ya no existe. '
      'Regenerando: ${song.filePath}',
    );

    final newCover = await _artworkService.extractCover(
      filePath: song.filePath,
      songId: song.id,
      fileSize: song.fileSize,
      fileLastModified: song.fileLastModified,
      forceRefresh: true,
    );

    return song.copyWith(coverPath: newCover);
  }

  // ============================================================
  // PERMISO
  // ============================================================

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

  // ============================================================
  // LEER METADATOS
  // ============================================================

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

      // ----------------------------------------------------------
      // CARÁTULA
      // ----------------------------------------------------------

      final coverPath = await _getCover(
        filePath: filePath,
        songId: id,
        fileSize: fileSize,
        lastModified: lastModified,
        previousSong: previousSong,
      );

      // ----------------------------------------------------------
      // TÍTULO
      // ----------------------------------------------------------

      String title;

      final metadataTitle = data['title']?.toString();

      final previousTitle = previousSong?.title;

      final previousTitleIsValid =
          previousTitle != null &&
          previousTitle.isNotEmpty &&
          previousTitle != previousSong?.filePath &&
          !previousTitle.startsWith('/');

      if (metadataTitle != null && metadataTitle.isNotEmpty) {
        title = metadataTitle;
      } else if (previousTitleIsValid) {
        title = previousTitle;
      } else {
        title = _titleFromPath(filePath);
      }

      print(
        '[SONARA ANDROID SCAN] '
        'Título: "$title"',
      );

      return Song(
        id: id,
        filePath: filePath,
        title: title,
        artist: data['artist'] as String?,
        album: data['album'] as String?,
        duration: Duration(milliseconds: _readInt(data['duration']) ?? 0),
        coverPath: coverPath,

        // Mantener la fecha original de la canción.
        dateAdded:
            previousSong?.dateAdded ??
            DateTime.fromMillisecondsSinceEpoch(
              _readInt(data['dateAdded']) ??
                  lastModified ??
                  DateTime.now().millisecondsSinceEpoch,
            ),

        source: SongSource.local,

        isFavorite: previousSong?.isFavorite ?? false,

        fileLastModified: lastModified,
        fileSize: fileSize,

        // ReplayGain se recalcula después.
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
        id: previousSong?.id ?? filePath,
        filePath: filePath,

        // Nunca reemplazar el título existente por la ruta.
        title: previousSong?.title ?? _titleFromPath(filePath),

        artist: previousSong?.artist,
        album: previousSong?.album,
        duration: previousSong?.duration ?? Duration.zero,
        coverPath: previousSong?.coverPath,

        dateAdded:
            previousSong?.dateAdded ??
            DateTime.fromMillisecondsSinceEpoch(
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

  // ============================================================
  // REPLAYGAIN
  // ============================================================

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

  // ============================================================
  // CARÁTULA
  // ============================================================

  Future<String?> _getCover({
    required String filePath,
    required String songId,
    required int? fileSize,
    required int? lastModified,
    required Song? previousSong,
  }) async {
    // Si la canción ya existía, significa que el archivo cambió.
    //
    // Por lo tanto NO reutilizamos previousSong.coverPath.
    //
    // Primero eliminamos la portada vieja del cache.
    await _deletePreviousArtwork(previousSong);

    print(
      '[SONARA ANDROID COVER] '
      'Extrayendo nueva portada: $filePath',
    );

    return _artworkService.extractCover(
      filePath: filePath,
      songId: songId,
      fileSize: fileSize,
      fileLastModified: lastModified,
      forceRefresh: true,
    );
  }

  Future<void> _deletePreviousArtwork(Song? previousSong) async {
    final previousCoverPath = previousSong?.coverPath;

    if (previousCoverPath == null || previousCoverPath.isEmpty) {
      return;
    }

    final isRemoteCover =
        previousCoverPath.startsWith('content://') ||
        previousCoverPath.startsWith('http://') ||
        previousCoverPath.startsWith('https://');

    if (isRemoteCover) {
      return;
    }

    try {
      final previousCover = File(previousCoverPath);

      if (!await previousCover.exists()) {
        return;
      }

      await previousCover.delete();

      print(
        '[SONARA ANDROID COVER CACHE] '
        'Carátula anterior eliminada: '
        '$previousCoverPath',
      );
    } catch (error) {
      print(
        '[SONARA ANDROID COVER CACHE] '
        'No se pudo eliminar la carátula anterior: '
        '$error',
      );
    }
  }

  // ============================================================
  // UTILIDADES
  // ============================================================

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

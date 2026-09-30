import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/models/album.dart';
import '../../domain/models/artist.dart';
import '../../domain/models/song.dart';
import '../../domain/repositories/library_repository.dart';

import '../services/android_music_service.dart';
import '../services/library_cache_service.dart';
import '../services/linux_audio_metadata_service.dart';
import '../services/local_music_scanner.dart';
import '../services/music_directory_service.dart';
import '../services/replay_gain_service.dart';

class LocalLibraryRepository extends ChangeNotifier
    implements LibraryRepository {
  static final LocalLibraryRepository _instance =
      LocalLibraryRepository._internal();

  factory LocalLibraryRepository({
    LocalMusicScanner? scanner,
    MusicDirectoryService? musicDirectoryService,
    AndroidMusicService? androidMusicService,
    LinuxAudioMetadataService? linuxAudioMetadataService,
    LibraryCacheService? libraryCacheService,
  }) {
    return _instance;
  }

  LocalLibraryRepository._internal()
    : _scanner = LocalMusicScanner(),
      _musicDirectoryService = MusicDirectoryService(),
      _androidMusicService = AndroidMusicService(),
      _linuxAudioMetadataService = LinuxAudioMetadataService(),
      _libraryCacheService = LibraryCacheService(),
      _replayGainService = ReplayGainService();

  final LocalMusicScanner _scanner;
  final MusicDirectoryService _musicDirectoryService;
  final AndroidMusicService _androidMusicService;
  final LinuxAudioMetadataService _linuxAudioMetadataService;
  final LibraryCacheService _libraryCacheService;
  final ReplayGainService _replayGainService;

  final List<Song> _songs = <Song>[];

  late final UnmodifiableListView<Song> _songsView = UnmodifiableListView<Song>(
    _songs,
  );

  Future<void>? _loadFuture;
  Future<void>? _scanFuture;

  bool _hasLoaded = false;

  // ===========================================================================
  // OBTENER CANCIONES
  // ===========================================================================

  @override
  Future<List<Song>> getSongs() async {
    await _ensureLibraryLoaded();

    return _songsView;
  }

  /// Devuelve la biblioteca actual.
  ///
  /// Es una copia inmutable para evitar que otros componentes modifiquen
  /// directamente la lista interna.
  List<Song> get currentSongs {
    return List<Song>.unmodifiable(_songs);
  }

  // ===========================================================================
  // ACTUALIZAR UNA CANCIÓN
  // ===========================================================================

  /// Actualiza una única canción dentro de la biblioteca.
  ///
  /// Se utiliza para operaciones que modifican físicamente un archivo sin
  /// necesidad de volver a escanear toda la biblioteca.
  ///
  /// Ejemplo:
  ///
  /// - eliminar carátula incrustada;
  /// - cambiar metadata;
  /// - modificar alguna propiedad de una canción.
  ///
  /// También persiste inmediatamente la biblioteca actualizada en cache
  /// y notifica a los listeners para que LibraryPage pueda reconstruirse.
  Future<void> updateSong(Song updatedSong) async {
    await _ensureLibraryLoaded();

    final index = _songs.indexWhere((song) => song.id == updatedSong.id);

    if (index == -1) {
      if (kDebugMode) {
        print(
          '[SONARA LIBRARY] '
          'No se encontró la canción para actualizar: '
          '${updatedSong.filePath}',
        );
      }

      return;
    }

    _songs[index] = updatedSong;

    _songs.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );

    await _libraryCacheService.saveSongs(_songs);

    if (kDebugMode) {
      print(
        '[SONARA LIBRARY] '
        'Canción actualizada: '
        '${updatedSong.title}',
      );
    }

    notifyListeners();
  }

  // ===========================================================================
  // CARGAR CACHÉ
  // ===========================================================================

  Future<void> _ensureLibraryLoaded() async {
    if (_hasLoaded) {
      return;
    }

    final currentLoad = _loadFuture;

    if (currentLoad != null) {
      return currentLoad;
    }

    final completer = Completer<void>();

    _loadFuture = completer.future;

    try {
      final cachedSongs = await _libraryCacheService.loadSongs();

      if (cachedSongs.isNotEmpty) {
        _replaceSongs(cachedSongs);

        _hasLoaded = true;

        if (kDebugMode) {
          print(
            '[SONARA LIBRARY] '
            'Biblioteca cargada desde caché.',
          );
        }

        completer.complete();

        return;
      }

      if (kDebugMode) {
        print(
          '[SONARA LIBRARY] '
          'No hay caché. '
          'Realizando primer escaneo...',
        );
      }

      await _scanLibraryInternal();

      _hasLoaded = true;

      completer.complete();
    } catch (error, stackTrace) {
      _hasLoaded = false;

      completer.completeError(error, stackTrace);

      rethrow;
    } finally {
      _loadFuture = null;
    }
  }

  // ===========================================================================
  // ESCANEAR BIBLIOTECA
  // ===========================================================================

  @override
  Future<void> scanLibrary() async {
    await _ensureLibraryLoaded();

    await _scanLibraryInternal();
  }

  Future<void> _scanLibraryInternal() async {
    final currentScan = _scanFuture;

    if (currentScan != null) {
      return currentScan;
    }

    final completer = Completer<void>();

    _scanFuture = completer.future;

    try {
      final previousSongs = List<Song>.from(_songs);

      if (Platform.isAndroid) {
        await _scanAndroidLibrary();
      } else if (Platform.isLinux) {
        await _scanLinuxLibrary(previousSongs);
      } else {
        await _scanDesktopLibrary(previousSongs);
      }

      await _applyReplayGain(previousSongs);

      await _libraryCacheService.saveSongs(_songs);

      _hasLoaded = true;

      if (kDebugMode) {
        print(
          '[SONARA LIBRARY] '
          'Biblioteca actualizada y guardada.',
        );
      }

      completer.complete();

      notifyListeners();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);

      rethrow;
    } finally {
      _scanFuture = null;
    }
  }

  // ===========================================================================
  // ANDROID
  // ===========================================================================

  Future<void> _scanAndroidLibrary() async {
    final songs = await _androidMusicService.refreshLibrary(
      List<Song>.from(_songs),
    );

    _replaceSongs(songs);
  }

  // ===========================================================================
  // LINUX
  // ===========================================================================

  Future<void> _scanLinuxLibrary(List<Song> previousSongs) async {
    final directoryPaths = await _musicDirectoryService.getMusicDirectories();

    if (directoryPaths.isEmpty) {
      _replaceSongs(const <Song>[]);

      return;
    }

    final files = await _scanner.scanDirectories(directoryPaths);

    if (files.isEmpty) {
      _replaceSongs(const <Song>[]);

      return;
    }

    final previousByPath = <String, Song>{
      for (final song in previousSongs) song.filePath: song,
    };

    final songs = await _processLinuxFiles(files, previousByPath);

    _replaceSongs(songs);
  }

  Future<List<Song>> _processLinuxFiles(
    List<File> files,
    Map<String, Song> previousByPath,
  ) async {
    const concurrency = 4;

    final results = List<Song?>.filled(files.length, null);

    for (var start = 0; start < files.length; start += concurrency) {
      final end = (start + concurrency).clamp(0, files.length);

      final futures = <Future<void>>[];

      for (var index = start; index < end; index++) {
        final file = files[index];

        futures.add(() async {
          final previousSong = previousByPath[file.path];

          final song = await _createLinuxSongFromFile(file, previousSong);

          results[index] = song;
        }());
      }

      await Future.wait(futures);
    }

    return results.whereType<Song>().toList(growable: false);
  }

  // ===========================================================================
  // DESKTOP
  // ===========================================================================

  Future<void> _scanDesktopLibrary(List<Song> previousSongs) async {
    final directoryPaths = await _musicDirectoryService.getMusicDirectories();

    if (directoryPaths.isEmpty) {
      _replaceSongs(const <Song>[]);

      return;
    }

    final files = await _scanner.scanDirectories(directoryPaths);

    if (files.isEmpty) {
      _replaceSongs(const <Song>[]);

      return;
    }

    final previousByPath = <String, Song>{
      for (final song in previousSongs) song.filePath: song,
    };

    final songs = <Song>[];

    for (final file in files) {
      final previous = previousByPath[file.path];

      try {
        final stat = await file.stat();

        final isSameFile =
            previous != null &&
            previous.fileLastModified == stat.modified.millisecondsSinceEpoch &&
            previous.fileSize == stat.size;

        if (isSameFile) {
          songs.add(previous);

          continue;
        }

        songs.add(
          Song(
            id: file.path,
            filePath: file.path,
            title: _removeExtension(
              file.path.split(Platform.pathSeparator).last,
            ),
            duration: Duration.zero,
            dateAdded: previous?.dateAdded ?? stat.modified,
            source: SongSource.local,
            isFavorite: previous?.isFavorite ?? false,
            fileLastModified: stat.modified.millisecondsSinceEpoch,
            fileSize: stat.size,
          ),
        );
      } catch (error) {
        if (kDebugMode) {
          print(
            '[SONARA LIBRARY] '
            'No se pudo procesar: ${file.path}',
          );
        }

        if (kDebugMode) {
          print('[SONARA LIBRARY] $error');
        }
      }
    }

    _replaceSongs(songs);
  }

  // ===========================================================================
  // CREAR CANCIÓN LINUX
  // ===========================================================================

  Future<Song> _createLinuxSongFromFile(File file, Song? previousSong) async {
    final stat = await file.stat();

    final modified = stat.modified.millisecondsSinceEpoch;
    final size = stat.size;

    final isSameFile =
        previousSong != null &&
        previousSong.fileLastModified == modified &&
        previousSong.fileSize == size;

    if (kDebugMode) {
      print('[SONARA SCAN DEBUG]');
    }
    if (kDebugMode) {
      print('Archivo: ${file.path}');
    }
    if (kDebugMode) {
      print('Anterior size: ${previousSong?.fileSize}');
    }
    if (kDebugMode) {
      print('Actual size: $size');
    }
    if (kDebugMode) {
      print(
        'Anterior modified: '
        '${previousSong?.fileLastModified}',
      );
    }
    if (kDebugMode) {
      print('Actual modified: $modified');
    }
    if (kDebugMode) {
      print('Título anterior: ${previousSong?.title}');
    }

    // -------------------------------------------------------------------------
    // ARCHIVO SIN CAMBIOS
    // -------------------------------------------------------------------------

    if (isSameFile) {
      // ignore: unnecessary_non_null_assertion
      final coverPath = previousSong!.coverPath;

      if (coverPath == null || coverPath.isEmpty) {
        if (kDebugMode) {
          print(
            '[SONARA SCAN] '
            'Sin cambios y sin portada: ${file.path}',
          );
        }

        return previousSong;
      }

      final isRemoteCover =
          coverPath.startsWith('content://') ||
          coverPath.startsWith('http://') ||
          coverPath.startsWith('https://');

      if (isRemoteCover) {
        if (kDebugMode) {
          print(
            '[SONARA SCAN] '
            'Sin cambios: ${file.path}',
          );
        }

        return previousSong;
      }

      final coverFile = File(coverPath);

      if (await coverFile.exists()) {
        final coverLength = await coverFile.length();

        if (coverLength > 0) {
          if (kDebugMode) {
            print(
              '[SONARA SCAN] '
              'Sin cambios: ${file.path}',
            );
          }

          return previousSong;
        }
      }

      // La canción no cambió, pero su portada ya no existe.
      if (kDebugMode) {
        print(
          '[SONARA SCAN] '
          'La portada cacheada ya no existe. '
          'Regenerando: ${file.path}',
        );
      }

      final metadata = await _linuxAudioMetadataService.readMetadata(
        file.path,
        fileSize: size,
        fileLastModified: modified,
      );

      return previousSong.copyWith(
        coverPath: metadata.coverPath,
        artist: metadata.artist,
        album: metadata.album,
        duration: metadata.duration,
      );
    }

    // -------------------------------------------------------------------------
    // ARCHIVO MODIFICADO
    // -------------------------------------------------------------------------

    if (kDebugMode) {
      print(
        '[SONARA SCAN] '
        'Archivo modificado: ${file.path}',
      );
    }

    if (previousSong != null) {
      if (kDebugMode) {
        print(
          '[SONARA SCAN] '
          'Conservando título anterior: '
          '"${previousSong.title}"',
        );
      }

      await _deletePreviousArtwork(previousSong);
    } else {
      if (kDebugMode) {
        print(
          '[SONARA SCAN] '
          'No existe canción anterior para: ${file.path}',
        );
      }
    }

    final metadata = await _linuxAudioMetadataService.readMetadata(
      file.path,
      fileSize: size,
      fileLastModified: modified,
    );

    // -------------------------------------------------------------------------
    // OBTENER TÍTULO
    // -------------------------------------------------------------------------

    String title;

    final previousTitle = previousSong?.title;

    final previousTitleIsValid =
        previousTitle != null &&
        previousTitle.isNotEmpty &&
        previousTitle != previousSong?.filePath &&
        !previousTitle.startsWith('/');

    if (previousTitleIsValid) {
      title = previousTitle;
    } else {
      final fileName = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : file.path;

      final lastDot = fileName.lastIndexOf('.');

      if (lastDot > 0) {
        title = fileName.substring(0, lastDot);
      } else {
        title = fileName;
      }
    }

    if (kDebugMode) {
      print(
        '[SONARA SCAN] '
        'Título final: "$title"',
      );
    }

    // -------------------------------------------------------------------------
    // CREAR SONG ACTUALIZADO
    // -------------------------------------------------------------------------

    return Song(
      id: file.path,
      filePath: file.path,
      title: title,
      artist: metadata.artist,
      album: metadata.album,
      duration: metadata.duration,
      coverPath: metadata.coverPath,
      dateAdded: previousSong?.dateAdded ?? stat.modified,
      source: SongSource.local,
      isFavorite: previousSong?.isFavorite ?? false,
      volumeGain: previousSong?.volumeGain,
      fileLastModified: modified,
      fileSize: size,
    );
  }

  // ===========================================================================
  // ELIMINAR CARÁTULA ANTERIOR
  // ===========================================================================

  Future<void> _deletePreviousArtwork(Song song) async {
    final coverPath = song.coverPath;

    if (coverPath == null || coverPath.isEmpty) {
      return;
    }

    if (coverPath.startsWith('content://') ||
        coverPath.startsWith('http://') ||
        coverPath.startsWith('https://')) {
      return;
    }

    try {
      final coverFile = File(coverPath);

      if (!await coverFile.exists()) {
        return;
      }

      await coverFile.delete();

      if (kDebugMode) {
        print(
          '[SONARA COVER CACHE] '
          'Carátula anterior eliminada: '
          '$coverPath',
        );
      }
    } catch (error) {
      if (kDebugMode) {
        print(
          '[SONARA COVER CACHE] '
          'No se pudo eliminar la carátula anterior: '
          '$coverPath',
        );
      }

      if (kDebugMode) {
        print('[SONARA COVER CACHE] $error');
      }
    }
  }

  // ===========================================================================
  // REPLAYGAIN
  // ===========================================================================

  Future<void> _applyReplayGain(List<Song> previousSongs) async {
    if (_songs.isEmpty) {
      return;
    }

    final previousByPath = <String, Song>{
      for (final song in previousSongs) song.filePath: song,
    };

    final pendingIndexes = <int>[];

    for (var index = 0; index < _songs.length; index++) {
      final song = _songs[index];

      final previous = previousByPath[song.filePath];

      final isSameFile = _isSameFile(previous, song);

      if (isSameFile && previous?.volumeGain != null) {
        _songs[index] = song.copyWith(volumeGain: previous!.volumeGain);

        continue;
      }

      if (!isSameFile && song.volumeGain != null) {
        _songs[index] = song.copyWith(volumeGain: null);
      }

      final currentSong = _songs[index];

      if (currentSong.volumeGain != null) {
        continue;
      }

      pendingIndexes.add(index);
    }

    if (pendingIndexes.isEmpty) {
      if (kDebugMode) {
        print(
          '[SONARA REPLAYGAIN] '
          'No hay pistas nuevas para analizar.',
        );
      }

      return;
    }

    if (kDebugMode) {
      print(
        '[SONARA REPLAYGAIN] '
        'Calculando ganancia para '
        '${pendingIndexes.length} pista(s)...',
      );
    }

    final concurrency = Platform.isAndroid ? 1 : 3;

    for (var start = 0; start < pendingIndexes.length; start += concurrency) {
      final end = (start + concurrency).clamp(0, pendingIndexes.length);

      final futures = <Future<void>>[];

      for (var position = start; position < end; position++) {
        final index = pendingIndexes[position];

        futures.add(_calculateReplayGainForSong(index));
      }

      await Future.wait(futures);
    }
  }

  Future<void> _calculateReplayGainForSong(int index) async {
    final song = _songs[index];

    if (kDebugMode) {
      print(
        '[SONARA REPLAYGAIN] '
        'Analizando: ${song.title}',
      );
    }

    final gain = await _replayGainService.calculateTrackGain(song.filePath);

    if (gain == null) {
      if (kDebugMode) {
        print(
          '[SONARA REPLAYGAIN] '
          'No se pudo calcular: ${song.title}',
        );
      }

      return;
    }

    _songs[index] = song.copyWith(volumeGain: gain);

    if (kDebugMode) {
      print(
        '[SONARA REPLAYGAIN] '
        '${song.title}: '
        '${gain.toStringAsFixed(2)} dB',
      );
    }
  }

  bool _isSameFile(Song? previous, Song current) {
    if (previous == null) {
      return false;
    }

    if (previous.filePath != current.filePath) {
      return false;
    }

    if (previous.fileLastModified == null ||
        current.fileLastModified == null ||
        previous.fileSize == null ||
        current.fileSize == null) {
      return false;
    }

    return previous.fileLastModified == current.fileLastModified &&
        previous.fileSize == current.fileSize;
  }

  // ===========================================================================
  // ÁLBUMES
  // ===========================================================================

  @override
  Future<List<Album>> getAlbums() async {
    await _ensureLibraryLoaded();

    if (_songs.isEmpty) {
      return const <Album>[];
    }

    final groups = <String, List<Song>>{};

    for (final song in _songs) {
      final album = _normalizeAlbum(song.album);

      (groups[album] ??= <Song>[]).add(song);
    }

    final albums = <Album>[];

    for (final entry in groups.entries) {
      albums.add(
        Album(
          name: entry.key,
          artist: entry.value.first.artist,
          songs: List<Song>.unmodifiable(entry.value),
        ),
      );
    }

    albums.sort(_compareNames);

    return List<Album>.unmodifiable(albums);
  }

  // ===========================================================================
  // ARTISTAS
  // ===========================================================================

  @override
  Future<List<Artist>> getArtists() async {
    await _ensureLibraryLoaded();

    if (_songs.isEmpty) {
      return const <Artist>[];
    }

    final groups = <String, List<Song>>{};

    for (final song in _songs) {
      final artist = _normalizeArtist(song.artist);

      (groups[artist] ??= <Song>[]).add(song);
    }

    final artists = <Artist>[];

    for (final entry in groups.entries) {
      artists.add(
        Artist(name: entry.key, songs: List<Song>.unmodifiable(entry.value)),
      );
    }

    artists.sort(_compareNames);

    return List<Artist>.unmodifiable(artists);
  }

  // ===========================================================================
  // BÚSQUEDA
  // ===========================================================================

  @override
  Future<List<Song>> searchSongs(String query) async {
    await _ensureLibraryLoaded();

    final normalizedQuery = query.trim().toLowerCase();

    if (normalizedQuery.isEmpty) {
      return const <Song>[];
    }

    final results = <Song>[];

    for (final song in _songs) {
      final title = song.title.toLowerCase();

      final artist = song.artist?.toLowerCase() ?? '';

      final album = song.album?.toLowerCase() ?? '';

      if (title.contains(normalizedQuery) ||
          artist.contains(normalizedQuery) ||
          album.contains(normalizedQuery)) {
        results.add(song);
      }
    }

    return List<Song>.unmodifiable(results);
  }

  // ===========================================================================
  // REEMPLAZAR
  // ===========================================================================

  void _replaceSongs(List<Song> songs) {
    _songs
      ..clear()
      ..addAll(songs);

    _songs.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );

    notifyListeners();
  }

  // ===========================================================================
  // UTILIDADES
  // ===========================================================================

  String _normalizeAlbum(String? album) {
    final value = album?.trim();

    return value == null || value.isEmpty ? 'Sin álbum' : value;
  }

  String _normalizeArtist(String? artist) {
    final value = artist?.trim();

    return value == null || value.isEmpty ? 'Artista desconocido' : value;
  }

  int _compareNames(dynamic a, dynamic b) {
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  String _removeExtension(String fileName) {
    final index = fileName.lastIndexOf('.');

    return index <= 0 ? fileName : fileName.substring(0, index);
  }
}

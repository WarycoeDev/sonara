import 'dart:async';
import 'dart:collection';
import 'dart:io';

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

class LocalLibraryRepository implements LibraryRepository {
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

  // OBTENER CANCIONES

  @override
  Future<List<Song>> getSongs() async {
    await _ensureLibraryLoaded();

    return _songsView;
  }

  // CARGAR CACHÉ

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

        print(
          '[SONARA LIBRARY] '
          'Biblioteca cargada desde caché.',
        );

        completer.complete();

        return;
      }

      print(
        '[SONARA LIBRARY] '
        'No hay caché. '
        'Realizando primer escaneo...',
      );

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

  // ESCANEAR BIBLIOTECA

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
      // Conservamos el estado anterior para:
      //
      // - reutilizar metadatos;
      // - reutilizar favoritos;
      // - reutilizar ReplayGain;
      // - detectar archivos modificados.
      final previousSongs = List<Song>.from(_songs);

      if (Platform.isAndroid) {
        await _scanAndroidLibrary();
      } else if (Platform.isLinux) {
        await _scanLinuxLibrary(previousSongs);
      } else {
        await _scanDesktopLibrary();
      }

      // ReplayGain se aplica únicamente después de terminar el escaneo.
      await _applyReplayGain(previousSongs);

      await _libraryCacheService.saveSongs(_songs);

      _hasLoaded = true;

      print(
        '[SONARA LIBRARY] '
        'Biblioteca actualizada y guardada.',
      );

      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);

      rethrow;
    } finally {
      _scanFuture = null;
    }
  }

  // ANDROID

  Future<void> _scanAndroidLibrary() async {
    final songs = await _androidMusicService.refreshLibrary(
      List<Song>.from(_songs),
    );

    _replaceSongs(songs);
  }

  // LINUX

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
    // Lectura de metadatos con concurrencia limitada.
    //
    // Evitamos:
    // - abrir demasiados archivos;
    // - saturar procesos externos;
    // - crear cientos de tareas simultáneamente.
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

  // DESKTOP

  Future<void> _scanDesktopLibrary() async {
    final directoryPaths = await _musicDirectoryService.getMusicDirectories();

    if (directoryPaths.isEmpty) {
      _replaceSongs(const <Song>[]);

      return;
    }

    final files = await _scanner.scanDirectories(directoryPaths);

    final songs = List<Song>.generate(
      files.length,
      (index) => _createSongFromFile(files[index]),
      growable: false,
    );

    _replaceSongs(songs);
  }

  // REPLAYGAIN

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

      // =====================================================================
      // ARCHIVO SIN CAMBIOS
      // =====================================================================
      //
      // Si el archivo es exactamente el mismo y anteriormente ya teníamos
      // una ganancia calculada, reutilizamos ese valor.
      // =====================================================================

      if (isSameFile && previous?.volumeGain != null) {
        _songs[index] = song.copyWith(volumeGain: previous!.volumeGain);

        continue;
      }

      // =====================================================================
      // ARCHIVO NUEVO O MODIFICADO
      // =====================================================================
      //
      // Una ganancia existente solamente se conserva si sabemos que pertenece
      // al archivo actual.
      //
      // Si el archivo cambió, la ganancia anterior deja de ser válida.
      // =====================================================================

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
      print(
        '[SONARA REPLAYGAIN] '
        'No hay pistas nuevas para analizar.',
      );

      return;
    }

    print(
      '[SONARA REPLAYGAIN] '
      'Calculando ganancia para '
      '${pendingIndexes.length} pista(s)...',
    );

    // Android utiliza MediaCodec.
    //
    // Ejecutar varios decoders simultáneamente puede provocar:
    //
    // - saturación;
    // - mayor consumo;
    // - errores de codec;
    // - peor rendimiento.
    //
    // Linux/Desktop puede ejecutar varios análisis simultáneamente.
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

    print(
      '[SONARA REPLAYGAIN] '
      'Analizando: '
      '${song.title}',
    );

    final gain = await _replayGainService.calculateTrackGain(song.filePath);

    if (gain == null) {
      print(
        '[SONARA REPLAYGAIN] '
        'No se pudo calcular: '
        '${song.title}',
      );

      return;
    }

    _songs[index] = song.copyWith(volumeGain: gain);

    print(
      '[SONARA REPLAYGAIN] '
      '${song.title}: '
      '${gain.toStringAsFixed(2)} dB',
    );
  }

  bool _isSameFile(Song? previous, Song current) {
    if (previous == null) {
      return false;
    }

    if (previous.filePath != current.filePath) {
      return false;
    }

    // Necesitamos ambos datos para considerar seguro reutilizar ReplayGain.
    if (previous.fileLastModified == null ||
        current.fileLastModified == null ||
        previous.fileSize == null ||
        current.fileSize == null) {
      return false;
    }

    return previous.fileLastModified == current.fileLastModified &&
        previous.fileSize == current.fileSize;
  }

  // ÁLBUMES

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

  // ARTISTAS

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

  // BÚSQUEDA

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

  // CREAR CANCIÓN LINUX

  Future<Song> _createLinuxSongFromFile(File file, Song? previousSong) async {
    final stat = await file.stat();

    // Si el archivo no cambió, reutilizamos los metadatos completos.
    if (previousSong != null &&
        previousSong.fileLastModified == stat.modified.millisecondsSinceEpoch &&
        previousSong.fileSize == stat.size) {
      return previousSong;
    }

    final metadata = await _linuxAudioMetadataService.readMetadata(file.path);

    return Song(
      id: file.path,
      filePath: file.path,
      title: _removeExtension(file.path.split(Platform.pathSeparator).last),
      artist: metadata.artist,
      album: metadata.album,
      duration: metadata.duration,
      coverPath: metadata.coverPath,
      dateAdded: stat.modified,
      source: SongSource.local,
      isFavorite: previousSong?.isFavorite ?? false,
      fileLastModified: stat.modified.millisecondsSinceEpoch,
      fileSize: stat.size,
    );
  }

  // CREAR CANCIÓN DESKTOP

  Song _createSongFromFile(File file) {
    final fileName = file.path.split(Platform.pathSeparator).last;

    return Song(
      id: file.path,
      filePath: file.path,
      title: _removeExtension(fileName),
      duration: Duration.zero,
      dateAdded: DateTime.now(),
      source: SongSource.local,
    );
  }

  // REEMPLAZAR

  void _replaceSongs(List<Song> songs) {
    _songs
      ..clear()
      ..addAll(songs);

    _songs.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
  }

  // UTILIDADES

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

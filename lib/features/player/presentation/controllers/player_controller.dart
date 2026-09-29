import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sonara/features/library/data/repositories/local_library_repository.dart';

import '../../../library/data/services/song_artwork_service.dart';

import '../../../favorites/data/favorites_repository.dart';
import '../../../library/domain/models/song.dart';
import '../../../statistics/data/statistics_repository.dart';
import '../../data/services/audio_player_service.dart';
import '../../data/services/artwork_file_service.dart';

enum SonaraRepeatMode { off, one, all }

class PlayerController extends ChangeNotifier {
  final AudioPlayerService _audioPlayerService = AudioPlayerService.instance;

  final StatisticsRepository _statisticsRepository = StatisticsRepository();

  final FavoritesRepository _favoritesRepository = FavoritesRepository();

  final ArtworkFileService _artworkFileService = ArtworkFileService();

  final SongArtworkService _songArtworkService = SongArtworkService();

  final Random _random = Random();

  final List<Song> _queue = <Song>[];

  Song? _currentSong;

  int _currentIndex = -1;

  bool _isPlaying = false;

  bool _isShuffleEnabled = false;

  bool _isFavorite = false;

  bool _isHandlingCompletion = false;

  bool _isDisposed = false;

  int _activeSeeks = 0;

  int _seekRequestId = 0;

  bool _isChangingTrack = false;

  bool _hasRegisteredCurrentPlayback = false;

  SonaraRepeatMode _repeatMode = SonaraRepeatMode.off;

  Duration _position = Duration.zero;

  DateTime? _positionAnchorTime;

  Duration _duration = Duration.zero;

  static const Duration _positionJitterThreshold = Duration(milliseconds: 1000);

  static const Duration _durationTolerance = Duration(seconds: 5);

  static const Duration _completionThreshold = Duration(milliseconds: 500);

  static const Duration _tickInterval = Duration(milliseconds: 200);

  Timer? _positionTicker;

  StreamSubscription<Duration>? _positionSubscription;

  StreamSubscription<Duration?>? _durationSubscription;

  StreamSubscription<PlayerState>? _playerStateSubscription;

  StreamSubscription<int?>? _currentIndexSubscription;

  int _playbackRequestId = 0;

  bool get _isSeeking => _activeSeeks > 0;

  PlayerController() {
    _statisticsRepository.initialize();

    _favoritesRepository.initialize();

    _audioPlayerService.setPlaybackModes(
      shuffleEnabled: _isShuffleEnabled,
      repeatMode: _repeatMode.index,
    );

    _listenToPlayer();
  }

  // ---------------------------------------------------------------------------
  // GETTERS
  // ---------------------------------------------------------------------------

  Song? get currentSong => _currentSong;

  bool get isPlaying => _isPlaying;

  bool get isShuffleEnabled => _isShuffleEnabled;

  bool get isFavorite => _isFavorite;

  SonaraRepeatMode get repeatMode => _repeatMode;

  Duration get position {
    if (_isPlaying && !_isSeeking && _positionAnchorTime != null) {
      final elapsed = DateTime.now().difference(_positionAnchorTime!);

      var estimated = _position + elapsed;

      if (_duration > Duration.zero && estimated > _duration) {
        estimated = _duration;
      }

      return estimated;
    }

    return _position;
  }

  Duration get duration => _duration;

  Duration get displayDuration => _duration;

  List<Song> get queue => List<Song>.unmodifiable(_queue);

  int get currentIndex => _currentIndex;

  bool isInQueue(String songId) {
    return _queue.any((song) => song.id == songId);
  }

  bool get hasNext {
    if (_queue.isEmpty || _currentIndex < 0) {
      return false;
    }

    if (_isShuffleEnabled) {
      return _queue.length > 1;
    }

    return _currentIndex < _queue.length - 1 ||
        _repeatMode == SonaraRepeatMode.all;
  }

  bool get hasPrevious {
    if (_queue.isEmpty || _currentIndex < 0) {
      return false;
    }

    if (position.inSeconds > 3) {
      return true;
    }

    if (_isShuffleEnabled) {
      return _queue.length > 1;
    }

    return _currentIndex > 0;
  }

  // ---------------------------------------------------------------------------
  // STREAMS
  // ---------------------------------------------------------------------------

  void _listenToPlayer() {
    _positionSubscription = _audioPlayerService.positionStream.listen(
      _handlePosition,
    );

    _durationSubscription = _audioPlayerService.durationStream.listen(
      _handleDuration,
    );

    _playerStateSubscription = _audioPlayerService.playerStateStream.listen(
      _handlePlayerState,
    );

    _currentIndexSubscription = _audioPlayerService.currentIndexStream.listen(
      _handleCurrentIndex,
    );
  }

  // ---------------------------------------------------------------------------
  // ÍNDICE ACTUAL
  // ---------------------------------------------------------------------------

  void _handleCurrentIndex(int? index) {
    if (_isDisposed || index == null || index < 0 || index >= _queue.length) {
      return;
    }

    final song = _queue[index];

    final changed = _currentSong?.id != song.id;

    _currentIndex = index;

    _currentSong = song;

    if (changed) {
      _hasRegisteredCurrentPlayback = false;

      _position = Duration.zero;

      _positionAnchorTime = _isPlaying ? DateTime.now() : null;

      _duration = song.duration;

      _isFavorite = _favoritesRepository.isFavorite(song.id);

      if (_isPlaying) {
        _registerCurrentPlayback();
      }
    }

    _notify();
  }

  // ---------------------------------------------------------------------------
  // POSICIÓN
  // ---------------------------------------------------------------------------

  void _handlePosition(Duration newPosition) {
    if (_isDisposed || _isSeeking || _isChangingTrack) {
      return;
    }

    if (newPosition.isNegative) {
      return;
    }

    if (_duration > Duration.zero && newPosition > _duration) {
      newPosition = _duration;
    }

    final displayed = position;

    if (newPosition < displayed &&
        (displayed - newPosition) <= _positionJitterThreshold) {
      return;
    }

    _position = newPosition;

    _positionAnchorTime = _isPlaying ? DateTime.now() : null;

    _notify();
  }

  // ---------------------------------------------------------------------------
  // DURACIÓN
  // ---------------------------------------------------------------------------

  Duration _sanitizeDuration(Duration? live) {
    final value = live ?? Duration.zero;
    final hint = _currentSong?.duration;

    if (hint != null &&
        hint > Duration.zero &&
        value > Duration.zero &&
        (value - hint).abs() > _durationTolerance) {
      return hint;
    }

    return value;
  }

  void _handleDuration(Duration? duration) {
    if (_isDisposed) {
      return;
    }

    final newDuration = _sanitizeDuration(duration);

    if (_duration == newDuration) {
      return;
    }

    _duration = newDuration;

    if (_duration > Duration.zero && _position > _duration) {
      _position = _duration;
    }

    _notify();
  }

  // ---------------------------------------------------------------------------
  // ESTADO DEL PLAYER
  // ---------------------------------------------------------------------------

  void _handlePlayerState(PlayerState state) {
    if (_isDisposed) {
      return;
    }

    final playing = state.playing;

    if (_isPlaying != playing) {
      _isPlaying = playing;

      if (playing) {
        if (!_isChangingTrack) {
          _position = _audioPlayerService.position;
        }

        _positionAnchorTime = DateTime.now();

        _registerCurrentPlayback();
      } else {
        _position = _audioPlayerService.position;

        _positionAnchorTime = null;
      }

      _notify();
    }

    if (state.processingState == ProcessingState.completed) {
      _position = _duration;

      _positionAnchorTime = null;

      _isPlaying = false;

      _notify();

      unawaited(_onSongCompleted());
    }
  }

  // ---------------------------------------------------------------------------
  // COMPLETADO
  // ---------------------------------------------------------------------------

  void _checkCompletionFallback() {
    if (_isDisposed ||
        _isSeeking ||
        _isHandlingCompletion ||
        _currentSong == null ||
        _duration <= Duration.zero) {
      return;
    }

    final remaining = _duration - _position;

    if (remaining <= _completionThreshold) {
      _position = _duration;

      _positionAnchorTime = null;

      _isPlaying = false;

      unawaited(_onSongCompleted());
    }
  }

  Future<void> _onSongCompleted() async {
    if (_isHandlingCompletion ||
        _currentSong == null ||
        _queue.isEmpty ||
        _currentIndex < 0 ||
        _isDisposed) {
      return;
    }

    final completedIndex = _currentIndex;

    _isHandlingCompletion = true;

    try {
      if (_repeatMode == SonaraRepeatMode.one) {
        await _playExistingQueueIndex(completedIndex);

        return;
      }

      if (_isShuffleEnabled && _queue.length > 1) {
        final nextIndex = _getRandomIndexExcluding(completedIndex);

        await _playExistingQueueIndex(nextIndex);

        return;
      }

      if (completedIndex < _queue.length - 1) {
        await _playExistingQueueIndex(completedIndex + 1);

        return;
      }

      if (_repeatMode == SonaraRepeatMode.all) {
        await _playExistingQueueIndex(0);

        return;
      }

      _isPlaying = false;

      _position = _duration;

      _positionAnchorTime = null;

      _notify();
    } finally {
      _isHandlingCompletion = false;
    }
  }

  // ---------------------------------------------------------------------------
  // ESTADÍSTICAS
  // ---------------------------------------------------------------------------

  void _registerCurrentPlayback() {
    if (_isDisposed || _currentSong == null || _hasRegisteredCurrentPlayback) {
      return;
    }

    _hasRegisteredCurrentPlayback = true;

    _registerPlaybackAsync(_currentSong!);
  }

  Future<void> _registerPlaybackAsync(Song song) async {
    try {
      await _statisticsRepository.registerPlay(song.id);
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA STATISTICS ERROR] '
        '${song.title}: $error',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // TICKER
  // ---------------------------------------------------------------------------

  void _startPositionTicker() {
    if (_positionTicker != null) {
      return;
    }

    _positionTicker = Timer.periodic(_tickInterval, (_) {
      if (_isDisposed || !_isPlaying) {
        return;
      }

      _notify();
    });
  }

  void _stopPositionTicker() {
    _positionTicker?.cancel();

    _positionTicker = null;
  }

  // ---------------------------------------------------------------------------
  // NUEVA COLA
  // ---------------------------------------------------------------------------

  Future<void> _playNewQueue(List<Song> songs, int index) async {
    if (songs.isEmpty || index < 0 || index >= songs.length || _isDisposed) {
      return;
    }

    final requestId = ++_playbackRequestId;

    _queue
      ..clear()
      ..addAll(songs);

    final song = _queue[index];

    _currentIndex = index;

    _currentSong = song;

    _hasRegisteredCurrentPlayback = false;

    _position = Duration.zero;

    _positionAnchorTime = null;

    _duration = Duration.zero;

    _isPlaying = false;

    _isFavorite = _favoritesRepository.isFavorite(song.id);

    _isChangingTrack = true;

    _notify();

    try {
      await _favoritesRepository.initialize();

      if (_isDisposed || requestId != _playbackRequestId) {
        return;
      }

      _isFavorite = _favoritesRepository.isFavorite(song.id);

      _notify();

      final duration = await _audioPlayerService.playQueue(
        _queue,
        initialIndex: index,
      );

      if (_isDisposed || requestId != _playbackRequestId) {
        return;
      }

      if (duration != null) {
        _duration = duration;
      }

      _position = Duration.zero;

      _positionAnchorTime = DateTime.now();

      _isPlaying = _audioPlayerService.playing;

      _notify();
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA ERROR] '
        'No se pudo reproducir '
        '${song.title}: $error',
      );

      debugPrintStack(stackTrace: stackTrace);

      if (_isDisposed || requestId != _playbackRequestId) {
        return;
      }

      _isPlaying = false;

      _notify();
    } finally {
      if (requestId == _playbackRequestId) {
        _isChangingTrack = false;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // REPRODUCIR ÍNDICE EXISTENTE
  // ---------------------------------------------------------------------------

  Future<void> _playExistingQueueIndex(int index) async {
    if (_queue.isEmpty || index < 0 || index >= _queue.length || _isDisposed) {
      return;
    }

    final requestId = ++_playbackRequestId;

    final song = _queue[index];

    _currentIndex = index;

    _currentSong = song;

    _hasRegisteredCurrentPlayback = false;

    _position = Duration.zero;

    _positionAnchorTime = null;

    _duration = Duration.zero;

    _isPlaying = false;

    _isFavorite = _favoritesRepository.isFavorite(song.id);

    _isChangingTrack = true;

    _notify();

    try {
      final duration = await _audioPlayerService.playAtIndex(index);

      if (_isDisposed || requestId != _playbackRequestId) {
        return;
      }

      _currentIndex = _audioPlayerService.currentIndex ?? index;

      if (_currentIndex >= 0 && _currentIndex < _queue.length) {
        _currentSong = _queue[_currentIndex];

        _isFavorite = _favoritesRepository.isFavorite(_currentSong!.id);
      }

      if (duration != null) {
        _duration = duration;
      }

      _position = _audioPlayerService.position;

      _isPlaying = _audioPlayerService.playing;

      if (_isPlaying) {
        _positionAnchorTime = DateTime.now();
      }

      _notify();
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA ERROR] '
        '${song.title}: $error',
      );

      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (requestId == _playbackRequestId) {
        _isChangingTrack = false;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // REPRODUCIR CANCIÓN
  // ---------------------------------------------------------------------------

  Future<void> playSong(Song song) async {
    await _playNewQueue([song], 0);
  }

  // ---------------------------------------------------------------------------
  // REPRODUCIR LISTA
  // ---------------------------------------------------------------------------

  Future<void> playFromQueue(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) {
      return;
    }

    final safeIndex = startIndex.clamp(0, songs.length - 1).toInt();

    await _playNewQueue(songs, safeIndex);
  }

  // ---------------------------------------------------------------------------
  // REPRODUCIR DESDE LISTA
  // ---------------------------------------------------------------------------

  Future<void> playSongFromList(List<Song> songs, Song song) async {
    if (songs.isEmpty) {
      return;
    }

    final index = songs.indexWhere((item) => item.id == song.id);

    if (index == -1) {
      return;
    }

    await _playNewQueue(songs, index);
  }

  // ---------------------------------------------------------------------------
  // SIGUIENTE
  // ---------------------------------------------------------------------------

  Future<void> playNext() async {
    if (_queue.isEmpty) {
      return;
    }

    if (_currentIndex < 0) {
      await _playExistingQueueIndex(0);

      return;
    }

    if (_isShuffleEnabled) {
      if (_queue.length <= 1) {
        return;
      }

      await _playExistingQueueIndex(_getRandomIndexExcluding(_currentIndex));

      return;
    }

    final nextIndex = _currentIndex + 1;

    if (nextIndex < _queue.length) {
      await _playExistingQueueIndex(nextIndex);

      return;
    }

    if (_repeatMode == SonaraRepeatMode.all) {
      await _playExistingQueueIndex(0);
    }
  }

  // ---------------------------------------------------------------------------
  // ANTERIOR
  // ---------------------------------------------------------------------------

  Future<void> playPrevious() async {
    if (_queue.isEmpty || _currentIndex < 0) {
      return;
    }

    if (position.inSeconds > 3) {
      await seek(Duration.zero);

      return;
    }

    if (_isShuffleEnabled && _queue.length > 1) {
      await _playExistingQueueIndex(_getRandomIndexExcluding(_currentIndex));

      return;
    }

    final previousIndex = _currentIndex - 1;

    if (previousIndex >= 0) {
      await _playExistingQueueIndex(previousIndex);

      return;
    }

    await seek(Duration.zero);
  }

  int _getRandomIndexExcluding(int excludedIndex) {
    if (_queue.length <= 1) {
      return 0;
    }

    var index = _random.nextInt(_queue.length - 1);

    if (index >= excludedIndex) {
      index++;
    }

    return index;
  }

  // ---------------------------------------------------------------------------
  // CONTROLES
  // ---------------------------------------------------------------------------

  Future<void> pause() {
    return _audioPlayerService.pause();
  }

  Future<void> resume() async {
    if (_currentSong == null) {
      return;
    }

    await _audioPlayerService.resume();
  }

  Future<void> togglePlayPause() async {
    if (_currentSong == null) {
      return;
    }

    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
  }

  // ---------------------------------------------------------------------------
  // SINCRONIZAR LIBRERÍA CON PLAYER
  // ---------------------------------------------------------------------------

  /// Reemplaza las instancias antiguas de Song que utiliza el player
  /// por las nuevas instancias producidas por el escaneo de la librería.
  ///
  /// Esto es importante cuando un archivo cambia y Android genera un
  /// nuevo coverPath.
  ///
  /// NO reinicia la reproducción.
  /// NO vuelve a cargar el audio.
  /// NO modifica position.
  /// NO modifica currentIndex.
  void syncLibrarySongs(List<Song> librarySongs) {
    if (_isDisposed || librarySongs.isEmpty) {
      return;
    }

    final songsByPath = <String, Song>{
      for (final song in librarySongs)
        if (song.filePath.isNotEmpty) song.filePath: song,
    };

    final songsById = <String, Song>{
      for (final song in librarySongs)
        if (song.id.isNotEmpty) song.id: song,
    };

    Song? findUpdatedSong(Song currentSong) {
      final byPath = songsByPath[currentSong.filePath];

      if (byPath != null) {
        return byPath;
      }

      return songsById[currentSong.id];
    }

    var changed = false;

    // ---------------------------------------------------------------
    // Actualizar canciones de la cola.
    // ---------------------------------------------------------------

    for (var index = 0; index < _queue.length; index++) {
      final currentSong = _queue[index];

      final updatedSong = findUpdatedSong(currentSong);

      if (updatedSong == null) {
        continue;
      }

      if (!_songsAreEquivalent(currentSong, updatedSong)) {
        _queue[index] = updatedSong;

        changed = true;
      }
    }

    // ---------------------------------------------------------------
    // Mantener currentSong sincronizado.
    // ---------------------------------------------------------------

    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      final queueSong = _queue[_currentIndex];

      if (_currentSong != queueSong) {
        _currentSong = queueSong;

        changed = true;
      }
    } else if (_currentSong != null) {
      final updatedCurrentSong = findUpdatedSong(_currentSong!);

      if (updatedCurrentSong != null &&
          !_songsAreEquivalent(_currentSong!, updatedCurrentSong)) {
        _currentSong = updatedCurrentSong;

        changed = true;
      }
    }

    if (!changed) {
      return;
    }

    // ---------------------------------------------------------------
    // Actualizar solamente datos derivados.
    //
    // NO tocar position.
    // NO tocar currentIndex.
    // NO recargar AudioPlayer.
    // ---------------------------------------------------------------

    if (_currentSong != null) {
      _isFavorite = _favoritesRepository.isFavorite(_currentSong!.id);

      if (_duration == Duration.zero &&
          _currentSong!.duration > Duration.zero) {
        _duration = _currentSong!.duration;
      }
    }

    _notify();
  }

  bool _songsAreEquivalent(Song a, Song b) {
    return a.id == b.id &&
        a.filePath == b.filePath &&
        a.title == b.title &&
        a.artist == b.artist &&
        a.album == b.album &&
        a.duration == b.duration &&
        a.coverPath == b.coverPath &&
        a.isFavorite == b.isFavorite &&
        a.volumeGain == b.volumeGain &&
        a.fileLastModified == b.fileLastModified &&
        a.fileSize == b.fileSize;
  }

  // ---------------------------------------------------------------------------
  // SEEK
  // ---------------------------------------------------------------------------

  Future<void> seek(Duration newPosition) async {
    if (_currentSong == null) {
      return;
    }

    var safePosition = newPosition;

    if (safePosition.isNegative) {
      safePosition = Duration.zero;
    }

    if (_duration > Duration.zero && safePosition > _duration) {
      safePosition = _duration;
    }

    _activeSeeks++;

    final seekId = ++_seekRequestId;

    _position = safePosition;

    _positionAnchorTime = null;

    _notify();

    try {
      await _audioPlayerService.seek(safePosition);
    } finally {
      _activeSeeks--;

      if (!_isDisposed && seekId == _seekRequestId) {
        _position = safePosition;

        if (_isPlaying) {
          _positionAnchorTime = DateTime.now();
        }

        _notify();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // FAVORITOS
  // ---------------------------------------------------------------------------

  Future<void> toggleFavorite() async {
    final song = _currentSong;

    if (song == null || _isDisposed) {
      return;
    }

    try {
      final isFavorite = await _favoritesRepository.toggleFavorite(song.id);

      if (_isDisposed || _currentSong?.id != song.id) {
        return;
      }

      _isFavorite = isFavorite;

      _notify();
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA FAVORITES ERROR] '
        '${song.title}: $error',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // MODOS
  // ---------------------------------------------------------------------------

  void toggleShuffle() {
    _isShuffleEnabled = !_isShuffleEnabled;

    _audioPlayerService.setPlaybackModes(
      shuffleEnabled: _isShuffleEnabled,
      repeatMode: _repeatMode.index,
    );

    _notify();
  }

  void setRepeatMode(SonaraRepeatMode mode) {
    if (_repeatMode == mode) {
      return;
    }

    _repeatMode = mode;

    _audioPlayerService.setPlaybackModes(
      shuffleEnabled: _isShuffleEnabled,
      repeatMode: _repeatMode.index,
    );

    _notify();
  }

  // ---------------------------------------------------------------------------
  // AGREGAR A COLA
  // ---------------------------------------------------------------------------

  Future<void> addToQueue(Song song) async {
    if (_isDisposed || isInQueue(song.id)) {
      return;
    }

    _queue.add(song);

    try {
      await _audioPlayerService.addToQueue(song);

      if (_currentSong == null) {
        _currentSong = song;

        _currentIndex = 0;

        _duration = _audioPlayerService.duration ?? Duration.zero;

        _isFavorite = _favoritesRepository.isFavorite(song.id);
      }

      _notify();
    } catch (_) {
      _queue.removeWhere((item) => item.id == song.id);

      _notify();
    }
  }

  // ---------------------------------------------------------------------------
  // AGREGAR VARIAS A COLA
  // ---------------------------------------------------------------------------

  Future<void> addSongsToQueue(List<Song> songs) async {
    if (songs.isEmpty || _isDisposed) {
      return;
    }

    final newSongs = songs.where((song) => !isInQueue(song.id)).toList();

    if (newSongs.isEmpty) {
      return;
    }

    _queue.addAll(newSongs);

    try {
      await _audioPlayerService.addSongsToQueue(newSongs);

      if (_currentSong == null && _queue.isNotEmpty) {
        _currentSong = _queue.first;

        _currentIndex = 0;

        _duration = _audioPlayerService.duration ?? Duration.zero;
      }

      _notify();
    } catch (_) {
      _queue.removeWhere(
        (song) => newSongs.any((newSong) => newSong.id == song.id),
      );

      _notify();
    }
  }

  // ---------------------------------------------------------------------------
  // ELIMINAR DE COLA
  // ---------------------------------------------------------------------------

  Future<void> removeFromQueue(Song song) async {
    if (_isDisposed) {
      return;
    }

    final index = _queue.indexWhere((item) => item.id == song.id);

    if (index == -1 || index == _currentIndex) {
      return;
    }

    _queue.removeAt(index);

    if (index < _currentIndex) {
      _currentIndex--;
    }

    _notify();

    try {
      await _audioPlayerService.removeFromQueue(index);
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA QUEUE ERROR] '
        'No se pudo eliminar '
        '${song.title} del reproductor: '
        '$error',
      );

      debugPrintStack(stackTrace: stackTrace);

      if (_isDisposed) {
        return;
      }

      if (index <= _queue.length) {
        _queue.insert(index, song);
      } else {
        _queue.add(song);
      }

      if (index <= _currentIndex) {
        _currentIndex++;
      }

      _notify();
    }
  }

  // ---------------------------------------------------------------------------
  // REORDENAR
  // ---------------------------------------------------------------------------

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _queue.length ||
        newIndex < 0 ||
        newIndex >= _queue.length ||
        oldIndex == newIndex) {
      return;
    }

    await _audioPlayerService.reorderQueue(oldIndex, newIndex);

    final song = _queue.removeAt(oldIndex);

    _queue.insert(newIndex, song);

    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }

    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _currentSong = _queue[_currentIndex];
    }

    _notify();
  }

  // ---------------------------------------------------------------------------
  // ELIMINAR REPRODUCTOR
  // ---------------------------------------------------------------------------

  Future<void> removeCurrentSong() async {
    ++_playbackRequestId;

    _isChangingTrack = false;

    await _audioPlayerService.clear();

    _queue.clear();

    _currentSong = null;

    _currentIndex = -1;

    _position = Duration.zero;

    _positionAnchorTime = null;

    _duration = Duration.zero;

    _isPlaying = false;

    _isFavorite = false;

    _hasRegisteredCurrentPlayback = false;

    _notify();
  }

  Future<void> clearQueue() async {
    await removeCurrentSong();
  }

  // ---------------------------------------------------------------------------
  // CARÁTULA
  // ---------------------------------------------------------------------------

  /// Devuelve el archivo local de la carátula actual.
  ///
  /// Las carátulas content:// y http(s) no se tratan como archivos locales.
  Future<File?> getCurrentArtworkFile() async {
    final song = _currentSong;

    if (song == null) {
      return null;
    }

    final coverPath = song.coverPath;

    if (coverPath == null || coverPath.isEmpty) {
      return null;
    }

    // Las URI externas no se pueden manipular como File local.
    if (_isExternalArtworkPath(coverPath)) {
      return null;
    }

    final file = File(coverPath);

    if (!await file.exists()) {
      return null;
    }

    try {
      final length = await file.length();

      if (length <= 0) {
        return null;
      }
    } catch (_) {
      return null;
    }

    return file;
  }

  /// Cambia la carátula de la canción actualmente reproducida.
  ///
  /// Resultado:
  ///
  /// null  -> el usuario canceló el selector.
  /// true  -> carátula cambiada correctamente.
  /// false -> ocurrió un error.
  Future<bool?> changeCurrentArtwork() async {
    if (_isDisposed || _currentSong == null) {
      return false;
    }

    final song = _currentSong!;

    try {
      final artworkBytes = await _songArtworkService.changeArtwork(
        songPath: song.filePath,
      );

      // El usuario canceló el selector.
      if (artworkBytes == null) {
        return null;
      }

      // Obtenemos los nuevos datos físicos del MP3.
      final audioFile = File(song.filePath);

      if (!await audioFile.exists()) {
        return false;
      }

      final stat = await audioFile.stat();

      // Creamos una nueva instancia de Song.
      //
      // coverPath se conserva porque puede ser una ruta de cache,
      // content://, etc.
      //
      // coverBytes recibe inmediatamente la nueva imagen para que
      // la interfaz no tenga que esperar a que se vuelva a escanear
      // toda la biblioteca.
      final updatedSong = song.copyWith(
        coverBytes: artworkBytes,
        fileSize: stat.size,
        fileLastModified: stat.modified.millisecondsSinceEpoch,
      );

      // Actualizamos la canción dentro de la cola.
      _replaceSongInQueue(updatedSong);

      // Actualizamos la canción actual.
      _currentSong = updatedSong;

      // Mantener el índice actual apuntando a la instancia nueva.
      if (_currentIndex >= 0 &&
          _currentIndex < _queue.length &&
          _queue[_currentIndex].id == updatedSong.id) {
        _currentSong = _queue[_currentIndex];
      }

      // Esto NO reinicia el audio.
      // Solamente hace que PlayerPage, LibraryPage, Queue, etc.
      // reciban el nuevo Song.
      _notify();

      return true;
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA PLAYER ARTWORK] '
        'Error cambiando carátula: $error',
      );

      debugPrintStack(stackTrace: stackTrace);

      return false;
    }
  }

  /// Guarda la carátula actual usando FilePicker.
  ///
  /// El ArtworkFileService se encarga de abrir el selector de archivos
  /// y escribir los bytes, por lo que funciona también cuando Android
  /// devuelve una URI SAF en lugar de una ruta física.

  Future<bool> saveCurrentArtwork() async {
    if (_isDisposed || _currentSong == null) {
      return false;
    }

    final song = _currentSong!;

    final artworkFile = await getCurrentArtworkFile();

    if (artworkFile == null) {
      debugPrint(
        '[SONARA PLAYER ARTWORK] '
        'No existe una carátula local para guardar.',
      );

      return false;
    }

    try {
      final fileName = _buildArtworkFileName(song.title, artworkFile.path);

      final saved = await _artworkFileService.saveArtwork(
        sourcePath: artworkFile.path,
        suggestedFileName: fileName,
      );

      if (saved) {
        debugPrint(
          '[SONARA PLAYER ARTWORK] '
          'Carátula guardada: $fileName',
        );
      }

      return saved;
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA PLAYER ARTWORK] '
        'Error guardando carátula: $error',
      );

      debugPrintStack(stackTrace: stackTrace);

      return false;
    }
  }

  /// Elimina la carátula cacheada actualmente.
  ///
  /// Esto NO modifica la carátula incrustada dentro del archivo de audio.
  /// Solamente elimina nuestra copia cacheada y deja coverPath en null
  /// dentro del PlayerController.
  ///
  /// En un siguiente escaneo de la biblioteca, el artwork embebido puede
  /// volver a extraerse. Eso es intencional mientras no implementemos
  /// escritura de metadatos ID3/FLAC.

  Future<bool> clearCurrentArtwork() async {
    if (_isDisposed || _currentSong == null) {
      return false;
    }

    final song = _currentSong!;
    final audioPath = song.filePath;
    final coverPath = song.coverPath;

    if (audioPath.isEmpty) {
      return false;
    }

    try {
      debugPrint(
        '[SONARA PLAYER ARTWORK] '
        'Eliminando carátula incrustada de: $audioPath',
      );

      // -------------------------------------------------------------------------
      // 1. ELIMINAR LA CARÁTULA FÍSICAMENTE DEL AUDIO
      // -------------------------------------------------------------------------

      final removedFromAudio = await _artworkFileService.deleteEmbeddedArtwork(
        filePath: audioPath,
      );

      if (!removedFromAudio) {
        debugPrint(
          '[SONARA PLAYER ARTWORK] '
          'No se pudo eliminar la carátula incrustada.',
        );

        return false;
      }

      // -------------------------------------------------------------------------
      // 2. ELIMINAR EL CACHE DE LA CARÁTULA
      // -------------------------------------------------------------------------

      if (coverPath != null &&
          coverPath.isNotEmpty &&
          !_isExternalArtworkPath(coverPath)) {
        try {
          final coverFile = File(coverPath);

          if (await coverFile.exists()) {
            await coverFile.delete();

            debugPrint(
              '[SONARA PLAYER ARTWORK] '
              'Cache de carátula eliminada: $coverPath',
            );
          }
        } catch (error) {
          // No hacemos fallar la operación completa si solamente falla
          // el borrado del cache. El artwork ya fue eliminado físicamente
          // del archivo de audio.
          debugPrint(
            '[SONARA PLAYER ARTWORK] '
            'No se pudo eliminar el cache de carátula: $error',
          );
        }
      }

      // -------------------------------------------------------------------------
      // 3. OBTENER LOS DATOS ACTUALES DEL ARCHIVO
      // -------------------------------------------------------------------------

      final audioFile = File(audioPath);

      final stat = await audioFile.stat();

      // -------------------------------------------------------------------------
      // 4. CREAR SONG SIN CARÁTULA
      // -------------------------------------------------------------------------

      final updatedSong = song.copyWith(
        coverPath: null,
        coverBytes: null,
        fileSize: stat.size,
        fileLastModified: stat.modified.millisecondsSinceEpoch,
      );

      // -------------------------------------------------------------------------
      // 5. ACTUALIZAR PLAYER
      // -------------------------------------------------------------------------

      _replaceSongInQueue(updatedSong);

      _currentSong = updatedSong;

      // -------------------------------------------------------------------------
      // 6. ACTUALIZAR LIBRARY REPOSITORY + CACHE
      // -------------------------------------------------------------------------

      await LocalLibraryRepository().updateSong(updatedSong);

      // -------------------------------------------------------------------------
      // 7. NOTIFICAR A LOS LISTENERS DEL PLAYER
      // -------------------------------------------------------------------------

      _notify();

      debugPrint(
        '[SONARA PLAYER ARTWORK] '
        'Carátula eliminada correctamente del archivo de audio.',
      );

      return true;
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA PLAYER ARTWORK] '
        'Error eliminando carátula: $error',
      );

      debugPrintStack(stackTrace: stackTrace);

      return false;
    }
  }

  /// Reemplaza la Song actual dentro de la cola sin reiniciar el audio.
  void _replaceSongInQueue(Song updatedSong) {
    for (var index = 0; index < _queue.length; index++) {
      if (_queue[index].id == updatedSong.id) {
        _queue[index] = updatedSong;
        return;
      }
    }
  }

  bool _isExternalArtworkPath(String path) {
    return path.startsWith('content://') ||
        path.startsWith('http://') ||
        path.startsWith('https://');
  }

  String _buildArtworkFileName(String title, String sourcePath) {
    final extension = _artworkExtension(sourcePath);

    final safeTitle = title
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');

    final normalizedTitle = safeTitle.isEmpty ? 'sonara-cover' : safeTitle;

    return '$normalizedTitle$extension';
  }

  String _artworkExtension(String path) {
    final lastDot = path.lastIndexOf('.');

    if (lastDot == -1 || lastDot == path.length - 1) {
      return '.jpg';
    }

    final extension = path.substring(lastDot).toLowerCase();

    switch (extension) {
      case '.jpg':
      case '.jpeg':
      case '.png':
        return extension;

      default:
        return '.jpg';
    }
  }

  // ---------------------------------------------------------------------------
  // NOTIFICAR
  // ---------------------------------------------------------------------------

  void _notify() {
    if (_isDisposed) {
      return;
    }

    if (_isPlaying) {
      _startPositionTicker();
    } else {
      _stopPositionTicker();
    }

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _isDisposed = true;

    _stopPositionTicker();

    _positionSubscription?.cancel();

    _durationSubscription?.cancel();

    _playerStateSubscription?.cancel();

    _currentIndexSubscription?.cancel();

    unawaited(_audioPlayerService.dispose());

    super.dispose();
  }
}

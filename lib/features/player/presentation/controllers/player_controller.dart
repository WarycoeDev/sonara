import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../../favorites/data/favorites_repository.dart';
import '../../../library/domain/models/song.dart';
import '../../../statistics/data/statistics_repository.dart';
import '../../data/services/audio_player_service.dart';

enum SonaraRepeatMode { off, one, all }

class PlayerController extends ChangeNotifier {
  final AudioPlayerService _audioPlayerService = AudioPlayerService.instance;

  final StatisticsRepository _statisticsRepository = StatisticsRepository();

  final FavoritesRepository _favoritesRepository = FavoritesRepository();

  final Random _random = Random();

  final List<Song> _queue = [];

  Song? _currentSong;

  int _currentIndex = -1;

  bool _isPlaying = false;

  bool _isShuffleEnabled = false;

  bool _isFavorite = false;

  bool _isHandlingCompletion = false;

  bool _isDisposed = false;

  bool _isSeeking = false;

  bool _hasRegisteredCurrentPlayback = false;

  SonaraRepeatMode _repeatMode = SonaraRepeatMode.off;

  Duration _position = Duration.zero;

  DateTime? _positionAnchorTime;

  Duration _duration = Duration.zero;

  static const Duration _positionJitterThreshold = Duration(milliseconds: 350);

  static const Duration _completionThreshold = Duration(milliseconds: 500);

  static const Duration _tickInterval = Duration(milliseconds: 200);

  Timer? _positionTicker;

  StreamSubscription<Duration>? _positionSubscription;

  StreamSubscription<Duration?>? _durationSubscription;

  StreamSubscription<PlayerState>? _playerStateSubscription;

  StreamSubscription<int?>? _currentIndexSubscription;

  int _playbackRequestId = 0;

  PlayerController() {
    _statisticsRepository.initialize();

    _favoritesRepository.initialize();

    _audioPlayerService.setPlaybackModes(
      shuffleEnabled: _isShuffleEnabled,
      repeatMode: _repeatMode.index,
    );

    _listenToPlayer();
  }

  // GETTERS

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

  List<Song> get queue => List.unmodifiable(_queue);

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

  // STREAMS

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

  // ÍNDICE

  void _handleCurrentIndex(int? index) {
    if (_isDisposed || index == null || index < 0 || index >= _queue.length) {
      return;
    }

    final song = _queue[index];

    _currentIndex = index;

    _currentSong = song;

    _hasRegisteredCurrentPlayback = false;

    _position = _audioPlayerService.position;

    _positionAnchorTime = _isPlaying ? DateTime.now() : null;

    _duration = _audioPlayerService.duration ?? Duration.zero;

    _isFavorite = _favoritesRepository.isFavorite(song.id);

    _notify();
  }

  // POSICIÓN

  void _handlePosition(Duration newPosition) {
    if (_isDisposed || _isSeeking) {
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

    if (!_audioPlayerService.isCrossfading) {
      _checkCompletionFallback();
    }

    _notify();
  }

  // DURACIÓN

  void _handleDuration(Duration? duration) {
    if (_isDisposed) {
      return;
    }

    final newDuration = duration ?? Duration.zero;

    if (_duration == newDuration) {
      return;
    }

    _duration = newDuration;

    if (_duration > Duration.zero && _position > _duration) {
      _position = _duration;
    }

    _notify();
  }

  // ESTADO

  void _handlePlayerState(PlayerState state) {
    if (_isDisposed) {
      return;
    }

    final playing = state.playing;

    if (_isPlaying != playing) {
      _isPlaying = playing;

      if (playing) {
        _position = _audioPlayerService.position;

        _positionAnchorTime = DateTime.now();

        _startPositionTicker();

        _registerCurrentPlayback();
      } else {
        _position = _audioPlayerService.position;

        _positionAnchorTime = null;

        _stopPositionTicker();
      }

      _notify();
    }

    if (state.processingState == ProcessingState.completed) {
      if (_audioPlayerService.isCrossfading) {
        return;
      }

      _position = _duration;

      _positionAnchorTime = null;

      _isPlaying = false;

      _stopPositionTicker();

      _notify();

      unawaited(_onSongCompleted());
    }
  }

  // COMPLETADO

  void _checkCompletionFallback() {
    if (_isDisposed ||
        _isSeeking ||
        _isHandlingCompletion ||
        _currentSong == null ||
        _duration <= Duration.zero ||
        _audioPlayerService.isCrossfading) {
      return;
    }

    final remaining = _duration - _position;

    if (remaining <= _completionThreshold) {
      _position = _duration;

      _positionAnchorTime = null;

      _isPlaying = false;

      _stopPositionTicker();

      unawaited(_onSongCompleted());
    }
  }

  Future<void> _onSongCompleted() async {
    if (_isHandlingCompletion ||
        _currentSong == null ||
        _queue.isEmpty ||
        _currentIndex < 0 ||
        _isDisposed ||
        _audioPlayerService.isCrossfading) {
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

      _stopPositionTicker();

      _notify();
    } finally {
      _isHandlingCompletion = false;
    }
  }

  // ESTADÍSTICAS

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

  // TICKER

  void _startPositionTicker() {
    if (_positionTicker != null) {
      return;
    }

    _positionTicker = Timer.periodic(_tickInterval, (_) {
      if (_isDisposed || _isSeeking || !_isPlaying) {
        return;
      }

      if (!_audioPlayerService.isCrossfading) {
        _checkCompletionFallback();
      }

      _notify();
    });
  }

  void _stopPositionTicker() {
    _positionTicker?.cancel();

    _positionTicker = null;
  }

  // NUEVA COLA

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

    _stopPositionTicker();

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
    }
  }

  // REPRODUCIR ÍNDICE EXISTENTE

  Future<void> _playExistingQueueIndex(int index) async {
    if (_queue.isEmpty || index < 0 || index >= _queue.length || _isDisposed) {
      return;
    }

    final requestId = ++_playbackRequestId;

    final song = _queue[index];

    // Actualizamos la interfaz ANTES
    // de cambiar el audio.
    _currentIndex = index;

    _currentSong = song;

    _hasRegisteredCurrentPlayback = false;

    _position = Duration.zero;

    _positionAnchorTime = null;

    _duration = Duration.zero;

    _isPlaying = false;

    _isFavorite = _favoritesRepository.isFavorite(song.id);

    _stopPositionTicker();

    _notify();

    try {
      final duration = await _audioPlayerService.playAtIndex(index);

      if (_isDisposed || requestId != _playbackRequestId) {
        return;
      }

      // Volvemos a sincronizar con
      // el índice real del reproductor.
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

        _startPositionTicker();
      }

      _notify();
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA ERROR] '
        '${song.title}: $error',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // REPRODUCIR CANCIÓN

  Future<void> playSong(Song song) async {
    await _playNewQueue([song], 0);
  }

  // REPRODUCIR LISTA

  Future<void> playFromQueue(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) {
      return;
    }

    final safeIndex = startIndex.clamp(0, songs.length - 1).toInt();

    await _playNewQueue(songs, safeIndex);
  }

  // REPRODUCIR DESDE LISTA

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

  // SIGUIENTE

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

  // ANTERIOR

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

  // CONTROLES

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

  // SEEK

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

    _isSeeking = true;

    _position = safePosition;

    _positionAnchorTime = null;

    _notify();

    try {
      await _audioPlayerService.seek(safePosition);
    } finally {
      _isSeeking = false;

      if (_isPlaying) {
        _positionAnchorTime = DateTime.now();
      }

      _notify();
    }
  }

  // FAVORITOS

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

  // MODOS

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

  // AGREGAR

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

  // AGREGAR VARIAS

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

  // ELIMINAR

  Future<void> removeFromQueue(Song song) async {
    if (_isDisposed) {
      return;
    }

    final index = _queue.indexWhere((item) => item.id == song.id);

    if (index == -1 || index == _currentIndex) {
      return;
    }

    // IMPORTANTE:
    // La canción debe desaparecer de la cola INMEDIATAMENTE.
    //
    // Dismissible ejecuta onDismissed cuando termina la animación.
    // Si esperamos al AudioPlayerService antes de modificar _queue,
    // el Dismissible sigue existiendo en el árbol y Flutter lanza:
    //
    // "A dismissed Dismissible widget is still part of the tree."

    _queue.removeAt(index);

    // Ajustamos el índice actual porque la cola ya cambió.
    if (index < _currentIndex) {
      _currentIndex--;
    }

    // Actualizamos inmediatamente la interfaz para que el Dismissible
    // desaparezca del árbol.
    _notify();

    // Ahora sincronizamos el reproductor de audio.

    try {
      await _audioPlayerService.removeFromQueue(index);
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA QUEUE ERROR] '
        'No se pudo eliminar ${song.title} del reproductor: $error',
      );

      debugPrintStack(stackTrace: stackTrace);

      // Si el servicio de audio falla, restauramos la canción en la misma
      // posición para mantener sincronizados ambos estados.
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

  // REORDENAR

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

  // ELIMINAR REPRODUCTOR

  Future<void> removeCurrentSong() async {
    ++_playbackRequestId;

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

    _stopPositionTicker();

    _notify();
  }

  Future<void> clearQueue() async {
    await removeCurrentSong();
  }

  // NOTIFICAR

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  // DISPOSE

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

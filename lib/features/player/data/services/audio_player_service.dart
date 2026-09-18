import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../app/crossfade_service.dart';
import '../../../library/domain/models/song.dart';

class AudioPlayerService {
  AudioPlayerService._internal() {
    _listenToPlayer();

    _crossfadeService.secondsNotifier.addListener(
      _handleCrossfadeSettingChanged,
    );
  }

  static final AudioPlayerService instance = AudioPlayerService._internal();

  factory AudioPlayerService() => instance;

  // ===========================================================================
  // PLAYER
  // ===========================================================================

  final AudioPlayer _player = AudioPlayer();

  final List<Song> _songs = [];

  ConcatenatingAudioSource? _playlist;

  // ===========================================================================
  // STREAMS
  // ===========================================================================

  final StreamController<PlayerState> _playerStateController =
      StreamController<PlayerState>.broadcast();

  final StreamController<int?> _currentIndexController =
      StreamController<int?>.broadcast();

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();

  // ===========================================================================
  // SUSCRIPCIONES
  // ===========================================================================

  StreamSubscription<PlayerState>? _playerStateSubscription;

  StreamSubscription<Duration>? _positionSubscription;

  StreamSubscription<Duration?>? _durationSubscription;

  StreamSubscription<int?>? _currentIndexSubscription;

  // ===========================================================================
  // REPLAYGAIN
  // ===========================================================================

  double _baseVolume = 1.0;

  double _currentTrackGainLinear = 1.0;

  static const double _replayGainPreamp = 1.0;

  static const double _minimumGainDb = -20.0;

  static const double _maximumGainDb = 20.0;

  bool _isApplyingVolume = false;

  bool _volumeUpdatePending = false;

  // ===========================================================================
  // CROSSFADE
  // ===========================================================================

  final CrossfadeService _crossfadeService = CrossfadeService.instance;

  Timer? _crossfadeMonitor;

  bool _crossfadeInProgress = false;

  int _crossfadeGeneration = 0;

  // Evita que dos comprobaciones del Timer ejecuten
  // la transición al mismo tiempo.
  bool _crossfadeCheckInProgress = false;

  // ===========================================================================
  // ESTADO
  // ===========================================================================

  bool _isDisposed = false;

  // ===========================================================================
  // MODOS
  // ===========================================================================

  bool _shuffleEnabled = false;

  int _repeatMode = 0;

  // 0 = off
  // 1 = one
  // 2 = all

  final math.Random _random = math.Random();

  // ===========================================================================
  // STREAMS PÚBLICOS
  // ===========================================================================

  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  Stream<int?> get currentIndexStream => _currentIndexController.stream;

  Stream<Duration> get positionStream => _positionController.stream;

  Stream<Duration?> get durationStream => _durationController.stream;

  Stream<bool> get playingStream {
    return Stream<bool>.multi((controller) {
      controller.add(playing);

      final subscription = playerStateStream.listen((state) {
        controller.add(state.playing);
      });

      controller.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  // ===========================================================================
  // GETTERS
  // ===========================================================================

  bool get playing => _player.playing;

  Duration get position => _player.position;

  Duration? get duration => _player.duration;

  int? get currentIndex => _player.currentIndex;

  bool get hasQueue => _songs.isNotEmpty;

  List<Song> get queue => List.unmodifiable(_songs);

  double get baseVolume => _baseVolume;

  int get crossfadeSeconds => _crossfadeService.seconds;

  bool get isCrossfading => _crossfadeInProgress;

  // ===========================================================================
  // LISTENERS
  // ===========================================================================

  void _listenToPlayer() {
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (_isDisposed) {
        return;
      }

      if (!_playerStateController.isClosed) {
        _playerStateController.add(state);
      }
    });

    _positionSubscription = _player.positionStream.listen((position) {
      if (_isDisposed) {
        return;
      }

      if (!_positionController.isClosed) {
        _positionController.add(position);
      }
    });

    _durationSubscription = _player.durationStream.listen((duration) {
      if (_isDisposed) {
        return;
      }

      if (!_durationController.isClosed) {
        _durationController.add(duration);
      }
    });

    _currentIndexSubscription = _player.currentIndexStream.listen((index) {
      if (_isDisposed) {
        return;
      }

      if (!_currentIndexController.isClosed) {
        _currentIndexController.add(index);
      }

      if (index != null && index >= 0 && index < _songs.length) {
        _updateTrackGain(_songs[index]);

        // Durante el crossfade no debemos sobrescribir el volumen
        // que está siendo animado manualmente.
        if (!_crossfadeInProgress) {
          unawaited(_applyEffectiveVolume());
        }
      }
    });
  }

  // ===========================================================================
  // AUDIO SOURCE
  // ===========================================================================

  Future<AudioSource> _createAudioSource(Song song) async {
    final file = File(song.filePath);

    if (!await file.exists()) {
      throw FileSystemException('El archivo no existe', song.filePath);
    }

    final mediaItem = await _createMediaItem(song);

    return AudioSource.uri(Uri.file(song.filePath), tag: mediaItem);
  }

  // ===========================================================================
  // REPLAYGAIN
  // ===========================================================================

  void _updateTrackGain(Song song) {
    final gainDb = song.volumeGain;

    if (gainDb == null || !gainDb.isFinite) {
      _currentTrackGainLinear = 1.0;
      return;
    }

    final safeGainDb = gainDb.clamp(_minimumGainDb, _maximumGainDb).toDouble();

    _currentTrackGainLinear = _dbToLinear(safeGainDb);

    debugPrint(
      '[SONARA REPLAYGAIN] '
      '${song.title} | '
      'Ganancia: ${safeGainDb.toStringAsFixed(2)} dB | '
      'Factor: ${_currentTrackGainLinear.toStringAsFixed(3)}',
    );
  }

  double _getTrackGainLinear(Song song) {
    final gainDb = song.volumeGain;

    if (gainDb == null || !gainDb.isFinite) {
      return 1.0;
    }

    final safeGainDb = gainDb.clamp(_minimumGainDb, _maximumGainDb).toDouble();

    return _dbToLinear(safeGainDb);
  }

  double _dbToLinear(double db) {
    return math.pow(10, db / 20).toDouble();
  }

  double _getEffectiveVolumeForSong(Song song) {
    final gain = _getTrackGainLinear(song);

    return (_baseVolume * _replayGainPreamp * gain).clamp(0.0, 1.0).toDouble();
  }

  // ===========================================================================
  // VOLUMEN
  // ===========================================================================

  Future<void> _applyEffectiveVolume() async {
    if (_isDisposed) {
      return;
    }

    if (_crossfadeInProgress) {
      return;
    }

    if (_isApplyingVolume) {
      _volumeUpdatePending = true;
      return;
    }

    _isApplyingVolume = true;

    try {
      do {
        _volumeUpdatePending = false;

        Song? currentSong;

        final index = _player.currentIndex;

        if (index != null && index >= 0 && index < _songs.length) {
          currentSong = _songs[index];
        }

        final effectiveVolume = currentSong == null
            ? _baseVolume
            : _getEffectiveVolumeForSong(currentSong);

        await _player.setVolume(effectiveVolume);
      } while (_volumeUpdatePending);
    } finally {
      _isApplyingVolume = false;
    }
  }

  Future<void> _setTrackGainForIndex(int index) async {
    if (index < 0 || index >= _songs.length) {
      _currentTrackGainLinear = 1.0;

      await _applyEffectiveVolume();

      return;
    }

    _updateTrackGain(_songs[index]);

    await _applyEffectiveVolume();
  }

  // ===========================================================================
  // CROSSFADE - CONFIGURACIÓN
  // ===========================================================================

  void _handleCrossfadeSettingChanged() {
    if (_isDisposed) {
      return;
    }

    if (!_crossfadeService.enabled) {
      _stopCrossfadeMonitor();

      // Si se desactivó mientras estaba haciendo una transición,
      // cancelamos la transición y recuperamos el volumen normal.
      if (_crossfadeInProgress) {
        _crossfadeGeneration++;
        _crossfadeInProgress = false;
        _crossfadeCheckInProgress = false;

        unawaited(_applyEffectiveVolume());
      }

      return;
    }

    if (_player.playing) {
      _startCrossfadeMonitor();
    }
  }

  void _startCrossfadeMonitor() {
    if (_isDisposed ||
        _crossfadeMonitor != null ||
        !_crossfadeService.enabled) {
      return;
    }

    _crossfadeMonitor = Timer.periodic(const Duration(milliseconds: 100), (_) {
      unawaited(_checkCrossfade());
    });
  }

  void _stopCrossfadeMonitor() {
    _crossfadeMonitor?.cancel();
    _crossfadeMonitor = null;
  }

  // ===========================================================================
  // CROSSFADE - COMPROBAR
  // ===========================================================================

  Future<void> _checkCrossfade() async {
    if (_isDisposed ||
        !_crossfadeService.enabled ||
        !_player.playing ||
        _crossfadeInProgress ||
        _crossfadeCheckInProgress) {
      return;
    }

    final currentIndex = _player.currentIndex;

    if (currentIndex == null ||
        currentIndex < 0 ||
        currentIndex >= _songs.length) {
      return;
    }

    final currentDuration = _player.duration;

    if (currentDuration == null || currentDuration <= Duration.zero) {
      return;
    }

    final remaining = currentDuration - _player.position;

    final fadeDuration = _crossfadeService.duration;

    if (fadeDuration <= Duration.zero) {
      return;
    }

    if (remaining <= fadeDuration) {
      _crossfadeCheckInProgress = true;

      try {
        await _performCrossfade();
      } finally {
        _crossfadeCheckInProgress = false;
      }
    }
  }

  // ===========================================================================
  // SIGUIENTE ÍNDICE
  // ===========================================================================

  int? _getCrossfadeNextIndex() {
    final index = _player.currentIndex;

    if (_songs.isEmpty ||
        index == null ||
        index < 0 ||
        index >= _songs.length) {
      return null;
    }

    if (_repeatMode == 1) {
      return index;
    }

    if (_shuffleEnabled && _songs.length > 1) {
      var next = _random.nextInt(_songs.length - 1);

      if (next >= index) {
        next++;
      }

      return next;
    }

    final nextIndex = index + 1;

    if (nextIndex < _songs.length) {
      return nextIndex;
    }

    if (_repeatMode == 2) {
      return 0;
    }

    return null;
  }

  // ===========================================================================
  // CROSSFADE - EJECUTAR
  // ===========================================================================

  Future<void> _performCrossfade() async {
    if (_crossfadeInProgress || _isDisposed || !_crossfadeService.enabled) {
      return;
    }

    final nextIndex = _getCrossfadeNextIndex();

    if (nextIndex == null) {
      // No hay siguiente canción.
      // Dejamos que just_audio termine normalmente.
      return;
    }

    final oldIndex = _player.currentIndex;

    if (oldIndex == null || oldIndex < 0 || oldIndex >= _songs.length) {
      return;
    }

    _crossfadeInProgress = true;

    final generation = ++_crossfadeGeneration;

    final oldSong = _songs[oldIndex];
    final nextSong = _songs[nextIndex];

    try {
      final duration = _crossfadeService.duration;

      final milliseconds = math.max(100, duration.inMilliseconds);

      final steps = math.max(2, (milliseconds / 50).round());

      final stepDuration = Duration(
        milliseconds: math.max(10, (milliseconds / steps).round()),
      );

      final oldVolume = _getEffectiveVolumeForSong(oldSong);
      final newVolume = _getEffectiveVolumeForSong(nextSong);

      debugPrint(
        '[SONARA CROSSFADE] '
        '${oldSong.title} -> ${nextSong.title} '
        '(${duration.inSeconds}s)',
      );

      // -----------------------------------------------------------------------
      // FADE OUT
      // -----------------------------------------------------------------------

      for (var step = 0; step <= steps; step++) {
        if (generation != _crossfadeGeneration ||
            _isDisposed ||
            !_crossfadeService.enabled) {
          return;
        }

        final progress = step / steps;

        final volume = oldVolume * (1.0 - progress);

        await _player.setVolume(volume.clamp(0.0, 1.0).toDouble());

        if (step < steps) {
          await Future<void>.delayed(stepDuration);
        }
      }

      if (generation != _crossfadeGeneration || _isDisposed) {
        return;
      }

      // -----------------------------------------------------------------------
      // CAMBIAR DE CANCIÓN SIN HACER STOP()
      // -----------------------------------------------------------------------

      await _player.setVolume(0.0);

      await _player.seek(Duration.zero, index: nextIndex);

      if (generation != _crossfadeGeneration || _isDisposed) {
        return;
      }

      // -----------------------------------------------------------------------
      // REPRODUCIR LA NUEVA CANCIÓN
      // -----------------------------------------------------------------------

      await _player.play();

      // -----------------------------------------------------------------------
      // FADE IN
      // -----------------------------------------------------------------------

      for (var step = 0; step <= steps; step++) {
        if (generation != _crossfadeGeneration ||
            _isDisposed ||
            !_crossfadeService.enabled) {
          return;
        }

        final progress = step / steps;

        final volume = newVolume * progress;

        await _player.setVolume(volume.clamp(0.0, 1.0).toDouble());

        if (step < steps) {
          await Future<void>.delayed(stepDuration);
        }
      }

      await _player.setVolume(newVolume);

      debugPrint(
        '[SONARA CROSSFADE] '
        'Transición completada -> ${nextSong.title}',
      );
    } catch (error, stackTrace) {
      debugPrint('[SONARA CROSSFADE ERROR] $error');

      debugPrintStack(stackTrace: stackTrace);

      // Recuperación.
      try {
        await _player.setVolume(
          _getEffectiveVolumeForSong(_songs[_player.currentIndex ?? oldIndex]),
        );

        if (!_player.playing) {
          await _player.play();
        }
      } catch (_) {}
    } finally {
      _crossfadeInProgress = false;

      if (!_isDisposed && _crossfadeService.enabled && _player.playing) {
        _startCrossfadeMonitor();
      }
    }
  }

  // ===========================================================================
  // COLA
  // ===========================================================================

  Future<Duration?> setQueue(
    List<Song> songs, {
    required int initialIndex,
  }) async {
    if (songs.isEmpty) {
      await clear();
      return null;
    }

    _cancelTransition();

    _songs
      ..clear()
      ..addAll(songs);

    final safeIndex = initialIndex.clamp(0, _songs.length - 1).toInt();

    final audioSources = <AudioSource>[];

    for (final song in _songs) {
      audioSources.add(await _createAudioSource(song));
    }

    _playlist = ConcatenatingAudioSource(children: audioSources);

    await _player.setAudioSource(
      _playlist!,
      initialIndex: safeIndex,
      initialPosition: Duration.zero,
      preload: true,
    );

    _updateTrackGain(_songs[safeIndex]);

    await _applyEffectiveVolume();

    _emitCurrentState();

    return await _waitForDuration();
  }

  // ===========================================================================
  // REPRODUCIR COLA
  // ===========================================================================

  Future<Duration?> playQueue(
    List<Song> songs, {
    required int initialIndex,
  }) async {
    final duration = await setQueue(songs, initialIndex: initialIndex);

    await play();

    return duration;
  }

  // ===========================================================================
  // REPRODUCIR ÍNDICE
  // ===========================================================================

  Future<Duration?> playAtIndex(int index) async {
    if (_songs.isEmpty || index < 0 || index >= _songs.length) {
      return null;
    }

    // IMPORTANTE:
    // No hacemos stop() aquí.
    //
    // Hacer stop() antes de cambiar de índice era la causa
    // de que "Siguiente" pudiera terminar dejando el reproductor
    // en estado pausado/detenido.
    _cancelTransition();

    final wasPlaying = _player.playing;

    final targetSong = _songs[index];

    debugPrint(
      '[SONARA PLAYER] '
      'Cambiando a índice $index: ${targetSong.title}',
    );

    // Ponemos temporalmente el volumen correcto de la nueva canción.
    // Si estaba reproduciendo, hacemos el cambio manteniendo play.
    await _player.setVolume(0.0);

    await _player.seek(Duration.zero, index: index);

    _updateTrackGain(targetSong);

    final newVolume = _getEffectiveVolumeForSong(targetSong);

    await _player.setVolume(newVolume);

    _emitCurrentState();

    final result = await _waitForDuration();

    // playAtIndex se utiliza como acción explícita de reproducción.
    // Por tanto, siempre debe terminar reproduciendo.
    //
    // Esto es especialmente importante para el botón Siguiente.
    if (wasPlaying || !wasPlaying) {
      await _player.play();
    }

    if (_crossfadeService.enabled) {
      _startCrossfadeMonitor();
    }

    return result;
  }

  Future<Duration?> playSingleSong(Song song) {
    return playQueue([song], initialIndex: 0);
  }

  // ===========================================================================
  // SINCRONIZAR COLA
  // ===========================================================================

  Future<void> syncQueue(
    List<Song> songs, {
    required int currentIndex,
    bool keepPosition = true,
    bool resumePlayback = true,
  }) async {
    if (songs.isEmpty) {
      await clear();
      return;
    }

    final wasPlaying = playing;

    final oldPosition = keepPosition ? position : Duration.zero;

    final safeIndex = currentIndex.clamp(0, songs.length - 1).toInt();

    await setQueue(songs, initialIndex: safeIndex);

    final currentDuration = duration;

    if (keepPosition &&
        oldPosition > Duration.zero &&
        currentDuration != null &&
        oldPosition < currentDuration) {
      await seek(oldPosition, index: safeIndex);
    }

    if (resumePlayback && wasPlaying) {
      await play();
    }
  }

  // ===========================================================================
  // AGREGAR
  // ===========================================================================

  Future<void> addToQueue(Song song) async {
    if (_songs.any((item) => item.id == song.id)) {
      return;
    }

    if (_playlist == null) {
      await setQueue([song], initialIndex: 0);

      return;
    }

    final source = await _createAudioSource(song);

    await _playlist!.add(source);

    _songs.add(song);

    _emitCurrentState();
  }

  Future<void> addSongsToQueue(List<Song> songs) async {
    if (songs.isEmpty) {
      return;
    }

    final newSongs = songs
        .where((song) => !_songs.any((existing) => existing.id == song.id))
        .toList();

    if (newSongs.isEmpty) {
      return;
    }

    if (_playlist == null) {
      await setQueue(newSongs, initialIndex: 0);

      return;
    }

    final sources = <AudioSource>[];

    for (final song in newSongs) {
      sources.add(await _createAudioSource(song));
    }

    await _playlist!.addAll(sources);

    _songs.addAll(newSongs);

    _emitCurrentState();
  }

  // ===========================================================================
  // ELIMINAR
  // ===========================================================================

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _songs.length) {
      return;
    }

    if (_playlist == null) {
      return;
    }

    final currentIndex = _player.currentIndex;

    // No eliminamos directamente la canción actual.
    if (index == currentIndex) {
      return;
    }

    await _playlist!.removeAt(index);

    _songs.removeAt(index);

    _emitCurrentState();
  }

  // ===========================================================================
  // REORDENAR
  // ===========================================================================

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _songs.length ||
        newIndex < 0 ||
        newIndex >= _songs.length ||
        oldIndex == newIndex ||
        _playlist == null) {
      return;
    }

    await _playlist!.move(oldIndex, newIndex);

    final song = _songs.removeAt(oldIndex);

    _songs.insert(newIndex, song);

    _emitCurrentState();
  }

  // ===========================================================================
  // CANCELAR TRANSICIÓN
  // ===========================================================================

  void _cancelTransition() {
    _crossfadeGeneration++;

    _crossfadeInProgress = false;

    _crossfadeCheckInProgress = false;

    _stopCrossfadeMonitor();
  }

  // ===========================================================================
  // SIGUIENTE
  // ===========================================================================

  Future<bool> playNext() async {
    if (_songs.isEmpty) {
      return false;
    }

    final currentIndex = _player.currentIndex ?? 0;

    // Si el crossfade estaba ejecutándose, lo cancelamos.
    _cancelTransition();

    int? nextIndex;

    if (_repeatMode == 1) {
      // Repetir canción actual.
      nextIndex = currentIndex;
    } else if (_shuffleEnabled) {
      if (_songs.length <= 1) {
        return false;
      }

      nextIndex = _getRandomIndexExcluding(currentIndex);
    } else {
      final candidate = currentIndex + 1;

      if (candidate < _songs.length) {
        nextIndex = candidate;
      } else if (_repeatMode == 2) {
        nextIndex = 0;
      }
    }

    if (nextIndex == null) {
      return false;
    }

    debugPrint(
      '[SONARA PLAYER] '
      'SIGUIENTE: $currentIndex -> $nextIndex',
    );

    await playAtIndex(nextIndex);

    return true;
  }

  // ===========================================================================
  // ANTERIOR
  // ===========================================================================

  Future<bool> playPrevious() async {
    if (_songs.isEmpty) {
      return false;
    }

    final currentIndex = _player.currentIndex ?? 0;

    _cancelTransition();

    if (position.inSeconds > 3) {
      await seek(Duration.zero);
      await play();
      return true;
    }

    int? previousIndex;

    if (_shuffleEnabled) {
      if (_songs.length <= 1) {
        return false;
      }

      previousIndex = _getRandomIndexExcluding(currentIndex);
    } else {
      final candidate = currentIndex - 1;

      if (candidate >= 0) {
        previousIndex = candidate;
      } else if (_repeatMode == 2) {
        previousIndex = _songs.length - 1;
      }
    }

    if (previousIndex == null) {
      return false;
    }

    debugPrint(
      '[SONARA PLAYER] '
      'ANTERIOR: $currentIndex -> $previousIndex',
    );

    await playAtIndex(previousIndex);

    return true;
  }

  int _getRandomIndexExcluding(int excludedIndex) {
    if (_songs.length <= 1) {
      return 0;
    }

    var index = _random.nextInt(_songs.length - 1);

    if (index >= excludedIndex) {
      index++;
    }

    return index;
  }

  // ===========================================================================
  // CONTROLES
  // ===========================================================================

  Future<void> play() async {
    if (_songs.isEmpty) {
      return;
    }

    if (_player.currentIndex == null) {
      await playAtIndex(0);
      return;
    }

    final index = _player.currentIndex!;

    if (index >= 0 && index < _songs.length) {
      _updateTrackGain(_songs[index]);

      await _applyEffectiveVolume();
    }

    await _player.play();

    if (_crossfadeService.enabled) {
      _startCrossfadeMonitor();
    }
  }

  Future<void> pause() async {
    _stopCrossfadeMonitor();

    _crossfadeGeneration++;

    _crossfadeInProgress = false;

    _crossfadeCheckInProgress = false;

    await _player.pause();
  }

  Future<void> resume() {
    return play();
  }

  Future<void> stop() async {
    _stopCrossfadeMonitor();

    _crossfadeGeneration++;

    _crossfadeInProgress = false;

    _crossfadeCheckInProgress = false;

    await _player.stop();
  }

  // ===========================================================================
  // SEEK
  // ===========================================================================

  Future<void> seek(Duration position, {int? index}) async {
    _cancelTransition();

    await _player.seek(position, index: index);

    if (_player.playing && _crossfadeService.enabled) {
      _startCrossfadeMonitor();
    }
  }

  // ===========================================================================
  // VOLUMEN
  // ===========================================================================

  Future<void> setVolume(double volume) async {
    _baseVolume = volume.clamp(0.0, 1.0).toDouble();

    if (_crossfadeInProgress) {
      return;
    }

    await _applyEffectiveVolume();
  }

  // ===========================================================================
  // VELOCIDAD
  // ===========================================================================

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  // ===========================================================================
  // MODOS
  // ===========================================================================

  void setPlaybackModes({
    required bool shuffleEnabled,
    required int repeatMode,
  }) {
    _shuffleEnabled = shuffleEnabled;

    _repeatMode = repeatMode;
  }

  // ===========================================================================
  // DURACIÓN
  // ===========================================================================

  Future<Duration?> _waitForDuration() async {
    final currentDuration = _player.duration;

    if (currentDuration != null && currentDuration > Duration.zero) {
      return currentDuration;
    }

    try {
      return await _player.durationStream
          .where((duration) => duration != null && duration > Duration.zero)
          .first
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      return _player.duration;
    }
  }

  // ===========================================================================
  // MEDIA ITEM
  // ===========================================================================

  Future<MediaItem> _createMediaItem(Song song) async {
    Uri? artworkUri;

    final coverPath = song.coverPath;

    if (coverPath != null && coverPath.isNotEmpty) {
      final coverFile = File(coverPath);

      if (await coverFile.exists()) {
        artworkUri = Uri.file(coverPath);
      }
    }

    return MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      artUri: artworkUri,
      duration: song.duration,
    );
  }

  Future<List<MediaItem>> getMediaQueue() async {
    final result = <MediaItem>[];

    for (final song in _songs) {
      result.add(await _createMediaItem(song));
    }

    return result;
  }

  // ===========================================================================
  // ESTADO
  // ===========================================================================

  void _emitCurrentState() {
    final index = _player.currentIndex;

    if (!_currentIndexController.isClosed) {
      _currentIndexController.add(index);
    }

    if (!_durationController.isClosed) {
      _durationController.add(_player.duration);
    }

    if (!_positionController.isClosed) {
      _positionController.add(_player.position);
    }

    if (!_playerStateController.isClosed) {
      _playerStateController.add(_player.playerState);
    }
  }

  // ===========================================================================
  // LIMPIAR
  // ===========================================================================

  Future<void> clear() async {
    _cancelTransition();

    await _player.stop();

    _songs.clear();

    _playlist = null;

    _currentTrackGainLinear = 1.0;

    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: []),
        preload: false,
      );
    } catch (_) {}

    await _applyEffectiveVolume();

    if (!_currentIndexController.isClosed) {
      _currentIndexController.add(null);
    }

    if (!_durationController.isClosed) {
      _durationController.add(Duration.zero);
    }

    if (!_positionController.isClosed) {
      _positionController.add(Duration.zero);
    }
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    _stopCrossfadeMonitor();

    _crossfadeGeneration++;

    _crossfadeService.secondsNotifier.removeListener(
      _handleCrossfadeSettingChanged,
    );

    await _playerStateSubscription?.cancel();

    await _positionSubscription?.cancel();

    await _durationSubscription?.cancel();

    await _currentIndexSubscription?.cancel();

    await _player.dispose();

    await _playerStateController.close();

    await _currentIndexController.close();

    await _positionController.close();

    await _durationController.close();
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/crossfade_service.dart';
import '../../../library/domain/models/song.dart';

class AudioPlayerService {
  AudioPlayerService._internal() {
    _loudnessEnhancer = AndroidLoudnessEnhancer();

    _player = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [_loudnessEnhancer]),
    );

    _listenToPlayer();

    _crossfadeService.secondsNotifier.addListener(
      _handleCrossfadeSettingChanged,
    );

    unawaited(_loadReplayGainPreamp());

    if (Platform.isAndroid) {
      unawaited(_initializeAndroidLoudnessEnhancer());
    }
  }

  static final AudioPlayerService instance = AudioPlayerService._internal();

  factory AudioPlayerService() => instance;

  // PLATFORM

  bool get _isLinux => Platform.isLinux;

  // PLAYER

  late final AndroidLoudnessEnhancer _loudnessEnhancer;
  late final AudioPlayer _player;

  final List<Song> _songs = [];

  ConcatenatingAudioSource? _playlist;

  int? _linuxCurrentIndex;
  bool _linuxLoading = false;

  int _linuxLoadGeneration = 0;

  // STREAMS

  final StreamController<PlayerState> _playerStateController =
      StreamController<PlayerState>.broadcast();

  final StreamController<int?> _currentIndexController =
      StreamController<int?>.broadcast();

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();

  // SUSCRIPCIONES

  StreamSubscription<PlayerState>? _playerStateSubscription;

  StreamSubscription<Duration>? _positionSubscription;

  StreamSubscription<Duration?>? _durationSubscription;

  StreamSubscription<int?>? _currentIndexSubscription;

  // REPLAYGAIN

  double _baseVolume = 1.0;

  double _currentTrackGainLinear = 1.0;

  // ReplayGain puede producir valores superiores a +20 dB
  // o inferiores a -20 dB.
  //
  // Estos límites protegen contra valores absurdos/corruptos
  // pero permiten valores como +25 dB.
  static const double _minimumGainDb = -60.0;
  static const double _maximumGainDb = 60.0;

  // Preamp configurable por el usuario.
  static const double _minimumPreampDb = -24.0;
  static const double _maximumPreampDb = 24.0;

  static const String _replayGainPreampPreferenceKey =
      'sonara_replaygain_preamp_db';

  double _replayGainPreampDb = 0.0;

  final ValueNotifier<double> replayGainPreampNotifier = ValueNotifier<double>(
    0.0,
  );

  bool _isApplyingVolume = false;

  bool _volumeUpdatePending = false;

  bool _androidLoudnessEnhancerReady = false;

  // CROSSFADE

  final CrossfadeService _crossfadeService = CrossfadeService.instance;

  Timer? _crossfadeMonitor;

  bool _crossfadeInProgress = false;

  int _crossfadeGeneration = 0;

  bool _crossfadeCheckInProgress = false;

  // ESTADO

  bool _isDisposed = false;

  // MODOS

  bool _shuffleEnabled = false;

  int _repeatMode = 0;

  // 0 = off
  // 1 = one
  // 2 = all

  final math.Random _random = math.Random();

  // STREAMS PÚBLICOS

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

  // GETTERS

  bool get playing => _player.playing;

  Duration get position => _player.position;

  Duration? get duration => _player.duration;

  int? get currentIndex => _isLinux ? _linuxCurrentIndex : _player.currentIndex;

  bool get hasQueue => _songs.isNotEmpty;

  List<Song> get queue => List.unmodifiable(_songs);

  double get baseVolume => _baseVolume;

  double get replayGainPreampDb => _replayGainPreampDb;

  int get crossfadeSeconds => _crossfadeService.seconds;

  bool get isCrossfading => _crossfadeInProgress;

  // ANDROID LOUDNESS ENHANCER

  Future<void> _initializeAndroidLoudnessEnhancer() async {
    if (!Platform.isAndroid || _isDisposed) {
      return;
    }

    try {
      await _loudnessEnhancer.setEnabled(true);

      _androidLoudnessEnhancerReady = true;

      debugPrint(
        '[SONARA REPLAYGAIN] '
        'Android LoudnessEnhancer habilitado.',
      );

      await _applyAndroidTrackGain();
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA REPLAYGAIN] '
        'No se pudo habilitar Android LoudnessEnhancer: $error',
      );

      debugPrintStack(stackTrace: stackTrace);

      _androidLoudnessEnhancerReady = false;
    }
  }

  Future<void> _applyAndroidTrackGain() async {
    if (!Platform.isAndroid || !_androidLoudnessEnhancerReady || _isDisposed) {
      return;
    }

    Song? currentSong;

    final index = currentIndex;

    if (index != null && index >= 0 && index < _songs.length) {
      currentSong = _songs[index];
    }

    final totalGainDb = currentSong == null
        ? 0.0
        : _getTotalGainDb(currentSong);

    try {
      await _loudnessEnhancer.setTargetGain(totalGainDb);

      debugPrint(
        '[SONARA REPLAYGAIN ANDROID] '
        'Ganancia aplicada: '
        '${totalGainDb.toStringAsFixed(2)} dB',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA REPLAYGAIN ANDROID] '
        'No se pudo aplicar la ganancia: $error',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // REPLAYGAIN PREAMP

  Future<void> _loadReplayGainPreamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final savedValue = prefs.getDouble(_replayGainPreampPreferenceKey);

      if (savedValue == null) {
        return;
      }

      final safeValue = savedValue
          .clamp(_minimumPreampDb, _maximumPreampDb)
          .toDouble();

      _replayGainPreampDb = safeValue;
      replayGainPreampNotifier.value = safeValue;

      if (!_isDisposed) {
        unawaited(_applyEffectiveVolume());
      }
    } catch (error) {
      debugPrint(
        '[SONARA REPLAYGAIN] '
        'No se pudo cargar el Preamp: $error',
      );
    }
  }

  Future<void> setReplayGainPreampDb(
    double value, {
    bool persist = true,
  }) async {
    if (_isDisposed) {
      return;
    }

    final safeValue = value
        .clamp(_minimumPreampDb, _maximumPreampDb)
        .toDouble();

    _replayGainPreampDb = safeValue;

    replayGainPreampNotifier.value = safeValue;

    // El nuevo Preamp se aplica inmediatamente.
    await _applyEffectiveVolume();

    if (!persist) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setDouble(_replayGainPreampPreferenceKey, safeValue);
    } catch (error) {
      debugPrint(
        '[SONARA REPLAYGAIN] '
        'No se pudo guardar el Preamp: $error',
      );
    }
  }

  // LISTENERS

  void _listenToPlayer() {
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (_isDisposed) {
        return;
      }

      if (!_playerStateController.isClosed) {
        _playerStateController.add(state);
      }

      if (_isLinux &&
          state.processingState == ProcessingState.completed &&
          !_crossfadeInProgress) {
        unawaited(_handleLinuxTrackCompleted());
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

      if (_isLinux) {
        return;
      }

      if (!_currentIndexController.isClosed) {
        _currentIndexController.add(index);
      }

      if (index != null && index >= 0 && index < _songs.length) {
        _updateTrackGain(_songs[index]);

        if (!_crossfadeInProgress) {
          unawaited(_applyEffectiveVolume());
        }
      }
    });
  }

  Future<void> _handleLinuxTrackCompleted() async {
    if (_isDisposed || !_isLinux || _songs.isEmpty || _linuxLoading) {
      return;
    }

    final index = _linuxCurrentIndex ?? 0;

    if (_repeatMode == 1) {
      await _loadLinuxSong(index, position: Duration.zero, autoplay: true);

      return;
    }

    if (_shuffleEnabled && _songs.length > 1) {
      final nextIndex = _getRandomIndexExcluding(index);

      await _loadLinuxSong(nextIndex, position: Duration.zero, autoplay: true);

      return;
    }

    final nextIndex = index + 1;

    if (nextIndex < _songs.length) {
      await _loadLinuxSong(nextIndex, position: Duration.zero, autoplay: true);

      return;
    }

    if (_repeatMode == 2) {
      await _loadLinuxSong(0, position: Duration.zero, autoplay: true);
    }
  }

  // AUDIO SOURCE

  Future<AudioSource> _createAudioSource(Song song) async {
    final file = File(song.filePath);

    if (!await file.exists()) {
      throw FileSystemException('El archivo no existe', song.filePath);
    }

    final mediaItem = await _createMediaItem(song);

    return AudioSource.uri(Uri.file(song.filePath), tag: mediaItem);
  }

  // LINUX

  Future<Duration?> _loadLinuxSong(
    int index, {
    Duration position = Duration.zero,
    bool autoplay = false,
  }) async {
    if (!Platform.isLinux ||
        index < 0 ||
        index >= _songs.length ||
        _isDisposed) {
      return null;
    }

    final generation = ++_linuxLoadGeneration;
    final song = _songs[index];

    if (_linuxLoading) {
      debugPrint(
        '[SONARA LINUX] '
        'Nueva carga solicitada mientras otra estaba en progreso: '
        '${song.title}',
      );
    }

    _linuxLoading = true;

    try {
      debugPrint(
        '[SONARA LINUX] '
        'Cargando índice $index: ${song.title}',
      );

      final source = await _createAudioSource(song);

      if (generation != _linuxLoadGeneration || _isDisposed) {
        return null;
      }

      _linuxCurrentIndex = index;

      await _player.setAudioSource(
        source,
        initialPosition: position,
        preload: true,
      );

      if (generation != _linuxLoadGeneration || _isDisposed) {
        return null;
      }

      _updateTrackGain(song);

      await _applyEffectiveVolume();

      if (generation != _linuxLoadGeneration || _isDisposed) {
        return null;
      }

      _emitCurrentState();

      final result = await _waitForDuration();

      if (generation != _linuxLoadGeneration || _isDisposed) {
        return result;
      }

      if (autoplay) {
        await _player.play();

        if (_crossfadeService.enabled) {
          _startCrossfadeMonitor();
        }
      }

      return result;
    } on PlayerInterruptedException catch (error) {
      debugPrint(
        '[SONARA LINUX] '
        'Carga interrumpida de ${song.title}: $error',
      );

      return null;
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA LINUX ERROR] '
        'No se pudo cargar ${song.title}: $error',
      );

      debugPrintStack(stackTrace: stackTrace);

      return null;
    } finally {
      if (generation == _linuxLoadGeneration) {
        _linuxLoading = false;
      }
    }
  }

  // REPLAYGAIN

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
      'ReplayGain: ${safeGainDb.toStringAsFixed(2)} dB | '
      'Preamp: ${_replayGainPreampDb.toStringAsFixed(2)} dB | '
      'Total: '
      '${(safeGainDb + _replayGainPreampDb).toStringAsFixed(2)} dB | '
      'Factor ReplayGain: '
      '${_currentTrackGainLinear.toStringAsFixed(3)}',
    );
  }

  double _getTrackGainDb(Song song) {
    final gainDb = song.volumeGain;

    if (gainDb == null || !gainDb.isFinite) {
      return 0.0;
    }

    return gainDb.clamp(_minimumGainDb, _maximumGainDb).toDouble();
  }

  double _getTotalGainDb(Song song) {
    final replayGainDb = _getTrackGainDb(song);

    return replayGainDb + _replayGainPreampDb;
  }

  double _getTrackGainLinear(Song song) {
    return _dbToLinear(_getTrackGainDb(song));
  }

  double _dbToLinear(double db) {
    return math.pow(10, db / 20).toDouble();
  }

  double _getEffectiveVolumeForSong(Song song) {
    final replayGainDb = _getTrackGainDb(song);
    final totalGainDb = _getTotalGainDb(song);

    /*
     * ANDROID
     *
     * ReplayGain + Preamp NO se convierte a volumen 0.0 - 1.0.
     *
     * La ganancia se aplica mediante AndroidLoudnessEnhancer.
     * De esta forma:
     *
     * +25 dB + +5 dB = +30 dB
     *
     * y no:
     *
     * 31.62 * baseVolume -> clamp(1.0)
     *
     * En Android setVolume() queda únicamente para el volumen
     * normal del reproductor.
     */
    if (Platform.isAndroid) {
      debugPrint(
        '[SONARA REPLAYGAIN ANDROID] '
        '${song.title} | '
        'ReplayGain: ${replayGainDb.toStringAsFixed(2)} dB | '
        'Preamp: ${_replayGainPreampDb.toStringAsFixed(2)} dB | '
        'Total: ${totalGainDb.toStringAsFixed(2)} dB | '
        'Base: ${_baseVolume.toStringAsFixed(3)}',
      );

      return _baseVolume;
    }

    /*
     * LINUX / OTRAS PLATAFORMAS
     *
     * Se conserva el comportamiento anterior.
     *
     * Aquí just_audio solamente acepta el volumen normal 0.0 - 1.0,
     * por lo que una ganancia positiva suficientemente grande termina
     * limitada a 1.0.
     */
    final totalGainLinear = _dbToLinear(totalGainDb);

    final effectiveVolume = _baseVolume * totalGainLinear;

    debugPrint(
      '[SONARA REPLAYGAIN] '
      '${song.title} | '
      'ReplayGain: ${replayGainDb.toStringAsFixed(2)} dB | '
      'Preamp: ${_replayGainPreampDb.toStringAsFixed(2)} dB | '
      'Total: ${totalGainDb.toStringAsFixed(2)} dB | '
      'Linear: ${totalGainLinear.toStringAsFixed(4)} | '
      'Base: ${_baseVolume.toStringAsFixed(3)} | '
      'Volumen: ${effectiveVolume.toStringAsFixed(4)}',
    );

    return effectiveVolume.clamp(0.0, 1.0).toDouble();
  }

  // VOLUMEN

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

        final index = currentIndex;

        if (index != null && index >= 0 && index < _songs.length) {
          currentSong = _songs[index];
        }

        /*
         * Android:
         *
         * 1. AndroidLoudnessEnhancer recibe ReplayGain + Preamp.
         * 2. setVolume recibe solamente el volumen base.
         *
         * Linux:
         *
         * setVolume recibe ReplayGain + Preamp convertido a lineal
         * y limitado a 1.0.
         */
        if (Platform.isAndroid) {
          await _applyAndroidTrackGain();
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

      if (Platform.isAndroid && _androidLoudnessEnhancerReady) {
        try {
          await _loudnessEnhancer.setTargetGain(0.0);
        } catch (_) {}
      }

      await _applyEffectiveVolume();

      return;
    }

    _updateTrackGain(_songs[index]);

    await _applyEffectiveVolume();
  }

  // CROSSFADE

  void _handleCrossfadeSettingChanged() {
    if (_isDisposed) {
      return;
    }

    if (!_crossfadeService.enabled) {
      _stopCrossfadeMonitor();

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

  Future<void> _checkCrossfade() async {
    if (_isDisposed ||
        !_crossfadeService.enabled ||
        !_player.playing ||
        _crossfadeInProgress ||
        _crossfadeCheckInProgress) {
      return;
    }

    final currentIndex = this.currentIndex;

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

  int? _getCrossfadeNextIndex() {
    final index = currentIndex;

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
      return _getRandomIndexExcluding(index);
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

  Future<void> _performCrossfade() async {
    if (_crossfadeInProgress || _isDisposed || !_crossfadeService.enabled) {
      return;
    }

    final nextIndex = _getCrossfadeNextIndex();

    if (nextIndex == null) {
      return;
    }

    final oldIndex = currentIndex;

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

      /*
       * En Android estas funciones devuelven únicamente _baseVolume.
       *
       * ReplayGain + Preamp permanecen en LoudnessEnhancer durante
       * toda la transición.
       */
      final oldVolume = _getEffectiveVolumeForSong(oldSong);
      final newVolume = _getEffectiveVolumeForSong(nextSong);

      debugPrint(
        '[SONARA CROSSFADE] '
        '${oldSong.title} -> ${nextSong.title} '
        '(${duration.inSeconds}s)',
      );

      // FADE OUT

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

      await _player.setVolume(0.0);

      // CAMBIAR CANCIÓN

      if (_isLinux) {
        await _loadLinuxSong(
          nextIndex,
          position: Duration.zero,
          autoplay: false,
        );
      } else {
        await _player.seek(Duration.zero, index: nextIndex);
      }

      if (generation != _crossfadeGeneration || _isDisposed) {
        return;
      }

      // Asegurar ReplayGain + Preamp de la nueva canción.

      if (Platform.isAndroid) {
        await _applyAndroidTrackGain();
      }

      // REPRODUCIR

      await _player.play();

      // FADE IN

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

      try {
        final index = currentIndex;

        if (index != null && index >= 0 && index < _songs.length) {
          if (Platform.isAndroid) {
            await _applyAndroidTrackGain();
          }

          await _player.setVolume(_getEffectiveVolumeForSong(_songs[index]));
        }

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

  // COLA

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

    if (_isLinux) {
      return _loadLinuxSong(
        safeIndex,
        position: Duration.zero,
        autoplay: false,
      );
    }

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

    return _waitForDuration();
  }

  Future<Duration?> playQueue(
    List<Song> songs, {
    required int initialIndex,
  }) async {
    final duration = await setQueue(songs, initialIndex: initialIndex);

    await play();

    return duration;
  }

  Future<Duration?> playAtIndex(int index) async {
    if (_songs.isEmpty || index < 0 || index >= _songs.length) {
      return null;
    }

    _cancelTransition();

    final targetSong = _songs[index];

    debugPrint(
      '[SONARA PLAYER] '
      'Cambiando a índice $index: ${targetSong.title}',
    );

    if (_isLinux) {
      return _loadLinuxSong(index, position: Duration.zero, autoplay: true);
    }

    await _player.setVolume(0.0);

    await _player.seek(Duration.zero, index: index);

    _updateTrackGain(targetSong);

    if (Platform.isAndroid) {
      await _applyAndroidTrackGain();
    }

    final newVolume = _getEffectiveVolumeForSong(targetSong);

    await _player.setVolume(newVolume);

    _emitCurrentState();

    final result = await _waitForDuration();

    await _player.play();

    if (_crossfadeService.enabled) {
      _startCrossfadeMonitor();
    }

    return result;
  }

  Future<Duration?> playSingleSong(Song song) {
    return playQueue([song], initialIndex: 0);
  }

  // SINCRONIZAR COLA

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

  // AGREGAR

  Future<void> addToQueue(Song song) async {
    if (_songs.any((item) => item.id == song.id)) {
      return;
    }

    if (_isLinux) {
      if (_songs.isEmpty) {
        await setQueue([song], initialIndex: 0);

        return;
      }

      _songs.add(song);

      _emitCurrentState();

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

    if (_isLinux) {
      if (_songs.isEmpty) {
        await setQueue(newSongs, initialIndex: 0);

        return;
      }

      _songs.addAll(newSongs);

      _emitCurrentState();

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

  // ELIMINAR

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _songs.length) {
      return;
    }

    final current = currentIndex;

    if (index == current) {
      return;
    }

    if (_isLinux) {
      _songs.removeAt(index);

      if (_linuxCurrentIndex != null && index < _linuxCurrentIndex!) {
        _linuxCurrentIndex = _linuxCurrentIndex! - 1;
      }

      _emitCurrentState();

      return;
    }

    if (_playlist == null) {
      return;
    }

    await _playlist!.removeAt(index);

    _songs.removeAt(index);

    _emitCurrentState();
  }

  // REORDENAR

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _songs.length ||
        newIndex < 0 ||
        newIndex >= _songs.length ||
        oldIndex == newIndex) {
      return;
    }

    final current = currentIndex;

    if (_isLinux) {
      final song = _songs.removeAt(oldIndex);

      _songs.insert(newIndex, song);

      if (current != null) {
        if (current == oldIndex) {
          _linuxCurrentIndex = newIndex;
        } else if (oldIndex < current && newIndex >= current) {
          _linuxCurrentIndex = current - 1;
        } else if (oldIndex > current && newIndex <= current) {
          _linuxCurrentIndex = current + 1;
        }
      }

      _emitCurrentState();

      return;
    }

    if (_playlist == null) {
      return;
    }

    await _playlist!.move(oldIndex, newIndex);

    final song = _songs.removeAt(oldIndex);

    _songs.insert(newIndex, song);

    _emitCurrentState();
  }

  // CANCELAR TRANSICIÓN

  void _cancelTransition() {
    _crossfadeGeneration++;

    _crossfadeInProgress = false;

    _crossfadeCheckInProgress = false;

    if (_isLinux) {
      _linuxLoadGeneration++;
    }

    _stopCrossfadeMonitor();
  }

  // SIGUIENTE

  Future<bool> playNext() async {
    if (_songs.isEmpty) {
      return false;
    }

    final current = currentIndex ?? 0;

    _cancelTransition();

    int? nextIndex;

    if (_repeatMode == 1) {
      nextIndex = current;
    } else if (_shuffleEnabled) {
      if (_songs.length <= 1) {
        return false;
      }

      nextIndex = _getRandomIndexExcluding(current);
    } else {
      final candidate = current + 1;

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
      'SIGUIENTE: $current -> $nextIndex',
    );

    await playAtIndex(nextIndex);

    return true;
  }

  // ANTERIOR

  Future<bool> playPrevious() async {
    if (_songs.isEmpty) {
      return false;
    }

    final current = currentIndex ?? 0;

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

      previousIndex = _getRandomIndexExcluding(current);
    } else {
      final candidate = current - 1;

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
      'ANTERIOR: $current -> $previousIndex',
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

  // CONTROLES

  Future<void> play() async {
    if (_songs.isEmpty) {
      return;
    }

    if (currentIndex == null) {
      await playAtIndex(0);

      return;
    }

    final index = currentIndex!;

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

  // SEEK

  Future<void> seek(Duration position, {int? index}) async {
    _cancelTransition();

    if (_isLinux && index != null) {
      if (index < 0 || index >= _songs.length) {
        return;
      }

      await _loadLinuxSong(
        index,
        position: position,
        autoplay: _player.playing,
      );

      return;
    }

    await _player.seek(position, index: index);

    if (index != null &&
        index >= 0 &&
        index < _songs.length &&
        Platform.isAndroid) {
      await _applyAndroidTrackGain();
    }

    if (_player.playing && _crossfadeService.enabled) {
      _startCrossfadeMonitor();
    }
  }

  // VOLUMEN

  Future<void> setVolume(double volume) async {
    _baseVolume = volume.clamp(0.0, 1.0).toDouble();

    if (_crossfadeInProgress) {
      return;
    }

    await _applyEffectiveVolume();
  }

  // VELOCIDAD

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  // MODOS

  void setPlaybackModes({
    required bool shuffleEnabled,
    required int repeatMode,
  }) {
    _shuffleEnabled = shuffleEnabled;

    _repeatMode = repeatMode;
  }

  // DURACIÓN

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

  // MEDIA ITEM

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

  // ESTADO

  void _emitCurrentState() {
    final index = currentIndex;

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

  // LIMPIAR

  Future<void> clear() async {
    _cancelTransition();

    await _player.stop();

    _songs.clear();

    _playlist = null;

    _linuxCurrentIndex = null;

    _currentTrackGainLinear = 1.0;

    if (Platform.isAndroid && _androidLoudnessEnhancerReady) {
      try {
        await _loudnessEnhancer.setTargetGain(0.0);
      } catch (_) {}
    }

    if (!_isLinux) {
      try {
        await _player.setAudioSource(
          ConcatenatingAudioSource(children: []),
          preload: false,
        );
      } catch (_) {}
    }

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

  // DISPOSE

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

    if (Platform.isAndroid) {
      try {
        await _loudnessEnhancer.setEnabled(false);
      } catch (_) {}
    }

    replayGainPreampNotifier.dispose();

    await _player.dispose();

    await _playerStateController.close();

    await _currentIndexController.close();

    await _positionController.close();

    await _durationController.close();
  }
}

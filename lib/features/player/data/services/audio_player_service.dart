import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/crossfade_service.dart';
import '../../../../app/playback_fade_layer.dart';
import '../../../library/domain/models/song.dart';

/// Un "candado de silencio". Cada operación toma el suyo y lo suelta una sola
/// vez. El volumen es 0 mientras exista al menos un candado.
class _MuteHold {
  bool released = false;
}

class AudioPlayerService {
  AudioPlayerService._internal() {
    _loudnessEnhancer = AndroidLoudnessEnhancer();

    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: <AndroidAudioEffect>[_loudnessEnhancer],
      ),
    );

    // ============================================================
    // ANDROID 8D
    // ============================================================

    if (Platform.isAndroid) {
      _androidAudioSessionSubscription = _player.androidAudioSessionIdStream
          .listen(_handleAndroidAudioSession);

      unawaited(_load8DPreference());
    }

    // La capa de fade vive fuera de este servicio. Solo le damos una foto del
    // reproductor y ella nos devuelve un multiplicador.
    _fade = PlaybackFadeLayer(
      settings: _crossfadeService,
      sampler: _sampleForFade,
      onGainChanged: () => unawaited(_syncVolume()),
    );

    _listenToPlayer();

    unawaited(_loadReplayGainPreamp());

    if (Platform.isAndroid) {
      unawaited(_initializeAndroidLoudnessEnhancer());
    }
  }

  static final AudioPlayerService instance = AudioPlayerService._internal();

  factory AudioPlayerService() => instance;

  // ============================================================
  // PLAYER
  // ============================================================

  late final AudioPlayer _player;

  late final AndroidLoudnessEnhancer _loudnessEnhancer;

  late final PlaybackFadeLayer _fade;

  final CrossfadeService _crossfadeService = CrossfadeService.instance;

  final List<Song> _songs = <Song>[];

  ConcatenatingAudioSource? _playlist;

  int? _linuxCurrentIndex;

  int _linuxLoadGeneration = 0;

  // ============================================================
  // ANDROID 8D
  // ============================================================

  static const MethodChannel _nativeMusicChannel = MethodChannel(
    'com.sonara/music',
  );

  static const String _8DPreferenceKey = 'sonara_8d_enabled';

  bool _8DEnabled = false;

  StreamSubscription<int?>? _androidAudioSessionSubscription;

  bool get is8DEnabled => _8DEnabled;

  /// La UI/controlador escuchan esto para reflejar el estado real del 8D.
  final ValueNotifier<bool> eightDEnabledNotifier = ValueNotifier<bool>(false);

  void _setEightDState(bool value) {
    _8DEnabled = value;

    if (!_isDisposed && eightDEnabledNotifier.value != value) {
      eightDEnabledNotifier.value = value;
    }
  }

  // ============================================================
  // OPERACIONES
  // ============================================================

  int _operationGeneration = 0;

  int _nextOperationGeneration() {
    return ++_operationGeneration;
  }

  bool _isOperationValid(int generation) {
    return !_isDisposed && generation == _operationGeneration;
  }

  // ============================================================
  // STREAMS
  // ============================================================

  final StreamController<PlayerState> _playerStateController =
      StreamController<PlayerState>.broadcast();

  final StreamController<int?> _currentIndexController =
      StreamController<int?>.broadcast();

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();

  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();

  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  Stream<int?> get currentIndexStream => _currentIndexController.stream;

  Stream<Duration> get positionStream => _positionController.stream;

  Stream<Duration?> get durationStream => _durationController.stream;

  Stream<bool> get playingStream {
    return Stream<bool>.multi((controller) {
      if (_isDisposed) {
        controller.close();
        return;
      }

      controller.add(playing);

      final subscription = playerStateStream.listen((state) {
        if (!_isDisposed) {
          controller.add(state.playing);
        }
      });

      controller.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  // ============================================================
  // GETTERS
  // ============================================================

  bool get playing => !_isDisposed && _player.playing;

  Duration get position => _isDisposed ? Duration.zero : _player.position;

  Duration? get duration => _isDisposed ? null : _player.duration;

  int? get currentIndex {
    if (_isDisposed) {
      return null;
    }

    if (_isLinux) {
      return _linuxCurrentIndex;
    }

    final index = _player.currentIndex;

    if (index == null) {
      return null;
    }

    if (index < 0 || index >= _songs.length) {
      return null;
    }

    return index;
  }

  bool get hasQueue => _songs.isNotEmpty;

  List<Song> get queue => List.unmodifiable(_songs);

  double get baseVolume => _baseVolume;

  double get replayGainPreampDb => _replayGainPreampDb;

  int get crossfadeSeconds => _crossfadeService.seconds;

  /// Solo informativo. El fade YA NO cambia cómo se reproducen o se completan
  /// las canciones, así que el PlayerController no debe usarlo para decidir
  /// nada sobre la lógica de reproducción.
  bool get isCrossfading => _crossfadeService.enabled;

  // ============================================================
  // PLATFORM
  // ============================================================

  bool get _isLinux => Platform.isLinux;

  // ============================================================
  // REPLAYGAIN
  // ============================================================

  /*
   * _baseVolume es el volumen solicitado por el usuario.
   *
   * Permitimos hasta 2.0.
   *
   * 1.0 = 100 %
   * 1.5 = 150 %
   * 2.0 = 200 %
   */
  double _baseVolume = 1.0;

  static const double _maximumPlayerVolume = 2.0;

  static const double _minimumGainDb = -60.0;

  static const double _maximumGainDb = 60.0;

  static const double _minimumPreampDb = -24.0;

  static const double _maximumPreampDb = 24.0;

  static const String _replayGainPreampPreferenceKey =
      'sonara_replaygain_preamp_db';

  double _replayGainPreampDb = 0.0;

  final ValueNotifier<double> replayGainPreampNotifier = ValueNotifier<double>(
    0.0,
  );

  bool _androidLoudnessEnhancerReady = false;

  /*
   * Id de la canción para la que el ReplayGain ya está preparado.
   *
   * Se LEE en _handleNativeIndexChange: si el callback nativo llega tarde o
   * duplicado para una pista que ya preparamos nosotros, se ignora.
   *
   * Se usa el id y no el índice porque los índices cambian al reordenar o
   * eliminar de la cola.
   */
  String? _preparedSongId;

  // ============================================================
  // VOLUMEN: UN SOLO ESCRITOR
  // ============================================================

  /*
   * El volumen final SIEMPRE se calcula desde el estado actual:
   *
   *   silencio (candados)  ×  volumen del usuario  ×  ReplayGain (solo Linux)
   *                        ×  fade (capa externa)
   *
   * y solo _runVolumeLoop llama a _player.setVolume. Nadie más.
   *
   * Nunca se pasan índices/generaciones a la función que escribe: se lee lo
   * que es verdad AHORA, no lo que era verdad cuando alguien la llamó.
   */

  int _muteHolds = 0;

  _MuteHold _holdMute() {
    _muteHolds++;

    // Fuerza que el 0.0 se escriba de verdad.
    _lastWrittenVolume = null;

    return _MuteHold();
  }

  void _releaseMute(_MuteHold hold) {
    if (hold.released) {
      return;
    }

    hold.released = true;

    if (_muteHolds > 0) {
      _muteHolds--;
    }
  }

  Future<void>? _volumeLoop;

  bool _volumeDirty = false;

  double? _lastWrittenVolume;

  /// Pide que el volumen del player refleje el estado actual.
  Future<void> _syncVolume() {
    if (_isDisposed) {
      return Future<void>.value();
    }

    _volumeDirty = true;

    return _volumeLoop ??= _runVolumeLoop();
  }

  Future<void> _runVolumeLoop() async {
    // Cede un microtask para que _volumeLoop ya esté asignado antes de que el
    // bucle pueda terminar.
    await Future<void>.value();

    try {
      while (_volumeDirty && !_isDisposed) {
        _volumeDirty = false;

        final volume = _computeVolume();

        final last = _lastWrittenVolume;

        if (last != null && (volume - last).abs() < 0.0005) {
          continue;
        }

        try {
          await _player.setVolume(volume);

          _lastWrittenVolume = volume;
        } catch (error) {
          _lastWrittenVolume = null;

          if (!_isDisposed) {
            debugPrint(
              '[SONARA PLAYER] '
              'Error setVolume: $error',
            );
          }
        }
      }
    } finally {
      _volumeLoop = null;
    }
  }

  double _computeVolume() {
    if (_isDisposed || _muteHolds > 0) {
      return 0.0;
    }

    final index = currentIndex;

    if (index == null || index < 0 || index >= _songs.length) {
      return 0.0;
    }

    final song = _songs[index];

    /*
     * Android: ReplayGain + Preamp los aplica el LoudnessEnhancer.
     * Linux: se aplican aquí, sobre el volumen del player.
     */
    final replayGain = Platform.isAndroid
        ? 1.0
        : _dbToLinear(_getTotalGainDb(song));

    final volume = _baseVolume * replayGain * _fade.gain;

    return volume.clamp(0.0, _maximumPlayerVolume).toDouble();
  }

  // ============================================================
  // FADE
  // ============================================================

  static const Duration _durationTolerance = Duration(seconds: 5);

  FadeSample _sampleForFade() {
    if (_isDisposed) {
      return const FadeSample(
        position: Duration.zero,
        duration: null,
        playing: false,
        isTransitioning: true,
      );
    }

    final index = currentIndex;

    final Song? song = (index != null && index >= 0 && index < _songs.length)
        ? _songs[index]
        : null;

    return FadeSample(
      position: _player.position,
      duration: _resolveTrackDuration(song),
      playing: _player.playing,
      isTransitioning: _muteHolds > 0,
    );
  }

  Duration? _resolveTrackDuration(Song? song) {
    if (_isDisposed) {
      return null;
    }

    final hint = song?.duration;
    final live = _player.duration;

    final Duration? validHint = (hint != null && hint > Duration.zero)
        ? hint
        : null;

    final Duration? validLive = (live != null && live > Duration.zero)
        ? live
        : null;

    if (validHint != null && validLive != null) {
      final Duration hintDuration = validHint;
      final Duration liveDuration = validLive;

      return (liveDuration - hintDuration).abs() <= _durationTolerance
          ? liveDuration
          : hintDuration;
    }

    return validHint ?? validLive;
  }

  // ============================================================
  // ESTADO
  // ============================================================

  bool _isDisposed = false;

  // ============================================================
  // MODOS
  // ============================================================

  bool _shuffleEnabled = false;

  int _repeatMode = 0;

  final math.Random _random = math.Random();

  // ============================================================
  // SUSCRIPCIONES
  // ============================================================

  StreamSubscription<PlayerState>? _playerStateSubscription;

  StreamSubscription<Duration>? _positionSubscription;

  StreamSubscription<Duration?>? _durationSubscription;

  StreamSubscription<int?>? _currentIndexSubscription;

  // ============================================================
  // ANDROID 8D
  // ============================================================

  Future<void> _load8DPreference() async {
    if (!Platform.isAndroid || _isDisposed) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      if (_isDisposed) {
        return;
      }

      _setEightDState(prefs.getBool(_8DPreferenceKey) ?? false);

      final sessionId = _player.androidAudioSessionId;

      if (sessionId != null && sessionId > 0) {
        await _connect8DSession(sessionId);
      }
    } catch (error) {
      debugPrint('[SONARA 8D] Error cargando estado: $error');
    }
  }

  Future<void> _handleAndroidAudioSession(int? sessionId) async {
    if (!Platform.isAndroid ||
        _isDisposed ||
        sessionId == null ||
        sessionId <= 0) {
      return;
    }

    await _connect8DSession(sessionId);
  }

  Future<void> _connect8DSession(int sessionId) async {
    if (_isDisposed) {
      return;
    }

    try {
      await _nativeMusicChannel.invokeMethod<bool>(
        'set8DAudioSession',
        <String, dynamic>{'sessionId': sessionId},
      );

      if (_isDisposed) {
        return;
      }

      final applied =
          await _nativeMusicChannel.invokeMethod<bool>(
            'set8DEnabled',
            <String, dynamic>{'enabled': _8DEnabled},
          ) ??
          false;

      // Si estaba guardado como activo pero el dispositivo no lo soporta,
      // la UI no debe mostrarlo encendido.
      if (_8DEnabled && !applied) {
        _setEightDState(false);
      }
    } catch (error) {
      debugPrint('[SONARA 8D] Error conectando sesión: $error');
    }
  }

  Future<bool> set8DEnabled(bool enabled) async {
    if (!Platform.isAndroid || _isDisposed) {
      return false;
    }

    try {
      // Si just_audio ya tiene sesión pero el nativo aún no la recibió,
      // la mandamos antes de activar el efecto.
      final sessionId = _player.androidAudioSessionId;

      if (enabled && sessionId != null && sessionId > 0) {
        await _nativeMusicChannel.invokeMethod<bool>(
          'set8DAudioSession',
          <String, dynamic>{'sessionId': sessionId},
        );
      }

      final applied =
          await _nativeMusicChannel.invokeMethod<bool>(
            'set8DEnabled',
            <String, dynamic>{'enabled': enabled},
          ) ??
          false;

      if (enabled && !applied) {
        return false;
      }

      if (_isDisposed) {
        return false;
      }

      _setEightDState(enabled);

      final prefs = await SharedPreferences.getInstance();

      if (_isDisposed) {
        return false;
      }

      await prefs.setBool(_8DPreferenceKey, enabled);

      return true;
    } catch (error) {
      debugPrint('[SONARA 8D] Error activando/desactivando: $error');

      return false;
    }
  }

  // ============================================================
  // REPRODUCCIÓN
  // ============================================================

  void _startPlayback() {
    if (_isDisposed) {
      return;
    }

    unawaited(
      _player.play().catchError((Object error, StackTrace stackTrace) {
        if (_isDisposed || error is PlayerInterruptedException) {
          return;
        }

        debugPrint(
          '[SONARA PLAYER] '
          'Error en play(): $error',
        );

        debugPrintStack(stackTrace: stackTrace);
      }),
    );
  }

  // ============================================================
  // ANDROID LOUDNESS ENHANCER
  // ============================================================

  Future<void> _initializeAndroidLoudnessEnhancer() async {
    if (!Platform.isAndroid || _isDisposed) {
      return;
    }

    try {
      await _loudnessEnhancer.setEnabled(true);

      if (_isDisposed) {
        return;
      }

      _androidLoudnessEnhancerReady = true;

      debugPrint(
        '[SONARA REPLAYGAIN] '
        'Android LoudnessEnhancer habilitado.',
      );

      final index = currentIndex;

      if (index != null && index >= 0 && index < _songs.length) {
        await _prepareAndroidGainForIndex(index);
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA REPLAYGAIN] '
        'No se pudo habilitar LoudnessEnhancer: $error',
      );

      debugPrintStack(stackTrace: stackTrace);

      _androidLoudnessEnhancerReady = false;
    }
  }

  Future<void> _prepareAndroidGainForIndex(int index) async {
    if (!Platform.isAndroid || !_androidLoudnessEnhancerReady || _isDisposed) {
      return;
    }

    if (index < 0 || index >= _songs.length) {
      return;
    }

    final song = _songs[index];

    final totalGainDb = _getTotalGainDb(song);

    try {
      await _loudnessEnhancer.setTargetGain(totalGainDb);

      if (_isDisposed) {
        return;
      }

      _preparedSongId = song.id;

      debugPrint(
        '[SONARA REPLAYGAIN ANDROID] '
        'Índice $index | '
        '${song.title} | '
        '${totalGainDb.toStringAsFixed(2)} dB',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SONARA REPLAYGAIN ANDROID] '
        'Error aplicando ganancia: $error',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _prepareTrackGain(int index, {bool force = false}) async {
    if (_isDisposed || index < 0 || index >= _songs.length) {
      return;
    }

    final song = _songs[index];

    if (!force && _preparedSongId == song.id) {
      return;
    }

    _updateTrackGain(song);

    if (Platform.isAndroid) {
      await _prepareAndroidGainForIndex(index);
    } else {
      _preparedSongId = song.id;
    }
  }

  // ============================================================
  // PREAMP
  // ============================================================

  Future<void> _loadReplayGainPreamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_isDisposed) {
        return;
      }

      final saved = prefs.getDouble(_replayGainPreampPreferenceKey);

      if (saved == null) {
        return;
      }

      final value = saved.clamp(_minimumPreampDb, _maximumPreampDb).toDouble();

      _replayGainPreampDb = value;

      replayGainPreampNotifier.value = value;

      unawaited(_syncVolume());
    } catch (error) {
      debugPrint(
        '[SONARA REPLAYGAIN] '
        'Error cargando Preamp: $error',
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

    final index = currentIndex;

    if (Platform.isAndroid &&
        index != null &&
        index >= 0 &&
        index < _songs.length &&
        _androidLoudnessEnhancerReady) {
      await _prepareAndroidGainForIndex(index);
    }

    await _syncVolume();

    if (_isDisposed || !persist) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      if (_isDisposed) {
        return;
      }

      await prefs.setDouble(_replayGainPreampPreferenceKey, safeValue);
    } catch (error) {
      debugPrint(
        '[SONARA REPLAYGAIN] '
        'Error guardando Preamp: $error',
      );
    }
  }

  // ============================================================
  // LISTENERS
  // ============================================================

  void _listenToPlayer() {
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (_isDisposed) {
        return;
      }

      if (!_playerStateController.isClosed) {
        _playerStateController.add(state);
      }

      if (state.processingState == ProcessingState.completed) {
        unawaited(_handleTrackCompleted());
      }

      _fade.setPlaying(state.playing);
    });

    _positionSubscription = _player.positionStream.listen((value) {
      if (_isDisposed) {
        return;
      }

      if (!_positionController.isClosed) {
        _positionController.add(value);
      }
    });

    _durationSubscription = _player.durationStream.listen((value) {
      if (_isDisposed) {
        return;
      }

      if (!_durationController.isClosed) {
        _durationController.add(value);
      }
    });

    _currentIndexSubscription = _player.currentIndexStream.listen((index) {
      if (_isDisposed || _isLinux) {
        return;
      }

      if (!_currentIndexController.isClosed) {
        _currentIndexController.add(index);
      }

      if (index == null || index < 0 || index >= _songs.length) {
        return;
      }

      unawaited(_handleNativeIndexChange(index));
    });
  }

  Future<void> _handleNativeIndexChange(int index) async {
    if (_isDisposed || index < 0 || index >= _songs.length) {
      return;
    }

    if (_muteHolds > 0) {
      return;
    }

    if (_preparedSongId == _songs[index].id) {
      return;
    }

    final generation = _operationGeneration;

    final hold = _holdMute();

    try {
      await _syncVolume();

      if (!_isOperationValid(generation)) {
        return;
      }

      await _prepareTrackGain(index);

      if (!_isOperationValid(generation)) {
        return;
      }

      _fade.resync(position: Duration.zero);
    } finally {
      _releaseMute(hold);

      await _syncVolume();
    }
  }

  // ============================================================
  // FIN DE PISTA
  // ============================================================

  Future<void> _handleTrackCompleted() async {
    if (_isDisposed || _songs.isEmpty || _muteHolds > 0) {
      return;
    }

    final generation = _operationGeneration;

    final index = currentIndex;

    if (index == null || index < 0 || index >= _songs.length) {
      return;
    }

    if (_repeatMode == 1) {
      if (!_isOperationValid(generation)) {
        return;
      }

      await playAtIndex(index);
      return;
    }

    if (_shuffleEnabled && _songs.length > 1) {
      if (!_isOperationValid(generation)) {
        return;
      }

      await playAtIndex(_getRandomIndexExcluding(index));
      return;
    }

    final nextIndex = index + 1;

    if (nextIndex < _songs.length) {
      if (!_isOperationValid(generation)) {
        return;
      }

      await playAtIndex(nextIndex);
      return;
    }

    if (_repeatMode == 2) {
      if (!_isOperationValid(generation)) {
        return;
      }

      await playAtIndex(0);
      return;
    }

    final hold = _holdMute();

    try {
      await _syncVolume();

      if (_isDisposed) {
        return;
      }

      await _player.pause();

      if (_isDisposed) {
        return;
      }

      await _player.seek(Duration.zero);

      if (_isDisposed) {
        return;
      }

      _fade.resync(position: Duration.zero);

      _emitCurrentState();
    } catch (error, stackTrace) {
      if (_isDisposed) {
        return;
      }

      debugPrint(
        '[SONARA PLAYER] '
        'Error en fin de cola: $error',
      );

      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _releaseMute(hold);

      await _syncVolume();
    }
  }

  // ============================================================
  // AUDIO SOURCE
  // ============================================================

  Future<AudioSource> _createAudioSource(Song song) async {
    final file = File(song.filePath);

    if (!await file.exists()) {
      throw FileSystemException('El archivo no existe', song.filePath);
    }

    final mediaItem = await _createMediaItem(song);

    if (_isDisposed) {
      throw StateError('AudioPlayerService disposed');
    }

    return AudioSource.uri(Uri.file(song.filePath), tag: mediaItem);
  }

  // ============================================================
  // LINUX
  // ============================================================

  Future<Duration?> _loadLinuxSong(
    int index, {
    Duration position = Duration.zero,
    bool autoplay = false,
  }) async {
    if (!Platform.isLinux ||
        _isDisposed ||
        index < 0 ||
        index >= _songs.length) {
      return null;
    }

    final generation = ++_linuxLoadGeneration;

    final operation = _operationGeneration;

    final song = _songs[index];

    final hold = _holdMute();

    try {
      await _syncVolume();

      if (!_isOperationValid(operation) || generation != _linuxLoadGeneration) {
        return null;
      }

      final source = await _createAudioSource(song);

      if (!_isOperationValid(operation) || generation != _linuxLoadGeneration) {
        return null;
      }

      _linuxCurrentIndex = index;

      final loadedDuration = await _player.setAudioSource(
        source,
        initialPosition: position,
        preload: true,
      );

      if (!_isOperationValid(operation) || generation != _linuxLoadGeneration) {
        return loadedDuration;
      }

      await _syncNativeLoopMode();

      await _prepareTrackGain(index, force: true);

      _fade.resync(position: position);

      _releaseMute(hold);

      await _syncVolume();

      if (!_isOperationValid(operation) || generation != _linuxLoadGeneration) {
        return loadedDuration;
      }

      _emitCurrentState();

      if (autoplay) {
        _startPlayback();
      }

      return loadedDuration ?? await _waitForDuration();
    } on PlayerInterruptedException catch (error) {
      debugPrint(
        '[SONARA LINUX] '
        'Carga interrumpida: $error',
      );

      return null;
    } catch (error, stackTrace) {
      if (!_isDisposed) {
        debugPrint(
          '[SONARA LINUX] '
          'Error cargando ${song.title}: $error',
        );

        debugPrintStack(stackTrace: stackTrace);
      }

      return null;
    } finally {
      _releaseMute(hold);

      await _syncVolume();
    }
  }

  // ============================================================
  // REPLAYGAIN
  // ============================================================

  void _updateTrackGain(Song song) {
    final gainDb = _getTrackGainDb(song);

    debugPrint(
      '[SONARA REPLAYGAIN] '
      '${song.title} | '
      'Gain=${gainDb.toStringAsFixed(2)} dB | '
      'Preamp=${_replayGainPreampDb.toStringAsFixed(2)} dB | '
      'Total=${_getTotalGainDb(song).toStringAsFixed(2)} dB',
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
    return _getTrackGainDb(song) + _replayGainPreampDb;
  }

  double _dbToLinear(double db) {
    return math.pow(10, db / 20).toDouble();
  }

  // ============================================================
  // LOOP
  // ============================================================

  Future<void> _syncNativeLoopMode() async {
    if (_isDisposed) {
      return;
    }

    try {
      await _player.setLoopMode(_repeatMode == 1 ? LoopMode.one : LoopMode.off);
    } catch (error) {
      if (!_isDisposed) {
        debugPrint(
          '[SONARA PLAYER] '
          'Error LoopMode: $error',
        );
      }
    }
  }

  // ============================================================
  // COLA
  // ============================================================

  Future<Duration?> setQueue(
    List<Song> songs, {
    required int initialIndex,
  }) async {
    if (_isDisposed) {
      return null;
    }

    final operation = _nextOperationGeneration();

    final hold = _holdMute();

    try {
      await _syncVolume();

      if (!_isOperationValid(operation)) {
        return null;
      }

      if (songs.isEmpty) {
        await clear();
        return null;
      }

      _songs
        ..clear()
        ..addAll(songs);

      _preparedSongId = null;

      final safeIndex = initialIndex.clamp(0, _songs.length - 1).toInt();

      if (_isLinux) {
        _releaseMute(hold);

        return await _loadLinuxSong(
          safeIndex,
          position: Duration.zero,
          autoplay: false,
        );
      }

      final sources = <AudioSource>[];

      for (final song in _songs) {
        if (!_isOperationValid(operation)) {
          return null;
        }

        sources.add(await _createAudioSource(song));
      }

      if (!_isOperationValid(operation)) {
        return null;
      }

      _playlist = ConcatenatingAudioSource(children: sources);

      final loadedDuration = await _player.setAudioSource(
        _playlist!,
        initialIndex: safeIndex,
        initialPosition: Duration.zero,
        preload: true,
      );

      if (!_isOperationValid(operation)) {
        return loadedDuration;
      }

      await _syncNativeLoopMode();

      await _prepareTrackGain(safeIndex, force: true);

      if (!_isOperationValid(operation)) {
        return loadedDuration;
      }

      _fade.resync(position: Duration.zero);

      _emitCurrentState();

      return loadedDuration ?? await _waitForDuration();
    } finally {
      _releaseMute(hold);

      await _syncVolume();
    }
  }

  Future<Duration?> playQueue(
    List<Song> songs, {
    required int initialIndex,
  }) async {
    final result = await setQueue(songs, initialIndex: initialIndex);

    if (_isDisposed) {
      return result;
    }

    await play();

    return result;
  }

  // ============================================================
  // CAMBIO DE PISTA
  // ============================================================

  Future<Duration?> playAtIndex(int index) async {
    if (_isDisposed || _songs.isEmpty || index < 0 || index >= _songs.length) {
      return null;
    }

    final operation = _nextOperationGeneration();

    final hold = _holdMute();

    try {
      await _syncVolume();

      if (!_isOperationValid(operation)) {
        return null;
      }

      final targetSong = _songs[index];

      debugPrint(
        '[SONARA PLAYER] '
        'Cambio a [$index] ${targetSong.title}',
      );

      if (_isLinux) {
        _releaseMute(hold);

        return await _loadLinuxSong(
          index,
          position: Duration.zero,
          autoplay: true,
        );
      }

      await _player.seek(Duration.zero, index: index);

      if (!_isOperationValid(operation)) {
        return null;
      }

      if (index < 0 || index >= _songs.length) {
        return null;
      }

      await _prepareTrackGain(index);

      if (!_isOperationValid(operation)) {
        return null;
      }

      final result = await _waitForDuration();

      if (!_isOperationValid(operation)) {
        return result;
      }

      _fade.resync(position: Duration.zero);

      _releaseMute(hold);

      await _syncVolume();

      if (!_isOperationValid(operation)) {
        return result;
      }

      _startPlayback();

      return result;
    } finally {
      _releaseMute(hold);

      await _syncVolume();
    }
  }

  Future<Duration?> playSingleSong(Song song) {
    return playQueue(<Song>[song], initialIndex: 0);
  }

  // ============================================================
  // SYNC QUEUE
  // ============================================================

  Future<void> syncQueue(
    List<Song> songs, {
    required int currentIndex,
    bool keepPosition = true,
    bool resumePlayback = true,
  }) async {
    if (_isDisposed) {
      return;
    }

    if (songs.isEmpty) {
      await clear();
      return;
    }

    final wasPlaying = playing;

    final oldPosition = keepPosition ? position : Duration.zero;

    final safeIndex = currentIndex.clamp(0, songs.length - 1).toInt();

    await setQueue(songs, initialIndex: safeIndex);

    if (_isDisposed) {
      return;
    }

    final currentDuration = duration;

    if (keepPosition &&
        oldPosition > Duration.zero &&
        currentDuration != null &&
        oldPosition < currentDuration) {
      await seek(oldPosition, index: safeIndex);
    }

    if (_isDisposed) {
      return;
    }

    if (resumePlayback && wasPlaying) {
      await play();
    }
  }

  // ============================================================
  // ADD
  // ============================================================

  Future<void> addToQueue(Song song) async {
    if (_isDisposed) {
      return;
    }

    if (_songs.any((item) => item.id == song.id)) {
      return;
    }

    if (_isLinux) {
      if (_songs.isEmpty) {
        await setQueue(<Song>[song], initialIndex: 0);
        return;
      }

      _songs.add(song);

      _emitCurrentState();

      return;
    }

    if (_playlist == null) {
      await setQueue(<Song>[song], initialIndex: 0);
      return;
    }

    final source = await _createAudioSource(song);

    if (_isDisposed) {
      return;
    }

    await _playlist!.add(source);

    if (_isDisposed) {
      return;
    }

    _songs.add(song);

    _emitCurrentState();
  }

  Future<void> addSongsToQueue(List<Song> songs) async {
    if (_isDisposed || songs.isEmpty) {
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
      if (_isDisposed) {
        return;
      }

      sources.add(await _createAudioSource(song));
    }

    if (_isDisposed) {
      return;
    }

    await _playlist!.addAll(sources);

    if (_isDisposed) {
      return;
    }

    _songs.addAll(newSongs);

    _emitCurrentState();
  }

  // ============================================================
  // REMOVE
  // ============================================================

  Future<void> removeFromQueue(int index) async {
    if (_isDisposed || index < 0 || index >= _songs.length) {
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

    if (_isDisposed) {
      return;
    }

    if (index >= _songs.length) {
      return;
    }

    _songs.removeAt(index);

    _emitCurrentState();
  }

  // ============================================================
  // REORDER
  // ============================================================

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (_isDisposed ||
        oldIndex < 0 ||
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

    if (_isDisposed) {
      return;
    }

    final song = _songs.removeAt(oldIndex);

    _songs.insert(newIndex, song);

    _emitCurrentState();
  }

  // ============================================================
  // NEXT
  // ============================================================

  Future<bool> playNext() async {
    if (_isDisposed || _songs.isEmpty) {
      return false;
    }

    final current = currentIndex ?? 0;

    if (current < 0 || current >= _songs.length) {
      return false;
    }

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

    if (nextIndex == null || nextIndex < 0 || nextIndex >= _songs.length) {
      return false;
    }

    await playAtIndex(nextIndex);

    return !_isDisposed;
  }

  // ============================================================
  // PREVIOUS
  // ============================================================

  Future<bool> playPrevious() async {
    if (_isDisposed || _songs.isEmpty) {
      return false;
    }

    final current = currentIndex ?? 0;

    if (current < 0 || current >= _songs.length) {
      return false;
    }

    if (position.inSeconds > 3) {
      await seek(Duration.zero);

      if (!_isDisposed) {
        await play();
      }

      return !_isDisposed;
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

    if (previousIndex == null ||
        previousIndex < 0 ||
        previousIndex >= _songs.length) {
      return false;
    }

    await playAtIndex(previousIndex);

    return !_isDisposed;
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

  // ============================================================
  // PLAY
  // ============================================================

  Future<void> play() async {
    if (_isDisposed || _songs.isEmpty) {
      return;
    }

    final index = currentIndex;

    if (index == null || index < 0 || index >= _songs.length) {
      await playAtIndex(0);
      return;
    }

    if (_player.playing) {
      return;
    }

    final hold = _holdMute();

    try {
      await _syncVolume();

      if (_isDisposed) {
        return;
      }

      await _prepareTrackGain(index);

      if (_isDisposed) {
        return;
      }

      _fade.resync();
    } finally {
      _releaseMute(hold);

      await _syncVolume();
    }

    _startPlayback();
  }

  // ============================================================
  // PAUSE
  // ============================================================

  Future<void> pause() async {
    if (_isDisposed) {
      return;
    }

    await _player.pause();
  }

  // ============================================================
  // RESUME
  // ============================================================

  Future<void> resume() {
    return play();
  }

  // ============================================================
  // STOP
  // ============================================================

  Future<void> stop() async {
    if (_isDisposed) {
      return;
    }

    final hold = _holdMute();

    try {
      await _syncVolume();

      if (_isDisposed) {
        return;
      }

      await _player.stop();

      if (_isDisposed) {
        return;
      }

      _preparedSongId = null;

      _fade.resync(position: Duration.zero);
    } finally {
      _releaseMute(hold);

      await _syncVolume();
    }
  }

  // ============================================================
  // SEEK
  // ============================================================

  Future<void> seek(Duration position, {int? index}) async {
    if (_isDisposed || _songs.isEmpty) {
      return;
    }

    final operation = _nextOperationGeneration();

    final wasPlaying = _player.playing;

    final hold = _holdMute();

    try {
      await _syncVolume();

      if (!_isOperationValid(operation)) {
        return;
      }

      if (_isLinux && index != null) {
        if (index < 0 || index >= _songs.length) {
          return;
        }

        _releaseMute(hold);

        await _loadLinuxSong(index, position: position, autoplay: wasPlaying);

        return;
      }

      await _player.seek(position, index: index);

      if (!_isOperationValid(operation)) {
        return;
      }

      final effectiveIndex = index ?? currentIndex;

      if (effectiveIndex != null &&
          effectiveIndex >= 0 &&
          effectiveIndex < _songs.length) {
        await _prepareTrackGain(effectiveIndex);

        if (!_isOperationValid(operation)) {
          return;
        }

        _fade.resync(position: position);
      }
    } finally {
      _releaseMute(hold);

      await _syncVolume();
    }
  }

  // ============================================================
  // VOLUMEN PÚBLICO
  // ============================================================

  Future<void> setVolume(double volume) async {
    if (_isDisposed) {
      return;
    }

    _baseVolume = volume.clamp(0.0, _maximumPlayerVolume).toDouble();

    await _syncVolume();
  }

  // ============================================================
  // SPEED
  // ============================================================

  Future<void> setSpeed(double speed) async {
    if (_isDisposed) {
      return;
    }

    await _player.setSpeed(speed);
  }

  // ============================================================
  // MODOS
  // ============================================================

  void setPlaybackModes({
    required bool shuffleEnabled,
    required int repeatMode,
  }) {
    if (_isDisposed) {
      return;
    }

    _shuffleEnabled = shuffleEnabled;

    _repeatMode = repeatMode;

    unawaited(_syncNativeLoopMode());
  }

  // ============================================================
  // DURACIÓN
  // ============================================================

  Future<Duration?> _waitForDuration() async {
    if (_isDisposed) {
      return null;
    }

    final current = _player.duration;

    if (current != null && current > Duration.zero) {
      return current;
    }

    try {
      return await _player.durationStream
          .where((value) => value != null && value > Duration.zero)
          .first
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      if (_isDisposed) {
        return null;
      }

      return _player.duration;
    }
  }

  // ============================================================
  // MEDIA ITEM
  // ============================================================

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
      if (_isDisposed) {
        break;
      }

      result.add(await _createMediaItem(song));
    }

    return result;
  }

  // ============================================================
  // ESTADO
  // ============================================================

  void _emitCurrentState() {
    if (_isDisposed) {
      return;
    }

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

  // ============================================================
  // CLEAR
  // ============================================================

  Future<void> clear() async {
    if (_isDisposed) {
      return;
    }

    _nextOperationGeneration();

    _linuxLoadGeneration++;

    final hold = _holdMute();

    try {
      await _syncVolume();

      if (_isDisposed) {
        return;
      }

      await _player.stop();

      if (_isDisposed) {
        return;
      }

      _songs.clear();

      _playlist = null;

      _linuxCurrentIndex = null;

      _preparedSongId = null;

      if (Platform.isAndroid && _androidLoudnessEnhancerReady) {
        try {
          await _loudnessEnhancer.setTargetGain(0.0);
        } catch (_) {}
      }

      if (_isDisposed) {
        return;
      }

      if (!_currentIndexController.isClosed) {
        _currentIndexController.add(null);
      }

      if (!_durationController.isClosed) {
        _durationController.add(Duration.zero);
      }

      if (!_positionController.isClosed) {
        _positionController.add(Duration.zero);
      }
    } finally {
      _releaseMute(hold);

      await _syncVolume();
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    _operationGeneration++;

    _linuxLoadGeneration++;

    _fade.dispose();

    try {
      await _playerStateSubscription?.cancel();
    } catch (_) {}

    try {
      await _positionSubscription?.cancel();
    } catch (_) {}

    try {
      await _durationSubscription?.cancel();
    } catch (_) {}

    try {
      await _currentIndexSubscription?.cancel();
    } catch (_) {}

    try {
      await _androidAudioSessionSubscription?.cancel();
    } catch (_) {}

    _androidAudioSessionSubscription = null;

    if (Platform.isAndroid) {
      try {
        await _loudnessEnhancer.setEnabled(false);
      } catch (_) {}
    }

    try {
      replayGainPreampNotifier.dispose();
    } catch (_) {}

    try {
      eightDEnabledNotifier.dispose();
    } catch (_) {}

    try {
      await _player.dispose();
    } catch (_) {}

    try {
      await _playerStateController.close();
    } catch (_) {}

    try {
      await _currentIndexController.close();
    } catch (_) {}

    try {
      await _positionController.close();
    } catch (_) {}

    try {
      await _durationController.close();
    } catch (_) {}
  }
}

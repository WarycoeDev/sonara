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
      audioPipeline: AudioPipeline(
        androidAudioEffects: <AndroidAudioEffect>[_loudnessEnhancer],
      ),
    );

    _listenToPlayer();

    _crossfadeService.secondsNotifier.addListener(_handleFadeSettingChanged);

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

  final List<Song> _songs = <Song>[];

  ConcatenatingAudioSource? _playlist;

  int? _linuxCurrentIndex;

  bool _linuxLoading = false;

  int _linuxLoadGeneration = 0;

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

  bool get isCrossfading => _crossfadeService.enabled;

  // ============================================================
  // PLATFORM
  // ============================================================

  bool get _isLinux => Platform.isLinux;

  // ============================================================
  // REPLAYGAIN
  // ============================================================

  /*
   * IMPORTANTE:
   *
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
   * Ganancia actualmente preparada para la pista.
   *
   * No se utiliza para decidir el volumen Android,
   * pero sirve como estado interno.
   */
  double _currentTrackGainLinear = 1.0;

  /*
   * Índice para el que el ReplayGain Android ya fue preparado.
   *
   * Esto evita que callbacks atrasados vuelvan a aplicar
   * la ganancia de una pista anterior.
   */
  int? _preparedAndroidIndex;

  // ============================================================
  // VOLUMEN / TRANSICIONES
  // ============================================================

  bool _trackTransitionInProgress = false;

  bool _isApplyingVolume = false;

  bool _volumeUpdatePending = false;

  /*
   * Última operación que autorizó modificar el volumen.
   *
   * Sirve para impedir que un callback viejo gane una carrera
   * contra un cambio de pista nuevo.
   */
  int _volumeGeneration = 0;

  // ============================================================
  // FADE
  // ============================================================

  final CrossfadeService _crossfadeService = CrossfadeService.instance;

  Timer? _fadeMonitor;

  bool _fadeUpdateInProgress = false;

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

      _preparedAndroidIndex = index;

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

      unawaited(_applyEffectiveVolume());
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

    /*
     * Si Android está reproduciendo una pista,
     * actualizamos el enhancer.
     */
    final index = currentIndex;

    if (Platform.isAndroid &&
        index != null &&
        index >= 0 &&
        index < _songs.length &&
        _androidLoudnessEnhancerReady) {
      await _prepareAndroidGainForIndex(index);
    }

    await _applyEffectiveVolume();

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

      if (state.playing) {
        _startFadeMonitor();
      } else {
        _stopFadeMonitor();
      }
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

      /*
         * MUY IMPORTANTE:
         *
         * currentIndex puede ser null, o puede llegar durante
         * una operación en la que nuestra lista ya cambió.
         *
         * Nunca acceder sin validar.
         */
      if (index == null || index < 0 || index >= _songs.length) {
        return;
      }

      /*
         * No aplicamos ReplayGain directamente aquí.
         *
         * Este callback puede llegar tarde.
         *
         * En su lugar iniciamos una preparación controlada.
         */
      unawaited(_handleNativeIndexChange(index));
    });
  }

  Future<void> _handleNativeIndexChange(int index) async {
    if (_isDisposed || index < 0 || index >= _songs.length) {
      return;
    }

    /*
     * Si estamos haciendo nosotros mismos el cambio,
     * la operación principal ya se encarga del volumen.
     */
    if (_trackTransitionInProgress) {
      return;
    }

    final generation = _operationGeneration;

    final song = _songs[index];

    _updateTrackGain(song);

    if (Platform.isAndroid) {
      /*
       * Silenciamos ANTES de modificar ReplayGain.
       */
      await _player.setVolume(0.0);

      if (!_isOperationValid(generation)) {
        return;
      }

      await _prepareAndroidGainForIndex(index);

      if (!_isOperationValid(generation)) {
        return;
      }
    }

    if (!_isOperationValid(generation)) {
      return;
    }

    await _applyEffectiveVolume(expectedIndex: index, generation: generation);
  }

  // ============================================================
  // FIN DE PISTA
  // ============================================================

  Future<void> _handleTrackCompleted() async {
    if (_isDisposed || _songs.isEmpty || _trackTransitionInProgress) {
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

    /*
     * FIN REAL DE LA COLA.
     */
    _stopFadeMonitor();

    try {
      await _player.setVolume(0.0);

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

    _linuxLoading = true;

    _trackTransitionInProgress = true;

    try {
      /*
       * Silencio antes de TODO.
       */
      await _player.setVolume(0.0);

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

      _updateTrackGain(song);

      await _applyEffectiveVolume(expectedIndex: index, generation: operation);

      if (!_isOperationValid(operation) || generation != _linuxLoadGeneration) {
        return loadedDuration;
      }

      _emitCurrentState();

      if (autoplay) {
        /*
         * ReplayGain y fade ya están preparados.
         */
        await _player.play();
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
      if (generation == _linuxLoadGeneration) {
        _linuxLoading = false;
      }

      if (!_isDisposed && operation == _operationGeneration) {
        _trackTransitionInProgress = false;
      }
    }
  }

  // ============================================================
  // REPLAYGAIN
  // ============================================================

  void _updateTrackGain(Song song) {
    final gainDb = _getTrackGainDb(song);

    _currentTrackGainLinear = _dbToLinear(gainDb);

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
  // VOLUMEN EFECTIVO
  // ============================================================

  double _getEffectiveVolumeForSong(Song song) {
    /*
     * Android:
     *
     * ReplayGain + Preamp se aplican en
     * LoudnessEnhancer.
     *
     * El volumen del player solamente controla
     * volumen del usuario + fade.
     */
    if (Platform.isAndroid) {
      return _baseVolume;
    }

    /*
     * Linux/Desktop:
     *
     * ReplayGain se aplica directamente al
     * volumen del player.
     */
    final gainDb = _getTotalGainDb(song);

    final gainLinear = _dbToLinear(gainDb);

    return _baseVolume * gainLinear;
  }

  Future<void> _applyEffectiveVolume({
    int? expectedIndex,
    int? generation,
  }) async {
    if (_isDisposed) {
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

        if (_isDisposed) {
          return;
        }

        /*
         * Si la operación que inició esta llamada ya quedó
         * obsoleta, no tocar el volumen.
         */
        if (generation != null && generation != _operationGeneration) {
          return;
        }

        Song? song;

        final index = currentIndex;

        if (index != null && index >= 0 && index < _songs.length) {
          song = _songs[index];
        }

        /*
         * Si esperamos una pista concreta y ya estamos en otra,
         * abortamos.
         */
        if (expectedIndex != null && index != expectedIndex) {
          return;
        }

        /*
         * Durante cambio de pista:
         *
         * SIEMPRE 0.
         */
        if (_trackTransitionInProgress) {
          await _player.setVolume(0.0);
          continue;
        }

        /*
         * Sin canción:
         * silencio.
         */
        if (song == null) {
          await _player.setVolume(0.0);
          continue;
        }

        /*
         * Volumen normal.
         */
        final normalVolume = _getEffectiveVolumeForSong(song);

        /*
         * Fade.
         */
        final fadeFactor = _getFadeFactor();

        final effectiveVolume = normalVolume * fadeFactor;

        /*
         * IMPORTANTE:
         *
         * Permitimos > 1.0.
         *
         * just_audio acepta un double de volumen y 1.0
         * representa volumen normal. DDart packages

         */
        final safeVolume = effectiveVolume
            .clamp(0.0, _maximumPlayerVolume)
            .toDouble();

        await _player.setVolume(safeVolume);
      } while (_volumeUpdatePending);
    } finally {
      _isApplyingVolume = false;
    }
  }

  // ============================================================
  // FADE
  // ============================================================

  double _getFadeFactor() {
    if (!_crossfadeService.enabled) {
      return 1.0;
    }

    final fadeDuration = _crossfadeService.duration;

    if (fadeDuration <= Duration.zero) {
      return 1.0;
    }

    final currentPosition = _player.position;

    final currentDuration = _player.duration;

    if (currentPosition < Duration.zero) {
      return 0.0;
    }

    /*
     * Sin duración todavía:
     *
     * La pista acaba de cargar.
     * No permitimos que aparezca a volumen completo.
     */
    if (currentDuration == null || currentDuration <= Duration.zero) {
      if (currentPosition <= Duration.zero) {
        return 0.0;
      }

      if (currentPosition >= fadeDuration) {
        return 1.0;
      }

      return _linearProgress(currentPosition, fadeDuration);
    }

    var effectiveDuration = fadeDuration;

    final halfDuration = Duration(
      microseconds: currentDuration.inMicroseconds ~/ 2,
    );

    if (effectiveDuration > halfDuration) {
      effectiveDuration = halfDuration;
    }

    if (effectiveDuration <= Duration.zero) {
      return 1.0;
    }

    /*
     * FADE IN
     */
    if (currentPosition < effectiveDuration) {
      return _linearProgress(currentPosition, effectiveDuration);
    }

    /*
     * FADE OUT
     */
    final remaining = currentDuration - currentPosition;

    if (remaining <= effectiveDuration) {
      return _linearProgress(remaining, effectiveDuration);
    }

    return 1.0;
  }

  double _linearProgress(Duration elapsed, Duration total) {
    if (total <= Duration.zero) {
      return 1.0;
    }

    final value = elapsed.inMicroseconds / total.inMicroseconds;

    return value.clamp(0.0, 1.0).toDouble();
  }

  void _startFadeMonitor() {
    if (_isDisposed || !_crossfadeService.enabled || _fadeMonitor != null) {
      return;
    }

    _fadeMonitor = Timer.periodic(const Duration(milliseconds: 40), (_) {
      unawaited(_updateFadeVolume());
    });
  }

  void _stopFadeMonitor() {
    _fadeMonitor?.cancel();
    _fadeMonitor = null;
  }

  Future<void> _updateFadeVolume() async {
    if (_isDisposed ||
        !_crossfadeService.enabled ||
        !_player.playing ||
        _fadeUpdateInProgress ||
        _trackTransitionInProgress) {
      return;
    }

    _fadeUpdateInProgress = true;

    try {
      await _applyEffectiveVolume();
    } finally {
      _fadeUpdateInProgress = false;
    }
  }

  void _handleFadeSettingChanged() {
    if (_isDisposed) {
      return;
    }

    if (!_crossfadeService.enabled) {
      _stopFadeMonitor();

      unawaited(_applyEffectiveVolume());

      return;
    }

    unawaited(_applyEffectiveVolume());

    if (_player.playing) {
      _startFadeMonitor();
    }
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

    _trackTransitionInProgress = true;

    _stopFadeMonitor();

    /*
     * Silencio ANTES de tocar la cola.
     */
    await _player.setVolume(0.0);

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

    final safeIndex = initialIndex.clamp(0, _songs.length - 1).toInt();

    try {
      if (_isLinux) {
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

      /*
       * just_audio 0.10.x permite cargar la lista
       * con setAudioSources().
       *
       * Aquí usamos setAudioSource porque queremos
       * conservar explícitamente el objeto playlist.
       */
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

      final song = _songs[safeIndex];

      _updateTrackGain(song);

      /*
       * ReplayGain se prepara mientras el player sigue
       * completamente silenciado.
       */
      if (Platform.isAndroid) {
        await _prepareAndroidGainForIndex(safeIndex);
      }

      if (!_isOperationValid(operation)) {
        return loadedDuration;
      }

      /*
       * El volumen se prepara AHORA.
       *
       * Si fade está activo:
       *
       *   posición = 0
       *   fade = 0
       *   volumen = 0
       */
      await _applyEffectiveVolume(
        expectedIndex: safeIndex,
        generation: operation,
      );

      if (!_isOperationValid(operation)) {
        return loadedDuration;
      }

      _emitCurrentState();

      return loadedDuration ?? await _waitForDuration();
    } finally {
      if (_isOperationValid(operation)) {
        _trackTransitionInProgress = false;

        /*
         * Una última aplicación.
         *
         * Si fade está activo y la posición es 0,
         * seguirá siendo 0.
         *
         * Si fade está desactivado,
         * será el volumen normal.
         */
        await _applyEffectiveVolume(
          expectedIndex: safeIndex,
          generation: operation,
        );
      }
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

    _trackTransitionInProgress = true;

    _stopFadeMonitor();

    /*
     * SILENCIO INMEDIATO.
     */
    await _player.setVolume(0.0);

    if (!_isOperationValid(operation)) {
      return null;
    }

    final targetSong = _songs[index];

    debugPrint(
      '[SONARA PLAYER] '
      'Cambio a [$index] ${targetSong.title}',
    );

    try {
      if (_isLinux) {
        return await _loadLinuxSong(
          index,
          position: Duration.zero,
          autoplay: true,
        );
      }

      /*
       * El seek ocurre mientras el volumen es 0.
       */
      await _player.seek(Duration.zero, index: index);

      if (!_isOperationValid(operation)) {
        return null;
      }

      /*
       * VALIDACIÓN EXTRA.
       */
      if (index < 0 || index >= _songs.length) {
        return null;
      }

      final song = _songs[index];

      _updateTrackGain(song);

      /*
       * ReplayGain ANTES de play().
       */
      if (Platform.isAndroid) {
        await _prepareAndroidGainForIndex(index);
      }

      if (!_isOperationValid(operation)) {
        return null;
      }

      /*
       * Fade/RePlayGain quedan preparados
       * mientras seguimos silenciados.
       */
      await _applyEffectiveVolume(expectedIndex: index, generation: operation);

      if (!_isOperationValid(operation)) {
        return null;
      }

      final result = await _waitForDuration();

      if (!_isOperationValid(operation)) {
        return result;
      }

      /*
       * SOLO AHORA empezamos a reproducir.
       *
       * Esto evita el pequeño instante en que se podía
       * escuchar la pista con el volumen anterior.
       */
      await _player.play();

      if (!_isOperationValid(operation)) {
        return result;
      }

      return result;
    } finally {
      if (_isOperationValid(operation)) {
        _trackTransitionInProgress = false;

        /*
         * NO esperamos otro cambio de ReplayGain.
         *
         * Simplemente calculamos el volumen final desde
         * la pista actual.
         */
        await _applyEffectiveVolume(
          expectedIndex: index,
          generation: operation,
        );

        if (_crossfadeService.enabled && _player.playing) {
          _startFadeMonitor();
        }
      }
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

    final operation = _nextOperationGeneration();

    _trackTransitionInProgress = true;

    /*
     * Silencio antes de preparar ReplayGain.
     */
    await _player.setVolume(0.0);

    if (!_isOperationValid(operation)) {
      return;
    }

    final song = _songs[index];

    _updateTrackGain(song);

    if (Platform.isAndroid) {
      await _prepareAndroidGainForIndex(index);
    }

    if (!_isOperationValid(operation)) {
      return;
    }

    /*
     * Preparar volumen + fade.
     */
    await _applyEffectiveVolume(expectedIndex: index, generation: operation);

    if (!_isOperationValid(operation)) {
      return;
    }

    /*
     * Quitamos el bloqueo JUSTO antes de play().
     *
     * El volumen ya está preparado.
     */
    _trackTransitionInProgress = false;

    await _applyEffectiveVolume(expectedIndex: index, generation: operation);

    if (!_isOperationValid(operation)) {
      return;
    }

    await _player.play();

    if (_isDisposed) {
      return;
    }

    if (_crossfadeService.enabled) {
      _startFadeMonitor();
    }
  }

  // ============================================================
  // PAUSE
  // ============================================================

  Future<void> pause() async {
    _stopFadeMonitor();

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
    _stopFadeMonitor();

    if (_isDisposed) {
      return;
    }

    _trackTransitionInProgress = true;

    try {
      await _player.setVolume(0.0);

      if (_isDisposed) {
        return;
      }

      await _player.stop();

      if (_isDisposed) {
        return;
      }

      _preparedAndroidIndex = null;
    } finally {
      if (!_isDisposed) {
        _trackTransitionInProgress = false;
      }
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

    _trackTransitionInProgress = true;

    try {
      /*
       * Silencio durante seek.
       */
      await _player.setVolume(0.0);

      if (!_isOperationValid(operation)) {
        return;
      }

      if (_isLinux && index != null) {
        if (index < 0 || index >= _songs.length) {
          return;
        }

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
        final song = _songs[effectiveIndex];

        _updateTrackGain(song);

        if (Platform.isAndroid) {
          await _prepareAndroidGainForIndex(effectiveIndex);
        }

        if (!_isOperationValid(operation)) {
          return;
        }

        /*
         * Para seek dentro de una canción,
         * recalculamos fade desde la nueva posición.
         */
        _trackTransitionInProgress = false;

        await _applyEffectiveVolume(
          expectedIndex: effectiveIndex,
          generation: operation,
        );
      }
    } finally {
      if (!_isDisposed && operation == _operationGeneration) {
        _trackTransitionInProgress = false;

        await _applyEffectiveVolume(
          expectedIndex: index ?? currentIndex,
          generation: operation,
        );

        if (_player.playing && _crossfadeService.enabled) {
          _startFadeMonitor();
        }
      }
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

    await _applyEffectiveVolume();
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

    /*
     * Invalidar absolutamente todo.
     */
    _nextOperationGeneration();

    _linuxLoadGeneration++;

    _stopFadeMonitor();

    _trackTransitionInProgress = true;

    try {
      /*
       * SILENCIO.
       */
      await _player.setVolume(0.0);

      if (_isDisposed) {
        return;
      }

      /*
       * Detener libera los decoders.
       */
      await _player.stop();

      if (_isDisposed) {
        return;
      }

      _songs.clear();

      _playlist = null;

      _linuxCurrentIndex = null;

      _currentTrackGainLinear = 1.0;

      _preparedAndroidIndex = null;

      /*
       * Resetear LoudnessEnhancer.
       */
      if (Platform.isAndroid && _androidLoudnessEnhancerReady) {
        try {
          await _loudnessEnhancer.setTargetGain(0.0);
        } catch (_) {}
      }

      if (_isDisposed) {
        return;
      }

      /*
       * NO hacemos:
       *
       * setAudioSource(
       *   ConcatenatingAudioSource(children: [])
       * )
       *
       * Esto puede producir estados inválidos en just_audio
       * y era una de las zonas problemáticas al cerrar/vaciar.
       *
       * stop() ya conserva el estado suficiente para que
       * podamos cargar posteriormente una nueva fuente.
       */

      await _player.setVolume(0.0);

      if (_currentIndexController.isClosed == false) {
        _currentIndexController.add(null);
      }

      if (_durationController.isClosed == false) {
        _durationController.add(Duration.zero);
      }

      if (_positionController.isClosed == false) {
        _positionController.add(Duration.zero);
      }
    } finally {
      if (!_isDisposed) {
        _trackTransitionInProgress = false;
      }
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    /*
     * INVALIDAR TODO antes de cualquier await.
     */
    _isDisposed = true;

    _operationGeneration++;

    _linuxLoadGeneration++;

    _trackTransitionInProgress = true;

    _stopFadeMonitor();

    _crossfadeService.secondsNotifier.removeListener(_handleFadeSettingChanged);

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

    if (Platform.isAndroid) {
      try {
        await _loudnessEnhancer.setEnabled(false);
      } catch (_) {}
    }

    try {
      replayGainPreampNotifier.dispose();
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

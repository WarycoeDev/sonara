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

    _crossfadeService.secondsNotifier.addListener(_handleFadeSettingChanged);

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

  bool _isApplyingVolume = false;

  bool _volumeUpdatePending = false;

  bool _androidLoudnessEnhancerReady = false;

  // FADE IN / FADE OUT

  final CrossfadeService _crossfadeService = CrossfadeService.instance;

  Timer? _fadeMonitor;

  bool _fadeUpdateInProgress = false;

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

  bool get isCrossfading => _crossfadeService.enabled;

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

      /*
       * IMPORTANTE (FIX):
       *
       * Antes este manejador de "fin de pista" solo se ejecutaba en
       * Linux. En el resto de plataformas no existía NINGÚN código
       * que reaccionara a que una canción terminara, así que el modo
       * "Repetir" simplemente no tenía nada que lo disparara.
       *
       * Ahora se ejecuta en TODAS las plataformas, y como el Fade
       * In / Fade Out se calcula a partir de la posición de la
       * canción actual (no de la lista completa), queda garantizado
       * que la transición de volumen se aplique canción por canción,
       * tanto al inicio como al final, sin importar la plataforma.
       */
      if (state.processingState == ProcessingState.completed) {
        unawaited(_handleTrackCompleted());
      }

      if (state.playing) {
        _startFadeMonitor();
      } else {
        _stopFadeMonitor();
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
        final song = _songs[index];

        _updateTrackGain(song);

        /*
         * MUY IMPORTANTE:
         *
         * Cuando just_audio cambia automáticamente a la siguiente
         * canción, su posición vuelve a 0.
         *
         * Por lo tanto, este cálculo produce automáticamente el
         * comienzo del Fade In de la nueva canción.
         */
        unawaited(_applyEffectiveVolume());
      }
    });
  }

  /*
   * FIN DE PISTA (TODAS LAS PLATAFORMAS)
   *
   * Se dispara cuando el reproductor llega de forma natural al final
   * de lo que tenía cargado (una sola canción, o el final de toda la
   * lista continua). A partir de aquí decidimos, canción por canción,
   * qué sigue según Repetir / Aleatorio, reutilizando exactamente el
   * mismo camino (playAtIndex) que usa el usuario al tocar "siguiente"
   * o "anterior" manualmente, así el Fade se aplica siempre igual.
   */
  Future<void> _handleTrackCompleted() async {
    if (_isDisposed || _songs.isEmpty) {
      return;
    }

    if (_isLinux && _linuxLoading) {
      return;
    }

    final index = currentIndex ?? 0;

    if (_repeatMode == 1) {
      /*
       * Modo "Repetir una".
       *
       * En condiciones normales, LoopMode.one del propio reproductor
       * (ver _syncNativeLoopMode) ya repite la pista de forma nativa
       * e instantánea, sin volver a abrir el archivo, así que este
       * evento normalmente ni siquiera debería dispararse en este
       * modo. Esta rama queda como respaldo por si la plataforma no
       * soporta LoopMode.one.
       */
      await playAtIndex(index);

      return;
    }

    if (_shuffleEnabled && _songs.length > 1) {
      final nextIndex = _getRandomIndexExcluding(index);

      await playAtIndex(nextIndex);

      return;
    }

    final nextIndex = index + 1;

    if (nextIndex < _songs.length) {
      await playAtIndex(nextIndex);

      return;
    }

    if (_repeatMode == 2) {
      await playAtIndex(0);
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

      // Mantiene sincronizado el LoopMode nativo con el nuevo audio
      // source recién cargado (ver _syncNativeLoopMode).
      unawaited(_syncNativeLoopMode());

      _updateTrackGain(song);

      /*
       * Aquí el volumen se calcula usando `position`.
       *
       * Si position == 0 y el Fade In está activo:
       *
       *     fadeFactor = 0
       *
       * Si position == 2 y la transición dura 4:
       *
       *     fadeFactor = 0.5
       */
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

  // FADE IN / FADE OUT

  /*
   * Devuelve un factor entre 0.0 y 1.0.
   *
   * Este valor es calculado DIRECTAMENTE a partir de la posición
   * actual de reproducción.
   *
   * No existe un "progreso interno" que pueda desincronizarse
   * después de un seek.
   */
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
      return 1.0;
    }

    /*
     * Si todavía no conocemos la duración no podemos calcular
     * el Fade Out.
     *
     * Pero sí podemos calcular el Fade In.
     */
    if (currentDuration == null || currentDuration <= Duration.zero) {
      if (currentPosition >= fadeDuration) {
        return 1.0;
      }

      return _linearProgress(currentPosition, fadeDuration);
    }

    /*
     * Para canciones suficientemente largas:
     *
     * 0s -------------------- final-fade ---------------- final
     * |                           |                         |
     * |       volumen normal      |       FADE OUT          |
     *
     * Y al principio:
     *
     * 0 ---------------- fadeDuration
     * |                        |
     * FADE IN                   normal
     */
    var effectiveFadeDuration = fadeDuration;

    /*
     * Si la canción es demasiado corta para tener un Fade In
     * y un Fade Out completos sin solaparlos, dividimos la canción
     * en dos mitades.
     *
     * Esto evita comportamientos imposibles como intentar hacer
     * Fade In y Fade Out al mismo tiempo con un solo reproductor.
     */
    final halfDuration = Duration(
      microseconds: currentDuration.inMicroseconds ~/ 2,
    );

    if (effectiveFadeDuration > halfDuration) {
      effectiveFadeDuration = halfDuration;
    }

    if (effectiveFadeDuration <= Duration.zero) {
      return 1.0;
    }

    /*
     * FADE IN
     *
     * Posición:
     *
     * 0s      -> 0%
     * 1s      -> 25% si T = 4
     * 2s      -> 50%
     * 3s      -> 75%
     * 4s      -> 100%
     */
    if (currentPosition < effectiveFadeDuration) {
      final progress = _linearProgress(currentPosition, effectiveFadeDuration);

      debugPrint(
        '[SONARA FADE IN] '
        'Posición: '
        '${_formatDuration(currentPosition)} | '
        'Duración: '
        '${_formatDuration(effectiveFadeDuration)} | '
        'Progreso: ${(progress * 100).toStringAsFixed(1)}% | '
        'Factor: ${progress.toStringAsFixed(3)}',
      );

      return progress.clamp(0.0, 1.0);
    }

    /*
     * FADE OUT
     *
     * Calculamos cuánto falta realmente.
     *
     * Si T = 4:
     *
     * quedan 4s -> 100%
     * quedan 3s -> 75%
     * quedan 2s -> 50%
     * quedan 1s -> 25%
     * quedan 0s -> 0%
     */
    final remaining = currentDuration - currentPosition;

    if (remaining <= effectiveFadeDuration) {
      final progress = _linearProgress(remaining, effectiveFadeDuration);

      debugPrint(
        '[SONARA FADE OUT] '
        'Restante: '
        '${_formatDuration(remaining)} | '
        'Duración: '
        '${_formatDuration(effectiveFadeDuration)} | '
        'Volumen: ${(progress * 100).toStringAsFixed(1)}% | '
        'Factor: ${progress.toStringAsFixed(3)}',
      );

      return progress.clamp(0.0, 1.0);
    }

    return 1.0;
  }

  double _linearProgress(Duration elapsed, Duration total) {
    if (total <= Duration.zero) {
      return 1.0;
    }

    final progress = elapsed.inMicroseconds / total.inMicroseconds;

    return progress.clamp(0.0, 1.0).toDouble();
  }

  String _formatDuration(Duration value) {
    final milliseconds = value.inMilliseconds;

    final seconds = milliseconds / 1000.0;

    return '${seconds.toStringAsFixed(2)}s';
  }

  // VOLUMEN

  Future<void> _applyEffectiveVolume() async {
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

        Song? currentSong;

        final index = currentIndex;

        if (index != null && index >= 0 && index < _songs.length) {
          currentSong = _songs[index];
        }

        /*
         * ReplayGain + Preamp se mantienen independientes
         * del Fade.
         */
        if (Platform.isAndroid) {
          await _applyAndroidTrackGain();
        }

        final normalVolume = currentSong == null
            ? _baseVolume
            : _getEffectiveVolumeForSong(currentSong);

        /*
         * Aquí está la nueva arquitectura:
         *
         *     volumen normal × factor del Fade
         *
         * Ejemplo:
         *
         * volumen normal = 0.8
         * fade factor    = 0.50
         *
         * volumen final  = 0.4
         */
        final fadeFactor = _getFadeFactor();

        final effectiveVolume = normalVolume * fadeFactor;

        debugPrint(
          '[SONARA FADE VOLUME] '
          'Normal: ${normalVolume.toStringAsFixed(4)} | '
          'Factor: ${fadeFactor.toStringAsFixed(4)} | '
          'Final: ${effectiveVolume.toStringAsFixed(4)}',
        );

        await _player.setVolume(effectiveVolume.clamp(0.0, 1.0).toDouble());
      } while (_volumeUpdatePending);
    } finally {
      _isApplyingVolume = false;
    }
  }

  // FADE MONITOR

  void _startFadeMonitor() {
    if (_isDisposed || !_crossfadeService.enabled || _fadeMonitor != null) {
      return;
    }

    /*
     * El Timer NO controla el progreso del Fade.
     *
     * Solamente vuelve a preguntar:
     *
     * "¿Dónde está ahora mismo la canción?"
     *
     * y _getFadeFactor() calcula el volumen correspondiente.
     *
     * Esto es lo que garantiza que, incluso cuando el propio
     * reproductor repite una pista de forma nativa (LoopMode.one) y
     * la posición vuelve a 0 sin que se dispare ningún evento
     * especial, el Fade In se recalcule solo, canción por canción.
     */
    _fadeMonitor = Timer.periodic(const Duration(milliseconds: 50), (_) {
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
        _fadeUpdateInProgress) {
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

    /*
     * No reiniciamos ningún progreso.
     *
     * Simplemente recalculamos el volumen utilizando:
     *
     *     posición actual + nueva duración
     */
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

  // MODO NATIVO DE BUCLE

  /*
   * Sincroniza el LoopMode nativo del reproductor con el modo
   * "Repetir" elegido por el usuario.
   *
   * Se usa ÚNICAMENTE para "Repetir una" (LoopMode.one): así la
   * propia pista se repite de forma instantánea y sin cortes, sin
   * necesidad de volver a abrir el archivo ni esperar el evento de
   * finalización, que es justo lo que provocaba que el bucle
   * "se tardara demasiado" o, en algunas plataformas, ni siquiera
   * llegara a repetirse.
   *
   * "Repetir toda la lista" y el modo aleatorio se resuelven en
   * _handleTrackCompleted, porque ahí sí hace falta decidir CUÁL es
   * la siguiente canción (la primera de la lista, o una al azar).
   */
  Future<void> _syncNativeLoopMode() async {
    if (_isDisposed) {
      return;
    }

    final mode = _repeatMode == 1 ? LoopMode.one : LoopMode.off;

    try {
      await _player.setLoopMode(mode);
    } catch (error) {
      debugPrint(
        '[SONARA PLAYER] '
        'No se pudo aplicar LoopMode: $error',
      );
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

    // Mantiene sincronizado el LoopMode nativo con la lista recién
    // cargada (ver _syncNativeLoopMode).
    unawaited(_syncNativeLoopMode());

    _updateTrackGain(_songs[safeIndex]);

    /*
     * Como la posición es 0, esto establece correctamente
     * el comienzo del Fade In.
     */
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

    /*
     * Primero cambiamos la pista.
     *
     * La posición será 0.
     *
     * _applyEffectiveVolume() calculará automáticamente:
     *
     *     Fade Factor = 0
     *
     * si el Fade In está activo.
     */
    await _player.seek(Duration.zero, index: index);

    _updateTrackGain(targetSong);

    if (Platform.isAndroid) {
      await _applyAndroidTrackGain();
    }

    await _applyEffectiveVolume();

    _emitCurrentState();

    final result = await _waitForDuration();

    await _player.play();

    if (_crossfadeService.enabled) {
      _startFadeMonitor();
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
    if (_isLinux) {
      _linuxLoadGeneration++;
    }

    /*
     * Ya no existe una animación de crossfade que haya que cancelar.
     *
     * El Fade se basa en la posición, por lo que cambiar de pista
     * o hacer seek simplemente provoca un nuevo cálculo.
     */
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

      if (Platform.isAndroid) {
        await _applyAndroidTrackGain();
      }

      /*
       * Esto es importante al reanudar.
       *
       * Si la canción está en el segundo 2 de un Fade In de 4s,
       * volverá exactamente al 50%.
       *
       * Si está en el segundo 198 de una canción de 200s con
       * Fade Out de 4s, volverá exactamente al 50%.
       */
      await _applyEffectiveVolume();
    }

    await _player.play();

    if (_crossfadeService.enabled) {
      _startFadeMonitor();
    }
  }

  Future<void> pause() async {
    _stopFadeMonitor();

    await _player.pause();
  }

  Future<void> resume() {
    return play();
  }

  Future<void> stop() async {
    _stopFadeMonitor();

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

    if (index != null && index >= 0 && index < _songs.length) {
      _updateTrackGain(_songs[index]);

      if (Platform.isAndroid) {
        await _applyAndroidTrackGain();
      }
    }

    /*
     * EL PUNTO CLAVE DEL NUEVO SISTEMA.
     *
     * Después del seek no iniciamos ninguna animación.
     *
     * Simplemente preguntamos:
     *
     * "¿En qué posición quedamos?"
     *
     * y calculamos el factor correspondiente.
     *
     * Ejemplo:
     *
     * Fade = 4s
     * Seek = 2s
     *
     * Fade In = 50%
     *
     * Seek = duración - 2s
     *
     * Fade Out = 50%
     */
    await _applyEffectiveVolume();

    if (_player.playing && _crossfadeService.enabled) {
      _startFadeMonitor();
    }
  }

  // VOLUMEN

  Future<void> setVolume(double volume) async {
    _baseVolume = volume.clamp(0.0, 1.0).toDouble();

    /*
     * El volumen configurado por el usuario sigue siendo
     * el volumen BASE.
     *
     * El Fade se aplica encima:
     *
     * baseVolume × fadeFactor
     */
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

    // Mantiene el LoopMode nativo del reproductor sincronizado con el
    // modo "Repetir" elegido (ver _syncNativeLoopMode).
    unawaited(_syncNativeLoopMode());
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

    _stopFadeMonitor();

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

    _stopFadeMonitor();

    _crossfadeService.secondsNotifier.removeListener(_handleFadeSettingChanged);

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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'crossfade_service.dart';

@immutable
class FadeSample {
  const FadeSample({
    required this.position,
    required this.duration,
    required this.playing,
    required this.isTransitioning,
  });

  final Duration position;
  final Duration? duration;
  final bool playing;
  final bool isTransitioning;
}

class PlaybackFadeLayer {
  PlaybackFadeLayer({
    required CrossfadeService settings,
    required FadeSample Function() sampler,
    required VoidCallback onGainChanged,
  }) : _settings = settings,
       _sampler = sampler,
       _onGainChanged = onGainChanged {
    _settings.secondsNotifier.addListener(_handleSettingsChanged);
  }

  static const Duration tickInterval = Duration(milliseconds: 40);
  static const Duration _wrapThreshold = Duration(seconds: 1);
  static const double _epsilon = 0.002;

  /// El fade-out llega a 0 este tiempo ANTES del final de la pista. Compensa
  /// la latencia de salida (~330 ms en este dispositivo) y el retraso del
  /// evento de cambio de pista, para que el cambio nativo ocurra en silencio.
  static const Duration _tailSilence = Duration(milliseconds: 500);

  final CrossfadeService _settings;
  final FadeSample Function() _sampler;
  final VoidCallback _onGainChanged;

  double _gain = 1.0;
  bool _playing = false;
  bool _disposed = false;
  Timer? _ticker;

  // Reloj propio del fade-in: posición de la pista cuando arrancó + tiempo
  // transcurrido sonando. No lo afectan las correcciones de player.position.
  final Stopwatch _clock = Stopwatch();
  Duration _clockBase = Duration.zero;
  Duration _lastPosition = Duration.zero;

  Duration get _fadeInPosition => _clockBase + _clock.elapsed;

  double get gain => _gain;

  bool get enabled => _settings.enabled;

  static double gainFor({
    required Duration position,
    required Duration? duration,
    required Duration fade,
    Duration? fadeInPosition,
  }) {
    if (fade <= Duration.zero) {
      return 1.0;
    }

    final pos = position.isNegative ? Duration.zero : position;
    final total = duration;
    final hasDuration = total != null && total > Duration.zero;

    var window = fade;

    if (hasDuration) {
      final half = Duration(microseconds: total.inMicroseconds ~/ 2);

      if (window > half) {
        window = half;
      }
    }

    if (window <= Duration.zero) {
      return 1.0;
    }

    final fadeIn = _progress(fadeInPosition ?? pos, window);

    if (!hasDuration) {
      return fadeIn;
    }

    final fadeOut = _progress(total - pos - _tailSilence, window);

    return math.min(fadeIn, fadeOut);
  }

  static double _progress(Duration elapsed, Duration total) {
    if (total <= Duration.zero) {
      return 1.0;
    }

    final value = elapsed.inMicroseconds / total.inMicroseconds;

    return value.clamp(0.0, 1.0).toDouble();
  }

  double _compute(Duration position, Duration? duration) {
    if (!_settings.enabled) {
      return 1.0;
    }

    return gainFor(
      position: position,
      fadeInPosition: _fadeInPosition,
      duration: duration,
      fade: _settings.duration,
    );
  }

  void _restartClock(Duration from) {
    _clockBase = from.isNegative ? Duration.zero : from;

    _clock
      ..stop()
      ..reset();

    if (_playing) {
      _clock.start();
    }
  }

  void setPlaying(bool playing) {
    if (_playing == playing) {
      return;
    }

    _playing = playing;

    if (playing) {
      _clock.start();
    } else {
      _clock.stop();
    }

    _syncTicker();
  }

  void resync({Duration? position}) {
    if (_disposed) {
      return;
    }

    final sample = _sampler();

    final pos = position ?? sample.position;

    _restartClock(pos);

    _lastPosition = _clockBase;

    _apply(_compute(pos, sample.duration), notify: false);
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _clock.stop();

    _ticker?.cancel();

    _ticker = null;

    _settings.secondsNotifier.removeListener(_handleSettingsChanged);
  }

  void _handleSettingsChanged() {
    if (_disposed) {
      return;
    }

    _syncTicker();

    final sample = _sampler();

    _apply(_compute(sample.position, sample.duration), notify: true);
  }

  void _syncTicker() {
    final shouldRun = !_disposed && _playing && _settings.enabled;

    if (shouldRun) {
      _ticker ??= Timer.periodic(tickInterval, (_) => _tick());
    } else {
      _ticker?.cancel();

      _ticker = null;
    }
  }

  void _tick() {
    if (_disposed) {
      return;
    }

    final sample = _sampler();

    if (sample.isTransitioning || !sample.playing) {
      return;
    }

    final position = sample.position;

    // Salto grande hacia atrás sin resync (loop nativo, cambio nativo de
    // pista): es una pista/vuelta nueva, el fade-in empieza de nuevo.
    // Las correcciones pequeñas de just_audio (~0.3 s) NO cuentan.
    if (position + _wrapThreshold < _lastPosition) {
      _restartClock(position);
    }

    _lastPosition = position;

    _apply(_compute(position, sample.duration), notify: true);
  }

  void _apply(double value, {required bool notify}) {
    final reachedLimit = value != _gain && (value == 0.0 || value == 1.0);

    if ((value - _gain).abs() < _epsilon && !reachedLimit) {
      return;
    }

    _gain = value;

    if (notify) {
      _onGainChanged();
    }
  }
}

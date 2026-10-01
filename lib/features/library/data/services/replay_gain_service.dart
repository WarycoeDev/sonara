import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'android_music_service.dart';

// REPLAYGAIN POR PISTA
//
// Calcula la ganancia de sonoridad de una pista (objetivo: -18 LUFS).
//
// Android:
// - Delega el análisis al código nativo (ReplayGainCalculator.kt), que
//   analiza una ventana de 15 s con un pool de hilos.
//
// Linux/Desktop:
// - ffmpeg + ebur128 sobre una ventana de 15 s (no la pista completa).
//
// Para bibliotecas grandes usa [calculateTrackGains]: lanza varias pistas en
// paralelo. El resultado se guarda después en Song.volumeGain; no vuelvas a
// calcular las canciones que ya tengan volumeGain.

class ReplayGainService {
  ReplayGainService({AndroidMusicService? androidMusicService})
    : _androidMusicService = androidMusicService ?? AndroidMusicService();

  final AndroidMusicService _androidMusicService;

  // ============================================================
  // CONFIGURACIÓN
  // ============================================================

  static const double targetLoudnessLufs = -18.0;

  static const double _minValidGainDb = -30.0;
  static const double _maxValidGainDb = 30.0;

  // Debe coincidir con ANALYSIS_SECONDS en el código nativo.
  static const double _analysisSeconds = 15.0;

  static const Duration _androidTimeout = Duration(seconds: 30);

  static final RegExp _integratedLoudnessPattern = RegExp(
    r'I:\s*(-?\d+(?:\.\d+)?)\s*LUFS',
  );

  // Evita calcular dos veces la misma ruta a la vez.
  final Map<String, Future<double?>> _inFlight = <String, Future<double?>>{};

  static int get _defaultConcurrency {
    if (Platform.isAndroid) {
      // El pool nativo limita el paralelismo real; las demás peticiones
      // esperan en su cola sin bloquear nada.
      return 8;
    }

    return math.max(2, math.min(8, Platform.numberOfProcessors ~/ 2));
  }

  // ============================================================
  // CALCULAR GANANCIA (UNA PISTA)
  // ============================================================

  Future<double?> calculateTrackGain(String filePath) {
    return _inFlight.putIfAbsent(filePath, () {
      return _calculate(filePath).whenComplete(() {
        _inFlight.remove(filePath);
      });
    });
  }

  Future<double?> _calculate(String filePath) async {
    try {
      final double? gain = Platform.isAndroid
          ? await _androidMusicService
                .calculateTrackGain(filePath)
                .timeout(_androidTimeout)
          : await _calculateViaFfmpeg(filePath);

      return _sanitize(gain);
    } catch (error) {
      _log('Error calculando ganancia de "$filePath": $error');

      return null;
    }
  }

  // ============================================================
  // CALCULAR GANANCIA (VARIAS PISTAS, EN PARALELO)
  // ============================================================

  /// Calcula varias pistas con [concurrency] trabajos simultáneos.
  ///
  /// [onResult] se llama en cuanto termina cada pista, útil para guardar el
  /// resultado en la base de datos de forma incremental.
  Future<Map<String, double?>> calculateTrackGains(
    Iterable<String> filePaths, {
    int? concurrency,
    void Function(String filePath, double? gain)? onResult,
    void Function(int completed, int total)? onProgress,
  }) async {
    final List<String> paths = filePaths.toSet().toList();
    final Map<String, double?> results = <String, double?>{};

    if (paths.isEmpty) {
      return results;
    }

    final int workers = math.max(
      1,
      math.min(concurrency ?? _defaultConcurrency, paths.length),
    );

    int nextIndex = 0;
    int completed = 0;

    Future<void> worker() async {
      while (true) {
        final int index = nextIndex++;

        if (index >= paths.length) {
          return;
        }

        final String path = paths[index];
        final double? gain = await calculateTrackGain(path);

        results[path] = gain;
        completed++;

        onResult?.call(path, gain);
        onProgress?.call(completed, paths.length);
      }
    }

    await Future.wait(<Future<void>>[
      for (int i = 0; i < workers; i++) worker(),
    ]);

    return results;
  }

  // ============================================================
  // FFMPEG
  // ============================================================

  Future<double?> _calculateViaFfmpeg(String filePath) async {
    if (!await File(filePath).exists()) {
      _log('El archivo no existe: "$filePath".');

      return null;
    }

    try {
      final double startSeconds = await _pickStartSeconds(filePath);

      final ProcessResult process = await Process.run(
        'ffmpeg',
        <String>[
          '-hide_banner',
          '-nostdin',
          '-nostats',
          '-v',
          'info',
          // Seek rápido (antes de -i) y solo 15 s de audio.
          '-ss',
          startSeconds.toStringAsFixed(3),
          '-t',
          _analysisSeconds.toStringAsFixed(1),
          '-i',
          filePath,
          // Ignorar carátulas, subtítulos y datos.
          '-vn',
          '-sn',
          '-dn',
          // framelog=quiet: solo el resumen final, sin una línea por frame.
          '-af',
          'ebur128=framelog=quiet',
          '-f',
          'null',
          '-',
        ],
        // latin1 nunca falla al decodificar; el patrón es ASCII.
        stdoutEncoding: latin1,
        stderrEncoding: latin1,
      );

      final String output = '${process.stdout}\n${process.stderr}';

      final double? integratedLoudness = _parseIntegratedLoudness(output);

      if (integratedLoudness == null) {
        _log('No se pudo leer la sonoridad de "$filePath".');

        return null;
      }

      return targetLoudnessLufs - integratedLoudness;
    } on ProcessException catch (error) {
      _log('ffmpeg no está disponible en este sistema: ${error.message}');

      return null;
    } catch (error) {
      _log('Error ejecutando ffmpeg para "$filePath": $error');

      return null;
    }
  }

  /// Centra la ventana en la pista usando ffprobe. Si no hay ffprobe,
  /// analiza desde el inicio.
  Future<double> _pickStartSeconds(String filePath) async {
    try {
      final ProcessResult probe = await Process.run(
        'ffprobe',
        <String>[
          '-v',
          'error',
          '-show_entries',
          'format=duration',
          '-of',
          'default=noprint_wrappers=1:nokey=1',
          filePath,
        ],
        stdoutEncoding: latin1,
        stderrEncoding: latin1,
      );

      final double? duration = double.tryParse(probe.stdout.toString().trim());

      if (duration == null || duration <= _analysisSeconds) {
        return 0;
      }

      return (duration - _analysisSeconds) / 2;
    } catch (_) {
      return 0;
    }
  }

  // ============================================================
  // PARSEAR LUFS
  // ============================================================

  double? _parseIntegratedLoudness(String ffmpegOutput) {
    final List<RegExpMatch> matches = _integratedLoudnessPattern
        .allMatches(ffmpegOutput)
        .toList();

    if (matches.isEmpty) {
      return null;
    }

    final String? value = matches.last.group(1);

    if (value == null) {
      return null;
    }

    return double.tryParse(value);
  }

  // ============================================================
  // VALIDAR
  // ============================================================

  double? _sanitize(double? gainDb) {
    if (gainDb == null || gainDb.isNaN || gainDb.isInfinite) {
      return null;
    }

    if (gainDb < _minValidGainDb || gainDb > _maxValidGainDb) {
      _log(
        'Ganancia fuera del rango esperado: '
        '${gainDb.toStringAsFixed(2)} dB. Se aplicará clamp.',
      );
    }

    return gainDb.clamp(_minValidGainDb, _maxValidGainDb).toDouble();
  }

  void _log(String message) {
    developer.log(message, name: 'SONARA REPLAYGAIN');
  }
}

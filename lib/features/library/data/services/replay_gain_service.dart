import 'dart:io';

import 'android_music_service.dart';

// REPLAYGAIN POR PISTA
// Calcula la ganancia de sonoridad de una pista.
// Android:
// - Delega el cálculo al código nativo.
// Linux/Desktop:
// - Usa ffmpeg + filtro ebur128.
// El resultado se guarda posteriormente en Song.volumeGain.

class ReplayGainService {
  ReplayGainService({AndroidMusicService? androidMusicService})
    : _androidMusicService = androidMusicService ?? AndroidMusicService();

  final AndroidMusicService _androidMusicService;

  // CONFIGURACIÓN

  /// Objetivo de sonoridad utilizado por Sonara.
  static const double _targetLoudnessLufs = -18.0;

  /// Límites de seguridad.
  static const double _minValidGainDb = -30.0;
  static const double _maxValidGainDb = 30.0;

  static final RegExp _integratedLoudnessPattern = RegExp(
    r'I:\s*(-?\d+(?:\.\d+)?)\s*LUFS',
  );

  // CALCULAR GANANCIA

  Future<double?> calculateTrackGain(String filePath) async {
    try {
      if (Platform.isAndroid) {
        final gain = await _androidMusicService.calculateTrackGain(filePath);

        return _sanitize(gain);
      }

      final gain = await _calculateViaFfmpeg(filePath);

      return _sanitize(gain);
    } catch (error) {
      print(
        '[SONARA REPLAYGAIN] '
        'Error calculando ganancia de "$filePath": '
        '$error',
      );

      return null;
    }
  }

  // FFMPEG

  Future<double?> _calculateViaFfmpeg(String filePath) async {
    final file = File(filePath);

    if (!await file.exists()) {
      print(
        '[SONARA REPLAYGAIN] '
        'El archivo no existe: "$filePath".',
      );

      return null;
    }

    try {
      final process = await Process.run('ffmpeg', <String>[
        '-hide_banner',
        '-nostdin',
        '-nostats',
        '-v',
        'info',
        '-i',
        filePath,
        '-af',
        'ebur128=framelog=verbose',
        '-f',
        'null',
        '-',
      ]);

      final output =
          '${process.stdout}\n'
          '${process.stderr}';

      final integratedLoudness = _parseIntegratedLoudness(output);

      if (integratedLoudness == null) {
        print(
          '[SONARA REPLAYGAIN] '
          'No se pudo leer la sonoridad de '
          '"$filePath".',
        );

        return null;
      }

      return _targetLoudnessLufs - integratedLoudness;
    } on ProcessException catch (error) {
      print(
        '[SONARA REPLAYGAIN] '
        'ffmpeg no está disponible en este sistema: '
        '${error.message}',
      );

      return null;
    } catch (error) {
      print(
        '[SONARA REPLAYGAIN] '
        'Error ejecutando ffmpeg para '
        '"$filePath": '
        '$error',
      );

      return null;
    }
  }

  // PARSEAR LUFS

  double? _parseIntegratedLoudness(String ffmpegOutput) {
    final matches = _integratedLoudnessPattern
        .allMatches(ffmpegOutput)
        .toList();

    if (matches.isEmpty) {
      return null;
    }

    // ffmpeg puede mostrar varios valores I durante el procesamiento.
    //
    // El último valor corresponde al resultado integrado final.
    final value = matches.last.group(1);

    if (value == null) {
      return null;
    }

    return double.tryParse(value);
  }

  // VALIDAR

  double? _sanitize(double? gainDb) {
    if (gainDb == null || gainDb.isNaN || gainDb.isInfinite) {
      return null;
    }

    return gainDb.clamp(_minValidGainDb, _maxValidGainDb).toDouble();
  }
}

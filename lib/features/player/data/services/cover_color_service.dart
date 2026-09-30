import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../library/domain/models/song.dart';

/// Lee carátulas `content://` de Android una sola vez y las comparte.
class ArtworkBytesLoader {
  static const MethodChannel _channel = MethodChannel('sonara/media_store');
  static const int _maxEntries = 24;

  static final Map<String, Uint8List> _resolved = <String, Uint8List>{};
  static final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};

  static Uint8List? peek(String uri) {
    final bytes = _resolved.remove(uri);

    if (bytes != null) {
      _resolved[uri] = bytes;
    }

    return bytes;
  }

  static Future<Uint8List?> load(String uri) {
    final cached = peek(uri);

    if (cached != null) {
      return Future<Uint8List?>.value(cached);
    }

    return _inFlight.putIfAbsent(uri, () => _read(uri));
  }

  static Future<Uint8List?> _read(String uri) async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'readContentUri',
        <String, dynamic>{'uri': uri},
      );

      Uint8List? bytes;

      if (result is Uint8List) {
        bytes = result;
      } else if (result is List) {
        bytes = Uint8List.fromList(result.cast<int>());
      }

      if (bytes != null && bytes.isNotEmpty) {
        _resolved[uri] = bytes;

        if (_resolved.length > _maxEntries) {
          _resolved.remove(_resolved.keys.first);
        }
      }

      return bytes;
    } catch (_) {
      return null;
    } finally {
      _inFlight.remove(uri);
    }
  }
}

/// Color dominante de la carátula de una canción, con caché LRU compartida
/// entre el fondo del player y el color de acento de la app.
class CoverColorService {
  CoverColorService._();

  static final CoverColorService instance = CoverColorService._();

  static const int _maxEntries = 60;

  final Map<String, Color> _cache = <String, Color>{};
  final Map<String, Future<Color?>> _inFlight = <String, Future<Color?>>{};

  /// Clave que cambia cuando cambia la carátula de la canción.
  static String keyFor(Song song) {
    return '${song.id}|${song.coverPath ?? ''}|${song.fileLastModified ?? 0}|'
        '${song.coverBytes?.length ?? 0}';
  }

  /// Devuelve el color si ya está calculado (sin esperar nada).
  Color? peek(Song song) {
    final key = keyFor(song);
    final color = _cache.remove(key);

    if (color != null) {
      _cache[key] = color;
    }

    return color;
  }

  Future<Color?> seedFor(Song song) {
    final key = keyFor(song);
    final cached = peek(song);

    if (cached != null) {
      return Future<Color?>.value(cached);
    }

    return _inFlight.putIfAbsent(key, () => _compute(song, key));
  }

  Future<Color?> _compute(Song song, String key) async {
    try {
      final seed = await CoverColorExtractor.extract(song);

      if (seed != null) {
        if (_cache.length >= _maxEntries) {
          _cache.remove(_cache.keys.first);
        }

        _cache[key] = seed;
      }

      return seed;
    } catch (_) {
      return null;
    } finally {
      _inFlight.remove(key);
    }
  }
}

/// Saca un color dominante de la carátula de forma barata: decodifica la
/// imagen a 24x24 y promedia los tonos más vivos.
class CoverColorExtractor {
  static const int _sampleSize = 24;
  static const int _hueBuckets = 12;

  static Future<Color?> extract(Song song) async {
    final bytes = await _loadBytes(song);

    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    ui.Codec? codec;
    ui.Image? image;

    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _sampleSize,
        targetHeight: _sampleSize,
      );

      final frame = await codec.getNextFrame();
      image = frame.image;

      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (data == null) {
        return null;
      }

      return _dominantColor(data);
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static Future<Uint8List?> _loadBytes(Song song) async {
    final bytes = song.coverBytes;

    if (bytes != null && bytes.isNotEmpty) {
      return bytes;
    }

    final path = song.coverPath;

    if (path == null || path.isEmpty) {
      return null;
    }

    if (path.startsWith('content://')) {
      return ArtworkBytesLoader.load(path);
    }

    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Color? _dominantColor(ByteData data) {
    final weights = List<double>.filled(_hueBuckets, 0);
    final reds = List<double>.filled(_hueBuckets, 0);
    final greens = List<double>.filled(_hueBuckets, 0);
    final blues = List<double>.filled(_hueBuckets, 0);

    double totalR = 0;
    double totalG = 0;
    double totalB = 0;
    var count = 0;

    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      if (data.getUint8(i + 3) < 128) {
        continue;
      }

      final r = data.getUint8(i);
      final g = data.getUint8(i + 1);
      final b = data.getUint8(i + 2);

      totalR += r;
      totalG += g;
      totalB += b;
      count++;

      final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));

      // Ignora grises y casi negros: no aportan "color".
      if (hsv.saturation < 0.2 || hsv.value < 0.2) {
        continue;
      }

      final bucket = math.min(_hueBuckets - 1, hsv.hue ~/ (360 / _hueBuckets));
      final weight = hsv.saturation * hsv.value;

      weights[bucket] += weight;
      reds[bucket] += r * weight;
      greens[bucket] += g * weight;
      blues[bucket] += b * weight;
    }

    if (count == 0) {
      return null;
    }

    var best = 0;

    for (var i = 1; i < _hueBuckets; i++) {
      if (weights[i] > weights[best]) {
        best = i;
      }
    }

    // Carátula casi en escala de grises: usa el promedio general.
    if (weights[best] < count * 0.03) {
      return Color.fromARGB(
        255,
        (totalR / count).round(),
        (totalG / count).round(),
        (totalB / count).round(),
      );
    }

    final w = weights[best];

    return Color.fromARGB(
      255,
      (reds[best] / w).round(),
      (greens[best] / w).round(),
      (blues[best] / w).round(),
    );
  }
}

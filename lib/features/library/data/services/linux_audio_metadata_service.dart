import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LinuxAudioMetadata {
  final String? artist;
  final String? album;
  final Duration duration;
  final String? coverPath;

  const LinuxAudioMetadata({
    this.artist,
    this.album,
    required this.duration,
    this.coverPath,
  });
}

class LinuxAudioMetadataService {
  Future<LinuxAudioMetadata> readMetadata(
    String filePath, {
    int? fileSize,
    int? fileLastModified,
  }) async {
    try {
      final result = await Process.run('ffprobe', [
        '-v',
        'quiet',
        '-print_format',
        'json',
        '-show_format',
        '-show_streams',
        filePath,
      ]);

      if (result.exitCode != 0) {
        print(
          '[SONARA COVER] '
          'ffprobe fallo para: $filePath',
        );

        print(
          '[SONARA COVER] '
          'stderr: ${result.stderr}',
        );

        return const LinuxAudioMetadata(duration: Duration.zero);
      }

      final output =
          jsonDecode(result.stdout.toString()) as Map<String, dynamic>;

      final format = output['format'] as Map<String, dynamic>?;

      if (format == null) {
        return const LinuxAudioMetadata(duration: Duration.zero);
      }

      final tags = format['tags'] as Map<String, dynamic>?;

      final artist = tags?['artist']?.toString();

      final album = tags?['album']?.toString();

      final durationValue =
          double.tryParse(format['duration']?.toString() ?? '0') ?? 0;

      final duration = Duration(milliseconds: (durationValue * 1000).round());

      final coverPath = await _extractCover(
        filePath,
        fileSize: fileSize,
        fileLastModified: fileLastModified,
      );

      print('[SONARA COVER] $filePath');

      print(
        '[SONARA COVER] '
        'portada: $coverPath',
      );

      return LinuxAudioMetadata(
        artist: artist,
        album: album,
        duration: duration,
        coverPath: coverPath,
      );
    } catch (error) {
      print(
        '[SONARA COVER] '
        'Error leyendo metadata de $filePath',
      );

      print(
        '[SONARA COVER] '
        '$error',
      );

      return const LinuxAudioMetadata(duration: Duration.zero);
    }
  }

  Future<String?> _extractCover(
    String filePath, {
    int? fileSize,
    int? fileLastModified,
  }) async {
    try {
      final audioFile = File(filePath);

      if (!await audioFile.exists()) {
        print(
          '[SONARA COVER] '
          'El archivo no existe: $filePath',
        );

        return null;
      }

      final supportDirectory = await getTemporaryDirectory();

      final artworkDirectory = Directory(
        '${supportDirectory.path}'
        '${Platform.pathSeparator}'
        'sonara'
        '${Platform.pathSeparator}'
        'artwork',
      );

      if (!await artworkDirectory.exists()) {
        await artworkDirectory.create(recursive: true);
      }

      final actualSize = fileSize ?? await audioFile.length();

      final actualModified =
          fileLastModified ??
          (await audioFile.stat()).modified.millisecondsSinceEpoch;

      final pathHash = _simpleHash(filePath);

      final cacheKey = '${pathHash}_${actualSize}_$actualModified';

      final coverPath =
          '${artworkDirectory.path}'
          '${Platform.pathSeparator}'
          '$cacheKey.sonara-cover.jpg';

      final coverFile = File(coverPath);

      // =======================================================================
      // CACHE VÁLIDO
      // =======================================================================

      if (await coverFile.exists()) {
        final length = await coverFile.length();

        if (length > 0) {
          print(
            '[SONARA COVER] '
            'Usando portada cacheada: '
            '$coverPath',
          );

          return coverPath;
        }

        try {
          await coverFile.delete();
        } catch (_) {}
      }

      // =======================================================================
      // EXTRAER NUEVA CARÁTULA
      // =======================================================================

      print(
        '[SONARA COVER] '
        'Extrayendo nueva portada: '
        '$filePath',
      );

      final result = await Process.run('ffmpeg', [
        '-y',
        '-i',
        filePath,
        '-map',
        '0:v:0',
        '-frames:v',
        '1',
        '-c:v',
        'mjpeg',
        '-q:v',
        '2',
        coverPath,
      ]);

      if (result.exitCode != 0) {
        print(
          '[SONARA COVER] '
          'ffmpeg fallo para: $filePath',
        );

        print(
          '[SONARA COVER] '
          'stderr:',
        );

        print(result.stderr);

        return null;
      }

      if (!await coverFile.exists()) {
        print(
          '[SONARA COVER] '
          'ffmpeg terminó correctamente, '
          'pero no creó la portada.',
        );

        return null;
      }

      final length = await coverFile.length();

      if (length <= 0) {
        try {
          await coverFile.delete();
        } catch (_) {}

        return null;
      }

      print(
        '[SONARA COVER] '
        'Portada creada: $coverPath',
      );

      // Limpieza de versiones anteriores del mismo archivo.
      await _removeOldVersions(artworkDirectory, pathHash, coverFile);

      return coverPath;
    } catch (error) {
      print(
        '[SONARA COVER] '
        'Error extrayendo portada: $error',
      );

      return null;
    }
  }

  Future<void> _removeOldVersions(
    Directory artworkDirectory,
    String pathHash,
    File currentCover,
  ) async {
    try {
      await for (final entity in artworkDirectory.list()) {
        if (entity is! File) {
          continue;
        }

        if (entity.path == currentCover.path) {
          continue;
        }

        final fileName = entity.uri.pathSegments.last;

        if (!fileName.startsWith('${pathHash}_')) {
          continue;
        }

        try {
          await entity.delete();

          print(
            '[SONARA COVER CACHE] '
            'Versión anterior eliminada: '
            '${entity.path}',
          );
        } catch (_) {}
      }
    } catch (error) {
      print(
        '[SONARA COVER CACHE] '
        'No se pudieron limpiar versiones antiguas: '
        '$error',
      );
    }
  }

  String _simpleHash(String value) {
    var hash = 0x811c9dc5;

    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;

      hash = (hash * 0x01000193) & 0xffffffff;
    }

    return hash.toRadixString(16);
  }
}

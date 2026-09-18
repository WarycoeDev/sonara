import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class AndroidArtworkService {
  Future<String?> extractCover({
    required String filePath,
    required String songId,
  }) async {
    try {
      final audioFile = File(filePath);

      if (!await audioFile.exists()) {
        print(
          '[SONARA ANDROID COVER] '
          'El archivo no existe: $filePath',
        );

        return null;
      }

      // =======================================================================
      // DIRECTORIO PERSISTENTE
      // =======================================================================

      final supportDirectory = await getApplicationSupportDirectory();

      final artworkDirectory = Directory(
        '${supportDirectory.path}'
        '${Platform.pathSeparator}'
        'sonara_artwork',
      );

      if (!await artworkDirectory.exists()) {
        await artworkDirectory.create(recursive: true);
      }

      final safeSongId = _sanitizeFileName(songId);

      final coverPath =
          '${artworkDirectory.path}'
          '${Platform.pathSeparator}'
          '$safeSongId.sonara-cover.jpg';

      final coverFile = File(coverPath);

      // =======================================================================
      // REUTILIZAR PORTADA EXISTENTE
      // =======================================================================

      if (await coverFile.exists()) {
        final length = await coverFile.length();

        if (length > 0) {
          return coverPath;
        }

        try {
          await coverFile.delete();
        } catch (_) {}
      }

      // =======================================================================
      // EXTRAER
      // =======================================================================

      print(
        '[SONARA ANDROID COVER] '
        'Extrayendo portada: $filePath',
      );

      final command = [
        '-y',
        '-i',
        _quoteArgument(filePath),
        '-map',
        '0:v:0',
        '-frames:v',
        '1',
        '-c:v',
        'mjpeg',
        '-q:v',
        '2',
        _quoteArgument(coverPath),
      ].join(' ');

      final session = await FFmpegKit.execute(command);

      final returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode)) {
        print(
          '[SONARA ANDROID COVER] '
          'FFmpeg no pudo extraer la portada.',
        );

        return null;
      }

      if (!await coverFile.exists()) {
        return null;
      }

      final length = await coverFile.length();

      if (length <= 0) {
        try {
          await coverFile.delete();
        } catch (_) {}

        return null;
      }

      return coverPath;
    } catch (error) {
      print(
        '[SONARA ANDROID COVER] '
        'Error: $error',
      );

      return null;
    }
  }

  String _sanitizeFileName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

    return sanitized.isEmpty ? 'unknown' : sanitized;
  }

  String _quoteArgument(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}

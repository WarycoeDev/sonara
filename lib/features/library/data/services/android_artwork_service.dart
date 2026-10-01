import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sonara/core/services/sonara_storage_service.dart';

class AndroidArtworkService {
  Future<String?> extractCover({
    required String filePath,
    required String songId,
    int? fileSize,
    int? fileLastModified,
    bool forceRefresh = false,
  }) async {
    try {
      final audioFile = File(filePath);

      if (!await audioFile.exists()) {
        if (kDebugMode) {
          print(
            '[SONARA ANDROID COVER] '
            'El archivo no existe: $filePath',
          );
        }

        return null;
      }

      // ========================================================
      // DIRECTORIO DE CACHÉ
      // ========================================================

      final artworkDirectory =
          await SonaraStorageService.getArtworkCacheDirectory();

      // ========================================================
      // DATOS DEL ARCHIVO
      // ========================================================

      final actualSize = fileSize ?? await audioFile.length();

      final actualModified =
          fileLastModified ??
          (await audioFile.stat()).modified.millisecondsSinceEpoch;

      // ========================================================
      // CACHÉ VERSIONADO
      // ========================================================

      final songHash = _simpleHash(songId);

      final cacheKey = '${songHash}_${actualSize}_$actualModified';

      final coverPath = p.join(
        artworkDirectory.path,
        '$cacheKey.sonara-cover.jpg',
      );

      final coverFile = File(coverPath);

      // ========================================================
      // USAR CACHÉ EXISTENTE
      // ========================================================

      if (!forceRefresh && await coverFile.exists()) {
        final length = await coverFile.length();

        if (length > 0) {
          if (kDebugMode) {
            print(
              '[SONARA ANDROID COVER] '
              'Usando portada cacheada: '
              '$coverPath',
            );
          }

          return coverPath;
        }
      }

      // ========================================================
      // SI forceRefresh, ELIMINAR VERSIÓN ACTUAL
      // ========================================================

      if (forceRefresh) {
        try {
          if (await coverFile.exists()) {
            await coverFile.delete();

            if (kDebugMode) {
              print(
                '[SONARA ANDROID COVER CACHE] '
                'Versión actual eliminada: '
                '$coverPath',
              );
            }
          }
        } catch (_) {}
      }

      // ========================================================
      // EXTRAER PORTADA
      // ========================================================

      if (kDebugMode) {
        print(
          '[SONARA ANDROID COVER] '
          'Extrayendo nueva portada: '
          '$filePath',
        );
      }

      final arguments = [
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
      ];

      final session = await FFmpegKit.executeWithArguments(arguments);

      final returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode)) {
        if (kDebugMode) {
          print(
            '[SONARA ANDROID COVER] '
            'FFmpeg no pudo extraer la portada.',
          );
        }

        return null;
      }

      // ========================================================
      // VALIDAR ARCHIVO
      // ========================================================

      if (!await coverFile.exists()) {
        if (kDebugMode) {
          print(
            '[SONARA ANDROID COVER] '
            'FFmpeg terminó correctamente, '
            'pero no creó la portada.',
          );
        }

        return null;
      }

      final length = await coverFile.length();

      if (length <= 0) {
        try {
          await coverFile.delete();
        } catch (_) {}

        return null;
      }

      if (kDebugMode) {
        print(
          '[SONARA ANDROID COVER] '
          'Portada creada: $coverPath',
        );
      }

      // ========================================================
      // LIMPIAR VERSIONES ANTERIORES
      // ========================================================

      await _removeOldVersions(artworkDirectory, songHash, coverFile);

      return coverPath;
    } catch (error) {
      if (kDebugMode) {
        print(
          '[SONARA ANDROID COVER] '
          'Error extrayendo portada: '
          '$error',
        );
      }

      return null;
    }
  }

  // ============================================================
  // ELIMINAR VERSIONES ANTERIORES
  // ============================================================

  Future<void> _removeOldVersions(
    Directory artworkDirectory,
    String songHash,
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

        final fileName = p.basename(entity.path);

        if (!fileName.startsWith('${songHash}_')) {
          continue;
        }

        try {
          await entity.delete();

          if (kDebugMode) {
            print(
              '[SONARA ANDROID COVER CACHE] '
              'Versión anterior eliminada: '
              '${entity.path}',
            );
          }
        } catch (_) {}
      }
    } catch (error) {
      if (kDebugMode) {
        print(
          '[SONARA ANDROID COVER CACHE] '
          'No se pudieron limpiar versiones antiguas: '
          '$error',
        );
      }
    }
  }

  // ============================================================
  // HASH
  // ============================================================

  String _simpleHash(String value) {
    var hash = 0x811c9dc5;

    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;

      hash = (hash * 0x01000193) & 0xffffffff;
    }

    return hash.toRadixString(16);
  }
}

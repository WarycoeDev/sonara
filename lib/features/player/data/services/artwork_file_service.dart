import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';

class ArtworkFileService {
  static const MethodChannel _musicChannel = MethodChannel('com.sonara/music');
  // =====================================
  //
  // ======================================
  // GUARDAR CARÁTULA COMO ARCHIVO
  // ===========================================================================

  Future<bool> saveArtwork({
    required String sourcePath,
    required String suggestedFileName,
  }) async {
    try {
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) {
        print(
          '[SONARA ARTWORK SAVE] '
          'La carátula de origen no existe: $sourcePath',
        );

        return false;
      }

      final fileLength = await sourceFile.length();

      if (fileLength <= 0) {
        print(
          '[SONARA ARTWORK SAVE] '
          'La carátula está vacía.',
        );

        return false;
      }

      final bytes = await sourceFile.readAsBytes();

      if (bytes.isEmpty) {
        print(
          '[SONARA ARTWORK SAVE] '
          'No se pudieron leer los bytes de la carátula.',
        );

        return false;
      }

      print(
        '[SONARA ARTWORK SAVE] '
        'Abriendo selector para guardar: '
        '$suggestedFileName',
      );

      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar carátula',
        fileName: suggestedFileName,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png'],
        bytes: bytes,
      );

      if (savedPath == null || savedPath.isEmpty) {
        print(
          '[SONARA ARTWORK SAVE] '
          'El usuario canceló el guardado.',
        );

        return false;
      }

      print(
        '[SONARA ARTWORK SAVE] '
        'Carátula guardada: $savedPath',
      );

      return true;
    } catch (error, stackTrace) {
      print(
        '[SONARA ARTWORK SAVE] '
        'Error guardando carátula: $error',
      );

      print(stackTrace);

      return false;
    }
  }

  // ===========================================================================
  // ELIMINAR CARÁTULA EMBEBIDA
  // ===========================================================================

  /// Elimina la carátula incrustada dentro del archivo de audio.
  ///
  /// El audio no se recodifica.
  ///
  /// FFmpeg copia únicamente los streams de audio:
  ///
  ///   -map 0:a
  ///   -c:a copy
  ///
  /// Por lo tanto, los streams de imagen/attached picture no se copian.
  ///
  /// También se conservan:
  ///
  ///   - metadatos normales
  ///   - capítulos
  ///
  /// Y se elimina explícitamente:
  ///
  ///   METADATA_BLOCK_PICTURE
  ///
  /// para evitar conservar artwork mediante ese campo.
  Future<bool> deleteEmbeddedArtwork({required String filePath}) async {
    if (filePath.trim().isEmpty) {
      print(
        '[SONARA ARTWORK DELETE] '
        'La ruta del archivo está vacía.',
      );

      return false;
    }

    if (Platform.isAndroid) {
      return _deleteEmbeddedArtworkAndroid(filePath);
    }

    if (Platform.isLinux) {
      return _deleteEmbeddedArtworkLinux(filePath);
    }

    print(
      '[SONARA ARTWORK DELETE] '
      'Plataforma no soportada: ${Platform.operatingSystem}',
    );

    return false;
  }

  // ===========================================================================
  // ANDROID
  // ===========================================================================

  Future<bool> _deleteEmbeddedArtworkAndroid(String filePath) async {
    try {
      final sourceFile = File(filePath);

      if (!await sourceFile.exists()) {
        print(
          '[SONARA ARTWORK DELETE] '
          'Android: el archivo no existe: $filePath',
        );

        return false;
      }

      print(
        '[SONARA ARTWORK DELETE] '
        'Android: eliminando artwork de $filePath',
      );

      final temporaryPath = await _buildTemporaryPath(filePath);
      final temporaryFile = File(temporaryPath);

      await _deleteIfExists(temporaryFile);

      final command = _buildFfmpegCommand(
        sourcePath: filePath,
        destinationPath: temporaryPath,
      );

      print(
        '[SONARA ARTWORK DELETE] '
        'Android FFmpeg: $command',
      );

      final session = await FFmpegKit.execute(command);

      final returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode)) {
        print(
          '[SONARA ARTWORK DELETE] '
          'Android: FFmpeg falló al eliminar la carátula.',
        );

        final output = await session.getOutput();

        if (output != null && output.isNotEmpty) {
          print(
            '[SONARA ARTWORK DELETE] '
            'Android FFmpeg output:\n$output',
          );
        }

        await _deleteIfExists(temporaryFile);

        return false;
      }

      if (!await temporaryFile.exists()) {
        print(
          '[SONARA ARTWORK DELETE] '
          'Android: FFmpeg no creó el archivo temporal.',
        );

        return false;
      }

      final temporaryLength = await temporaryFile.length();

      if (temporaryLength <= 0) {
        print(
          '[SONARA ARTWORK DELETE] '
          'Android: el archivo temporal está vacío.',
        );

        await _deleteIfExists(temporaryFile);

        return false;
      }

      print(
        '[SONARA ARTWORK DELETE] '
        'Android: archivo temporal creado correctamente '
        '($temporaryLength bytes).',
      );

      // =====================================================================
      // IMPORTANTE:
      //
      // NO hacemos:
      //
      //   sourceFile.rename(...)
      //
      // porque Android 10+ bloquea esa operación sobre MediaStore.
      //
      // MainActivity se encargará de escribir el temporal mediante MediaStore.
      // =====================================================================

      final replaced = await _musicChannel.invokeMethod<bool>(
        'replaceMediaStoreAudio',
        <String, dynamic>{
          'sourcePath': filePath,
          'temporaryPath': temporaryPath,
        },
      );

      if (replaced != true) {
        print(
          '[SONARA ARTWORK DELETE] '
          'Android: MediaStore no pudo reemplazar el audio.',
        );

        await _deleteIfExists(temporaryFile);

        return false;
      }

      // MainActivity normalmente ya elimina el temporal después de copiarlo,
      // pero lo limpiamos también por seguridad.
      await _deleteIfExists(temporaryFile);

      print(
        '[SONARA ARTWORK DELETE] '
        'Android: artwork eliminado físicamente del audio.',
      );

      return true;
    } catch (error, stackTrace) {
      print(
        '[SONARA ARTWORK DELETE] '
        'Android: error eliminando artwork: $error',
      );

      print(stackTrace);

      return false;
    }
  }

  // ===========================================================================
  // LINUX
  // ===========================================================================

  Future<bool> _deleteEmbeddedArtworkLinux(String filePath) async {
    try {
      final sourceFile = File(filePath);

      if (!await sourceFile.exists()) {
        print(
          '[SONARA ARTWORK DELETE] '
          'Linux: el archivo no existe: $filePath',
        );

        return false;
      }

      print(
        '[SONARA ARTWORK DELETE] '
        'Linux: eliminando artwork de $filePath',
      );

      final temporaryPath = await _buildTemporaryPath(filePath);
      final temporaryFile = File(temporaryPath);

      await _deleteIfExists(temporaryFile);

      final result = await Process.run('ffmpeg', [
        '-y',
        '-i',
        filePath,

        // Solo streams de audio.
        '-map',
        '0:a',

        // Mantener metadatos normales.
        '-map_metadata',
        '0',

        // Mantener capítulos.
        '-map_chapters',
        '0',

        // No recodificar audio.
        '-c:a',
        'copy',

        // Eliminar específicamente METADATA_BLOCK_PICTURE.
        '-metadata',
        'METADATA_BLOCK_PICTURE=',

        temporaryPath,
      ]);

      if (result.exitCode != 0) {
        print(
          '[SONARA ARTWORK DELETE] '
          'Linux: FFmpeg falló.',
        );

        print(
          '[SONARA ARTWORK DELETE] '
          'stderr:\n${result.stderr}',
        );

        await _deleteIfExists(temporaryFile);

        return false;
      }

      // -----------------------------------------------------------------------
      // Comprobar archivo temporal
      // -----------------------------------------------------------------------

      if (!await temporaryFile.exists()) {
        print(
          '[SONARA ARTWORK DELETE] '
          'Linux: FFmpeg terminó pero no creó '
          'el archivo temporal.',
        );

        return false;
      }

      final temporaryLength = await temporaryFile.length();

      if (temporaryLength <= 0) {
        print(
          '[SONARA ARTWORK DELETE] '
          'Linux: el archivo temporal está vacío.',
        );

        await _deleteIfExists(temporaryFile);

        return false;
      }

      print(
        '[SONARA ARTWORK DELETE] '
        'Linux: archivo temporal creado correctamente '
        '($temporaryLength bytes).',
      );

      // -----------------------------------------------------------------------
      // Reemplazar archivo original
      // -----------------------------------------------------------------------

      final replaced = await _replaceOriginalFile(
        sourceFile: sourceFile,
        temporaryFile: temporaryFile,
      );

      if (!replaced) {
        print(
          '[SONARA ARTWORK DELETE] '
          'Linux: no se pudo reemplazar el archivo original.',
        );

        await _deleteIfExists(temporaryFile);

        return false;
      }

      print(
        '[SONARA ARTWORK DELETE] '
        'Linux: artwork eliminado correctamente.',
      );

      return true;
    } catch (error, stackTrace) {
      print(
        '[SONARA ARTWORK DELETE] '
        'Linux: error eliminando artwork: $error',
      );

      print(stackTrace);

      return false;
    }
  }

  // ===========================================================================
  // COMANDO FFMPEG
  // ===========================================================================

  String _buildFfmpegCommand({
    required String sourcePath,
    required String destinationPath,
  }) {
    return [
      '-y',

      // Archivo original.
      '-i',
      _quoteArgument(sourcePath),

      // Solo audio.
      '-map',
      '0:a',

      // Mantener metadatos normales.
      '-map_metadata',
      '0',

      // Mantener capítulos.
      '-map_chapters',
      '0',

      // Copiar audio sin recodificar.
      '-c:a',
      'copy',

      // Eliminar artwork almacenado como METADATA_BLOCK_PICTURE.
      '-metadata',
      'METADATA_BLOCK_PICTURE=',

      // Archivo de salida.
      _quoteArgument(destinationPath),
    ].join(' ');
  }

  // ===========================================================================
  // REEMPLAZAR ARCHIVO ORIGINAL
  // ===========================================================================

  Future<bool> _replaceOriginalFile({
    required File sourceFile,
    required File temporaryFile,
  }) async {
    final sourcePath = sourceFile.path;

    final backupPath = '$sourcePath.sonara-backup';

    final backupFile = File(backupPath);

    try {
      // -----------------------------------------------------------------------
      // Limpiar backup anterior
      // -----------------------------------------------------------------------

      await _deleteIfExists(backupFile);

      // -----------------------------------------------------------------------
      // Original → backup
      // -----------------------------------------------------------------------

      print(
        '[SONARA ARTWORK DELETE] '
        'Moviendo original a backup...',
      );

      await sourceFile.rename(backupPath);

      // -----------------------------------------------------------------------
      // Temporal → original
      // -----------------------------------------------------------------------

      try {
        print(
          '[SONARA ARTWORK DELETE] '
          'Colocando nuevo archivo sin artwork...',
        );

        await temporaryFile.rename(sourcePath);

        // ---------------------------------------------------------------------
        // Verificación básica
        // ---------------------------------------------------------------------

        final newFile = File(sourcePath);

        if (!await newFile.exists()) {
          throw Exception('El nuevo archivo no existe después del reemplazo.');
        }

        final newLength = await newFile.length();

        if (newLength <= 0) {
          throw Exception('El nuevo archivo está vacío después del reemplazo.');
        }

        // ---------------------------------------------------------------------
        // Todo correcto → eliminar backup
        // ---------------------------------------------------------------------

        await _deleteIfExists(backupFile);

        print(
          '[SONARA ARTWORK DELETE] '
          'Archivo reemplazado correctamente.',
        );

        return true;
      } catch (error) {
        print(
          '[SONARA ARTWORK DELETE] '
          'No se pudo colocar el archivo nuevo: $error',
        );

        // ---------------------------------------------------------------------
        // ROLLBACK
        // ---------------------------------------------------------------------

        try {
          final currentFile = File(sourcePath);

          if (await currentFile.exists()) {
            await currentFile.delete();
          }
        } catch (_) {}

        try {
          if (await backupFile.exists()) {
            await backupFile.rename(sourcePath);

            print(
              '[SONARA ARTWORK DELETE] '
              'Rollback completado correctamente.',
            );
          }
        } catch (rollbackError) {
          print(
            '[SONARA ARTWORK DELETE] '
            'ERROR CRÍTICO durante rollback: '
            '$rollbackError',
          );
        }

        return false;
      }
    } catch (error) {
      print(
        '[SONARA ARTWORK DELETE] '
        'No se pudo crear backup del archivo original: $error',
      );

      return false;
    }
  }

  // ===========================================================================
  // CREAR ARCHIVO TEMPORAL
  // ===========================================================================

  Future<String> _buildTemporaryPath(String sourcePath) async {
    final sourceFile = File(sourcePath);

    final parentDirectory = sourceFile.parent;

    // Carpeta oculta para que el escáner de Sonara no detecte
    // el archivo temporal como una canción.
    final temporaryDirectory = Directory(
      '${parentDirectory.path}'
      '${Platform.pathSeparator}'
      '.sonara_artwork',
    );

    if (!await temporaryDirectory.exists()) {
      await temporaryDirectory.create(recursive: true);
    }

    final originalName = sourceFile.uri.pathSegments.last;

    final extension = _getExtension(originalName);

    final baseName = _removeExtension(originalName, extension);

    final temporaryName = '$baseName.sonara-no-artwork$extension';

    return '${temporaryDirectory.path}'
        '${Platform.pathSeparator}'
        '$temporaryName';
  }

  // ===========================================================================
  // ELIMINAR ARCHIVO SI EXISTE
  // ===========================================================================

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  // ===========================================================================
  // EXTENSIÓN
  // ===========================================================================

  String _getExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');

    if (dotIndex <= 0 || dotIndex == fileName.length - 1) {
      return '';
    }

    return fileName.substring(dotIndex);
  }

  // ===========================================================================
  // QUITAR EXTENSIÓN
  // ===========================================================================

  String _removeExtension(String fileName, String extension) {
    if (extension.isEmpty) {
      return fileName;
    }

    return fileName.substring(0, fileName.length - extension.length);
  }

  // ===========================================================================
  // ESCAPAR ARGUMENTOS PARA FFMPEG
  // ===========================================================================

  String _quoteArgument(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}

import 'dart:io';

import 'package:file_picker/file_picker.dart';

class ArtworkFileService {
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
        'Abriendo selector para guardar: $suggestedFileName',
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
        'FilePicker devolvió: $savedPath',
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
}

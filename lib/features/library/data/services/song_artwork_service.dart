import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:id3_codec/id3_codec.dart';
import 'package:image/image.dart' as img;

class SongArtworkService {
  const SongArtworkService();

  static const MethodChannel _platform = MethodChannel('com.sonara/music');

  // =========================================================================
  // SELECCIONAR Y PREPARAR CARÁTULA
  // =========================================================================

  Future<Uint8List?> pickAndPrepareArtwork() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );

    // El usuario canceló.
    if (result == null || result.files.isEmpty) {
      return null;
    }

    final pickedFile = result.files.single;

    Uint8List? bytes = pickedFile.bytes;

    // Algunos dispositivos no entregan bytes directamente.
    if ((bytes == null || bytes.isEmpty) &&
        pickedFile.path != null &&
        pickedFile.path!.isNotEmpty) {
      final file = File(pickedFile.path!);

      if (await file.exists()) {
        bytes = await file.readAsBytes();
      }
    }

    if (bytes == null || bytes.isEmpty) {
      throw Exception('No se pudo leer la imagen seleccionada.');
    }

    return _prepareArtwork(bytes);
  }

  // =========================================================================
  // PREPARAR IMAGEN
  // =========================================================================

  Uint8List _prepareArtwork(Uint8List originalBytes) {
    final decoded = img.decodeImage(originalBytes);

    if (decoded == null) {
      throw Exception('La imagen seleccionada no es válida.');
    }

    // Primero corregimos la orientación EXIF.
    final oriented = img.bakeOrientation(decoded);

    // Después hacemos el recorte cuadrado centrado.
    final square = _cropToSquare(oriented);

    return Uint8List.fromList(img.encodeJpg(square, quality: 95));
  }

  // =========================================================================
  // RECORTE CUADRADO CENTRADO
  // =========================================================================

  img.Image _cropToSquare(img.Image source) {
    if (source.width == source.height) {
      return source;
    }

    // Horizontal:
    // se eliminan los lados.
    if (source.width > source.height) {
      final side = source.height;

      final offsetX = ((source.width - side) / 2).round();

      return img.copyCrop(source, x: offsetX, y: 0, width: side, height: side);
    }

    // Vertical:
    // se eliminan arriba y abajo.
    final side = source.width;

    final offsetY = ((source.height - side) / 2).round();

    return img.copyCrop(source, x: 0, y: offsetY, width: side, height: side);
  }

  // =========================================================================
  // CREAR MP3 MODIFICADO
  // =========================================================================

  Future<Uint8List> _createModifiedMp3Bytes({
    required String songPath,
    required Uint8List artworkBytes,
  }) async {
    final mp3File = File(songPath);

    if (!await mp3File.exists()) {
      throw Exception('No se encontró el archivo de audio.');
    }

    final originalBytes = await mp3File.readAsBytes();

    final encoder = ID3Encoder(originalBytes);

    // encodeSync() devuelve List<int>.
    // Lo convertimos explícitamente a Uint8List.
    return Uint8List.fromList(
      encoder.encodeSync(MetadataV2p3Body(imageBytes: artworkBytes)),
    );
  }

  // =========================================================================
  // ANDROID: REEMPLAZAR MEDIANTE MEDIASTORE
  // =========================================================================

  Future<void> _replaceAndroidAudio({
    required String songPath,
    required Uint8List modifiedMp3Bytes,
  }) async {
    Directory? temporaryDirectory;
    File? temporaryFile;

    try {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'sonara_artwork_',
      );

      temporaryFile = File('${temporaryDirectory.path}/modified.mp3');

      await temporaryFile.writeAsBytes(modifiedMp3Bytes, flush: true);

      final result = await _platform.invokeMethod<bool>(
        'replaceMediaStoreAudio',
        <String, dynamic>{
          'sourcePath': songPath,
          'temporaryPath': temporaryFile.path,
        },
      );

      if (result != true) {
        throw Exception('Android no pudo reemplazar el archivo de audio.');
      }
    } on PlatformException catch (error) {
      throw Exception(
        error.message ?? 'Android no pudo modificar el archivo de audio.',
      );
    } finally {
      try {
        if (temporaryFile != null && await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      } catch (_) {}

      try {
        if (temporaryDirectory != null && await temporaryDirectory.exists()) {
          await temporaryDirectory.delete();
        }
      } catch (_) {}
    }
  }

  // =========================================================================
  // CAMBIAR CARÁTULA
  // =========================================================================

  Future<Uint8List?> changeArtwork({required String songPath}) async {
    final artworkBytes = await pickAndPrepareArtwork();

    // null = usuario canceló.
    if (artworkBytes == null) {
      return null;
    }

    final modifiedMp3Bytes = await _createModifiedMp3Bytes(
      songPath: songPath,
      artworkBytes: artworkBytes,
    );

    if (Platform.isAndroid) {
      await _replaceAndroidAudio(
        songPath: songPath,
        modifiedMp3Bytes: modifiedMp3Bytes,
      );
    } else {
      // Linux / escritorio:
      // aquí sí podemos modificar directamente el archivo.
      final mp3File = File(songPath);

      await mp3File.writeAsBytes(modifiedMp3Bytes, flush: true);
    }

    return artworkBytes;
  }
}

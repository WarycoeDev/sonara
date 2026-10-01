import 'dart:io';
import 'dart:isolate';

/// Escáner de música para escritorio (Linux/Windows).
///
/// En Android se recomienda usar `getLibraryFiles` por MethodChannel, que
/// consulta MediaStore y ya devuelve los metadatos.
class LocalMusicScanner {
  static const Set<String> _supportedExtensions = {
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.flac',
    '.ogg',
  };

  Future<List<File>> scanDirectory(String directoryPath) =>
      scanDirectories(<String>[directoryPath]);

  Future<List<File>> scanDirectories(List<String> directoryPaths) async {
    // Un isolate por directorio raíz, en paralelo y sin bloquear la UI.
    final results = await Future.wait(
      directoryPaths.map((root) => Isolate.run(() => _scanRoot(root))),
    );

    final seen = <String>{};
    final files = <File>[];

    for (final paths in results) {
      for (final path in paths) {
        if (seen.add(path)) {
          files.add(File(path));
        }
      }
    }

    return List<File>.unmodifiable(files);
  }

  // Métodos estáticos: el isolate no necesita capturar `this`.
  static List<String> _scanRoot(String rootPath) {
    final output = <String>[];
    _walk(Directory(rootPath), output);
    return output;
  }

  static void _walk(Directory directory, List<String> output) {
    final List<FileSystemEntity> entries;

    try {
      entries = directory.listSync(followLinks: false);
    } on FileSystemException {
      return; // Sin permisos o el directorio no existe.
    }

    for (final entity in entries) {
      final path = entity.path;
      final name = path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);

      // Oculto: no se entra a la carpeta ni se evalúa el archivo.
      if (name.startsWith('.')) {
        continue;
      }

      if (entity is Directory) {
        _walk(entity, output);
      } else if (entity is File && _isAudioFile(name)) {
        output.add(path);
      }
    }
  }

  static bool _isAudioFile(String fileName) {
    final dot = fileName.lastIndexOf('.');

    if (dot <= 0) {
      return false;
    }

    return _supportedExtensions.contains(fileName.substring(dot).toLowerCase());
  }
}

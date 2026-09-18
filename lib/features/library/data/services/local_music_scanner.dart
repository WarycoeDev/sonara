import 'dart:io';

class LocalMusicScanner {
  static const Set<String> _supportedExtensions = {
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.flac',
    '.ogg',
  };

  Future<List<File>> scanDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);

    try {
      if (!await directory.exists()) {
        print('[SCANNER] El directorio no existe: $directoryPath');
        return const <File>[];
      }

      final audioFiles = <File>[];

      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) {
          continue;
        }

        final path = entity.path;

        if (_isHiddenPath(path, directoryPath)) {
          print('[SCANNER IGNORADO - Oculto]: $path');
          continue;
        }

        if (!_isAudioFile(path)) {
          print('[SCANNER IGNORADO - Extensión no válida]: $path');
          continue;
        }

        print('[SCANNER DETECTADO]: $path');
        audioFiles.add(entity);
      }

      return List<File>.unmodifiable(audioFiles);
    } on FileSystemException catch (e) {
      print('[SCANNER ERROR DE SISTEMA] en $directoryPath: $e');
      return const <File>[];
    }
  }

  Future<List<File>> scanDirectories(List<String> directoryPaths) async {
    final audioFiles = <File>[];
    final scannedPaths = <String>{};

    for (final directoryPath in directoryPaths) {
      final files = await scanDirectory(directoryPath);

      for (final file in files) {
        if (scannedPaths.add(file.path)) {
          audioFiles.add(file);
        } else {
          print('[SCANNER DUPLICADO OMITIDO]: ${file.path}');
        }
      }
    }

    return List<File>.unmodifiable(audioFiles);
  }

  bool _isAudioFile(String filePath) {
    final lastDotIndex = filePath.lastIndexOf('.');

    if (lastDotIndex <= 0) {
      return false;
    }

    final extension = filePath.substring(lastDotIndex).toLowerCase();

    return _supportedExtensions.contains(extension);
  }

  bool _isHiddenPath(String path, String rootPath) {
    if (path.length <= rootPath.length) {
      return false;
    }

    var relativePath = path.substring(rootPath.length);

    if (relativePath.startsWith(Platform.pathSeparator)) {
      relativePath = relativePath.substring(1);
    }

    var start = 0;

    while (true) {
      final separatorIndex = relativePath.indexOf(
        Platform.pathSeparator,
        start,
      );

      final end = separatorIndex == -1 ? relativePath.length : separatorIndex;

      if (end > start) {
        final part = relativePath.substring(start, end);

        if (part.startsWith('.')) {
          return true;
        }
      }

      if (separatorIndex == -1) {
        break;
      }

      start = separatorIndex + 1;
    }

    return false;
  }
}

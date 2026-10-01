import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SonaraStorageService {
  static Directory? _rootDirectory;

  /// Retorna el directorio de soporte de la aplicación (`ApplicationSupportDirectory`).
  static Future<Directory> getAppSupportDirectory() async {
    return await getApplicationSupportDirectory();
  }

  /// Retorna el directorio raíz según la plataforma.
  static Future<Directory> getRootDirectory() async {
    if (_rootDirectory != null) return _rootDirectory!;

    if (Platform.isAndroid) {
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        _rootDirectory = directory;
        return directory;
      }
    }

    _rootDirectory = await getApplicationSupportDirectory();
    return _rootDirectory!;
  }

  /// Retorna el directorio de caché base.
  static Future<Directory> getCacheDirectory() async {
    if (Platform.isAndroid) {
      final root = await getRootDirectory();
      final cacheDirectory = Directory(p.join(root.parent.path, 'cache'));

      if (!await cacheDirectory.exists()) {
        await cacheDirectory.create(recursive: true);
      }

      return cacheDirectory;
    }

    return await getAppSupportDirectory();
  }

  /// Retorna el directorio de archivos persistentes.
  static Future<Directory> getFilesDirectory() async {
    final directory = await getRootDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  // --- MÉTODOS HELPER PRIVADOS ---

  static Future<Directory> _getSubFolder(
    Future<Directory> Function() getParent,
    String folderName,
  ) async {
    final parent = await getParent();
    final directory = Directory(p.join(parent.path, folderName));

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  // --- DIRECTORIOS DE CACHÉ ---

  static Future<Directory> getLibraryCacheDirectory() =>
      _getSubFolder(getCacheDirectory, 'library');

  static Future<Directory> getArtworkCacheDirectory() =>
      _getSubFolder(getCacheDirectory, 'artwork');

  static Future<Directory> getMetadataCacheDirectory() =>
      _getSubFolder(getCacheDirectory, 'metadata');

  static Future<Directory> getYoutubeCacheDirectory() =>
      _getSubFolder(getCacheDirectory, 'youtube');

  // --- DIRECTORIOS DE ARCHIVOS ---

  static Future<Directory> getDownloadsDirectory() =>
      _getSubFolder(getFilesDirectory, 'downloads');

  static Future<Directory> getTempDirectory() =>
      _getSubFolder(getFilesDirectory, 'temp');

  static Future<Directory> getMusicDirectory() =>
      _getSubFolder(getFilesDirectory, 'Music');
}

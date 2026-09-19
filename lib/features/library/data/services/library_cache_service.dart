import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/song.dart';

class LibraryCacheService {
  static const String _cacheFileName = 'library_cache.json';

  Future<File> _getCacheFile() async {
    final supportDirectory = await getApplicationSupportDirectory();

    final cacheDirectory = Directory(
      '${supportDirectory.path}'
      '${Platform.pathSeparator}'
      'sonara_library',
    );

    if (!await cacheDirectory.exists()) {
      await cacheDirectory.create(recursive: true);
    }

    return File(
      '${cacheDirectory.path}'
      '${Platform.pathSeparator}'
      '$_cacheFileName',
    );
  }

  // CARGAR CANCIONES

  Future<List<Song>> loadSongs() async {
    try {
      final file = await _getCacheFile();

      if (!await file.exists()) {
        print('[SONARA LIBRARY CACHE] No existe caché.');

        return const <Song>[];
      }

      final content = await file.readAsString();

      if (content.trim().isEmpty) {
        return const <Song>[];
      }

      final decoded = jsonDecode(content);

      if (decoded is! List) {
        print('[SONARA LIBRARY CACHE] Formato inválido.');

        return const <Song>[];
      }

      final songs = <Song>[];

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        try {
          songs.add(Song.fromJson(Map<String, dynamic>.from(item)));
        } catch (error) {
          print(
            '[SONARA LIBRARY CACHE] '
            'Error leyendo canción: $error',
          );
        }
      }

      print(
        '[SONARA LIBRARY CACHE] '
        '${songs.length} canciones cargadas desde caché.',
      );

      return List<Song>.unmodifiable(songs);
    } catch (error) {
      print(
        '[SONARA LIBRARY CACHE] '
        'Error cargando caché: $error',
      );

      return const <Song>[];
    }
  }

  // GUARDAR CANCIONES

  Future<void> saveSongs(List<Song> songs) async {
    try {
      final file = await _getCacheFile();

      final data = songs.map((song) => song.toJson()).toList(growable: false);

      final content = jsonEncode(data);

      // Guardar primero en un archivo temporal evita
      // dejar el caché corrupto si la app se cierra
      // durante la escritura.
      final temporaryFile = File('${file.path}.tmp');

      await temporaryFile.writeAsString(content, flush: true);

      if (await file.exists()) {
        await file.delete();
      }

      await temporaryFile.rename(file.path);

      print(
        '[SONARA LIBRARY CACHE] '
        '${songs.length} canciones guardadas.',
      );
    } catch (error) {
      print(
        '[SONARA LIBRARY CACHE] '
        'Error guardando caché: $error',
      );
    }
  }

  // ELIMINAR CACHÉ

  Future<void> clear() async {
    try {
      final file = await _getCacheFile();

      if (await file.exists()) {
        await file.delete();

        print('[SONARA LIBRARY CACHE] Caché eliminado.');
      }
    } catch (error) {
      print(
        '[SONARA LIBRARY CACHE] '
        'Error eliminando caché: $error',
      );
    }
  }
}

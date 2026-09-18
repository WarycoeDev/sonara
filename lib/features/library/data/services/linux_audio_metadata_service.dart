import 'dart:convert';
import 'dart:io';

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
  Future<LinuxAudioMetadata> readMetadata(String filePath) async {
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
        print('[SONARA COVER] ffprobe fallo para: $filePath');

        print('[SONARA COVER] stderr: ${result.stderr}');

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

      final coverPath = await _extractCover(filePath);

      print('[SONARA COVER] $filePath');

      print('[SONARA COVER] portada: $coverPath');

      return LinuxAudioMetadata(
        artist: artist,
        album: album,
        duration: duration,
        coverPath: coverPath,
      );
    } catch (error) {
      print('[SONARA COVER] Error leyendo metadata de $filePath');

      print('[SONARA COVER] $error');

      return const LinuxAudioMetadata(duration: Duration.zero);
    }
  }

  Future<String?> _extractCover(String filePath) async {
    try {
      final audioFile = File(filePath);

      if (!await audioFile.exists()) {
        print('[SONARA COVER] El archivo no existe: $filePath');

        return null;
      }

      final coverPath = '${audioFile.path}.sonara-cover.jpg';

      final coverFile = File(coverPath);

      // Si ya fue extraída anteriormente, reutilizamos la portada.
      if (await coverFile.exists()) {
        print('[SONARA COVER] Usando portada existente: $coverPath');

        return coverPath;
      }

      print('[SONARA COVER] Extrayendo portada de: $filePath');

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
        print('[SONARA COVER] ffmpeg fallo para: $filePath');

        print('[SONARA COVER] stderr:');

        print(result.stderr);

        return null;
      }

      if (!await coverFile.exists()) {
        print(
          '[SONARA COVER] ffmpeg terminó correctamente, '
          'pero no creó la portada.',
        );

        print('[SONARA COVER] Ruta esperada: $coverPath');

        return null;
      }

      print('[SONARA COVER] Portada creada: $coverPath');

      return coverPath;
    } catch (error) {
      print('[SONARA COVER] Error extrayendo portada: $error');

      return null;
    }
  }
}

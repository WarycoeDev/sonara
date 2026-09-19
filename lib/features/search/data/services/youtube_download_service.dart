import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:extractor/extractor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:id3_codec/id3_codec.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../library/domain/models/song.dart';
import 'youtube_search_service.dart';

class YouTubeDownloadProgress {
  final double progress;
  final Duration eta;
  final String status;

  const YouTubeDownloadProgress({
    required this.progress,
    required this.eta,
    required this.status,
  });

  bool get isIndeterminate => progress <= 0;

  double get normalizedProgress {
    return (progress / 100).clamp(0.0, 1.0);
  }
}

class YouTubeDownloadService {
  YouTubeDownloadService();

  final YoutubeDLFlutter _youtubeDL = YoutubeDLFlutter.instance;

  static const MethodChannel _musicChannel = MethodChannel('com.sonara/music');

  Future<void>? _initializationFuture;

  Directory? _extractorCacheDirectory;
  Directory? _downloadDirectory;

  final StreamController<YouTubeDownloadProgress> _progressController =
      StreamController<YouTubeDownloadProgress>.broadcast();

  Stream<YouTubeDownloadProgress> get progressStream =>
      _progressController.stream;

  /// Inicializa Extractor una sola vez.
  Future<void> _initialize() async {
    try {
      await (_initializationFuture ??= _initializeExtractor());
    } catch (_) {
      _initializationFuture = null;
      rethrow;
    }
  }

  Future<void> _initializeExtractor() async {
    debugPrint('[YouTubeDownload] Inicializando Extractor...');

    final result = await _youtubeDL.initialize(
      enableFFmpeg: true,
      enableAria2c: false,
    );

    if (!result.success) {
      throw Exception(
        'No se pudo inicializar el sistema de descargas: '
        '${result.errorMessage ?? "Error desconocido"}',
      );
    }

    debugPrint('[YouTubeDownload] Extractor inicializado correctamente.');
  }

  Future<Song> downloadAudio({
    required YouTubeSearchResult result,
    required String fileName,
    ValueChanged<double>? onProgress,
  }) async {
    final sanitizedFileName = _cleanFileName(fileName);

    if (sanitizedFileName.isEmpty) {
      throw ArgumentError('El nombre del archivo no puede estar vacío.');
    }

    await _initialize();

    debugPrint(
      '[YouTubeDownload] Iniciando descarga con Extractor: '
      '${result.title} (${result.id})',
    );

    _progressController.add(
      const YouTubeDownloadProgress(
        progress: 0,
        eta: Duration.zero,
        status: 'Preparando descarga...',
      ),
    );

    // En Android Extractor descarga primero en el almacenamiento
    // privado de la aplicación. Después el archivo terminado se
    // publica en la carpeta pública Music mediante MediaStore.
    final destinationDirectory = await _getDestinationDirectory();

    if (!await destinationDirectory.exists()) {
      await destinationDirectory.create(recursive: true);
    }

    debugPrint(
      '[YouTubeDownload] Directorio de descarga: '
      '${destinationDirectory.path}',
    );

    final cacheDirectory = await _getExtractorCacheDirectory();

    final videoUrl = _buildYouTubeUrl(result.id);

    final processId = 'sonara_audio_${DateTime.now().microsecondsSinceEpoch}';

    final outputFile = File(
      '${destinationDirectory.path}'
      '${Platform.pathSeparator}'
      '$sanitizedFileName.mp3',
    );

    if (await outputFile.exists()) {
      await outputFile.delete();
    }

    StreamSubscription<DownloadProgress>? progressSubscription;
    StreamSubscription<DownloadError>? errorSubscription;
    StreamSubscription<LogMessage>? logSubscription;

    Object? downloadError;
    StackTrace? downloadStackTrace;

    try {
      progressSubscription = _youtubeDL.onProgress.listen((progress) {
        if (progress.processId != processId) {
          return;
        }

        onProgress?.call(progress.progress);

        debugPrint(
          '[YouTubeDownload] Progreso: '
          '${progress.progress.toStringAsFixed(1)}%',
        );
      });

      errorSubscription = _youtubeDL.onError.listen((error) {
        if (error.processId != processId) {
          return;
        }

        downloadError = Exception(error.error);
        downloadStackTrace = StackTrace.current;

        debugPrint(
          '[YouTubeDownload] Error del extractor: '
          '${error.error}',
        );
      });

      logSubscription = _youtubeDL.onLog.listen((log) {
        debugPrint('[YouTubeDownload][Extractor] ${log.message}');
      });

      _progressController.add(
        const YouTubeDownloadProgress(
          progress: 0,
          eta: Duration.zero,
          status: 'Iniciando descarga...',
        ),
      );

      downloadError = null;

      var downloadResult = await _attemptDownload(
        videoUrl: videoUrl,
        destinationDirectory: destinationDirectory,
        sanitizedFileName: sanitizedFileName,
        cacheDirectory: cacheDirectory,
        processId: processId,
        fastPath: true,
      );

      if (downloadError != null ||
          downloadResult.status != OperationStatus.success) {
        debugPrint(
          '[YouTubeDownload] El camino rápido falló, '
          'reintentando con android+tv '
          '(más lento pero más compatible)...',
        );

        downloadError = null;

        downloadResult = await _attemptDownload(
          videoUrl: videoUrl,
          destinationDirectory: destinationDirectory,
          sanitizedFileName: sanitizedFileName,
          cacheDirectory: cacheDirectory,
          processId: processId,
          fastPath: false,
        );
      }

      if (downloadError != null) {
        Error.throwWithStackTrace(
          downloadError!,
          downloadStackTrace ?? StackTrace.current,
        );
      }

      if (downloadResult.status != OperationStatus.success) {
        throw Exception(
          downloadResult.errorMessage ??
              'Extractor no pudo descargar el audio.',
        );
      }

      _progressController.add(
        const YouTubeDownloadProgress(
          progress: 100,
          eta: Duration.zero,
          status: 'Procesando archivo...',
        ),
      );

      File finalFile = outputFile;

      if (!await finalFile.exists()) {
        final resultPath = downloadResult.outputPath;

        if (resultPath != null && resultPath.isNotEmpty) {
          final candidate = File(resultPath);

          if (await candidate.exists()) {
            finalFile = candidate;
          }
        }
      }

      if (!await finalFile.exists()) {
        final files = await destinationDirectory
            .list()
            .where(
              (entity) =>
                  entity is File && entity.path.toLowerCase().endsWith('.mp3'),
            )
            .cast<File>()
            .toList();

        final matchingFiles = files.where((file) {
          final name = file.uri.pathSegments.last.toLowerCase();

          return name == '$sanitizedFileName.mp3'.toLowerCase();
        }).toList();

        if (matchingFiles.isNotEmpty) {
          finalFile = matchingFiles.first;
        }
      }

      if (!await finalFile.exists()) {
        throw Exception(
          'La descarga terminó, pero no se encontró '
          'el archivo MP3 generado.',
        );
      }

      final fileLength = await finalFile.length();

      if (fileLength <= 0) {
        throw Exception('El archivo MP3 generado está vacío.');
      }

      // =====================================================================
      // CARÁTULA
      // =====================================================================

      _progressController.add(
        const YouTubeDownloadProgress(
          progress: 100,
          eta: Duration.zero,
          status: 'Descargando carátula...',
        ),
      );

      await _attachSquareThumbnail(
        mp3File: finalFile,
        videoId: result.id,
        fallbackThumbnailUrl: result.thumbnailUrl,
      );

      // =====================================================================
      // PUBLICAR EN MUSIC
      // =====================================================================

      _progressController.add(
        const YouTubeDownloadProgress(
          progress: 100,
          eta: Duration.zero,
          status: 'Guardando en Music...',
        ),
      );

      final publicFilePath = await _publishToPublicMusic(
        sourceFile: finalFile,
        fileName: '$sanitizedFileName.mp3',
      );

      final publicFile = File(publicFilePath);

      if (!await publicFile.exists()) {
        throw Exception('El archivo no apareció en la carpeta pública Music.');
      }

      final publicFileLength = await publicFile.length();

      if (publicFileLength <= 0) {
        throw Exception('El archivo publicado en Music está vacío.');
      }

      final fileModified = await publicFile.lastModified();

      final song = Song(
        id: publicFile.path,
        filePath: publicFile.path,
        title: sanitizedFileName,
        artist: result.author,
        duration: result.duration ?? Duration.zero,
        dateAdded: fileModified,
        source: SongSource.local,
      );

      _progressController.add(
        const YouTubeDownloadProgress(
          progress: 100,
          eta: Duration.zero,
          status: 'Descarga completada',
        ),
      );

      debugPrint(
        '[YouTubeDownload] Descarga completada correctamente: '
        '$publicFilePath',
      );

      debugPrint(
        '[YouTubeDownload] Tamaño final: '
        '${_formatBytes(publicFileLength)}',
      );

      return song;
    } catch (error, stackTrace) {
      debugPrint('[YouTubeDownload] ERROR descargando audio: $error');

      debugPrintStack(stackTrace: stackTrace);

      if (await outputFile.exists()) {
        try {
          await outputFile.delete();
        } catch (_) {}
      }

      rethrow;
    } finally {
      await progressSubscription?.cancel();
      await errorSubscription?.cancel();
      await logSubscription?.cancel();
    }
  }

  /// Lanza un intento de descarga con Extractor.
  Future<DownloadResult> _attemptDownload({
    required String videoUrl,
    required Directory destinationDirectory,
    required String sanitizedFileName,
    required Directory cacheDirectory,
    required String processId,
    required bool fastPath,
  }) {
    final request = DownloadRequest(
      url: videoUrl,
      outputPath: destinationDirectory.path,
      outputTemplate: '$sanitizedFileName.%(ext)s',
      noPlaylist: true,
      extractAudio: true,
      audioFormat: 'mp3',
      audioQuality: 0,
      embedMetadata: true,
      embedThumbnail: false,
      processId: processId,
      customOptions: _buildExtractorOptions(
        cacheDirPath: cacheDirectory.path,
        fastPath: fastPath,
      ),
    );

    return _youtubeDL
        .download(request)
        .timeout(
          const Duration(minutes: 10),
          onTimeout: () {
            throw TimeoutException('La descarga tardó demasiado tiempo.');
          },
        );
  }

  /// Opciones pasadas a yt-dlp por debajo de Extractor.
  Map<String, String> _buildExtractorOptions({
    required String cacheDirPath,
    required bool fastPath,
  }) {
    return {
      '--retries': '5',
      '--fragment-retries': '5',
      '--no-playlist': '',
      '--no-mtime': '',
      '--format': 'bestaudio/best',
      '--cache-dir': cacheDirPath,
      '--extractor-args': fastPath
          ? 'youtube:player_client=android;player_skip=webpage,configs'
          : 'youtube:player_client=android,tv',
    };
  }

  // DIRECTORIO DE DESCARGA

  /// En Android esta carpeta es temporal.
  ///
  /// Extractor descarga aquí porque puede crear archivos .part
  /// sin las restricciones de almacenamiento público.
  ///
  /// Después el MP3 terminado se publica mediante MediaStore
  /// en la carpeta pública Music.
  Future<Directory> _getDestinationDirectory() async {
    final cached = _downloadDirectory;

    if (cached != null) {
      return cached;
    }

    if (Platform.isAndroid) {
      final externalDirectory = await getExternalStorageDirectory();

      if (externalDirectory == null) {
        throw Exception(
          'No se pudo acceder al almacenamiento externo de Sonara.',
        );
      }

      final directory = Directory(
        '${externalDirectory.path}'
        '${Platform.pathSeparator}'
        'Music',
      );

      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      _downloadDirectory = directory;

      debugPrint(
        '[YouTubeDownload] Almacenamiento temporal Android: '
        '${directory.path}',
      );

      return directory;
    }

    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];

      if (home != null && home.isNotEmpty) {
        final directory = Directory('$home${Platform.pathSeparator}Music');

        _downloadDirectory = directory;

        return directory;
      }
    }

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];

      if (userProfile != null && userProfile.isNotEmpty) {
        final directory = Directory(
          '$userProfile${Platform.pathSeparator}Music',
        );

        _downloadDirectory = directory;

        return directory;
      }
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();

    final directory = Directory(
      '${documentsDirectory.path}'
      '${Platform.pathSeparator}'
      'Music',
    );

    _downloadDirectory = directory;

    return directory;
  }

  // PUBLICAR EN MUSIC

  /// Publica el MP3 terminado en la carpeta pública Music de Android.
  ///
  /// Android 10+:
  ///
  ///     MediaStore
  ///     RELATIVE_PATH = Music/
  ///
  /// Android anterior:
  ///
  ///     /storage/emulated/0/Music/
  Future<String> _publishToPublicMusic({
    required File sourceFile,
    required String fileName,
  }) async {
    if (!Platform.isAndroid) {
      return sourceFile.path;
    }

    try {
      final publicPath = await _musicChannel.invokeMethod<String>(
        'publishAudioToMusic',
        <String, dynamic>{'sourcePath': sourceFile.path, 'fileName': fileName},
      );

      if (publicPath == null || publicPath.isEmpty) {
        throw Exception('Android no devolvió la ruta del archivo publicado.');
      }

      final publicFile = File(publicPath);

      if (!await publicFile.exists()) {
        throw Exception('El archivo no apareció en la carpeta pública Music.');
      }

      final publicLength = await publicFile.length();

      if (publicLength <= 0) {
        throw Exception('El archivo publicado en Music está vacío.');
      }

      debugPrint(
        '[YouTubeDownload] Archivo publicado en Music: '
        '$publicPath',
      );

      // Eliminamos la copia temporal.
      if (sourceFile.path != publicPath && await sourceFile.exists()) {
        try {
          await sourceFile.delete();

          debugPrint('[YouTubeDownload] Copia temporal eliminada.');
        } catch (error) {
          debugPrint(
            '[YouTubeDownload] No se pudo eliminar la '
            'copia temporal: $error',
          );
        }
      }

      return publicPath;
    } on PlatformException catch (error) {
      throw Exception(
        'No se pudo guardar la canción en Music: '
        '${error.message ?? error.code}',
      );
    }
  }

  // CACHÉ PERSISTENTE DE EXTRACTOR

  Future<Directory> _getExtractorCacheDirectory() async {
    final cached = _extractorCacheDirectory;

    if (cached != null) {
      return cached;
    }

    final supportDirectory = await getApplicationSupportDirectory();

    final cacheDirectory = Directory(
      '${supportDirectory.path}'
      '${Platform.pathSeparator}'
      'yt-dlp-cache',
    );

    if (!await cacheDirectory.exists()) {
      await cacheDirectory.create(recursive: true);
    }

    _extractorCacheDirectory = cacheDirectory;

    return cacheDirectory;
  }

  // CARÁTULA

  Future<void> _attachSquareThumbnail({
    required File mp3File,
    required String videoId,
    required String fallbackThumbnailUrl,
  }) async {
    final candidateUrls = _buildThumbnailCandidates(
      videoId,
      fallbackThumbnailUrl,
    );

    if (candidateUrls.isEmpty) {
      return;
    }

    try {
      final coverBytes = await _downloadSquareThumbnail(candidateUrls);

      if (coverBytes == null) {
        debugPrint(
          '[YouTubeDownload] No se pudo obtener la miniatura, '
          'se omite la carátula.',
        );

        return;
      }

      await _embedCoverArt(mp3File, coverBytes);

      debugPrint('[YouTubeDownload] Carátula incrustada correctamente.');
    } catch (error, stackTrace) {
      debugPrint(
        '[YouTubeDownload] No se pudo incrustar la carátula: '
        '$error',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  List<String> _buildThumbnailCandidates(
    String videoId,
    String fallbackThumbnailUrl,
  ) {
    final candidates = <String>[
      'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg',
      'https://i.ytimg.com/vi/$videoId/sddefault.jpg',
      'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
    ];

    final fallback = fallbackThumbnailUrl.trim();

    if (fallback.isNotEmpty && !candidates.contains(fallback)) {
      candidates.add(fallback);
    }

    return candidates;
  }

  Future<Uint8List?> _downloadSquareThumbnail(
    List<String> candidateUrls,
  ) async {
    final results = await Future.wait(candidateUrls.map(_fetchBytes));

    for (final bytes in results) {
      if (bytes == null || bytes.isEmpty) {
        continue;
      }

      final decoded = img.decodeImage(bytes);

      if (decoded == null || _isMissingThumbnailPlaceholder(decoded)) {
        continue;
      }

      final squareImage = _cropToSquare(decoded);

      return Uint8List.fromList(img.encodeJpg(squareImage, quality: 95));
    }

    return null;
  }

  bool _isMissingThumbnailPlaceholder(img.Image image) {
    return image.width <= 120 && image.height <= 90;
  }

  img.Image _cropToSquare(img.Image source) {
    if (source.width == source.height) {
      return source;
    }

    if (source.width > source.height) {
      final side = source.height;

      final offsetX = ((source.width - side) / 2).round();

      return img.copyCrop(source, x: offsetX, y: 0, width: side, height: side);
    }

    final side = source.width;

    final offsetY = ((source.height - side) / 2).round();

    return img.copyCrop(source, x: 0, y: offsetY, width: side, height: side);
  }

  Future<void> _embedCoverArt(File mp3File, Uint8List coverBytes) async {
    final originalBytes = await mp3File.readAsBytes();

    final encoder = ID3Encoder(originalBytes);

    final updatedBytes = encoder.encodeSync(
      MetadataV2p3Body(imageBytes: coverBytes),
    );

    await mp3File.writeAsBytes(updatedBytes, flush: true);
  }

  Future<Uint8List?> _fetchBytes(String url) async {
    final client = HttpClient();

    try {
      final uri = Uri.parse(url);

      final request = await client.getUrl(uri);

      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );

      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final bytesBuilder = BytesBuilder(copy: false);

      await for (final chunk in response) {
        bytesBuilder.add(chunk);
      }

      return bytesBuilder.takeBytes();
    } catch (error) {
      debugPrint(
        '[YouTubeDownload] Error descargando la miniatura: '
        '$error',
      );

      return null;
    } finally {
      client.close(force: true);
    }
  }

  String _buildYouTubeUrl(String videoId) {
    return 'https://www.youtube.com/watch?v=$videoId';
  }

  String _cleanFileName(String value) {
    var result = value.trim();

    if (result.toLowerCase().endsWith('.mp3')) {
      result = result.substring(0, result.length - 4);
    }

    if (result.toLowerCase().endsWith('.m4a')) {
      result = result.substring(0, result.length - 4);
    }

    result = result.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');

    return result.trim();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }

    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  void dispose() {
    _progressController.close();
  }
}

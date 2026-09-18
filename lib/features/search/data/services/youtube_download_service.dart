import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:extractor/extractor.dart';
import 'package:flutter/foundation.dart';
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

  Future<void>? _initializationFuture;

  Directory? _extractorCacheDirectory;

  final StreamController<YouTubeDownloadProgress> _progressController =
      StreamController<YouTubeDownloadProgress>.broadcast();

  Stream<YouTubeDownloadProgress> get progressStream =>
      _progressController.stream;

  /// Inicializa Extractor una sola vez.
  Future<void> _initialize() {
    return _initializationFuture ??= _initializeExtractor();
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

    final destinationDirectory = await _getDestinationDirectory();

    if (!await destinationDirectory.exists()) {
      await destinationDirectory.create(recursive: true);
    }

    // Directorio persistente donde Extractor guarda su caché (sobre todo el
    // JavaScript del "player" de YouTube, que es lo más caro de descargar).
    // Al fijarlo explícitamente evitamos que quede en una carpeta temporal
    // que se borre entre ejecuciones de la app. Mientras se use siempre el
    // mismo cliente (ver _buildExtractorOptions), este player se descarga
    // una sola vez y se reutiliza en todas las canciones siguientes.
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

      // -----------------------------------------------------------------
      // Camino rápido: un solo cliente (android) y sin bajar la webpage ni
      // los "configs" de YouTube. Esto evita las 4-5 peticiones de red que
      // se veían en los logs (webpage, tv config, tv player API...) y deja
      // solo la petición imprescindible por video (la API del player).
      //
      // Si ese cliente falla (algunos videos lo rechazan, p. ej. por
      // requerir un token que "android" no siempre trae), se reintenta
      // automáticamente con el combo más robusto (android + tv) que ya
      // usaba el proyecto.
      // -----------------------------------------------------------------
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
          '[YouTubeDownload] El camino rápido falló, reintentando con '
          'android+tv (más lento pero más compatible)...',
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
          'La descarga terminó, pero no se encontró el archivo MP3 generado.',
        );
      }

      final fileLength = await finalFile.length();

      if (fileLength <= 0) {
        throw Exception('El archivo MP3 generado está vacío.');
      }

      // =======================================================================
      // CARÁTULA: descarga la miniatura en la mayor calidad disponible,
      // la recorta a cuadrado y la incrusta
      // =======================================================================
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

      final fileModified = await finalFile.lastModified();

      final song = Song(
        id: finalFile.path,
        filePath: finalFile.path,
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
        '${finalFile.path}',
      );

      debugPrint(
        '[YouTubeDownload] Tamaño final: '
        '${_formatBytes(fileLength)}',
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

  /// Lanza un intento de descarga con Extractor usando el set de opciones
  /// "rápido" (un solo cliente, sin webpage/configs) o el de respaldo
  /// (android + tv, como funcionaba antes) según [fastPath].
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

  /// Opciones pasadas a yt-dlp por debajo del extractor.
  ///
  /// [fastPath] = true: usa un solo cliente ("android") y le dice al
  /// extractor de YouTube que se salte la descarga de la webpage completa
  /// y de los "configs" regionales, que no hacen falta para bajar el
  /// audio. Esto es lo que elimina la mayoría de las peticiones extra que
  /// se veían en los logs (webpage, tv client config, tv player API...).
  ///
  /// [fastPath] = false: combo de respaldo (android + tv), más lento pero
  /// más compatible, para los pocos videos donde "android" solo no basta.
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
      // Caché persistente: aquí es donde Extractor guarda el JavaScript ya
      // interpretado del player de YouTube. Mientras fastPath use siempre
      // el mismo cliente, este player se descarga una única vez y se
      // reutiliza en todas las descargas siguientes (hasta que YouTube
      // rote esa versión del player, algo fuera de nuestro control).
      '--cache-dir': cacheDirPath,
      '--extractor-args': fastPath
          ? 'youtube:player_client=android;player_skip=webpage,configs'
          : 'youtube:player_client=android,tv',
    };
  }

  // ===========================================================================
  // CACHÉ PERSISTENTE DE EXTRACTOR (yt-dlp)
  // ===========================================================================

  /// Carpeta persistente (dentro del almacenamiento propio de la app) donde
  /// Extractor guarda su caché entre descargas: sobre todo el JavaScript del
  /// "player" de YouTube usado para descifrar firmas, que es lo más costoso
  /// de volver a descargar en cada video. Al no depender de una carpeta
  /// temporal, esta caché sobrevive entre descargas (y, en Android, entre
  /// aperturas de la app) mientras no se borren los datos de la app.
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

  // ===========================================================================
  // CARÁTULA A PARTIR DE LA MINIATURA DE YOUTUBE
  // ===========================================================================

  /// Descarga la miniatura del video en la mayor calidad disponible, la
  /// recorta al centro para obtener un cuadrado (el lado es igual a la
  /// altura original de la miniatura, recortando el sobrante de los
  /// costados) y la incrusta como carátula del MP3 ya descargado.
  ///
  /// Cualquier fallo aquí es silencioso a propósito: el audio ya se
  /// descargó correctamente y no debe fallar por no poder poner carátula.
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
      debugPrint('[YouTubeDownload] No se pudo incrustar la carátula: $error');

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Construye la lista de URLs de miniatura a probar, de mayor a menor
  /// calidad. `maxresdefault` es la de mejor resolución (1280x720) pero no
  /// existe para todos los videos; por eso se prueban alternativas en
  /// cascada, terminando con la miniatura que ya traía el resultado de
  /// búsqueda como último recurso.
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

  /// Pide todas las URLs candidatas en paralelo (en vez de una por una) y
  /// usa la primera, en orden de preferencia, que resulte ser una imagen
  /// real y no el placeholder de 120x90 que YouTube responde con HTTP 200
  /// cuando una resolución concreta no existe para ese video.
  ///
  /// Antes, si `maxresdefault.jpg` no existía, había que esperar su
  /// respuesta (o su timeout de 15s) antes de intentar la siguiente URL.
  /// Pidiéndolas todas a la vez, el tiempo total es el de la más lenta de
  /// las cuatro, no la suma de todas.
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

  /// YouTube responde con HTTP 200 y una imagen de relleno de 120x90
  /// cuando se pide una resolución de miniatura que no existe para ese
  /// video (por ejemplo, `maxresdefault.jpg` en videos antiguos). Esta
  /// comprobación detecta ese caso para seguir probando otra URL.
  bool _isMissingThumbnailPlaceholder(img.Image image) {
    return image.width <= 120 && image.height <= 90;
  }

  /// Recorta una imagen al centro para dejarla cuadrada.
  ///
  /// Las miniaturas de YouTube son apaisadas (más anchas que altas), así
  /// que el caso normal es: el lado del cuadrado final = la altura
  /// original, y el sobrante de ancho se recorta en partes iguales de
  /// cada costado.
  img.Image _cropToSquare(img.Image source) {
    if (source.width == source.height) {
      return source;
    }

    if (source.width > source.height) {
      final side = source.height;
      final offsetX = ((source.width - side) / 2).round();

      return img.copyCrop(source, x: offsetX, y: 0, width: side, height: side);
    }

    // Caso poco común: miniatura más alta que ancha. Se recorta arriba/abajo.
    final side = source.width;
    final offsetY = ((source.height - side) / 2).round();

    return img.copyCrop(source, x: 0, y: offsetY, width: side, height: side);
  }

  /// Incrusta la imagen como carátula (frame APIC) en el MP3 ya existente,
  /// conservando el resto de metadatos (título, artista, etc.) que
  /// Extractor ya haya escrito con `embedMetadata: true`.
  Future<void> _embedCoverArt(File mp3File, Uint8List coverBytes) async {
    final originalBytes = await mp3File.readAsBytes();

    final encoder = ID3Encoder(originalBytes);

    final updatedBytes = encoder.encodeSync(
      MetadataV2p3Body(imageBytes: coverBytes),
    );

    await mp3File.writeAsBytes(updatedBytes, flush: true);
  }

  /// Descarga los bytes de una URL cualquiera (usado para la miniatura).
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
      debugPrint('[YouTubeDownload] Error descargando la miniatura: $error');

      return null;
    } finally {
      client.close(force: true);
    }
  }

  String _buildYouTubeUrl(String videoId) {
    return 'https://www.youtube.com/watch?v=$videoId';
  }

  Future<Directory> _getDestinationDirectory() async {
    if (Platform.isAndroid) {
      final directory = await getExternalStorageDirectory();

      if (directory == null) {
        throw Exception('No se pudo acceder al almacenamiento externo.');
      }

      final storageRoot = Directory(
        directory.path.split('${Platform.pathSeparator}Android').first,
      );

      return Directory(
        '${storageRoot.path}'
        '${Platform.pathSeparator}'
        'Music',
      );
    }

    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];

      if (home != null && home.isNotEmpty) {
        return Directory('$home${Platform.pathSeparator}Music');
      }
    }

    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];

      if (userProfile != null && userProfile.isNotEmpty) {
        return Directory('$userProfile${Platform.pathSeparator}Music');
      }
    }

    final directory = await getApplicationDocumentsDirectory();

    return Directory(
      '${directory.path}'
      '${Platform.pathSeparator}'
      'Music',
    );
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

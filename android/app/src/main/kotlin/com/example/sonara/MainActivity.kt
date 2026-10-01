
package com.example.sonara

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.tan

class MainActivity : AudioServiceActivity() {

    private val channelName = "com.sonara/music"

    private val audioPermissionRequestCode = 1001

    private val mediaStoreWriteRequestCode = 2001

    private var pendingMediaStoreResult: MethodChannel.Result? = null
    private var pendingMediaStoreUri: Uri? = null
    private var pendingMediaStoreTempPath: String? = null

    private val supportedExtensions = setOf(
        "mp3",
        "m4a",
        "aac",
        "wav",
        "flac",
        "ogg"
    )

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "requestAudioPermission" -> {

                    if (checkStoragePermission()) {
                        result.success(true)
                    } else {
                        requestStoragePermission()
                        result.success(checkStoragePermission())
                    }
                }

                "getLibraryFiles" -> {

                    try {
                        result.success(getLibraryFiles())
                    } catch (exception: Exception) {
                        result.error(
                            "LIBRARY_FILES_QUERY_ERROR",
                            exception.message,
                            null
                        )
                    }
                }

                "getSongMetadata" -> {

                    val filePath =
                        call.argument<String>("filePath")

                    if (filePath.isNullOrEmpty()) {
                        result.error(
                            "INVALID_FILE_PATH",
                            "filePath es obligatorio.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    try {
                        result.success(
                            getSongMetadata(File(filePath))
                        )
                    } catch (exception: Exception) {
                        result.error(
                            "SONG_METADATA_ERROR",
                            exception.message,
                            null
                        )
                    }
                }

                "publishAudioToMusic" -> {

                    val sourcePath =
                        call.argument<String>("sourcePath")

                    val fileName =
                        call.argument<String>("fileName")

                    if (
                        sourcePath.isNullOrEmpty() ||
                        fileName.isNullOrEmpty()
                    ) {
                        result.error(
                            "INVALID_AUDIO_DATA",
                            "sourcePath y fileName son obligatorios.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    try {
                        result.success(
                            publishAudioToMusic(
                                sourcePath = sourcePath,
                                fileName = fileName
                            )
                        )
                    } catch (exception: Exception) {
                        result.error(
                            "PUBLISH_AUDIO_ERROR",
                            exception.message,
                            null
                        )
                    }
                }

                "replaceMediaStoreAudio" -> {

                    val sourcePath =
                        call.argument<String>("sourcePath")

                    val temporaryPath =
                        call.argument<String>("temporaryPath")

                    if (
                        sourcePath.isNullOrEmpty() ||
                        temporaryPath.isNullOrEmpty()
                    ) {
                        result.error(
                            "INVALID_AUDIO_REPLACEMENT_DATA",
                            "sourcePath y temporaryPath son obligatorios.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    replaceMediaStoreAudio(
                        sourcePath = sourcePath,
                        temporaryPath = temporaryPath,
                        result = result
                    )
                }

                "calculateTrackGain" -> {

                    val filePath =
                        call.argument<String>("filePath")

                    if (filePath.isNullOrEmpty()) {
                        result.error(
                            "INVALID_FILE_PATH",
                            "filePath es obligatorio.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    Thread {

                        val gain =
                            try {
                                android.util.Log.d(
                                    "SONARA_REPLAYGAIN",
                                    "Analizando: ${File(filePath).name}"
                                )

                                ReplayGainCalculator
                                    .calculateTrackGain(
                                        File(filePath)
                                    )
                            } catch (exception: Exception) {

                                android.util.Log.e(
                                    "SONARA_REPLAYGAIN",
                                    "Error calculando gain.",
                                    exception
                                )

                                null
                            }

                        runOnUiThread {
                            result.success(gain)
                        }

                    }.start()
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // =========================================================================
    // MEDIASTORE
    // =========================================================================

    private fun replaceMediaStoreAudio(
        sourcePath: String,
        temporaryPath: String,
        result: MethodChannel.Result
    ) {

        val temporaryFile = File(temporaryPath)

        if (!temporaryFile.exists()) {
            result.error(
                "TEMPORARY_FILE_NOT_FOUND",
                "El archivo temporal no existe: $temporaryPath",
                null
            )
            return
        }

        if (!temporaryFile.isFile) {
            result.error(
                "TEMPORARY_FILE_INVALID",
                "La ruta temporal no corresponde a un archivo.",
                null
            )
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {

            replaceAudioPreAndroid10(
                sourcePath = sourcePath,
                temporaryPath = temporaryPath,
                result = result
            )

            return
        }

        try {

            val mediaUri =
                findMediaStoreAudioUri(sourcePath)

            if (mediaUri == null) {
                result.error(
                    "MEDIASTORE_URI_NOT_FOUND",
                    "No se encontró el audio en MediaStore: $sourcePath",
                    null
                )
                return
            }

            android.util.Log.d(
                "SONARA_MEDIASTORE",
                "URI encontrada: $mediaUri"
            )

            try {

                copyTemporaryFileToMediaStore(
                    mediaUri = mediaUri,
                    temporaryFile = temporaryFile
                )

                temporaryFile.delete()

                android.util.Log.d(
                    "SONARA_MEDIASTORE",
                    "Audio reemplazado correctamente."
                )

                result.success(true)

            } catch (securityException: SecurityException) {

                android.util.Log.w(
                    "SONARA_MEDIASTORE",
                    "No hay permiso para modificar $mediaUri.",
                    securityException
                )

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {

                    requestMediaStoreWritePermission(
                        mediaUri = mediaUri,
                        temporaryPath = temporaryPath,
                        result = result
                    )

                } else {

                    result.error(
                        "MEDIASTORE_WRITE_PERMISSION",
                        "Android no permitió escribir el archivo.",
                        null
                    )
                }
            }

        } catch (exception: Exception) {

            android.util.Log.e(
                "SONARA_MEDIASTORE",
                "Error reemplazando audio.",
                exception
            )

            result.error(
                "MEDIASTORE_REPLACE_ERROR",
                exception.message
                    ?: "Error desconocido reemplazando el audio.",
                null
            )
        }
    }

    private fun findMediaStoreAudioUri(
        sourcePath: String
    ): Uri? {

        val resolver = contentResolver

        val collection =
            MediaStore.Audio.Media.getContentUri(
                MediaStore.VOLUME_EXTERNAL_PRIMARY
            )

        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DATA
        )

        val selection =
            "${MediaStore.Audio.Media.DATA} = ?"

        val selectionArgs =
            arrayOf(sourcePath)

        resolver.query(
            collection,
            projection,
            selection,
            selectionArgs,
            null
        )?.use { cursor ->

            val idColumn =
                cursor.getColumnIndex(
                    MediaStore.Audio.Media._ID
                )

            if (idColumn < 0) {
                return null
            }

            if (cursor.moveToFirst()) {

                val id =
                    cursor.getLong(idColumn)

                return Uri.withAppendedPath(
                    collection,
                    id.toString()
                )
            }
        }

        return null
    }

    private fun copyTemporaryFileToMediaStore(
        mediaUri: Uri,
        temporaryFile: File
    ) {

        val resolver = contentResolver

        resolver.openOutputStream(
            mediaUri,
            "w"
        ).use { outputStream ->

            if (outputStream == null) {
                throw IllegalStateException(
                    "MediaStore no pudo abrir el archivo para escritura."
                )
            }

            temporaryFile.inputStream().use { inputStream ->

                val buffer = ByteArray(64 * 1024)

                while (true) {

                    val bytesRead =
                        inputStream.read(buffer)

                    if (bytesRead == -1) {
                        break
                    }

                    outputStream.write(
                        buffer,
                        0,
                        bytesRead
                    )
                }

                outputStream.flush()
            }
        }

        try {

            val values =
                ContentValues().apply {

                    put(
                        MediaStore.Audio.Media.DATE_MODIFIED,
                        System.currentTimeMillis() / 1000L
                    )
                }

            resolver.update(
                mediaUri,
                values,
                null,
                null
            )

        } catch (_: Exception) {
        }
    }

    private fun requestMediaStoreWritePermission(
        mediaUri: Uri,
        temporaryPath: String,
        result: MethodChannel.Result
    ) {

        if (pendingMediaStoreResult != null) {

            result.error(
                "MEDIASTORE_WRITE_BUSY",
                "Ya existe una solicitud de escritura pendiente.",
                null
            )

            return
        }

        try {

            val writeRequest =
                MediaStore.createWriteRequest(
                    contentResolver,
                    listOf(mediaUri)
                )

            pendingMediaStoreResult = result
            pendingMediaStoreUri = mediaUri
            pendingMediaStoreTempPath = temporaryPath

            android.util.Log.d(
                "SONARA_MEDIASTORE",
                "Solicitando permiso para modificar: $mediaUri"
            )

            startIntentSenderForResult(
                writeRequest.intentSender,
                mediaStoreWriteRequestCode,
                null,
                0,
                0,
                0
            )

        } catch (exception: Exception) {

            pendingMediaStoreResult = null
            pendingMediaStoreUri = null
            pendingMediaStoreTempPath = null

            result.error(
                "MEDIASTORE_WRITE_REQUEST_ERROR",
                exception.message
                    ?: "No se pudo solicitar permiso de escritura.",
                null
            )
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {

        super.onActivityResult(
            requestCode,
            resultCode,
            data
        )

        if (
            requestCode !=
            mediaStoreWriteRequestCode
        ) {
            return
        }

        val result = pendingMediaStoreResult
        val mediaUri = pendingMediaStoreUri
        val temporaryPath = pendingMediaStoreTempPath

        pendingMediaStoreResult = null
        pendingMediaStoreUri = null
        pendingMediaStoreTempPath = null

        if (
            result == null ||
            mediaUri == null ||
            temporaryPath == null
        ) {
            return
        }

        if (resultCode != RESULT_OK) {

            result.success(false)
            return
        }

        Thread {

            try {

                val temporaryFile =
                    File(temporaryPath)

                if (!temporaryFile.exists()) {

                    runOnUiThread {

                        result.error(
                            "TEMPORARY_FILE_NOT_FOUND",
                            "El archivo temporal ya no existe.",
                            null
                        )
                    }

                    return@Thread
                }

                copyTemporaryFileToMediaStore(
                    mediaUri = mediaUri,
                    temporaryFile = temporaryFile
                )

                temporaryFile.delete()

                runOnUiThread {
                    result.success(true)
                }

            } catch (exception: Exception) {

                runOnUiThread {

                    result.error(
                        "MEDIASTORE_REPLACE_AFTER_PERMISSION_ERROR",
                        exception.message
                            ?: "Error reemplazando el audio.",
                        null
                    )
                }
            }

        }.start()
    }

    private fun replaceAudioPreAndroid10(
        sourcePath: String,
        temporaryPath: String,
        result: MethodChannel.Result
    ) {

        try {

            val sourceFile = File(sourcePath)
            val temporaryFile = File(temporaryPath)

            if (!sourceFile.exists()) {

                result.error(
                    "SOURCE_FILE_NOT_FOUND",
                    "El archivo original no existe.",
                    null
                )

                return
            }

            if (!temporaryFile.exists()) {

                result.error(
                    "TEMPORARY_FILE_NOT_FOUND",
                    "El archivo temporal no existe.",
                    null
                )

                return
            }

            val backupFile =
                File("$sourcePath.sonara-backup")

            if (backupFile.exists()) {
                backupFile.delete()
            }

            if (!sourceFile.renameTo(backupFile)) {

                result.error(
                    "LEGACY_BACKUP_ERROR",
                    "No se pudo crear el respaldo del audio.",
                    null
                )

                return
            }

            try {

                if (!temporaryFile.renameTo(sourceFile)) {

                    throw IllegalStateException(
                        "No se pudo colocar el archivo temporal."
                    )
                }

                backupFile.delete()

                result.success(true)

            } catch (exception: Exception) {

                try {
                    if (sourceFile.exists()) {
                        sourceFile.delete()
                    }
                } catch (_: Exception) {
                }

                try {
                    if (backupFile.exists()) {
                        backupFile.renameTo(sourceFile)
                    }
                } catch (_: Exception) {
                }

                result.error(
                    "LEGACY_AUDIO_REPLACE_ERROR",
                    exception.message
                        ?: "Error reemplazando el audio.",
                    null
                )
            }

        } catch (exception: Exception) {

            result.error(
                "LEGACY_AUDIO_REPLACE_ERROR",
                exception.message
                    ?: "Error reemplazando el audio.",
                null
            )
        }
    }

    // =========================================================================
    // PUBLICAR AUDIO
    // =========================================================================

    private fun publishAudioToMusic(
        sourcePath: String,
        fileName: String
    ): String {

        val sourceFile = File(sourcePath)

        if (!sourceFile.exists()) {
            throw IllegalArgumentException(
                "El archivo temporal no existe: $sourcePath"
            )
        }

        if (!sourceFile.isFile) {
            throw IllegalArgumentException(
                "La ruta temporal no corresponde a un archivo."
            )
        }

        val resolver = contentResolver

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {

            val audioCollection =
                MediaStore.Audio.Media.getContentUri(
                    MediaStore.VOLUME_EXTERNAL_PRIMARY
                )

            val values =
                ContentValues().apply {

                    put(
                        MediaStore.Audio.Media.DISPLAY_NAME,
                        fileName
                    )

                    put(
                        MediaStore.Audio.Media.MIME_TYPE,
                        "audio/mpeg"
                    )

                    put(
                        MediaStore.Audio.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_MUSIC
                    )

                    put(
                        MediaStore.Audio.Media.IS_MUSIC,
                        1
                    )

                    put(
                        MediaStore.Audio.Media.IS_PENDING,
                        1
                    )
                }

            val uri =
                resolver.insert(
                    audioCollection,
                    values
                )
                    ?: throw IllegalStateException(
                        "MediaStore no pudo crear el archivo."
                    )

            try {

                resolver.openOutputStream(
                    uri,
                    "w"
                ).use { outputStream ->

                    if (outputStream == null) {
                        throw IllegalStateException(
                            "No se pudo abrir el archivo de Music."
                        )
                    }

                    sourceFile.inputStream().use { inputStream ->

                        val buffer = ByteArray(64 * 1024)

                        while (true) {

                            val bytesRead =
                                inputStream.read(buffer)

                            if (bytesRead == -1) {
                                break
                            }

                            outputStream.write(
                                buffer,
                                0,
                                bytesRead
                            )
                        }

                        outputStream.flush()
                    }
                }

                val publishValues =
                    ContentValues().apply {

                        put(
                            MediaStore.Audio.Media.IS_PENDING,
                            0
                        )
                    }

                resolver.update(
                    uri,
                    publishValues,
                    null,
                    null
                )

                return Environment
                    .getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_MUSIC
                    )
                    .absolutePath +
                    File.separator +
                    fileName

            } catch (exception: Exception) {

                try {
                    resolver.delete(uri, null, null)
                } catch (_: Exception) {
                }

                throw exception
            }
        }

        val musicDirectory =
            Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_MUSIC
            )

        if (!musicDirectory.exists()) {
            musicDirectory.mkdirs()
        }

        val destinationFile =
            File(
                musicDirectory,
                fileName
            )

        sourceFile.inputStream().use { inputStream ->

            destinationFile.outputStream().use { outputStream ->

                inputStream.copyTo(
                    outputStream,
                    bufferSize = 64 * 1024
                )
            }
        }

        return destinationFile.absolutePath
    }

    // =========================================================================
    // PERMISOS
    // =========================================================================

    private fun checkStoragePermission(): Boolean {

        return when {

            Build.VERSION.SDK_INT >=
                    Build.VERSION_CODES.TIRAMISU -> {

                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_MEDIA_AUDIO
                ) ==
                    PackageManager.PERMISSION_GRANTED
            }

            Build.VERSION.SDK_INT >=
                    Build.VERSION_CODES.R -> {

                Environment.isExternalStorageManager()
            }

            else -> {

                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_EXTERNAL_STORAGE
                ) ==
                    PackageManager.PERMISSION_GRANTED
            }
        }
    }

    private fun requestStoragePermission() {

        when {

            Build.VERSION.SDK_INT >=
                    Build.VERSION_CODES.TIRAMISU -> {

                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.READ_MEDIA_AUDIO
                    ),
                    audioPermissionRequestCode
                )
            }

            Build.VERSION.SDK_INT >=
                    Build.VERSION_CODES.R -> {

                try {

                    val intent =
                        Intent(
                            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
                        ).apply {

                            data =
                                Uri.parse(
                                    "package:$packageName"
                                )
                        }

                    startActivity(intent)

                } catch (_: Exception) {

                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION
                        )
                    )
                }
            }

            else -> {

                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.READ_EXTERNAL_STORAGE
                    ),
                    audioPermissionRequestCode
                )
            }
        }
    }

    // =========================================================================
    // BIBLIOTECA
    // =========================================================================

    private fun getLibraryFiles():
        List<Map<String, Any?>> {

        val files =
            mutableListOf<Map<String, Any?>>()

        val externalStorage =
            Environment.getExternalStorageDirectory()

        val musicDirectory =
            File(
                externalStorage,
                Environment.DIRECTORY_MUSIC
            )

        val downloadDirectory =
            File(
                externalStorage,
                Environment.DIRECTORY_DOWNLOADS
            )

        scanLibraryFiles(
            directory = musicDirectory,
            files = files
        )

        scanLibraryFiles(
            directory = downloadDirectory,
            files = files
        )

        android.util.Log.d(
            "SONARA_ANDROID_SCAN",
            "Escaneo terminado. Archivos encontrados: ${files.size}"
        )

        return files
    }

    private fun scanLibraryFiles(
        directory: File,
        files: MutableList<Map<String, Any?>>
    ) {

        if (!directory.exists() ||
            !directory.isDirectory
        ) {
            return
        }

        val directoryFiles =
            try {
                directory.listFiles()
            } catch (_: Exception) {
                null
            } ?: return

        for (file in directoryFiles) {

            if (file.isDirectory) {

                if (file.name.startsWith(".")) {
                    continue
                }

                scanLibraryFiles(
                    directory = file,
                    files = files
                )

                continue
            }

            if (!file.isFile) {
                continue
            }

            val extension =
                file.extension.lowercase()

            if (
                !supportedExtensions.contains(
                    extension
                )
            ) {
                continue
            }

            files.add(
                mapOf(
                    "filePath" to file.absolutePath,
                    "lastModified" to file.lastModified(),
                    "fileSize" to file.length()
                )
            )
        }
    }

    // =========================================================================
    // METADATOS
    // =========================================================================

    private fun getSongMetadata(
        file: File
    ): Map<String, Any?> {

        if (!file.exists()) {
            throw IllegalArgumentException(
                "El archivo no existe."
            )
        }

        val metadataRetriever =
            MediaMetadataRetriever()

        try {

            metadataRetriever.setDataSource(
                file.absolutePath
            )

            val title =
                metadataRetriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_TITLE
                ) ?: file.nameWithoutExtension

            val artist =
                metadataRetriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_ARTIST
                )

            val album =
                metadataRetriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_ALBUM
                )

            val duration =
                metadataRetriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_DURATION
                )?.toLongOrNull() ?: 0L

            return mapOf(
                "id" to file.absolutePath,
                "filePath" to file.absolutePath,
                "title" to title,
                "artist" to artist,
                "album" to album,
                "duration" to duration,
                "dateAdded" to file.lastModified(),
                "lastModified" to file.lastModified(),
                "fileSize" to file.length()
            )

        } catch (_: Exception) {

            return createFallbackSong(file)

        } finally {

            try {
                metadataRetriever.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun createFallbackSong(
        file: File
    ): Map<String, Any?> {

        return mapOf(
            "id" to file.absolutePath,
            "filePath" to file.absolutePath,
            "title" to file.nameWithoutExtension,
            "artist" to null,
            "album" to null,
            "duration" to 0L,
            "dateAdded" to file.lastModified(),
            "lastModified" to file.lastModified(),
            "fileSize" to file.length()
        )
    }
}

// ===========================================================================
// REPLAYGAIN OPTIMIZADO
// ===========================================================================

private object ReplayGainCalculator {

    private const val TARGET_LOUDNESS_LUFS = -18.0

    private const val ABSOLUTE_GATE_LUFS = -70.0

    private const val RELATIVE_GATE_OFFSET_LU = -10.0

    private const val MIN_VALID_GAIN_DB = -30.0

    private const val MAX_VALID_GAIN_DB = 30.0

    private const val BLOCK_SECONDS = 0.4

    private const val STEP_SECONDS = 0.1

    /*
     * Para el escaneo de biblioteca:
     *
     * - canciones <= 15 s: completas
     * - canciones > 15 s: una única ventana de 15 s
     *
     * Esto elimina los 3 seek + 3 flush originales.
     */
    private const val MAX_ANALYSIS_SECONDS = 15.0

    private const val DEQUEUE_TIMEOUT_US = 10_000L

    fun calculateTrackGain(
        file: File
    ): Double? {

        if (!file.exists() || !file.isFile) {
            return null
        }

        return calculateTrackGainInternal(file)
    }

    private fun calculateTrackGainInternal(
        file: File
    ): Double? {

        val extractor =
            MediaExtractor()

        try {

            extractor.setDataSource(
                file.absolutePath
            )

        } catch (_: Exception) {

            extractor.release()
            return null
        }

        var trackIndex = -1
        var inputFormat: MediaFormat? = null

        for (
            index in 0 until extractor.trackCount
        ) {

            val format =
                extractor.getTrackFormat(index)

            val mime =
                format.getString(
                    MediaFormat.KEY_MIME
                )

            if (
                mime != null &&
                mime.startsWith("audio/")
            ) {

                trackIndex = index
                inputFormat = format
                break
            }
        }

        if (
            trackIndex < 0 ||
            inputFormat == null
        ) {

            extractor.release()
            return null
        }

        extractor.selectTrack(trackIndex)

        val mime =
            inputFormat.getString(
                MediaFormat.KEY_MIME
            )

        if (mime.isNullOrEmpty()) {

            extractor.release()
            return null
        }

        /*
         * MediaExtractor ya conoce la duración.
         * Evitamos crear otro MediaMetadataRetriever.
         */
        val durationUs =
            if (
                inputFormat.containsKey(
                    MediaFormat.KEY_DURATION
                )
            ) {

                inputFormat.getLong(
                    MediaFormat.KEY_DURATION
                )

            } else {

                0L
            }

        val codec =
            try {

                MediaCodec.createDecoderByType(
                    mime
                )

            } catch (_: Exception) {

                extractor.release()
                return null
            }

        return try {

            codec.configure(
                inputFormat,
                null,
                null,
                0
            )

            codec.start()

            /*
             * UNA SOLA VENTANA.
             *
             * En vez de:
             * 20% + 50% + 80%
             *
             * hacemos:
             * - pista corta → desde 0
             * - pista larga → centro de la pista
             *
             * Esto evita dos flush adicionales.
             */
            val startUs =
                calculateAnalysisStartUs(
                    durationUs
                )

            if (startUs > 0L) {

                extractor.seekTo(
                    startUs,
                    MediaExtractor.SEEK_TO_PREVIOUS_SYNC
                )

                /*
                 * Solo necesitamos un flush.
                 *
                 * El codec acaba de iniciarse, por lo que
                 * normalmente no es necesario hacer flush
                 * para startUs == 0.
                 */
                codec.flush()
            }

            val maxAnalysisUs =
                if (durationUs > 0L) {

                    minOf(
                        MAX_ANALYSIS_SECONDS * 1_000_000.0,
                        (
                            durationUs -
                                startUs
                        ).coerceAtLeast(0L) /
                            1.0
                    ).toLong()

                } else {

                    (
                        MAX_ANALYSIS_SECONDS *
                            1_000_000.0
                    ).toLong()
                }

            decodeAndMeasure(
                extractor = extractor,
                codec = codec,
                maxAnalysisUs = maxAnalysisUs
            )

        } catch (_: Exception) {

            null

        } finally {

            try {
                codec.stop()
            } catch (_: Exception) {
            }

            try {
                codec.release()
            } catch (_: Exception) {
            }

            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun calculateAnalysisStartUs(
        durationUs: Long
    ): Long {

        if (durationUs <= 0L) {
            return 0L
        }

        val maxAnalysisUs =
            (
                MAX_ANALYSIS_SECONDS *
                    1_000_000.0
            ).toLong()

        if (durationUs <= maxAnalysisUs) {
            return 0L
        }

        /*
         * Centro de la pista.
         *
         * Dejamos la ventana de 15 s centrada
         * aproximadamente en el 50%.
         */
        return (
            durationUs / 2L -
                maxAnalysisUs / 2L
        ).coerceIn(
            0L,
            durationUs - maxAnalysisUs
        )
    }

    private fun decodeAndMeasure(
        extractor: MediaExtractor,
        codec: MediaCodec,
        maxAnalysisUs: Long
    ): Double? {

        if (maxAnalysisUs <= 0L) {
            return null
        }

        val bufferInfo =
            MediaCodec.BufferInfo()

        var sawInputEOS = false
        var sawOutputEOS = false

        var firstOutputPtsUs: Long? = null

        var sampleRate = 44100
        var channelCount = 2
        var pcmEncoding =
            AudioFormat.ENCODING_PCM_16BIT

        var blockSize =
            (
                BLOCK_SECONDS *
                    sampleRate
            ).toInt()

        var stepSize =
            (
                STEP_SECONDS *
                    sampleRate
            ).toInt()

        var channelFilters =
            Array(channelCount) {
                KWeightingFilter(sampleRate)
            }

        var channelMeters =
            Array(channelCount) {
                ChannelMeter(blockSize)
            }

        val blockPowers =
            ArrayList<Double>(160)

        var processedFrames = 0L

        while (!sawOutputEOS) {

            /*
             * INPUT
             */
            if (!sawInputEOS) {

                val inputIndex =
                    codec.dequeueInputBuffer(
                        DEQUEUE_TIMEOUT_US
                    )

                if (inputIndex >= 0) {

                    val inputBuffer =
                        codec.getInputBuffer(
                            inputIndex
                        )

                    if (inputBuffer != null) {

                        inputBuffer.clear()

                        val sampleSize =
                            extractor.readSampleData(
                                inputBuffer,
                                0
                            )

                        if (sampleSize < 0) {

                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                0,
                                0L,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )

                            sawInputEOS = true

                        } else {

                            val presentationTimeUs =
                                extractor.sampleTime

                            codec.queueInputBuffer(
                                inputIndex,
                                0,
                                sampleSize,
                                presentationTimeUs,
                                0
                            )

                            extractor.advance()
                        }
                    }
                }
            }

            /*
             * OUTPUT
             */
            when (
                val outputIndex =
                    codec.dequeueOutputBuffer(
                        bufferInfo,
                        DEQUEUE_TIMEOUT_US
                    )
            ) {

                MediaCodec.INFO_TRY_AGAIN_LATER -> {

                    /*
                     * No hacemos 50 intentos artificiales.
                     *
                     * Si ya enviamos EOS y no hay salida,
                     * dejamos que el siguiente ciclo resuelva
                     * el estado del codec.
                     */
                    if (sawInputEOS) {

                        val second =
                            bufferInfo.presentationTimeUs

                        if (
                            second >= maxAnalysisUs &&
                            firstOutputPtsUs != null
                        ) {
                            sawOutputEOS = true
                        }
                    }
                }

                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {

                    val format =
                        codec.outputFormat

                    sampleRate =
                        if (
                            format.containsKey(
                                MediaFormat.KEY_SAMPLE_RATE
                            )
                        ) {
                            format.getInteger(
                                MediaFormat.KEY_SAMPLE_RATE
                            )
                        } else {
                            sampleRate
                        }

                    channelCount =
                        if (
                            format.containsKey(
                                MediaFormat.KEY_CHANNEL_COUNT
                            )
                        ) {
                            format.getInteger(
                                MediaFormat.KEY_CHANNEL_COUNT
                            ).coerceAtLeast(1)
                        } else {
                            channelCount
                        }

                    pcmEncoding =
                        if (
                            format.containsKey(
                                MediaFormat.KEY_PCM_ENCODING
                            )
                        ) {
                            format.getInteger(
                                MediaFormat.KEY_PCM_ENCODING
                            )
                        } else {
                            AudioFormat.ENCODING_PCM_16BIT
                        }

                    blockSize =
                        (
                            BLOCK_SECONDS *
                                sampleRate
                        )
                            .toInt()
                            .coerceAtLeast(1)

                    stepSize =
                        (
                            STEP_SECONDS *
                                sampleRate
                        )
                            .toInt()
                            .coerceAtLeast(1)

                    channelFilters =
                        Array(channelCount) {
                            KWeightingFilter(sampleRate)
                        }

                    channelMeters =
                        Array(channelCount) {
                            ChannelMeter(blockSize)
                        }
                }

                else -> {

                    if (outputIndex < 0) {
                        continue
                    }

                    try {

                        if (bufferInfo.size > 0) {

                            val outputBuffer =
                                codec.getOutputBuffer(
                                    outputIndex
                                )

                            if (outputBuffer != null) {

                                if (
                                    firstOutputPtsUs == null
                                ) {
                                    firstOutputPtsUs =
                                        bufferInfo.presentationTimeUs
                                }

                                outputBuffer.position(
                                    bufferInfo.offset
                                )

                                outputBuffer.limit(
                                    (
                                        bufferInfo.offset +
                                            bufferInfo.size
                                    ).coerceAtMost(
                                        outputBuffer.capacity()
                                    )
                                )

                                processedFrames =
                                    processPcmBufferOptimized(
                                        buffer =
                                            outputBuffer,
                                        pcmEncoding =
                                            pcmEncoding,
                                        channelCount =
                                            channelCount,
                                        channelFilters =
                                            channelFilters,
                                        channelMeters =
                                            channelMeters,
                                        blockPowers =
                                            blockPowers,
                                        blockSize =
                                            blockSize,
                                        stepSize =
                                            stepSize,
                                        processedFrames =
                                            processedFrames,
                                        maxFrames =
                                            (
                                                maxAnalysisUs *
                                                    sampleRate /
                                                    1_000_000L
                                            )
                                    )
                            }
                        }

                        if (
                            bufferInfo.flags and
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM !=
                            0
                        ) {
                            sawOutputEOS = true
                        }

                        /*
                         * Si ya procesamos la ventana completa,
                         * no necesitamos seguir decodificando.
                         */
                        if (
                            processedFrames >=
                                (
                                    maxAnalysisUs *
                                        sampleRate /
                                        1_000_000L
                                )
                        ) {
                            sawOutputEOS = true
                        }

                    } finally {

                        codec.releaseOutputBuffer(
                            outputIndex,
                            false
                        )
                    }
                }
            }
        }

        return computeGainFromBlockPowers(
            blockPowers
        )
    }

    /*
     * Hot loop optimizado.
     *
     * Especializamos estéreo porque es el formato más habitual.
     * Elimina llamadas processSample() y push() por cada sample.
     */
    private fun processPcmBufferOptimized(
        buffer: java.nio.ByteBuffer,
        pcmEncoding: Int,
        channelCount: Int,
        channelFilters:
            Array<KWeightingFilter>,
        channelMeters:
            Array<ChannelMeter>,
        blockPowers:
            MutableList<Double>,
        blockSize: Int,
        stepSize: Int,
        processedFrames: Long,
        maxFrames: Long
    ): Long {

        var currentFrame = processedFrames

        val ordered =
            buffer.slice().order(
                ByteOrder.nativeOrder()
            )

        if (channelCount == 2) {

            when (pcmEncoding) {

                AudioFormat.ENCODING_PCM_16BIT -> {

                    val pcm =
                        ordered.asShortBuffer()

                    val totalFrames =
                        pcm.remaining() / 2

                    var frame = 0

                    while (
                        frame < totalFrames &&
                        currentFrame < maxFrames
                    ) {

                        val left =
                            pcm.get(frame * 2)
                                .toDouble() /
                                32768.0

                        val right =
                            pcm.get(frame * 2 + 1)
                                .toDouble() /
                                32768.0

                        val filteredLeft =
                            channelFilters[0]
                                .process(left)

                        val filteredRight =
                            channelFilters[1]
                                .process(right)

                        channelMeters[0]
                            .push(filteredLeft)

                        channelMeters[1]
                            .push(filteredRight)

                        currentFrame++

                        if (
                            currentFrame >= blockSize &&
                            (
                                currentFrame -
                                    blockSize
                            ) %
                            stepSize.toLong() == 0L
                        ) {

                            val power =
                                channelMeters[0]
                                    .meanSquare +
                                channelMeters[1]
                                    .meanSquare

                            if (
                                power > 0.0 &&
                                power.isFinite()
                            ) {
                                blockPowers.add(power)
                            }
                        }

                        frame++
                    }
                }

                AudioFormat.ENCODING_PCM_FLOAT -> {

                    val pcm =
                        ordered.asFloatBuffer()

                    val totalFrames =
                        pcm.remaining() / 2

                    var frame = 0

                    while (
                        frame < totalFrames &&
                        currentFrame < maxFrames
                    ) {

                        val left =
                            pcm.get(frame * 2)
                                .toDouble()
                                .coerceIn(-1.0, 1.0)

                        val right =
                            pcm.get(frame * 2 + 1)
                                .toDouble()
                                .coerceIn(-1.0, 1.0)

                        val filteredLeft =
                            channelFilters[0]
                                .process(left)

                        val filteredRight =
                            channelFilters[1]
                                .process(right)

                        channelMeters[0]
                            .push(filteredLeft)

                        channelMeters[1]
                            .push(filteredRight)

                        currentFrame++

                        if (
                            currentFrame >= blockSize &&
                            (
                                currentFrame -
                                    blockSize
                            ) %
                            stepSize.toLong() == 0L
                        ) {

                            val power =
                                channelMeters[0]
                                    .meanSquare +
                                channelMeters[1]
                                    .meanSquare

                            if (
                                power > 0.0 &&
                                power.isFinite()
                            ) {
                                blockPowers.add(power)
                            }
                        }

                        frame++
                    }
                }
            }

            return currentFrame
        }

        /*
         * Fallback multicanal.
         */
        return processPcmBufferGeneric(
            ordered = ordered,
            pcmEncoding = pcmEncoding,
            channelCount = channelCount,
            channelFilters = channelFilters,
            channelMeters = channelMeters,
            blockPowers = blockPowers,
            blockSize = blockSize,
            stepSize = stepSize,
            processedFrames = processedFrames,
            maxFrames = maxFrames
        )
    }

    private fun processPcmBufferGeneric(
        ordered: java.nio.ByteBuffer,
        pcmEncoding: Int,
        channelCount: Int,
        channelFilters:
            Array<KWeightingFilter>,
        channelMeters:
            Array<ChannelMeter>,
        blockPowers:
            MutableList<Double>,
        blockSize: Int,
        stepSize: Int,
        processedFrames: Long,
        maxFrames: Long
    ): Long {

        var currentFrame = processedFrames

        when (pcmEncoding) {

            AudioFormat.ENCODING_PCM_16BIT -> {

                val pcm =
                    ordered.asShortBuffer()

                val totalFrames =
                    pcm.remaining() /
                        channelCount

                var frame = 0

                while (
                    frame < totalFrames &&
                    currentFrame < maxFrames
                ) {

                    var channel = 0

                    while (
                        channel < channelCount
                    ) {

                        val sample =
                            pcm.get(
                                frame *
                                    channelCount +
                                    channel
                            )
                                .toDouble() /
                                32768.0

                        val filtered =
                            channelFilters[channel]
                                .process(sample)

                        channelMeters[channel]
                            .push(filtered)

                        channel++

                    }

                    currentFrame++

                    if (
                        currentFrame >= blockSize &&
                        (
                            currentFrame -
                                blockSize
                        ) %
                        stepSize.toLong() == 0L
                    ) {

                        var power = 0.0

                        for (
                            meter in channelMeters
                        ) {
                            power += meter.meanSquare
                        }

                        if (
                            power > 0.0 &&
                            power.isFinite()
                        ) {
                            blockPowers.add(power)
                        }
                    }

                    frame++
                }
            }

            AudioFormat.ENCODING_PCM_FLOAT -> {

                val pcm =
                    ordered.asFloatBuffer()

                val totalFrames =
                    pcm.remaining() /
                        channelCount

                var frame = 0

                while (
                    frame < totalFrames &&
                    currentFrame < maxFrames
                ) {

                    var channel = 0

                    while (
                        channel < channelCount
                    ) {

                        val sample =
                            pcm.get(
                                frame *
                                    channelCount +
                                    channel
                            )
                                .toDouble()
                                .coerceIn(
                                    -1.0,
                                    1.0
                                )

                        val filtered =
                            channelFilters[channel]
                                .process(sample)

                        channelMeters[channel]
                            .push(filtered)

                        channel++

                    }

                    currentFrame++

                    if (
                        currentFrame >= blockSize &&
                        (
                            currentFrame -
                                blockSize
                        ) %
                        stepSize.toLong() == 0L
                    ) {

                        var power = 0.0

                        for (
                            meter in channelMeters
                        ) {
                            power += meter.meanSquare
                        }

                        if (
                            power > 0.0 &&
                            power.isFinite()
                        ) {
                            blockPowers.add(power)
                        }
                    }

                    frame++
                }
            }
        }

        return currentFrame
    }

    private fun computeGainFromBlockPowers(
        blockPowers: List<Double>
    ): Double? {

        if (blockPowers.isEmpty()) {
            return null
        }

        val absoluteGated =
            blockPowers.filter { power ->

                power > 0.0 &&
                    loudnessOf(power) >
                    ABSOLUTE_GATE_LUFS
            }

        if (absoluteGated.isEmpty()) {
            return null
        }

        val ungatedMeanPower =
            absoluteGated.average()

        if (
            ungatedMeanPower <= 0.0 ||
            !ungatedMeanPower.isFinite()
        ) {
            return null
        }

        val relativeThreshold =
            loudnessOf(
                ungatedMeanPower
            ) +
                RELATIVE_GATE_OFFSET_LU

        val relativeGated =
            absoluteGated.filter { power ->

                loudnessOf(power) >
                    relativeThreshold
            }

        val finalBlocks =
            if (relativeGated.isEmpty()) {
                absoluteGated
            } else {
                relativeGated
            }

        val gatedMeanPower =
            finalBlocks.average()

        if (
            gatedMeanPower <= 0.0 ||
            !gatedMeanPower.isFinite()
        ) {
            return null
        }

        val integratedLoudness =
            loudnessOf(
                gatedMeanPower
            )

        if (
            !integratedLoudness.isFinite()
        ) {
            return null
        }

        val gain =
            TARGET_LOUDNESS_LUFS -
                integratedLoudness

        if (!gain.isFinite()) {
            return null
        }

        return gain.coerceIn(
            MIN_VALID_GAIN_DB,
            MAX_VALID_GAIN_DB
        )
    }

    private fun loudnessOf(
        power: Double
    ): Double {

        if (
            power <= 0.0 ||
            !power.isFinite()
        ) {
            return Double.NEGATIVE_INFINITY
        }

        return -0.691 +
            10.0 *
            log10(power)
    }
}

// ===========================================================================
// K-WEIGHTING
// ===========================================================================

private class KWeightingFilter(
    sampleRate: Int
) {

    private val stage1: Biquad
    private val stage2: Biquad

    init {

        val rate =
            sampleRate.toDouble()

        val f0Stage1 =
            1681.974450955533

        val gStage1 =
            3.999843853973347

        val qStage1 =
            0.7071752369554196

        val k1 =
            tan(
                PI *
                    f0Stage1 /
                    rate
            )

        val vh =
            10.0.pow(
                gStage1 / 20.0
            )

        val vb =
            vh.pow(
                0.4996667741545416
            )

        val a0Stage1 =
            1.0 +
                k1 / qStage1 +
                k1 * k1

        stage1 =
            Biquad(
                b0 =
                    (
                        vh +
                            vb *
                            k1 /
                            qStage1 +
                            k1 *
                            k1
                        ) /
                        a0Stage1,

                b1 =
                    2.0 *
                        (
                            k1 * k1 -
                                vh
                            ) /
                        a0Stage1,

                b2 =
                    (
                        vh -
                            vb *
                            k1 /
                            qStage1 +
                            k1 *
                            k1
                        ) /
                        a0Stage1,

                a1 =
                    2.0 *
                        (
                            k1 * k1 -
                                1.0
                            ) /
                        a0Stage1,

                a2 =
                    (
                        1.0 -
                            k1 / qStage1 +
                            k1 * k1
                        ) /
                        a0Stage1
            )

        val f0Stage2 =
            38.13547087602444

        val qStage2 =
            0.5003270373238773

        val k2 =
            tan(
                PI *
                    f0Stage2 /
                    rate
            )

        val a0Stage2 =
            1.0 +
                k2 / qStage2 +
                k2 * k2

        stage2 =
            Biquad(
                b0 = 1.0,
                b1 = -2.0,
                b2 = 1.0,

                a1 =
                    2.0 *
                        (
                            k2 * k2 -
                                1.0
                            ) /
                        a0Stage2,

                a2 =
                    (
                        1.0 -
                            k2 / qStage2 +
                            k2 * k2
                        ) /
                        a0Stage2
            )
    }

    fun process(
        sample: Double
    ): Double {

        return stage2.process(
            stage1.process(sample)
        )
    }
}

// ===========================================================================
// BIQUAD
// ===========================================================================

private class Biquad(
    private val b0: Double,
    private val b1: Double,
    private val b2: Double,
    private val a1: Double,
    private val a2: Double
) {

    private var x1 = 0.0
    private var x2 = 0.0
    private var y1 = 0.0
    private var y2 = 0.0

    fun process(
        x0: Double
    ): Double {

        val y0 =
            b0 * x0 +
                b1 * x1 +
                b2 * x2 -
                a1 * y1 -
                a2 * y2

        x2 = x1
        x1 = x0
        y2 = y1
        y1 = y0

        return y0
    }
}

// ===========================================================================
// MEDIDOR
// ===========================================================================

private class ChannelMeter(
    private val blockSize: Int
) {

    private val squaredBuffer =
        DoubleArray(blockSize)

    private var writeIndex = 0
    private var sumOfSquares = 0.0

    fun push(
        filteredSample: Double
    ) {

        val square =
            filteredSample *
                filteredSample

        sumOfSquares -=
            squaredBuffer[writeIndex]

        squaredBuffer[writeIndex] =
            square

        sumOfSquares += square

        writeIndex++

        if (writeIndex >= blockSize) {
            writeIndex = 0
        }
    }

    val meanSquare: Double
        get() =
            sumOfSquares /
                blockSize
}

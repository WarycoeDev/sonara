
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

                    val filePath = call.argument<String>("filePath")

                    if (filePath.isNullOrEmpty()) {
                        result.error("INVALID_FILE_PATH", "filePath es obligatorio.", null)
                        return@setMethodCallHandler
                    }

                    ReplayGainCalculator.calculateTrackGainAsync(File(filePath)) { gain ->
                        runOnUiThread { result.success(gain) }
                    }
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

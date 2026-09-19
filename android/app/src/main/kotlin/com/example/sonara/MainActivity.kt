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
        super.configureFlutterEngine(
            flutterEngine
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                // =============================================================
                // PERMISO
                // =============================================================

                "requestAudioPermission" -> {

                    if (checkStoragePermission()) {

                        result.success(true)

                    } else {

                        requestStoragePermission()

                        result.success(
                            checkStoragePermission()
                        )
                    }
                }

                // =============================================================
                // ESCANEO LIGERO
                // =============================================================

                "getLibraryFiles" -> {

                    try {

                        result.success(
                            getLibraryFiles()
                        )

                    } catch (exception: Exception) {

                        result.error(
                            "LIBRARY_FILES_QUERY_ERROR",
                            exception.message,
                            null
                        )
                    }
                }

                // =============================================================
                // METADATOS
                // =============================================================

                "getSongMetadata" -> {

                    val filePath =
                        call.argument<String>(
                            "filePath"
                        )

                    if (
                        filePath.isNullOrEmpty()
                    ) {

                        result.error(
                            "INVALID_FILE_PATH",
                            "filePath es obligatorio.",
                            null
                        )

                        return@setMethodCallHandler
                    }

                    try {

                        result.success(
                            getSongMetadata(
                                File(filePath)
                            )
                        )

                    } catch (exception: Exception) {

                        result.error(
                            "SONG_METADATA_ERROR",
                            exception.message,
                            null
                        )
                    }
                }

                // =============================================================
                // PUBLICAR AUDIO EN MUSIC
                // =============================================================

                "publishAudioToMusic" -> {

                    val sourcePath =
                        call.argument<String>(
                            "sourcePath"
                        )

                    val fileName =
                        call.argument<String>(
                            "fileName"
                        )

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

                // =============================================================
                // REPLAYGAIN
                // =============================================================

                "calculateTrackGain" -> {

                    val filePath =
                        call.argument<String>(
                            "filePath"
                        )

                    if (
                        filePath.isNullOrEmpty()
                    ) {

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

                                ReplayGainCalculator
                                    .calculateTrackGain(
                                        File(filePath)
                                    )

                            } catch (
                                exception: Exception
                            ) {

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

    // =======================================================================
    // PUBLICAR AUDIO EN MUSIC
    // =======================================================================

    private fun publishAudioToMusic(
        sourcePath: String,
        fileName: String
    ): String {

        val sourceFile =
            File(sourcePath)

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

        val resolver =
            contentResolver

        // ===================================================================
        // ANDROID 10+
        // ===================================================================

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.Q
        ) {

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
                            "No se pudo abrir el archivo de Music para escritura."
                        )
                    }

                    sourceFile.inputStream().use { inputStream ->

                        val buffer =
                            ByteArray(
                                64 * 1024
                            )

                        while (true) {

                            val bytesRead =
                                inputStream.read(
                                    buffer
                                )

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

                val publicPath =
                    Environment
                        .getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_MUSIC
                        )
                        .absolutePath +
                        File.separator +
                        fileName

                return publicPath

            } catch (exception: Exception) {

                try {

                    resolver.delete(
                        uri,
                        null,
                        null
                    )

                } catch (_: Exception) {
                }

                throw exception
            }
        }

        // ===================================================================
        // ANDROID 9 Y ANTERIORES
        // ===================================================================

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

    // =======================================================================
    // PERMISOS
    // =======================================================================

    private fun checkStoragePermission(): Boolean {

        return when {

            Build.VERSION.SDK_INT >=
                    Build.VERSION_CODES.TIRAMISU -> {

                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_MEDIA_AUDIO
                ) == PackageManager.PERMISSION_GRANTED
            }

            Build.VERSION.SDK_INT >=
                    Build.VERSION_CODES.R -> {

                Environment
                    .isExternalStorageManager()
            }

            else -> {

                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_EXTERNAL_STORAGE
                ) == PackageManager.PERMISSION_GRANTED
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
                            Settings
                                .ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
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
                            Settings
                                .ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION
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

    // =======================================================================
    // ARCHIVOS
    // =======================================================================

    private fun getLibraryFiles():
            List<Map<String, Any?>> {

        val files =
            mutableListOf<
                Map<String, Any?>
            >()

        val storageRoot =
            Environment
                .getExternalStorageDirectory()

        scanLibraryFiles(
            directory = storageRoot,
            files = files
        )

        return files
    }

    private fun scanLibraryFiles(
        directory: File,
        files: MutableList<
            Map<String, Any?>
        >
    ) {

        val directoryFiles =
            try {

                directory.listFiles()

            } catch (_: Exception) {

                null
            }
                ?: return

        for (file in directoryFiles) {

            if (file.isDirectory) {

                if (
                    file.name == "Android" ||
                    file.name.startsWith(".")
                ) {
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
                !supportedExtensions
                    .contains(extension)
            ) {
                continue
            }

            files.add(
                mapOf(
                    "filePath" to
                        file.absolutePath,

                    "lastModified" to
                        file.lastModified(),

                    "fileSize" to
                        file.length()
                )
            )
        }
    }

    // =======================================================================
    // METADATOS
    // =======================================================================

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
                    MediaMetadataRetriever
                        .METADATA_KEY_TITLE
                )
                    ?: file.nameWithoutExtension

            val artist =
                metadataRetriever.extractMetadata(
                    MediaMetadataRetriever
                        .METADATA_KEY_ARTIST
                )

            val album =
                metadataRetriever.extractMetadata(
                    MediaMetadataRetriever
                        .METADATA_KEY_ALBUM
                )

            val duration =
                metadataRetriever.extractMetadata(
                    MediaMetadataRetriever
                        .METADATA_KEY_DURATION
                )
                    ?.toLongOrNull()
                    ?: 0L

            return mapOf(
                "id" to
                    file.absolutePath,

                "filePath" to
                    file.absolutePath,

                "title" to
                    title,

                "artist" to
                    artist,

                "album" to
                    album,

                "duration" to
                    duration,

                "dateAdded" to
                    file.lastModified(),

                "lastModified" to
                    file.lastModified(),

                "fileSize" to
                    file.length()
            )

        } catch (_: Exception) {

            return createFallbackSong(
                file
            )

        } finally {

            try {

                metadataRetriever.release()

            } catch (_: Exception) {
            }
        }
    }

    // =======================================================================
    // FALLBACK
    // =======================================================================

    private fun createFallbackSong(
        file: File
    ): Map<String, Any?> {

        return mapOf(
            "id" to
                file.absolutePath,

            "filePath" to
                file.absolutePath,

            "title" to
                file.nameWithoutExtension,

            "artist" to
                null,

            "album" to
                null,

            "duration" to
                0L,

            "dateAdded" to
                file.lastModified(),

            "lastModified" to
                file.lastModified(),

            "fileSize" to
                file.length()
        )
    }
}

// ===========================================================================
// REPLAYGAIN
// ===========================================================================

private object ReplayGainCalculator {

    private const val TARGET_LOUDNESS_LUFS =
        -18.0

    private const val ABSOLUTE_GATE_LUFS =
        -70.0

    private const val RELATIVE_GATE_OFFSET_LU =
        -10.0

    private const val MIN_VALID_GAIN_DB =
        -30.0

    private const val MAX_VALID_GAIN_DB =
        30.0

    private const val BLOCK_SECONDS =
        0.4

    private const val STEP_SECONDS =
        0.1

    private const val SEGMENT_COUNT =
        3

    private const val SEGMENT_SECONDS =
        5.0

    private const val MAX_ANALYSIS_SECONDS =
        15.0

    private const val DEQUEUE_TIMEOUT_US =
        10_000L

    private const val MAX_TRAILING_TRY_AGAIN =
        50

    fun calculateTrackGain(
        file: File
    ): Double? {

        if (
            !file.exists() ||
            !file.isFile
        ) {
            return null
        }

        val durationUs =
            getDurationUs(
                file
            )

        return try {

            calculateTrackGainInternal(
                file = file,
                durationUs = durationUs
            )

        } catch (_: Exception) {

            null
        }
    }

    private fun calculateTrackGainInternal(
        file: File,
        durationUs: Long
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

        var trackIndex =
            -1

        var inputFormat:
                MediaFormat? =
            null

        for (
            index in
            0 until extractor.trackCount
        ) {

            val trackFormat =
                extractor.getTrackFormat(
                    index
                )

            val mime =
                trackFormat.getString(
                    MediaFormat.KEY_MIME
                )

            if (
                mime != null &&
                mime.startsWith(
                    "audio/"
                )
            ) {

                trackIndex =
                    index

                inputFormat =
                    trackFormat

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

        extractor.selectTrack(
            trackIndex
        )

        val mime =
            inputFormat.getString(
                MediaFormat.KEY_MIME
            )

        if (
            mime.isNullOrEmpty()
        ) {

            extractor.release()

            return null
        }

        val codec =
            try {

                MediaCodec
                    .createDecoderByType(
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

            val segmentStartsUs =
                getSegmentStartsUs(
                    durationUs
                )

            val blockPowers =
                mutableListOf<Double>()

            for (
                startUs in
                segmentStartsUs
            ) {

                val segmentPowers =
                    measureSegmentWithExistingDecoder(
                        extractor = extractor,
                        codec = codec,
                        startUs = startUs,
                        segmentSeconds =
                            getSegmentDurationSeconds(
                                durationUs = durationUs,
                                startUs = startUs
                            )
                    )

                blockPowers.addAll(
                    segmentPowers
                )
            }

            computeGainFromBlockPowers(
                blockPowers
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

    private fun getDurationUs(
        file: File
    ): Long {

        val retriever =
            MediaMetadataRetriever()

        return try {

            retriever.setDataSource(
                file.absolutePath
            )

            val durationMs =
                retriever.extractMetadata(
                    MediaMetadataRetriever
                        .METADATA_KEY_DURATION
                )
                    ?.toLongOrNull()
                    ?: 0L

            durationMs * 1000L

        } catch (_: Exception) {

            0L

        } finally {

            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun getSegmentStartsUs(
        durationUs: Long
    ): List<Long> {

        if (
            durationUs <= 0L
        ) {

            return listOf(
                0L
            )
        }

        val durationSeconds =
            durationUs /
                    1_000_000.0

        if (
            durationSeconds <=
            MAX_ANALYSIS_SECONDS
        ) {

            return listOf(
                0L
            )
        }

        val starts =
            mutableListOf<Long>()

        val fractions =
            doubleArrayOf(
                0.20,
                0.50,
                0.80
            )

        for (
            fraction in fractions
        ) {

            val centerSeconds =
                durationSeconds *
                        fraction

            val startSeconds =
                (
                    centerSeconds -
                            SEGMENT_SECONDS / 2.0
                ).coerceIn(
                    0.0,
                    (
                        durationSeconds -
                                SEGMENT_SECONDS
                    )
                        .coerceAtLeast(
                            0.0
                        )
                )

            starts.add(
                (
                    startSeconds *
                            1_000_000.0
                ).toLong()
            )
        }

        return starts
    }

    private fun getSegmentDurationSeconds(
        durationUs: Long,
        startUs: Long
    ): Double {

        if (
            durationUs <= 0L
        ) {

            return MAX_ANALYSIS_SECONDS
        }

        val remainingUs =
            (
                durationUs -
                        startUs
            )
                .coerceAtLeast(
                    0L
                )

        val remainingSeconds =
            remainingUs /
                    1_000_000.0

        return minOf(
            if (
                durationUs /
                    1_000_000.0 <=
                MAX_ANALYSIS_SECONDS
            ) {

                MAX_ANALYSIS_SECONDS

            } else {

                SEGMENT_SECONDS
            },

            remainingSeconds
        )
    }

    private fun measureSegmentWithExistingDecoder(
        extractor: MediaExtractor,
        codec: MediaCodec,
        startUs: Long,
        segmentSeconds: Double
    ): List<Double> {

        if (
            segmentSeconds <= 0.0
        ) {

            return emptyList()
        }

        try {

            extractor.seekTo(
                startUs,
                MediaExtractor
                    .SEEK_TO_PREVIOUS_SYNC
            )

        } catch (_: Exception) {

            return emptyList()
        }

        try {

            codec.flush()

        } catch (_: Exception) {

            return emptyList()
        }

        val outputFormat =
            try {

                codec.outputFormat

            } catch (_: Exception) {

                null
            }

        var sampleRate =
            if (
                outputFormat != null &&
                outputFormat.containsKey(
                    MediaFormat.KEY_SAMPLE_RATE
                )
            ) {

                outputFormat.getInteger(
                    MediaFormat.KEY_SAMPLE_RATE
                )

            } else {

                44100
            }

        var channelCount =
            if (
                outputFormat != null &&
                outputFormat.containsKey(
                    MediaFormat.KEY_CHANNEL_COUNT
                )
            ) {

                outputFormat
                    .getInteger(
                        MediaFormat.KEY_CHANNEL_COUNT
                    )
                    .coerceAtLeast(
                        1
                    )

            } else {

                1
            }

        var pcmEncoding =
            if (
                outputFormat != null &&
                outputFormat.containsKey(
                    MediaFormat.KEY_PCM_ENCODING
                )
            ) {

                outputFormat.getInteger(
                    MediaFormat.KEY_PCM_ENCODING
                )

            } else {

                AudioFormat
                    .ENCODING_PCM_16BIT
            }

        var blockSize =
            (
                BLOCK_SECONDS *
                        sampleRate
            )
                .toInt()
                .coerceAtLeast(
                    1
                )

        var stepSize =
            (
                STEP_SECONDS *
                        sampleRate
            )
                .toInt()
                .coerceAtLeast(
                    1
                )

        var channelFilters =
            Array(
                channelCount
            ) {

                KWeightingFilter(
                    sampleRate
                )
            }

        var channelMeters =
            Array(
                channelCount
            ) {

                ChannelMeter(
                    blockSize
                )
            }

        var channelWeights =
            DoubleArray(
                channelCount
            ) {

                1.0
            }

        val blockPowers =
            mutableListOf<Double>()

        val maxFrames =
            (
                segmentSeconds *
                        sampleRate
            ).toLong()

        var processedFrames =
            0L

        val bufferInfo =
            MediaCodec.BufferInfo()

        var sawInputEOS =
            false

        var sawOutputEOS =
            false

        var trailingTryAgainCount =
            0

        try {

            while (
                !sawOutputEOS &&
                processedFrames <
                maxFrames
            ) {

                if (
                    !sawInputEOS
                ) {

                    val inputIndex =
                        codec.dequeueInputBuffer(
                            DEQUEUE_TIMEOUT_US
                        )

                    if (
                        inputIndex >= 0
                    ) {

                        val inputBuffer =
                            codec.getInputBuffer(
                                inputIndex
                            )

                        if (
                            inputBuffer != null
                        ) {

                            inputBuffer.clear()

                            val sampleSize =
                                extractor.readSampleData(
                                    inputBuffer,
                                    0
                                )

                            if (
                                sampleSize < 0
                            ) {

                                codec.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    0,
                                    0,
                                    MediaCodec
                                        .BUFFER_FLAG_END_OF_STREAM
                                )

                                sawInputEOS =
                                    true

                            } else {

                                codec.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    sampleSize,
                                    extractor.sampleTime,
                                    0
                                )

                                extractor.advance()
                            }
                        }
                    }
                }

                when (
                    val outputIndex =
                        codec.dequeueOutputBuffer(
                            bufferInfo,
                            DEQUEUE_TIMEOUT_US
                        )
                ) {

                    MediaCodec
                        .INFO_TRY_AGAIN_LATER -> {

                        if (
                            sawInputEOS
                        ) {

                            trailingTryAgainCount++

                            if (
                                trailingTryAgainCount >=
                                MAX_TRAILING_TRY_AGAIN
                            ) {

                                sawOutputEOS =
                                    true
                            }
                        }
                    }

                    MediaCodec
                        .INFO_OUTPUT_FORMAT_CHANGED -> {

                        trailingTryAgainCount =
                            0

                        val realOutputFormat =
                            codec.outputFormat

                        sampleRate =
                            if (
                                realOutputFormat.containsKey(
                                    MediaFormat.KEY_SAMPLE_RATE
                                )
                            ) {

                                realOutputFormat.getInteger(
                                    MediaFormat.KEY_SAMPLE_RATE
                                )

                            } else {

                                sampleRate
                            }

                        channelCount =
                            if (
                                realOutputFormat.containsKey(
                                    MediaFormat.KEY_CHANNEL_COUNT
                                )
                            ) {

                                realOutputFormat
                                    .getInteger(
                                        MediaFormat.KEY_CHANNEL_COUNT
                                    )
                                    .coerceAtLeast(
                                        1
                                    )

                            } else {

                                channelCount
                            }

                        pcmEncoding =
                            if (
                                realOutputFormat.containsKey(
                                    MediaFormat.KEY_PCM_ENCODING
                                )
                            ) {

                                realOutputFormat.getInteger(
                                    MediaFormat.KEY_PCM_ENCODING
                                )

                            } else {

                                AudioFormat
                                    .ENCODING_PCM_16BIT
                            }

                        blockSize =
                            (
                                BLOCK_SECONDS *
                                        sampleRate
                            )
                                .toInt()
                                .coerceAtLeast(
                                    1
                                )

                        stepSize =
                            (
                                STEP_SECONDS *
                                        sampleRate
                            )
                                .toInt()
                                .coerceAtLeast(
                                    1
                                )

                        channelFilters =
                            Array(
                                channelCount
                            ) {

                                KWeightingFilter(
                                    sampleRate
                                )
                            }

                        channelMeters =
                            Array(
                                channelCount
                            ) {

                                ChannelMeter(
                                    blockSize
                                )
                            }

                        channelWeights =
                            DoubleArray(
                                channelCount
                            ) {

                                1.0
                            }
                    }

                    else -> {

                        if (
                            outputIndex >= 0
                        ) {

                            trailingTryAgainCount =
                                0

                            try {

                                if (
                                    bufferInfo.size > 0
                                ) {

                                    val outputBuffer =
                                        codec.getOutputBuffer(
                                            outputIndex
                                        )

                                    if (
                                        outputBuffer != null
                                    ) {

                                        outputBuffer.position(
                                            bufferInfo.offset
                                        )

                                        outputBuffer.limit(
                                            bufferInfo.offset +
                                                    bufferInfo.size
                                        )

                                        processedFrames =
                                            processPcmBuffer(
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

                                                channelWeights =
                                                    channelWeights,

                                                blockPowers =
                                                    blockPowers,

                                                blockSize =
                                                    blockSize,

                                                stepSize =
                                                    stepSize,

                                                processedFrames =
                                                    processedFrames,

                                                maxFrames =
                                                    maxFrames
                                            )
                                    }
                                }

                                if (
                                    bufferInfo.flags and
                                    MediaCodec
                                        .BUFFER_FLAG_END_OF_STREAM
                                    != 0
                                ) {

                                    sawOutputEOS =
                                        true
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
            }

        } catch (_: Exception) {

            return emptyList()
        }

        return blockPowers
    }

    private fun processPcmBuffer(
        buffer: java.nio.ByteBuffer,
        pcmEncoding: Int,
        channelCount: Int,
        channelFilters:
                Array<KWeightingFilter>,
        channelMeters:
                Array<ChannelMeter>,
        channelWeights:
                DoubleArray,
        blockPowers:
                MutableList<Double>,
        blockSize: Int,
        stepSize: Int,
        processedFrames: Long,
        maxFrames: Long
    ): Long {

        var currentFrame =
            processedFrames

        val orderedBuffer =
            buffer
                .slice()
                .order(
                    ByteOrder
                        .nativeOrder()
                )

        when (
            pcmEncoding
        ) {

            AudioFormat
                .ENCODING_PCM_FLOAT -> {

                val floatBuffer =
                    orderedBuffer
                        .asFloatBuffer()

                val frames =
                    floatBuffer.remaining() /
                            channelCount

                var frame =
                    0

                while (
                    frame < frames &&
                    currentFrame <
                    maxFrames
                ) {

                    for (
                        channel in
                        0 until channelCount
                    ) {

                        val sample =
                            floatBuffer.get(
                                frame *
                                        channelCount +
                                        channel
                            )
                                .toDouble()
                                .coerceIn(
                                    -1.0,
                                    1.0
                                )

                        processSample(
                            sample = sample,
                            channel = channel,
                            channelFilters =
                                channelFilters,
                            channelMeters =
                                channelMeters
                        )
                    }

                    currentFrame++

                    addBlockIfNeeded(
                        frameIndex =
                            currentFrame,
                        blockSize =
                            blockSize,
                        stepSize =
                            stepSize,
                        channelWeights =
                            channelWeights,
                        channelMeters =
                            channelMeters,
                        blockPowers =
                            blockPowers
                    )

                    frame++
                }
            }

            AudioFormat
                .ENCODING_PCM_16BIT -> {

                val shortBuffer =
                    orderedBuffer
                        .asShortBuffer()

                val frames =
                    shortBuffer.remaining() /
                            channelCount

                var frame =
                    0

                while (
                    frame < frames &&
                    currentFrame <
                    maxFrames
                ) {

                    for (
                        channel in
                        0 until channelCount
                    ) {

                        val raw =
                            shortBuffer.get(
                                frame *
                                        channelCount +
                                        channel
                            )

                        val sample =
                            raw /
                                    32768.0

                        processSample(
                            sample = sample,
                            channel = channel,
                            channelFilters =
                                channelFilters,
                            channelMeters =
                                channelMeters
                        )
                    }

                    currentFrame++

                    addBlockIfNeeded(
                        frameIndex =
                            currentFrame,
                        blockSize =
                            blockSize,
                        stepSize =
                            stepSize,
                        channelWeights =
                            channelWeights,
                        channelMeters =
                            channelMeters,
                        blockPowers =
                            blockPowers
                    )

                    frame++
                }
            }

            else -> {
                // PCM no soportado.
            }
        }

        return currentFrame
    }

    private fun processSample(
        sample: Double,
        channel: Int,
        channelFilters:
                Array<KWeightingFilter>,
        channelMeters:
                Array<ChannelMeter>
    ) {

        val filtered =
            channelFilters[channel]
                .process(
                    sample
                )

        channelMeters[channel]
            .push(
                filtered
            )
    }

    private fun addBlockIfNeeded(
        frameIndex: Long,
        blockSize: Int,
        stepSize: Int,
        channelWeights:
                DoubleArray,
        channelMeters:
                Array<ChannelMeter>,
        blockPowers:
                MutableList<Double>
    ) {

        if (
            frameIndex <
            blockSize
        ) {
            return
        }

        if (
            (
                frameIndex -
                        blockSize
            ) %
            stepSize.toLong() !=
            0L
        ) {
            return
        }

        var weightedPower =
            0.0

        for (
            channel in
            channelMeters.indices
        ) {

            weightedPower +=
                channelWeights[channel] *
                        channelMeters[channel]
                            .meanSquare
        }

        if (
            weightedPower > 0.0 &&
            !weightedPower.isNaN() &&
            !weightedPower.isInfinite()
        ) {

            blockPowers.add(
                weightedPower
            )
        }
    }

    private fun computeGainFromBlockPowers(
        blockPowers: List<Double>
    ): Double? {

        if (
            blockPowers.isEmpty()
        ) {
            return null
        }

        val absoluteGated =
            blockPowers.filter {

                it > 0.0 &&
                        loudnessOf(it) >
                        ABSOLUTE_GATE_LUFS
            }

        if (
            absoluteGated.isEmpty()
        ) {
            return null
        }

        val ungatedMeanPower =
            absoluteGated.average()

        if (
            ungatedMeanPower <= 0.0
        ) {
            return null
        }

        val relativeThreshold =
            loudnessOf(
                ungatedMeanPower
            ) +
                    RELATIVE_GATE_OFFSET_LU

        val relativeGated =
            absoluteGated.filter {

                loudnessOf(it) >
                        relativeThreshold
            }

        val finalBlocks =
            if (
                relativeGated.isEmpty()
            ) {

                absoluteGated

            } else {

                relativeGated
            }

        val gatedMeanPower =
            finalBlocks.average()

        if (
            gatedMeanPower <= 0.0
        ) {
            return null
        }

        val integratedLoudness =
            loudnessOf(
                gatedMeanPower
            )

        if (
            integratedLoudness.isNaN() ||
            integratedLoudness.isInfinite()
        ) {
            return null
        }

        val gain =
            TARGET_LOUDNESS_LUFS -
                    integratedLoudness

        if (
            gain.isNaN() ||
            gain.isInfinite()
        ) {
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
            power <= 0.0
        ) {
            return Double.NEGATIVE_INFINITY
        }

        return -0.691 +
                10.0 *
                log10(
                    power
                )
    }
}

// ===========================================================================
// FILTRO K-WEIGHTING
// ===========================================================================

private class KWeightingFilter(
    sampleRate: Int
) {

    private val stage1:
            Biquad

    private val stage2:
            Biquad

    init {

        val rate =
            sampleRate
                .toDouble()

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
                gStage1 /
                        20.0
            )

        val vb =
            vh.pow(
                0.4996667741545416
            )

        val a0Stage1 =
            1.0 +
                    k1 /
                    qStage1 +
                    k1 *
                    k1

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
                                k1 *
                                        k1 -
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
                                k1 *
                                        k1 -
                                        1.0
                            ) /
                            a0Stage1,

                a2 =
                    (
                        1.0 -
                                k1 /
                                qStage1 +
                                k1 *
                                k1
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
                    k2 /
                    qStage2 +
                    k2 *
                    k2

        stage2 =
            Biquad(
                b0 =
                    1.0,

                b1 =
                    -2.0,

                b2 =
                    1.0,

                a1 =
                    2.0 *
                            (
                                k2 *
                                        k2 -
                                        1.0
                            ) /
                            a0Stage2,

                a2 =
                    (
                        1.0 -
                                k2 /
                                qStage2 +
                                k2 *
                                k2
                    ) /
                            a0Stage2
            )
    }

    fun process(
        sample: Double
    ): Double {

        return stage2.process(
            stage1.process(
                sample
            )
        )
    }
}

// ===========================================================================
// BIQUAD
// ===========================================================================

private class Biquad(
    private val b0:
            Double,

    private val b1:
            Double,

    private val b2:
            Double,

    private val a1:
            Double,

    private val a2:
            Double
) {

    private var x1 =
        0.0

    private var x2 =
        0.0

    private var y1 =
        0.0

    private var y2 =
        0.0

    fun process(
        x0: Double
    ): Double {

        val y0 =
            b0 *
                    x0 +
                    b1 *
                    x1 +
                    b2 *
                    x2 -
                    a1 *
                    y1 -
                    a2 *
                    y2

        x2 =
            x1

        x1 =
            x0

        y2 =
            y1

        y1 =
            y0

        return y0
    }
}

// ===========================================================================
// MEDIDOR POR CANAL
// ===========================================================================

private class ChannelMeter(
    private val blockSize:
            Int
) {

    private val squaredBuffer =
        DoubleArray(
            blockSize
        )

    private var writeIndex =
        0

    private var sumOfSquares =
        0.0

    fun push(
        filteredSample:
                Double
    ) {

        val square =
            filteredSample *
                    filteredSample

        sumOfSquares -=
            squaredBuffer[
                    writeIndex
            ]

        squaredBuffer[
                writeIndex
        ] =
            square

        sumOfSquares +=
            square

        writeIndex =
            (
                writeIndex +
                        1
            ) %
                    blockSize
    }

    val meanSquare:
            Double
        get() =
            sumOfSquares /
                    blockSize
}
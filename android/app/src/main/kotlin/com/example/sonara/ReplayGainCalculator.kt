package com.warycoe.sonara

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Process
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadFactory
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import kotlin.math.PI
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.tan

// =============================================================================
// REPLAYGAIN RÁPIDO (BS.1770 / EBU R128, objetivo -18 LUFS)
//
// Qué hace distinto respecto a la versión anterior:
//
//  1. Pool de hilos fijo (2..4) en vez de un Thread nuevo por canción.
//  2. Bucle de MediaCodec que llena TODOS los buffers de entrada antes de
//     drenar la salida (antes: 1 entrada -> esperar hasta 10 ms -> 1 salida).
//  3. Una sola ventana centrada de ANALYSIS_SECONDS, seek ANTES de crear el
//     codec (sin flush).
//  4. WAV/PCM ("audio/raw"): se lee directo del extractor, sin MediaCodec.
//  5. Medidor por sub-bloques de 100 ms: cada muestra solo cuesta 2 biquads
//     y una suma. Sin ring buffer por canal, sin deriva de punto flotante.
//  6. Hot loop estéreo especializado con estado en variables locales y un
//     solo paso de conversión (bulk copy) desde el buffer del codec.
//  7. Gating en dominio de potencia: un único log10 por canción.
// =============================================================================

internal object ReplayGainCalculator {

    private const val TAG = "SONARA_REPLAYGAIN"

    const val TARGET_LOUDNESS_LUFS = -18.0

    private const val ABSOLUTE_GATE_LUFS = -70.0
    private const val RELATIVE_GATE_OFFSET_LU = -10.0
    private const val MIN_VALID_GAIN_DB = -30.0
    private const val MAX_VALID_GAIN_DB = 30.0

    /** Ventana analizada. Menos segundos = más rápido, más segundos = más preciso. */
    private const val ANALYSIS_SECONDS = 7.0

    private const val CODEC_TIMEOUT_US = 4_000L
    private const val MAX_STALLED_POLLS = 500 // ~2 s sin salida del codec
    private const val RAW_MIME = "audio/raw"
    private const val RAW_READ_BYTES = 1 shl 20

    // -------------------------------------------------------------------------
    // POOL DE HILOS
    // -------------------------------------------------------------------------

    private val workerCount =
        (Runtime.getRuntime().availableProcessors() / 2).coerceIn(2, 4)

    private val executor: ThreadPoolExecutor by lazy {
        ThreadPoolExecutor(
            workerCount,
            workerCount,
            30L,
            TimeUnit.SECONDS,
            LinkedBlockingQueue<Runnable>(),
            ThreadFactory { runnable ->
                Thread(
                    {
                        // LESS_FAVORABLE no cae en el cgroup "background",
                        // así que no se estrangula la CPU.
                        Process.setThreadPriority(
                            Process.THREAD_PRIORITY_LESS_FAVORABLE
                        )
                        runnable.run()
                    },
                    "sonara-replaygain"
                ).apply { isDaemon = true }
            }
        ).apply { allowCoreThreadTimeOut(true) }
    }

    /** Encola el análisis. [onResult] se llama SIEMPRE, desde un hilo de trabajo. */
    fun calculateTrackGainAsync(
        file: File,
        onResult: (Double?) -> Unit
    ) {
        executor.execute {
            val gain = calculateTrackGain(file)

            try {
                onResult(gain)
            } catch (throwable: Throwable) {
                Log.e(TAG, "Error entregando resultado.", throwable)
            }
        }
    }

    /** Versión síncrona (bloquea el hilo que la llama). */
    fun calculateTrackGain(file: File): Double? {

        if (!file.isFile) {
            return null
        }

        val startNs = System.nanoTime()

        val gain =
            try {
                analyze(file)
            } catch (throwable: Throwable) {
                Log.e(TAG, "Error calculando gain: ${file.name}", throwable)
                null
            }

        Log.d(
            TAG,
            "${file.name}: gain=$gain dB " +
                "(${(System.nanoTime() - startNs) / 1_000_000} ms)"
        )

        return gain
    }

    // -------------------------------------------------------------------------
    // ANÁLISIS
    // -------------------------------------------------------------------------

    private fun analyze(file: File): Double? {

        val extractor = MediaExtractor()
        var codec: MediaCodec? = null

        try {

            extractor.setDataSource(file.absolutePath)

            var format: MediaFormat? = null

            for (index in 0 until extractor.trackCount) {

                val candidate = extractor.getTrackFormat(index)
                val candidateMime =
                    candidate.getString(MediaFormat.KEY_MIME)

                if (
                    candidateMime != null &&
                    candidateMime.startsWith("audio/")
                ) {
                    extractor.selectTrack(index)
                    format = candidate
                    break
                }
            }

            if (format == null) {
                return null
            }

            val mime =
                format.getString(MediaFormat.KEY_MIME)
                    ?: return null

            val durationUs =
                format.intOrLong(MediaFormat.KEY_DURATION) ?: 0L

            val windowUs =
                (ANALYSIS_SECONDS * 1_000_000.0).toLong()

            // Seek ANTES de crear el codec: no hace falta flush.
            if (durationUs > windowUs) {

                extractor.seekTo(
                    durationUs / 2L - windowUs / 2L,
                    MediaExtractor.SEEK_TO_PREVIOUS_SYNC
                )

                if (extractor.sampleTime < 0L) {
                    extractor.seekTo(
                        0L,
                        MediaExtractor.SEEK_TO_CLOSEST_SYNC
                    )
                }
            }

            val sampleRate =
                format.intOrNull(MediaFormat.KEY_SAMPLE_RATE) ?: 44100

            val channels =
                (format.intOrNull(MediaFormat.KEY_CHANNEL_COUNT) ?: 2)
                    .coerceAtLeast(1)

            // WAV / PCM: sin codec.
            if (mime == RAW_MIME) {

                val rawEncoding =
                    format.intOrNull(MediaFormat.KEY_PCM_ENCODING)
                        ?: AudioFormat.ENCODING_PCM_16BIT

                if (LoudnessMeter.supports(rawEncoding)) {

                    return readRawPcm(
                        extractor = extractor,
                        meter = LoudnessMeter(
                            sampleRate,
                            channels,
                            ANALYSIS_SECONDS
                        ),
                        encoding = rawEncoding
                    )
                }
            }

            val decoder =
                MediaCodec.createDecoderByType(mime)

            codec = decoder

            decoder.configure(format, null, null, 0)
            decoder.start()

            return decodeWithCodec(
                extractor = extractor,
                codec = decoder,
                initialMeter = LoudnessMeter(
                    sampleRate,
                    channels,
                    ANALYSIS_SECONDS
                )
            )

        } finally {

            // release() ya detiene el codec; evitamos un stop() extra.
            try {
                codec?.release()
            } catch (_: Exception) {
            }

            try {
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun readRawPcm(
        extractor: MediaExtractor,
        meter: LoudnessMeter,
        encoding: Int
    ): Double? {

        val buffer =
            ByteBuffer.allocateDirect(RAW_READ_BYTES)

        while (!meter.isFull) {

            buffer.clear()

            val size =
                extractor.readSampleData(buffer, 0)

            if (size < 0) {
                break
            }

            buffer.position(0)
            buffer.limit(size)

            meter.consume(
                buffer,
                encoding,
                ByteOrder.LITTLE_ENDIAN
            )

            extractor.advance()
        }

        return gainFromBlocks(
            meter.blockPowers,
            meter.blockCount
        )
    }

    private fun decodeWithCodec(
        extractor: MediaExtractor,
        codec: MediaCodec,
        initialMeter: LoudnessMeter
    ): Double? {

        var meter = initialMeter
        var encoding = AudioFormat.ENCODING_PCM_16BIT

        val info = MediaCodec.BufferInfo()

        var inputDone = false
        var outputDone = false
        var stalledPolls = 0

        while (!outputDone && !meter.isFull) {

            // -----------------------------------------------------------------
            // ENTRADA: llenar todos los buffers libres sin esperar.
            // -----------------------------------------------------------------
            var fed = false

            while (!inputDone) {

                val inputIndex =
                    codec.dequeueInputBuffer(0L)

                if (inputIndex < 0) {
                    break
                }

                val inputBuffer =
                    codec.getInputBuffer(inputIndex)

                val size =
                    if (inputBuffer != null) {
                        extractor.readSampleData(inputBuffer, 0)
                    } else {
                        -1
                    }

                if (size < 0) {

                    codec.queueInputBuffer(
                        inputIndex,
                        0,
                        0,
                        0L,
                        MediaCodec.BUFFER_FLAG_END_OF_STREAM
                    )

                    inputDone = true

                } else {

                    codec.queueInputBuffer(
                        inputIndex,
                        0,
                        size,
                        extractor.sampleTime,
                        0
                    )

                    extractor.advance()
                }

                fed = true
            }

            // -----------------------------------------------------------------
            // SALIDA: drenar todo lo disponible. Solo se espera si no se pudo
            // alimentar nada (el codec está ocupado procesando).
            // -----------------------------------------------------------------
            var firstPoll = true

            while (!meter.isFull) {

                val timeoutUs =
                    if (firstPoll && !fed) CODEC_TIMEOUT_US else 0L

                firstPoll = false

                val outputIndex =
                    codec.dequeueOutputBuffer(info, timeoutUs)

                if (outputIndex >= 0) {

                    stalledPolls = 0

                    val outputBuffer =
                        codec.getOutputBuffer(outputIndex)

                    if (outputBuffer != null && info.size > 0) {

                        outputBuffer.position(info.offset)
                        outputBuffer.limit(info.offset + info.size)

                        meter.consume(
                            outputBuffer,
                            encoding,
                            ByteOrder.nativeOrder()
                        )
                    }

                    codec.releaseOutputBuffer(outputIndex, false)

                    if (
                        (info.flags and
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                    ) {
                        outputDone = true
                        break
                    }

                } else if (
                    outputIndex ==
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED
                ) {

                    val outFormat = codec.outputFormat

                    val newRate =
                        outFormat.intOrNull(
                            MediaFormat.KEY_SAMPLE_RATE
                        ) ?: meter.sampleRate

                    val newChannels =
                        (
                            outFormat.intOrNull(
                                MediaFormat.KEY_CHANNEL_COUNT
                            ) ?: meter.channels
                            ).coerceAtLeast(1)

                    encoding =
                        outFormat.intOrNull(
                            MediaFormat.KEY_PCM_ENCODING
                        ) ?: AudioFormat.ENCODING_PCM_16BIT

                    if (
                        newRate != meter.sampleRate ||
                        newChannels != meter.channels
                    ) {
                        meter = LoudnessMeter(
                            newRate,
                            newChannels,
                            ANALYSIS_SECONDS
                        )
                    }

                } else if (
                    outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER
                ) {

                    if (timeoutUs > 0L) {
                        stalledPolls++
                    }

                    break
                }
                // Cualquier otro valor negativo (buffers changed): reintentar.
            }

            if (stalledPolls > MAX_STALLED_POLLS) {
                break
            }
        }

        return gainFromBlocks(
            meter.blockPowers,
            meter.blockCount
        )
    }

    // -------------------------------------------------------------------------
    // GATING (BS.1770-4) en dominio de potencia
    // -------------------------------------------------------------------------

    private fun gainFromBlocks(
        powers: DoubleArray,
        count: Int
    ): Double? {

        if (count <= 0) {
            return null
        }

        val absoluteThreshold =
            10.0.pow((ABSOLUTE_GATE_LUFS + 0.691) / 10.0)

        var sum = 0.0
        var kept = 0

        for (index in 0 until count) {

            val power = powers[index]

            if (power > absoluteThreshold) {
                sum += power
                kept++
            }
        }

        if (kept == 0) {
            return null
        }

        // -10 LU en potencia = x0.1
        val relativeThreshold =
            (sum / kept) *
                10.0.pow(RELATIVE_GATE_OFFSET_LU / 10.0)

        var gatedSum = 0.0
        var gatedKept = 0

        for (index in 0 until count) {

            val power = powers[index]

            if (
                power > absoluteThreshold &&
                power > relativeThreshold
            ) {
                gatedSum += power
                gatedKept++
            }
        }

        val meanPower =
            if (gatedKept > 0) {
                gatedSum / gatedKept
            } else {
                sum / kept
            }

        if (meanPower <= 0.0 || !meanPower.isFinite()) {
            return null
        }

        val loudness =
            -0.691 + 10.0 * log10(meanPower)

        val gain =
            TARGET_LOUDNESS_LUFS - loudness

        if (!gain.isFinite()) {
            return null
        }

        return gain.coerceIn(
            MIN_VALID_GAIN_DB,
            MAX_VALID_GAIN_DB
        )
    }

    // -------------------------------------------------------------------------
    // HELPERS
    // -------------------------------------------------------------------------

    private fun MediaFormat.intOrNull(key: String): Int? =
        if (containsKey(key)) getInteger(key) else null

    private fun MediaFormat.intOrLong(key: String): Long? =
        if (containsKey(key)) {
            try {
                getLong(key)
            } catch (_: Exception) {
                getInteger(key).toLong()
            }
        } else {
            null
        }
}

// =============================================================================
// MEDIDOR: K-weighting + bloques de 400 ms (paso 100 ms)
//
// Se acumula la energía por sub-bloques de 100 ms. Cada bloque de 400 ms es la
// suma de los últimos 4 sub-bloques (solape del 75 %, idéntico a BS.1770).
// =============================================================================

private class LoudnessMeter(
    val sampleRate: Int,
    val channels: Int,
    windowSeconds: Double
) {

    companion object {

        private const val INV_32768 = 1f / 32768f

        fun supports(encoding: Int): Boolean =
            encoding == AudioFormat.ENCODING_PCM_16BIT ||
                encoding == AudioFormat.ENCODING_PCM_FLOAT
    }

    val maxFrames: Long =
        (windowSeconds * sampleRate).toLong()

    var processedFrames = 0L
        private set

    val isFull: Boolean
        get() = processedFrames >= maxFrames

    private val subBlockFrames =
        (0.1 * sampleRate).roundToInt().coerceAtLeast(1)

    val blockPowers =
        DoubleArray((maxFrames / subBlockFrames).toInt() + 8)

    var blockCount = 0
        private set

    private val sub = DoubleArray(4)
    private var subTotal = 0
    private var subFilled = 0
    private var subAcc = 0.0

    private var shortScratch = ShortArray(0)
    private var floatScratch = FloatArray(0)

    // Estado de los biquads (TDF2): 4 valores por canal.
    private val z = DoubleArray(channels * 4)

    // Pesos de canal BS.1770 (LFE excluido, surround +1.5 dB).
    private val weights =
        DoubleArray(channels) { 1.0 }.also { w ->
            if (channels == 6) {
                w[3] = 0.0
                w[4] = 1.41
                w[5] = 1.41
            } else if (channels == 5) {
                w[3] = 1.41
                w[4] = 1.41
            }
        }

    // Coeficientes K-weighting.
    private val p0: Double
    private val p1: Double
    private val p2: Double
    private val pa1: Double
    private val pa2: Double
    private val qa1: Double
    private val qa2: Double

    init {

        val rate = sampleRate.toDouble()

        // Etapa 1: high-shelf.
        val f1 = 1681.974450955533
        val gain1 = 3.999843853973347
        val q1 = 0.7071752369554196

        val k1 = tan(PI * f1 / rate)
        val vh = 10.0.pow(gain1 / 20.0)
        val vb = vh.pow(0.4996667741545416)
        val a01 = 1.0 + k1 / q1 + k1 * k1

        p0 = (vh + vb * k1 / q1 + k1 * k1) / a01
        p1 = 2.0 * (k1 * k1 - vh) / a01
        p2 = (vh - vb * k1 / q1 + k1 * k1) / a01
        pa1 = 2.0 * (k1 * k1 - 1.0) / a01
        pa2 = (1.0 - k1 / q1 + k1 * k1) / a01

        // Etapa 2: high-pass (b = 1, -2, 1).
        val f2 = 38.13547087602444
        val q2 = 0.5003270373238773

        val k2 = tan(PI * f2 / rate)
        val a02 = 1.0 + k2 / q2 + k2 * k2

        qa1 = 2.0 * (k2 * k2 - 1.0) / a02
        qa2 = (1.0 - k2 / q2 + k2 * k2) / a02
    }

    /** Consume PCM intercalado. Ignora lo que exceda la ventana. */
    fun consume(
        buffer: ByteBuffer,
        encoding: Int,
        order: ByteOrder
    ) {

        if (isFull) {
            return
        }

        buffer.order(order)

        val sampleCount: Int

        when (encoding) {

            AudioFormat.ENCODING_PCM_16BIT -> {

                val shorts = buffer.asShortBuffer()

                sampleCount = shorts.remaining()

                if (shortScratch.size < sampleCount) {
                    shortScratch = ShortArray(sampleCount)
                }

                if (floatScratch.size < sampleCount) {
                    floatScratch = FloatArray(sampleCount)
                }

                shorts.get(shortScratch, 0, sampleCount)

                val source = shortScratch
                val target = floatScratch

                for (index in 0 until sampleCount) {
                    target[index] = source[index] * INV_32768
                }
            }

            AudioFormat.ENCODING_PCM_FLOAT -> {

                val floats = buffer.asFloatBuffer()

                sampleCount = floats.remaining()

                if (floatScratch.size < sampleCount) {
                    floatScratch = FloatArray(sampleCount)
                }

                floats.get(floatScratch, 0, sampleCount)
            }

            else -> throw UnsupportedOperationException(
                "Codificación PCM no soportada: $encoding"
            )
        }

        val frames =
            minOf(
                (sampleCount / channels).toLong(),
                maxFrames - processedFrames
            ).toInt()

        if (frames > 0) {
            process(frames)
        }
    }

    private fun process(frames: Int) {

        var offset = 0
        var remaining = frames

        while (remaining > 0) {

            val chunk =
                minOf(remaining, subBlockFrames - subFilled)

            subAcc +=
                if (channels == 2) {
                    accumulateStereo(offset, chunk)
                } else {
                    accumulateGeneric(offset, chunk)
                }

            subFilled += chunk
            offset += chunk
            remaining -= chunk
            processedFrames += chunk

            if (subFilled == subBlockFrames) {
                closeSubBlock()
            }
        }
    }

    private fun closeSubBlock() {

        sub[subTotal and 3] = subAcc
        subTotal++

        if (subTotal >= 4 && blockCount < blockPowers.size) {

            blockPowers[blockCount++] =
                (sub[0] + sub[1] + sub[2] + sub[3]) /
                    (4.0 * subBlockFrames)
        }

        subAcc = 0.0
        subFilled = 0
    }

    /** Hot loop estéreo: estado en locales, sin llamadas ni ramas internas. */
    private fun accumulateStereo(
        startFrame: Int,
        frames: Int
    ): Double {

        val x = floatScratch

        val c0 = p0
        val c1 = p1
        val c2 = p2
        val ca1 = pa1
        val ca2 = pa2
        val d1 = qa1
        val d2 = qa2

        var l1 = z[0]
        var l2 = z[1]
        var l3 = z[2]
        var l4 = z[3]

        var r1 = z[4]
        var r2 = z[5]
        var r3 = z[6]
        var r4 = z[7]

        var acc = 0.0

        var i = startFrame * 2
        val end = i + frames * 2

        while (i < end) {

            val xl = x[i].toDouble()
            val xr = x[i + 1].toDouble()

            i += 2

            // Izquierdo
            val l = c0 * xl + l1
            l1 = c1 * xl - ca1 * l + l2
            l2 = c2 * xl - ca2 * l

            val yl = l + l3
            l3 = -2.0 * l - d1 * yl + l4
            l4 = l - d2 * yl

            // Derecho
            val r = c0 * xr + r1
            r1 = c1 * xr - ca1 * r + r2
            r2 = c2 * xr - ca2 * r

            val yr = r + r3
            r3 = -2.0 * r - d1 * yr + r4
            r4 = r - d2 * yr

            acc += yl * yl + yr * yr
        }

        z[0] = l1
        z[1] = l2
        z[2] = l3
        z[3] = l4

        z[4] = r1
        z[5] = r2
        z[6] = r3
        z[7] = r4

        return acc
    }

    /** Mono y multicanal. */
    private fun accumulateGeneric(
        startFrame: Int,
        frames: Int
    ): Double {

        val x = floatScratch
        val count = channels

        var acc = 0.0
        var i = startFrame * count

        for (frame in 0 until frames) {

            for (channel in 0 until count) {

                val input = x[i++].toDouble()
                val s = channel * 4

                val a = p0 * input + z[s]
                z[s] = p1 * input - pa1 * a + z[s + 1]
                z[s + 1] = p2 * input - pa2 * a

                val y = a + z[s + 2]
                z[s + 2] = -2.0 * a - qa1 * y + z[s + 3]
                z[s + 3] = a - qa2 * y

                acc += weights[channel] * y * y
            }
        }

        return acc
    }
}
package com.example.sonara

import android.media.audiofx.DynamicsProcessing
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import kotlin.math.log10
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Efecto 8D estéreo de Sonara.
 *
 * Mueve la imagen estéreo mediante ganancias L/R independientes
 * sobre el AudioSession del reproductor usando DynamicsProcessing.
 *
 * Importante:
 * - NO toca setVolume(): ReplayGain y fade siguen funcionando.
 * - El efecto SOLO existe mientras el 8D está activado.
 * - La animación corre en un hilo propio, no en el hilo de UI.
 * - Usa la configuración predeterminada de DynamicsProcessing para
 *   evitar arquitecturas rechazadas por implementaciones OEM.
 */
class EightDAudioEffect {

    companion object {
        private const val TAG = "Sonara8D"

        /** DynamicsProcessing existe desde Android 9 / API 28. */
        private const val MIN_API = Build.VERSION_CODES.P

        /** Tiempo de una vuelta completa. */
        private const val CYCLE_MS = 12000L

        /** ~30 Hz. */
        private const val TICK_MS = 33L

        /** Ganancia mínima del canal lejano. */
        private const val MIN_GAIN_DB = -30.0

        /**
         * Amplitud máxima del paneo.
         *
         * 0.97 mantiene el canal lejano audible pero muy atenuado.
         */
        private const val MAX_PAN = 0.97

        private const val TWO_PI = Math.PI * 2.0
    }

    private val workerThread = HandlerThread("sonara-8d").apply {
        start()
    }

    private val handler = Handler(workerThread.looper)

    /**
     * Protege:
     * - dynamicsProcessing
     * - animating
     * - cycleStartedAt
     */
    private val lock = Any()

    private var dynamicsProcessing: DynamicsProcessing? = null
    private var animating = false
    private var cycleStartedAt = 0L

    /**
     * Solo se modifica desde el hilo principal / MethodChannel.
     */
    private var audioSessionId: Int? = null

    @Volatile
    private var enabled = false

    /**
     * Actualización periódica del paneo.
     */
    private val tick = object : Runnable {

        override fun run() {
            synchronized(lock) {
                if (!animating) {
                    return
                }

                val effect = dynamicsProcessing

                if (effect == null) {
                    animating = false
                    return
                }

                try {
                    updateStereoPosition(effect)
                } catch (error: Exception) {
                    /**
                     * El efecto puede haber sido liberado/reemplazado
                     * mientras este tick estaba ejecutándose.
                     *
                     * No dejamos que el hilo de audio/animación muera.
                     */
                    Log.w(
                        TAG,
                        "No se pudo actualizar el paneo 8D",
                        error
                    )
                }

                if (animating && dynamicsProcessing != null) {
                    handler.postDelayed(this, TICK_MS)
                }
            }
        }
    }

    /**
     * Conecta o reconecta el efecto al AudioSession de just_audio.
     *
     * Si el 8D está activo, crea el efecto en esta sesión.
     */
    fun setAudioSession(sessionId: Int?): Boolean {

        if (sessionId == null || sessionId <= 0) {
            releaseEffect()
            audioSessionId = null
            return false
        }

        if (Build.VERSION.SDK_INT < MIN_API) {
            audioSessionId = sessionId
            return false
        }

        /**
         * Misma sesión y efecto todavía vivo:
         * no lo recreamos y no reiniciamos el ciclo.
         */
        val sameSessionAndAlive =
            audioSessionId == sessionId &&
                synchronized(lock) {
                    dynamicsProcessing != null
                }

        if (sameSessionAndAlive) {
            if (enabled) {
                startAnimation()
            }

            return true
        }

        /**
         * La sesión cambió.
         * Liberamos el efecto anterior antes de asociarlo
         * a la nueva sesión.
         */
        releaseEffect()

        audioSessionId = sessionId

        return if (enabled) {
            createEffect(sessionId)
        } else {
            true
        }
    }

    /**
     * Activa o desactiva el 8D.
     *
     * true:
     *   - aplicado inmediatamente si existe AudioSession
     *   - pendiente si todavía no existe AudioSession
     *
     * false:
     *   - efecto liberado
     */
    fun setEnabled(value: Boolean): Boolean {

        enabled = value

        if (!value) {
            releaseEffect()
            return true
        }

        if (Build.VERSION.SDK_INT < MIN_API) {
            Log.w(
                TAG,
                "8D requiere Android API 28+; API actual=${Build.VERSION.SDK_INT}"
            )
            return false
        }

        val sessionId = audioSessionId

        /**
         * Todavía no tenemos AudioSession.
         * setAudioSession() creará el efecto cuando llegue.
         */
        if (sessionId == null) {
            return true
        }

        if (synchronized(lock) { dynamicsProcessing != null }) {
            startAnimation()
            return true
        }

        return createEffect(sessionId)
    }

    fun isEnabled(): Boolean = enabled

    /**
     * Libera todos los recursos.
     */
    fun release() {
        enabled = false
        releaseEffect()
        audioSessionId = null

        try {
            workerThread.quitSafely()
        } catch (_: Exception) {
        }
    }

    // ------------------------------------------------------------------
    // DynamicsProcessing
    // ------------------------------------------------------------------

    /**
     * Crea el DynamicsProcessing.
     *
     * IMPORTANTE:
     *
     * Antes se utilizaba:
     *
     *     Config.Builder(
     *         VARIANT_FAVOR_TIME_RESOLUTION,
     *         2,
     *         false, 0,
     *         false, 0,
     *         false, 0,
     *         false
     *     )
     *
     * Algunas implementaciones OEM rechazan esa arquitectura con:
     *
     *     AudioEffect: bad parameter value
     *
     * Por eso usamos cfg = null.
     *
     * Android crea entonces la configuración predeterminada válida
     * para el número de canales que tenga el AudioEffect.
     */
    private fun createEffect(sessionId: Int): Boolean {

        if (Build.VERSION.SDK_INT < MIN_API) {
            return false
        }

        return try {

            Log.d(
                TAG,
                "Creando DynamicsProcessing para session=$sessionId"
            )

            /**
             * null = configuración predeterminada de Android.
             *
             * Esto evita enviar manualmente una arquitectura que
             * el DSP del fabricante pueda rechazar.
             */
            val effect = DynamicsProcessing(
                0,
                sessionId,
                null
            )

            val channelCount = effect.channelCount

            Log.d(
                TAG,
                "DynamicsProcessing creado: channels=$channelCount"
            )

            if (channelCount < 2) {
                Log.w(
                    TAG,
                    "DynamicsProcessing no tiene al menos 2 canales: $channelCount"
                )

                try {
                    effect.release()
                } catch (_: Exception) {
                }

                return false
            }

            /**
             * Aplicamos el efecto antes de empezar la animación.
             */
            effect.enabled = true

            synchronized(lock) {
                /**
                 * Por seguridad, si otro efecto fue instalado
                 * entre medias, liberamos el nuevo.
                 */
                val previous = dynamicsProcessing

                if (previous != null) {
                    try {
                        previous.enabled = false
                    } catch (_: Exception) {
                    }

                    try {
                        previous.release()
                    } catch (_: Exception) {
                    }
                }

                dynamicsProcessing = effect
            }

            Log.i(
                TAG,
                "DynamicsProcessing habilitado correctamente " +
                    "(session=$sessionId, channels=$channelCount)"
            )

            startAnimation()

            true

        } catch (error: IllegalArgumentException) {

            /**
             * Este es precisamente el error que estaba apareciendo
             * en el Motorola.
             */
            Log.e(
                TAG,
                "El dispositivo rechazó DynamicsProcessing " +
                    "(session=$sessionId)",
                error
            )

            releaseEffect()
            false

        } catch (error: Exception) {

            Log.e(
                TAG,
                "No se pudo crear DynamicsProcessing " +
                    "(session=$sessionId)",
                error
            )

            releaseEffect()
            false
        }
    }

    // ------------------------------------------------------------------
    // Animation
    // ------------------------------------------------------------------

    private fun startAnimation() {

        synchronized(lock) {

            if (!enabled) {
                return
            }

            if (dynamicsProcessing == null) {
                return
            }

            if (animating) {
                return
            }

            animating = true
            cycleStartedAt = SystemClock.elapsedRealtime()

            handler.removeCallbacks(tick)
            handler.post(tick)
        }
    }

    private fun stopAnimation() {

        synchronized(lock) {
            animating = false
            handler.removeCallbacks(tick)
        }
    }

    // ------------------------------------------------------------------
    // Release
    // ------------------------------------------------------------------

    private fun releaseEffect() {

        stopAnimation()

        val effect = synchronized(lock) {
            val current = dynamicsProcessing
            dynamicsProcessing = null
            current
        }

        if (effect == null) {
            return
        }

        try {
            effect.enabled = false
        } catch (_: Exception) {
        }

        try {
            effect.release()
        } catch (_: Exception) {
        }

        Log.d(TAG, "DynamicsProcessing liberado")
    }

    // ------------------------------------------------------------------
    // 8D stereo movement
    // ------------------------------------------------------------------

    /**
     * Paneo equal-power:
     *
     * izquierda -> centro -> derecha -> centro -> izquierda
     *
     * Se llama con el lock tomado.
     */
    private fun updateStereoPosition(
        effect: DynamicsProcessing
    ) {

        /**
         * Si por alguna razón el efecto ya no tiene estéreo,
         * no intentamos modificar canales inexistentes.
         */
        if (effect.channelCount < 2) {
            return
        }

        val elapsed =
            (SystemClock.elapsedRealtime() - cycleStartedAt)
                .coerceAtLeast(0L)

        val progress =
            (elapsed % CYCLE_MS).toDouble() /
                CYCLE_MS.toDouble()

        /**
         * -MAX_PAN = izquierda
         * 0         = centro
         * +MAX_PAN = derecha
         */
        val position =
            sin(progress * TWO_PI) * MAX_PAN

        /**
         * Equal-power panning.
         *
         * En el centro:
         *
         *     L = 0.707
         *     R = 0.707
         *
         * En los extremos, un canal se acerca a 1 y el otro
         * disminuye considerablemente.
         */
        val leftGain =
            sqrt(
                ((1.0 - position) / 2.0)
                    .coerceIn(0.0, 1.0)
            )

        val rightGain =
            sqrt(
                ((1.0 + position) / 2.0)
                    .coerceIn(0.0, 1.0)
            )

        val leftDb =
            linearToDb(leftGain).toFloat()

        val rightDb =
            linearToDb(rightGain).toFloat()

        /**
         * setInputGainbyChannel() es la API disponible en
         * DynamicsProcessing para modificar la ganancia de entrada
         * de cada canal.
         *
         * NO usamos setVolume().
         */
        effect.setInputGainbyChannel(
            0,
            leftDb
        )

        effect.setInputGainbyChannel(
            1,
            rightDb
        )
    }

    // ------------------------------------------------------------------

    private fun linearToDb(value: Double): Double {

        if (value <= 0.000001) {
            return MIN_GAIN_DB
        }

        return (
            20.0 * log10(value)
        ).coerceAtLeast(MIN_GAIN_DB)
    }
}
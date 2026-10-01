package com.example.sonara

import android.media.audiofx.DynamicsProcessing
import android.os.Build
import android.os.Handler
import android.os.Looper
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Efecto 8D estéreo de Sonara.
 *
 * Hace un movimiento continuo de la imagen estéreo mediante
 * ganancias independientes L/R sobre el AudioSession del reproductor.
 *
 * NO modifica el volumen global del AudioPlayer.
 *
 * Por eso ReplayGain y PlaybackFadeLayer continúan controlando
 * independientemente el volumen general.
 *
 * DynamicsProcessing está disponible desde Android API 28.
 */
class EightDAudioEffect {

    companion object {
        private const val MIN_API = Build.VERSION_CODES.P

        /**
         * Tiempo de una vuelta completa.
         */
        private const val CYCLE_MS = 8000L

        /**
         * Frecuencia de actualización del movimiento.
         */
        private const val TICK_MS = 20L

        /**
         * Nunca llevamos un canal a -infinito.
         * Esto evita cortes demasiado agresivos.
         */
        private const val MIN_GAIN_DB = -42.0

        private const val TWO_PI = Math.PI * 2.0
    }

    private val handler =
        Handler(Looper.getMainLooper())

    private var dynamicsProcessing:
        DynamicsProcessing? = null

    private var audioSessionId:
        Int? = null

    private var enabled = false

    private var cycleStartedAt =
        System.currentTimeMillis()

    private val animationRunnable =
        object : Runnable {

            override fun run() {

                if (!enabled) {
                    return
                }

                val effect =
                    dynamicsProcessing

                if (effect == null) {
                    handler.postDelayed(
                        this,
                        TICK_MS
                    )
                    return
                }

                try {
                    updateStereoPosition(effect)
                } catch (_: Exception) {
                    // Algunos fabricantes pueden rechazar
                    // modificaciones dinámicas del efecto.
                }

                handler.postDelayed(
                    this,
                    TICK_MS
                )
            }
        }

    /**
     * Conecta el efecto al AudioSession de just_audio.
     */
    fun setAudioSession(
        sessionId: Int?
    ): Boolean {

        if (
            sessionId == null ||
            sessionId <= 0
        ) {
            releaseEffect()
            audioSessionId = null
            return false
        }

        if (
            Build.VERSION.SDK_INT <
            MIN_API
        ) {
            releaseEffect()
            audioSessionId = sessionId
            return false
        }

        if (
            audioSessionId == sessionId &&
            dynamicsProcessing != null
        ) {
            if (enabled) {
                startAnimation()
            }

            return true
        }

        releaseEffect()

        audioSessionId = sessionId

        return try {

            /*
             * Configuración mínima:
             *
             * - 2 canales
             * - sin EQ
             * - sin multibanda
             * - sin post EQ
             * - sin limiter
             *
             * Solo usamos input gain por canal.
             */
            val config =
                DynamicsProcessing.Config.Builder(
                    DynamicsProcessing.VARIANT_FAVOR_TIME_RESOLUTION,
                    2,
                    false,
                    0,
                    false,
                    0,
                    false,
                    0,
                    false
                ).build()

            val effect =
                DynamicsProcessing(
                    0,
                    sessionId,
                    config
                )

            if (
                effect.channelCount < 2
            ) {
                effect.release()
                return false
            }

            effect.enabled = true

            dynamicsProcessing =
                effect

            if (enabled) {
                startAnimation()
            }

            true

        } catch (_: Exception) {

            releaseEffect()

            false
        }
    }

    /**
     * Activa o desactiva el movimiento 8D.
     */
    fun setEnabled(
        value: Boolean
    ): Boolean {

        enabled = value

        if (!enabled) {

            stopAnimation()

            resetStereoGain()

            return dynamicsProcessing != null
        }

        if (
            dynamicsProcessing == null
        ) {
            return false
        }

        cycleStartedAt =
            System.currentTimeMillis()

        startAnimation()

        return true
    }

    fun isEnabled(): Boolean {
        return enabled
    }

    fun release() {

        enabled = false

        stopAnimation()

        releaseEffect()

        audioSessionId = null
    }

    private fun startAnimation() {

        handler.removeCallbacks(
            animationRunnable
        )

        cycleStartedAt =
            System.currentTimeMillis()

        handler.post(
            animationRunnable
        )
    }

    private fun stopAnimation() {

        handler.removeCallbacks(
            animationRunnable
        )
    }

    /**
     * Movimiento estéreo de tipo equal-power.
     *
     * La potencia percibida se mantiene mucho mejor que
     * haciendo simplemente 1.0 -> 0.0 en cada canal.
     */
    private fun updateStereoPosition(
        effect: DynamicsProcessing
    ) {

        val elapsed =
            (
                System.currentTimeMillis() -
                    cycleStartedAt
                ).coerceAtLeast(0L)

        val progress =
            (
                elapsed %
                    CYCLE_MS
                ).toDouble() /
                    CYCLE_MS.toDouble()

        val phase =
            progress * TWO_PI

        /*
         * Convertimos el seno en una posición
         * que va de izquierda -> centro -> derecha
         * -> centro -> izquierda.
         */
        val position =
            sin(phase)

        /*
         * Equal-power panning.
         *
         * position = -1 -> izquierda
         * position =  0 -> centro
         * position = +1 -> derecha
         */
        val leftGain =
            sqrt(
                (
                    1.0 - position
                ) / 2.0
            )

        val rightGain =
            sqrt(
                (
                    1.0 + position
                ) / 2.0
            )

        val leftDb =
            linearToDb(leftGain)
                .coerceAtLeast(
                    MIN_GAIN_DB
                )

        val rightDb =
            linearToDb(rightGain)
                .coerceAtLeast(
                    MIN_GAIN_DB
                )

        /*
         * IMPORTANTE:
         *
         * Este método NO llama setVolume().
         *
         * Por eso no pisa:
         * - ReplayGain
         * - fade in
         * - fade out
         * - crossfade
         * - volumen global
         */
        effect.setInputGainbyChannel(
            0,
            leftDb.toFloat()
        )

        effect.setInputGainbyChannel(
            1,
            rightDb.toFloat()
        )
    }

    private fun resetStereoGain() {

        val effect =
            dynamicsProcessing
                ?: return

        try {

            effect.setInputGainbyChannel(
                0,
                0.0f
            )

            effect.setInputGainbyChannel(
                1,
                0.0f
            )

        } catch (_: Exception) {
        }
    }

    private fun linearToDb(
        value: Double
    ): Double {

        if (value <= 0.000001) {
            return MIN_GAIN_DB
        }

        return (
            20.0 *
                kotlin.math.log10(value)
            ).coerceAtLeast(
                MIN_GAIN_DB
            )
    }

    private fun releaseEffect() {

        stopAnimation()

        try {
            dynamicsProcessing?.enabled =
                false
        } catch (_: Exception) {
        }

        try {
            dynamicsProcessing?.release()
        } catch (_: Exception) {
        }

        dynamicsProcessing =
            null
    }
}
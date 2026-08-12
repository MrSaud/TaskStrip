package com.saud.taskstrip.media

import android.content.Context
import android.speech.tts.TextToSpeech
import java.util.Locale

/** Single shared TTS engine reused across every strip row instead of one per row. */
object TextToSpeechHelper {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var pendingText: String? = null

    fun speak(context: Context, text: String) {
        if (text.isBlank()) return
        val engine = tts
        if (engine == null) {
            pendingText = text
            tts = TextToSpeech(context.applicationContext) { status ->
                ready = status == TextToSpeech.SUCCESS
                if (ready) {
                    tts?.language = Locale.getDefault()
                    pendingText?.let { tts?.speak(it, TextToSpeech.QUEUE_FLUSH, null, "taskstrip_notes") }
                    pendingText = null
                }
            }
        } else if (ready) {
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "taskstrip_notes")
        }
    }

    fun stop() {
        tts?.stop()
    }
}

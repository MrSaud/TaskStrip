package com.saud.taskstrip.media

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import java.util.Locale

/** Single shared TTS engine reused across every strip row instead of one per row. Starting a new
 * utterance (QUEUE_FLUSH) implicitly stops whatever row was reading before, so [speakingTaskId]
 * always reflects at most one row at a time. */
object TextToSpeechHelper {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var pendingTaskId: Long? = null
    private var pendingText: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val _speakingTaskId = mutableStateOf<Long?>(null)
    val speakingTaskId: State<Long?> = _speakingTaskId

    // TTS callbacks can land on a non-main thread depending on the engine, so hop back to main
    // before touching Compose state.
    private val progressListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {
            mainHandler.post { _speakingTaskId.value = utteranceId?.toLongOrNull() }
        }
        override fun onDone(utteranceId: String?) {
            mainHandler.post { if (_speakingTaskId.value?.toString() == utteranceId) _speakingTaskId.value = null }
        }
        @Deprecated("Deprecated in Java", ReplaceWith(""))
        override fun onError(utteranceId: String?) {
            mainHandler.post { if (_speakingTaskId.value?.toString() == utteranceId) _speakingTaskId.value = null }
        }
    }

    fun speak(context: Context, taskId: Long, text: String) {
        if (text.isBlank()) return
        val engine = tts
        if (engine == null) {
            pendingTaskId = taskId
            pendingText = text
            tts = TextToSpeech(context.applicationContext) { status ->
                ready = status == TextToSpeech.SUCCESS
                if (ready) {
                    tts?.language = Locale.getDefault()
                    tts?.setOnUtteranceProgressListener(progressListener)
                    val id = pendingTaskId
                    pendingText?.let { tts?.speak(it, TextToSpeech.QUEUE_FLUSH, null, id?.toString()) }
                    pendingText = null
                    pendingTaskId = null
                }
            }
        } else if (ready) {
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, taskId.toString())
        }
    }

    fun stop() {
        tts?.stop()
        _speakingTaskId.value = null
    }
}

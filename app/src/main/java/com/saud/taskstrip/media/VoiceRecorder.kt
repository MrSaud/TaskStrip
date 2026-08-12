package com.saud.taskstrip.media

import android.content.Context
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import java.io.File

class VoiceRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var outputFile: File? = null

    fun start(): File {
        val file = MediaStorage.newVoiceNoteFile(context)
        val mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
        mediaRecorder.apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setOutputFile(file.absolutePath)
            prepare()
            start()
        }
        recorder = mediaRecorder
        outputFile = file
        return file
    }

    /** Returns the recorded file, or null if nothing usable was captured. */
    fun stop(): File? {
        val file = outputFile
        return try {
            recorder?.apply {
                stop()
                release()
            }
            file
        } catch (e: Exception) {
            file?.delete()
            null
        } finally {
            recorder = null
            outputFile = null
        }
    }

    fun cancel() {
        try {
            recorder?.apply {
                stop()
                release()
            }
        } catch (e: Exception) {
            // recording never really started; nothing to clean up
        }
        outputFile?.delete()
        recorder = null
        outputFile = null
    }
}

class VoicePlayer {
    private var player: MediaPlayer? = null

    fun play(path: String, onCompletion: () -> Unit) {
        stop()
        player = MediaPlayer().apply {
            setDataSource(path)
            setOnCompletionListener { onCompletion() }
            prepare()
            start()
        }
    }

    fun stop() {
        player?.apply {
            if (isPlaying) stop()
            release()
        }
        player = null
    }

    fun positionMillis(): Int = try { player?.currentPosition ?: 0 } catch (e: IllegalStateException) { 0 }

    fun durationMillis(): Int = try { player?.duration ?: 0 } catch (e: IllegalStateException) { 0 }
}

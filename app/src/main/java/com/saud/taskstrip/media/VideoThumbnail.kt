package com.saud.taskstrip.media

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever

object VideoThumbnail {
    fun getFrame(path: String): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            retriever.frameAtTime
        } catch (e: Exception) {
            null
        } finally {
            retriever.release()
        }
    }
}

package com.saud.taskstrip.media

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.util.UUID

val DOCUMENT_MIME_TYPES = arrayOf(
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "text/csv",
    "application/vnd.ms-excel",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
)

object MediaStorage {

    private fun imagesDir(context: Context): File =
        File(context.filesDir, "images").apply { mkdirs() }

    private fun audioDir(context: Context): File =
        File(context.filesDir, "audio").apply { mkdirs() }

    private fun documentsDir(context: Context): File =
        File(context.filesDir, "documents").apply { mkdirs() }

    private fun videosDir(context: Context): File =
        File(context.filesDir, "videos").apply { mkdirs() }

    fun copyImageToLocal(context: Context, uri: Uri): String? {
        val destination = File(imagesDir(context), "${UUID.randomUUID()}.jpg")
        return try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                destination.outputStream().use { output -> input.copyTo(output) }
            }
            destination.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    fun newImageFile(context: Context): File =
        File(imagesDir(context), "${UUID.randomUUID()}.jpg")

    fun newVoiceNoteFile(context: Context): File =
        File(audioDir(context), "${UUID.randomUUID()}.m4a")

    fun newVideoFile(context: Context): File =
        File(videosDir(context), "${UUID.randomUUID()}.mp4")

    fun copyVideoToLocal(context: Context, uri: Uri): String? {
        val destination = File(videosDir(context), "${UUID.randomUUID()}.mp4")
        return try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                destination.outputStream().use { output -> input.copyTo(output) }
            }
            destination.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    /** Copies a picked document, preserving its original display name for the UI. Each document
     * gets its own UUID subfolder so two files with the same name never collide. */
    fun copyDocumentToLocal(context: Context, uri: Uri): String? {
        val displayName = queryDisplayName(context, uri) ?: "document_${System.currentTimeMillis()}"
        val folder = File(documentsDir(context), UUID.randomUUID().toString()).apply { mkdirs() }
        val destination = File(folder, displayName)
        return try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                destination.outputStream().use { output -> input.copyTo(output) }
            }
            destination.absolutePath
        } catch (e: Exception) {
            folder.deleteRecursively()
            null
        }
    }

    /** Copies a file already on local disk (e.g. a storage-library item) into a fresh
     * images/videos/documents entry, independent of the source — used when a strip "takes" a copy
     * of a library item, so deleting it from the strip (or the library) later never affects the
     * other side. */
    fun duplicateImage(context: Context, sourcePath: String): String? = try {
        val destination = File(imagesDir(context), "${UUID.randomUUID()}.jpg")
        File(sourcePath).copyTo(destination, overwrite = true)
        destination.absolutePath
    } catch (e: Exception) {
        null
    }

    fun duplicateVideo(context: Context, sourcePath: String): String? = try {
        val destination = File(videosDir(context), "${UUID.randomUUID()}.mp4")
        File(sourcePath).copyTo(destination, overwrite = true)
        destination.absolutePath
    } catch (e: Exception) {
        null
    }

    fun duplicateDocument(context: Context, sourcePath: String): String? = try {
        val source = File(sourcePath)
        val folder = File(documentsDir(context), UUID.randomUUID().toString()).apply { mkdirs() }
        val destination = File(folder, source.name)
        source.copyTo(destination, overwrite = true)
        destination.absolutePath
    } catch (e: Exception) {
        null
    }

    fun queryDisplayName(context: Context, uri: Uri): String? = try {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
        }
    } catch (e: Exception) {
        null
    }

    fun deleteFile(path: String) {
        runCatching { File(path).delete() }
    }

    /** Deletes a document file and its (now-empty) UUID container folder. */
    fun deleteDocument(path: String) {
        runCatching {
            val file = File(path)
            val parent = file.parentFile
            file.delete()
            if (parent != null && parent.isDirectory && parent.listFiles().isNullOrEmpty()) {
                parent.delete()
            }
        }
    }
}

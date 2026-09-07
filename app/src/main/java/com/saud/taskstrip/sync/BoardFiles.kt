package com.saud.taskstrip.sync

import com.saud.taskstrip.data.TaskEntity
import java.io.File

/**
 * The bridge between a strip's file lists and the hashes that travel.
 *
 * A strip keeps four lists of local paths — images, voice notes, documents, videos. A record keeps
 * one list of hashes, each saying which of those it belongs in. Turning one into the other is the
 * fiddly part of the wiring and is worth having on its own, away from the database work, because
 * getting it wrong loses attachments quietly.
 */
object BoardFiles {

    const val IMAGE = "image"
    const val VOICE = "voice"
    const val DOCUMENT = "document"
    const val VIDEO = "video"

    /** Every file a strip holds, paired with the list it came from. */
    fun localFiles(task: TaskEntity): List<Pair<String, String>> =
        task.images.map { it to IMAGE } +
            task.voiceNotes.map { it to VOICE } +
            task.documents.map { it to DOCUMENT } +
            task.videos.map { it to VIDEO }

    /**
     * A strip's attachments as they travel.
     *
     * A path that no longer exists is dropped rather than sent as a hash of nothing — the file was
     * deleted from under the strip at some point, and naming it would only ask the other device to
     * fetch something nobody has.
     */
    fun attachments(task: TaskEntity, hashOf: (File) -> String): List<SyncAttachment> =
        localFiles(task).mapNotNull { (path, kind) ->
            val file = File(path)
            if (!file.exists()) return@mapNotNull null
            SyncAttachment(hash = hashOf(file), name = file.name, kind = kind)
        }

    /**
     * A strip's file lists, rebuilt from what arrived.
     *
     * Hashes this device hasn't got are left out rather than turned into a path to nothing: the
     * strip shows the files it can actually open, and the next sync fills in the rest once the
     * bytes land. Order within each list follows the record, so a strip's photos stay in the order
     * they were added rather than the order this device happened to fetch them.
     */
    fun applyAttachments(task: TaskEntity, record: SyncTaskRecord, pathOf: (String) -> String?): TaskEntity {
        fun paths(kind: String) = record.attachments
            .filter { it.kind == kind }
            .mapNotNull { pathOf(it.hash) }

        return task.copy(
            images = paths(IMAGE),
            voiceNotes = paths(VOICE),
            documents = paths(DOCUMENT),
            videos = paths(VIDEO)
        )
    }
}

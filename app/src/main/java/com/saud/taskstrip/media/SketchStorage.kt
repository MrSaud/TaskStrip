package com.saud.taskstrip.media

import android.content.Context
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import java.time.format.DateTimeFormatter

/** A sketch note is a folder of one or more page PNGs (sketches/<note>/page1.png, page2.png, …)
 * rather than a single flat file, so a note can grow multiple pages. */
object SketchStorage {

    private fun sketchesDir(context: Context): File =
        File(context.filesDir, "sketches").apply { mkdirs() }

    fun listNotes(context: Context): List<File> =
        sketchesDir(context).listFiles { f -> f.isDirectory }
            ?.filter { listPages(it).isNotEmpty() }
            ?.sortedByDescending { lastModified(it) }
            ?: emptyList()

    /** Doesn't touch disk — the folder is only created when the first page is actually saved,
     * so backing out of a blank new note never leaves an empty folder behind. */
    fun newNoteRef(context: Context): File =
        File(sketchesDir(context), "note_${System.currentTimeMillis()}")

    fun noteRef(context: Context, name: String): File =
        File(sketchesDir(context), name)

    private fun pageNumber(file: File): Int =
        file.nameWithoutExtension.removePrefix("page").toIntOrNull() ?: 0

    fun listPages(note: File): List<File> =
        note.listFiles { f -> f.extension == "png" }
            ?.sortedBy { pageNumber(it) }
            ?: emptyList()

    /** A page's own mtime updates even when its content is overwritten in place (unlike the
     * folder's), so this reflects true last-edited time across every page in the note. */
    fun lastModified(note: File): Long =
        listPages(note).maxOfOrNull { it.lastModified() } ?: note.lastModified()

    fun newPageFile(note: File): File {
        val next = (listPages(note).maxOfOrNull(::pageNumber) ?: 0) + 1
        return File(note, "page$next.png")
    }

    private fun formatDate(millis: Long): String =
        Instant.ofEpochMilli(millis)
            .atZone(ZoneId.systemDefault())
            .format(DateTimeFormatter.ofPattern("dd MMM yyyy, HH:mm"))

    fun dateLabel(note: File): String = formatDate(lastModified(note))

    // A hidden dotfile inside the note's own folder — no separate extension filter needed since
    // it doesn't end in .png, so listPages()/listNotes() already ignore it.
    private fun nameFile(note: File): File = File(note, ".name")

    fun getName(note: File): String? {
        val file = nameFile(note)
        if (!file.exists()) return null
        return file.readText().trim().ifBlank { null }
    }

    fun setName(note: File, name: String) {
        val trimmed = name.trim()
        val file = nameFile(note)
        if (trimmed.isEmpty()) {
            file.delete()
        } else {
            note.mkdirs()
            file.writeText(trimmed)
        }
    }

    /** What to show for this sketch anywhere in the UI — its custom name if the user set one,
     * otherwise the last-edited date as before. */
    fun displayLabel(note: File): String = getName(note) ?: dateLabel(note)

    // A page's own file gets overwritten in place on every edit, so its mtime can't answer "when
    // was this sketch first created" — stamp it explicitly, once, the first time a page is saved.
    private fun createdFile(note: File): File = File(note, ".created")

    fun getCreatedAt(note: File): Long {
        val file = createdFile(note)
        if (file.exists()) file.readText().trim().toLongOrNull()?.let { return it }
        // Sketches created before this stamp existed still carry their creation time in the
        // auto-generated folder name (note_<millis>) — fall back to that before giving up.
        note.name.removePrefix("note_").toLongOrNull()?.let { return it }
        return note.lastModified()
    }

    fun stampCreatedIfMissing(note: File) {
        val file = createdFile(note)
        if (!file.exists()) {
            note.mkdirs()
            file.writeText(System.currentTimeMillis().toString())
        }
    }

    fun createdLabel(note: File): String = formatDate(getCreatedAt(note))

    // ---- Syncing ----

    // The third dotfile, alongside .name and .created and hidden the same way. A sketch is the one
    // thing this app keeps that has no row anywhere, so its shared id has to live beside it.
    private fun syncIdFile(note: File): File = File(note, ".syncid")

    // A folder whose pages are gone but which still says "this existed and was deleted". Kept so
    // the delete can reach the other device, the same reason a tombstoned strip keeps its row.
    private fun deletedFile(note: File): File = File(note, ".deleted")

    /** The id both devices know this sketch by, minted the first time it is asked for.
     *
     * On demand rather than at creation: sketches drawn before any of this existed have no id, and
     * the first sync should carry them across rather than skip them for being old. */
    fun getOrCreateSyncId(note: File): String {
        val file = syncIdFile(note)
        if (file.exists()) {
            file.readText().trim().takeIf { it.isNotEmpty() }?.let { return it }
        }
        val minted = UUID.randomUUID().toString()
        note.mkdirs()
        file.writeText(minted)
        return minted
    }

    fun setSyncId(note: File, syncId: String) {
        note.mkdirs()
        syncIdFile(note).writeText(syncId)
    }

    fun isDeleted(note: File): Boolean = deletedFile(note).exists()

    /** When it was deleted, so the merge can tell a fresh delete from a stale one. */
    fun getDeletedAt(note: File): Long =
        deletedFile(note).takeIf { it.exists() }?.readText()?.trim()?.toLongOrNull() ?: 0L

    /** A tombstone, not a removal.
     *
     * The pages go — they are the bulk, and nothing should point at them once the note is gone —
     * but the folder stays, holding the id and the moment of the delete. Removed outright, the
     * note would be indistinguishable from one the other device has never seen, and the next sync
     * would draw it again. listNotes already ignores what is left behind, because it only lists
     * folders that still have pages.
     */
    fun deleteNote(note: File) {
        runCatching {
            // Minted before the pages go, so a note deleted having never synced still has a name
            // to be deleted by.
            getOrCreateSyncId(note)
            listPages(note).forEach { it.delete() }
            // The name goes with the pages. A tombstone is only a name to be deleted by and the
            // moment it happened — keeping the title of a note nobody can open would be keeping
            // the one part of it that still reads like content.
            nameFile(note).delete()
            deletedFile(note).writeText(System.currentTimeMillis().toString())
        }
    }

    /** Every folder the sync cares about: live notes and the tombstones of dead ones. */
    fun listAllForSync(context: Context): List<File> =
        sketchesDir(context).listFiles { f -> f.isDirectory }?.toList() ?: emptyList()

    fun deletePage(page: File) {
        runCatching { page.delete() }
    }
}

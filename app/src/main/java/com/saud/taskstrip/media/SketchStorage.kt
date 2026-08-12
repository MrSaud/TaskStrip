package com.saud.taskstrip.media

import android.content.Context
import java.io.File
import java.time.Instant
import java.time.ZoneId
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

    fun deleteNote(note: File) {
        runCatching { note.deleteRecursively() }
    }

    fun deletePage(page: File) {
        runCatching { page.delete() }
    }
}

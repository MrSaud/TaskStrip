package com.saud.taskstrip.voice

import com.saud.taskstrip.data.Priority

// contactEmail/contactPhone are only set when this draft came from a shared vCard — they let the
// receiving screen add a structured contact entry instead of just dumping text into notes.
data class VoiceDraft(
    val title: String,
    val notes: String,
    val priority: Priority?,
    val contactEmail: String? = null,
    val contactPhone: String? = null
)

/**
 * Best-effort parser for spoken quick-add commands, e.g.
 * "create a strip for project a, description is call the vendor about pricing"
 * -> title="Project a", notes="call the vendor about pricing"
 *
 * This is intentionally simple pattern matching, not real NLP — the parsed result is always
 * shown in the editor for the user to review/correct before it's saved, since speech
 * recognition and this kind of matching are both fallible.
 */
object VoiceCommandParser {

    private val leadingPhrases = listOf(
        "create a strip for", "create a strip", "create strip for", "create strip",
        "new strip for", "new strip", "add a strip for", "add a strip", "add strip for", "add strip",
        "create a task for", "create a task", "create task for", "create task",
        "new task for", "new task", "add a task for", "add a task", "add task for", "add task",
        "file a strip for", "file a strip"
    ).sortedByDescending { it.length }

    private val descriptionKeywords = listOf(
        "the description is", "description is", "notes are", "notes is",
        "with description", "description", "notes"
    ).sortedByDescending { it.length }

    private val priorityRegex = Regex("\\b(urgent|high priority|low priority|normal priority)\\b", RegexOption.IGNORE_CASE)

    fun parse(raw: String): VoiceDraft {
        var text = raw.trim()
        val lower = text.lowercase()
        val lead = leadingPhrases.firstOrNull { lower.startsWith(it) }
        if (lead != null) {
            text = text.substring(lead.length).trim()
        }

        var priority: Priority? = null
        priorityRegex.find(text)?.let { match ->
            val kw = match.value.lowercase()
            priority = when {
                "urgent" in kw -> Priority.URGENT
                "high" in kw -> Priority.HIGH
                "low" in kw -> Priority.LOW
                else -> Priority.NORMAL
            }
            text = (text.substring(0, match.range.first) + text.substring(match.range.last + 1))
                .replace(",,", ",")
                .trim()
        }

        val lowerText = text.lowercase()
        val descHit = descriptionKeywords
            .mapNotNull { kw -> lowerText.indexOf(kw).takeIf { it >= 0 }?.let { idx -> idx to kw } }
            .minByOrNull { it.first }

        val title: String
        val notes: String
        if (descHit != null) {
            val (idx, kw) = descHit
            title = text.substring(0, idx).trim().trimEnd(',').trim()
            notes = text.substring(idx + kw.length).trim()
        } else {
            val commaIdx = text.indexOf(',')
            if (commaIdx >= 0) {
                title = text.substring(0, commaIdx).trim()
                notes = text.substring(commaIdx + 1).trim()
            } else {
                title = text.trim()
                notes = ""
            }
        }

        val finalTitle = title.ifBlank { raw.trim() }
        return VoiceDraft(
            title = finalTitle.replaceFirstChar { it.uppercaseChar() },
            notes = notes,
            priority = priority
        )
    }
}

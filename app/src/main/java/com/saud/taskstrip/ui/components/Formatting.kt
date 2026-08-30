package com.saud.taskstrip.ui.components

import java.time.Instant
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.chrono.HijrahChronology
import java.time.chrono.HijrahDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale

// ETA values are stored and displayed in UTC so the picked date/time always round-trips
// back to exactly what the user chose, regardless of device timezone.
fun formatEtaShort(epochMillis: Long): String {
    val zdt = Instant.ofEpochMilli(epochMillis).atZone(ZoneOffset.UTC)
    return zdt.format(DateTimeFormatter.ofPattern("dd MMM, HH:mm"))
}

fun formatEtaFull(epochMillis: Long): String {
    val zdt = Instant.ofEpochMilli(epochMillis).atZone(ZoneOffset.UTC)
    return zdt.format(DateTimeFormatter.ofPattern("dd MMM yyyy, HH:mm"))
}

// Real device timestamps (createdAt) are genuine instants, so unlike ETA these are shown
// in the device's actual local timezone.
fun formatTimestampShort(epochMillis: Long): String {
    val zdt = Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault())
    return zdt.format(DateTimeFormatter.ofPattern("dd MMM yy"))
}

// Real device timestamps, date + time — same "real instant, local zone" convention as
// formatTimestampShort above, just with the time of day included too.
fun formatTimestampFull(epochMillis: Long): String {
    val zdt = Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault())
    return zdt.format(DateTimeFormatter.ofPattern("dd MMM yyyy, HH:mm"))
}

// External apps like Calendar render a real instant in the device's actual timezone, unlike our
// own UTC-display convention — re-anchor the same picked wall-clock numbers to the local zone so
// what shows up there matches exactly what was picked here.
fun dueAtAsLocalInstant(epochMillis: Long): Long {
    val wallClock = Instant.ofEpochMilli(epochMillis).atZone(ZoneOffset.UTC).toLocalDateTime()
    return wallClock.atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
}

// A live header clock — always the device's real local time, unlike the UTC-display convention
// used for ETA fields above.
fun formatBoardHeaderClock(epochMillis: Long): String {
    val zdt = Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault())
    return zdt.format(DateTimeFormatter.ofPattern("EEE, dd MMM · HH:mm:ss")).uppercase()
}

/** Today in both calendars, with how long each month runs.
 *
 * "Is this month 29, 30 or 31 days?" is two questions at once: a Gregorian month runs 28 to 31,
 * an Umm al-Qura one 29 or 30, and neither answers the other. Both are shown rather than leaving
 * the conversion to the reader.
 *
 * HijrahChronology.INSTANCE is Umm al-Qura, which is also what the Mac app's
 * Calendar(identifier: .islamicUmmAlQura) uses — so both apps say the same thing on the same day.
 */
fun formatBoardHeaderCalendars(
    epochMillis: Long,
    locale: Locale = Locale.getDefault()
): String {
    val date = Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()).toLocalDate()
    val hijri = HijrahDate.from(date)
    val gregorianText = date.format(DateTimeFormatter.ofPattern("dd MMM yyyy", locale))
    val hijriText = DateTimeFormatter.ofPattern("d MMMM yyyy", locale)
        .withChronology(HijrahChronology.INSTANCE)
        .format(hijri)
    return "$gregorianText · ${date.lengthOfMonth()} DAYS · $hijriText · ${hijri.lengthOfMonth()} DAYS"
        .uppercase(locale)
}

// "Today" is evaluated in UTC to stay consistent with how dueAt is stored/displayed everywhere
// else (see the ETA comment above) — the calendar day shown in the DUE field is the one compared.
fun isDueTodayOrOverdue(dueAt: Long?, isDone: Boolean): Boolean {
    if (dueAt == null || isDone) return false
    val today = Instant.now().atZone(ZoneOffset.UTC).toLocalDate()
    val due = Instant.ofEpochMilli(dueAt).atZone(ZoneOffset.UTC).toLocalDate()
    return !due.isAfter(today)
}

fun formatDurationMinSec(millis: Long): String {
    val totalSeconds = (millis / 1000).coerceAtLeast(0)
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return String.format(Locale.US, "%d:%02d", minutes, seconds)
}

// ---- Board strip dates -------------------------------------------------------------------------
//
// A strip is a fixed 104dp carrying a title, tags, attachment counts and up to two more status
// lines, so a date drawn on one competes for room with everything else on it. The absolute forms
// above are right for the edit screen, which has the space to be unambiguous, and wrong for the
// board: "30 Aug, 00:00" spends thirteen characters to answer a question triage never asks. What
// the board asks is "is this late, is it today, can it wait", and the relative form answers that
// in a third of the width.

private val HOUR_MINUTE = DateTimeFormatter.ofPattern("HH:mm")
private val DAY_MONTH = DateTimeFormatter.ofPattern("dd MMM")
private val DAY_MONTH_YEAR = DateTimeFormatter.ofPattern("dd MMM yy")

// Past this, the exact count stops being information and starts being noise — and an unbounded
// number would let one very stale strip stretch the field wider than every other strip's.
private const val MAX_LATE_DAYS_SHOWN = 99L

// dueAt holds the wall clock that was picked, stored UTC-treated so it round-trips through the
// picker unchanged (see dueAtAsLocalInstant) — so read it back as a wall clock and compare it
// against the local one, rather than against a real instant.
private fun dueWallClock(epochMillis: Long): LocalDateTime =
    Instant.ofEpochMilli(epochMillis).atZone(ZoneOffset.UTC).toLocalDateTime()

private fun localWallClock(epochMillis: Long): LocalDateTime =
    Instant.ofEpochMilli(epochMillis).atZone(ZoneId.systemDefault()).toLocalDateTime()

private fun withClock(label: String, clock: String?): String =
    if (clock == null) label else "$label $clock"

/** A due date at board width: "TODAY 14:30", "TMRW", "WED 09:00", "3D LATE", "12 SEP".
 *
 * Relative while the answer is still a relative one, absolute once it stops being — a date more
 * than a week out is a date, not a countdown, and nobody triages by the hour that far ahead, so
 * the time of day is dropped there too.
 *
 * A midnight time is treated as "no particular time" rather than as midnight: it is what the
 * picker leaves behind when only a date was chosen, and printing "00:00" on those was most of
 * what made a board full of due dates hard to read.
 */
fun formatDueCompact(dueAt: Long, nowMillis: Long = System.currentTimeMillis()): String {
    val due = dueWallClock(dueAt)
    val now = localWallClock(nowMillis)
    val clock = due.toLocalTime().takeIf { it != LocalTime.MIDNIGHT }?.format(HOUR_MINUTE)
    val dayGap = ChronoUnit.DAYS.between(now.toLocalDate(), due.toLocalDate())

    if (due.isBefore(now)) {
        // Whole days, so something due at 09:00 and read at 10:00 says LATE rather than "0D LATE".
        val lateDays = -dayGap
        return when {
            lateDays <= 0L -> "LATE"
            lateDays > MAX_LATE_DAYS_SHOWN -> "${MAX_LATE_DAYS_SHOWN}D+ LATE"
            else -> "${lateDays}D LATE"
        }
    }

    return when (dayGap) {
        0L -> withClock("TODAY", clock)
        1L -> withClock("TMRW", clock)
        in 2L..6L ->
            withClock(due.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.getDefault()).uppercase(), clock)
        else ->
            if (due.year == now.year) due.format(DAY_MONTH).uppercase()
            else due.format(DAY_MONTH_YEAR).uppercase()
    }
}

/** How long a strip has been open, at board width: "TODAY", "4D", "3W", "5MO", "2Y".
 *
 * This replaces a filing date on the board. The date a strip was filed is not a thing anyone
 * looks up; how long it has been sitting there is, and that reads in two characters instead of
 * a printed date competing with the title for the same line.
 */
fun formatAgeCompact(createdAt: Long, nowMillis: Long = System.currentTimeMillis()): String {
    val filed = localWallClock(createdAt).toLocalDate()
    val today = localWallClock(nowMillis).toLocalDate()
    // Clock skew and restored backups can both put a creation date slightly in the future; a
    // negative age would print "-1D", so those read as filed today.
    val days = ChronoUnit.DAYS.between(filed, today).coerceAtLeast(0L)
    return when {
        days == 0L -> "TODAY"
        days < 7L -> "${days}D"
        days < 60L -> "${days / 7}W"
        days < 730L -> "${days / 30}MO"
        else -> "${days / 365}Y"
    }
}

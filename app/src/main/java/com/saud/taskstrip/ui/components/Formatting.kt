package com.saud.taskstrip.ui.components

import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
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

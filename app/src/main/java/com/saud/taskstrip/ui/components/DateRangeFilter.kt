package com.saud.taskstrip.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.DateRangePicker
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDateRangePickerState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/** [from]/[to] are real device-local instants (start/end of the picked calendar days), not the
 * raw UTC-midnight values a date picker returns — see [DateRange.fromPickerMillis]. */
data class DateRange(val from: Long?, val to: Long?) {
    val isSet: Boolean get() = from != null || to != null

    fun contains(timestamp: Long): Boolean =
        (from == null || timestamp >= from) && (to == null || timestamp <= to)

    fun label(): String? {
        if (!isSet) return null
        val fmt = DateTimeFormatter.ofPattern("dd MMM")
        val fromText = from?.let { Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()).format(fmt) } ?: "…"
        val toText = to?.let { Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()).format(fmt) } ?: "…"
        return "$fromText – $toText"
    }

    companion object {
        val EMPTY = DateRange(null, null)

        /** Converts a DateRangePicker's UTC-midnight selection into real local-day bounds. */
        fun fromPickerMillis(fromUtcMillis: Long?, toUtcMillis: Long?): DateRange {
            val from = fromUtcMillis?.let {
                Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                    .atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
            }
            val to = toUtcMillis?.let {
                Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                    .plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli() - 1
            }
            return DateRange(from, to)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateRangeFilterDialog(
    onDismiss: () -> Unit,
    onConfirm: (DateRange) -> Unit,
    onClear: () -> Unit
) {
    val state = rememberDateRangePickerState()
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.9f)) {
            Column(Modifier.fillMaxSize()) {
                DateRangePicker(
                    state = state,
                    modifier = Modifier.weight(1f),
                    title = { Text("FILTER BY FILED DATE", modifier = Modifier.padding(16.dp)) }
                )
                Row(
                    horizontalArrangement = Arrangement.End,
                    modifier = Modifier.fillMaxWidth().padding(12.dp)
                ) {
                    TextButton(onClick = { onClear(); onDismiss() }) { Text("CLEAR") }
                    TextButton(onClick = onDismiss) { Text("CANCEL") }
                    Button(onClick = {
                        onConfirm(DateRange.fromPickerMillis(state.selectedStartDateMillis, state.selectedEndDateMillis))
                        onDismiss()
                    }) { Text("APPLY") }
                }
            }
        }
    }
}

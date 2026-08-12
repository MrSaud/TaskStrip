package com.saud.taskstrip.ui.theme

import androidx.compose.ui.graphics.Color
import com.saud.taskstrip.data.Priority

fun Priority.tabColor(): Color = when (this) {
    Priority.URGENT -> PriorityUrgent
    Priority.HIGH -> PriorityHigh
    Priority.NORMAL -> PriorityNormal
    Priority.LOW -> PriorityLow
}

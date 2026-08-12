package com.saud.taskstrip.data

import java.io.Serializable

// A single free-text entry in a strip's activity log — the timestamp is always stamped
// automatically at the moment the entry is added, never user-editable.
data class TaskActionLogEntry(
    val text: String,
    val timestamp: Long
) : Serializable

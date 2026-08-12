package com.saud.taskstrip.data

import java.io.Serializable

// Serializable so it can ride inside a rememberSaveable list in the editor screen (survives a
// process death while the contact picker or a permission dialog is in front).
data class TaskContact(
    val name: String,
    val email: String = "",
    val phone: String = ""
) : Serializable

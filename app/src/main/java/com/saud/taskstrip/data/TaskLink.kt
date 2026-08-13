package com.saud.taskstrip.data

import java.io.Serializable

// A link attached to a strip — typically a URL back to an email, document, or web page the strip
// is about, so it can be reopened straight from the strip. `label` is an optional friendly name;
// when blank the UI falls back to showing the URL's host.
//
// Serializable so it can ride inside a rememberSaveable list in the editor screen (survives a
// process death while a dialog is in front), matching TaskContact.
data class TaskLink(
    val url: String,
    val label: String = ""
) : Serializable

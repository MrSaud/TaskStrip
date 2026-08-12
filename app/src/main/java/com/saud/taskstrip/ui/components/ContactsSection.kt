package com.saud.taskstrip.ui.components

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.ContactsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Contacts
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.saud.taskstrip.data.TaskContact
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.Paper

private fun readContact(context: android.content.Context, contactUri: Uri): TaskContact? {
    val resolver = context.contentResolver
    var name = ""
    var contactId: String? = null
    resolver.query(contactUri, null, null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) {
            val nameIdx = cursor.getColumnIndex(ContactsContract.Contacts.DISPLAY_NAME)
            val idIdx = cursor.getColumnIndex(ContactsContract.Contacts._ID)
            if (nameIdx >= 0) name = cursor.getString(nameIdx) ?: ""
            if (idIdx >= 0) contactId = cursor.getString(idIdx)
        }
    }
    if (contactId == null) return null

    var phone = ""
    resolver.query(
        ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
        null,
        "${ContactsContract.CommonDataKinds.Phone.CONTACT_ID} = ?",
        arrayOf(contactId),
        null
    )?.use { cursor ->
        if (cursor.moveToFirst()) {
            val numIdx = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
            if (numIdx >= 0) phone = cursor.getString(numIdx) ?: ""
        }
    }

    var email = ""
    resolver.query(
        ContactsContract.CommonDataKinds.Email.CONTENT_URI,
        null,
        "${ContactsContract.CommonDataKinds.Email.CONTACT_ID} = ?",
        arrayOf(contactId),
        null
    )?.use { cursor ->
        if (cursor.moveToFirst()) {
            val emailIdx = cursor.getColumnIndex(ContactsContract.CommonDataKinds.Email.ADDRESS)
            if (emailIdx >= 0) email = cursor.getString(emailIdx) ?: ""
        }
    }

    if (name.isBlank()) return null
    return TaskContact(name = name, email = email, phone = phone)
}

@Composable
fun ContactsSection(
    contacts: List<TaskContact>,
    onContactsChange: (List<TaskContact>) -> Unit
) {
    val context = LocalContext.current
    var showManualAdd by remember { mutableStateOf(false) }

    var hasContactsPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) ==
                PackageManager.PERMISSION_GRANTED
        )
    }

    val pickContactLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickContact()
    ) { uri: Uri? ->
        if (uri != null) {
            readContact(context, uri)?.let { onContactsChange(contacts + it) }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasContactsPermission = granted
        if (granted) pickContactLauncher.launch(null)
    }

    Text("CONTACTS", style = MaterialTheme.typography.labelSmall, color = Paper.copy(alpha = 0.7f))
    Spacer(Modifier.height(6.dp))

    Column {
        contacts.forEach { contact ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp)
            ) {
                Icon(Icons.Default.Person, contentDescription = null, tint = AmberTab)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        text = contact.name,
                        style = MaterialTheme.typography.bodyMedium,
                        color = Paper.copy(alpha = 0.9f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    val details = listOfNotNull(
                        contact.phone.takeIf { it.isNotBlank() },
                        contact.email.takeIf { it.isNotBlank() }
                    ).joinToString(" · ")
                    if (details.isNotBlank()) {
                        Text(
                            text = details,
                            style = MaterialTheme.typography.labelSmall,
                            color = Paper.copy(alpha = 0.55f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
                if (contact.phone.isNotBlank()) {
                    IconButton(onClick = {
                        val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:${contact.phone}"))
                        context.startActivity(intent)
                    }) {
                        Icon(Icons.Default.Call, contentDescription = "Call ${contact.name}", tint = Paper.copy(alpha = 0.7f))
                    }
                }
                if (contact.email.isNotBlank()) {
                    IconButton(onClick = {
                        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:${contact.email}"))
                        context.startActivity(intent)
                    }) {
                        Icon(Icons.Default.Email, contentDescription = "Email ${contact.name}", tint = Paper.copy(alpha = 0.7f))
                    }
                }
                IconButton(onClick = {
                    val text = buildString {
                        append(contact.name)
                        if (contact.phone.isNotBlank()) append("\n${contact.phone}")
                        if (contact.email.isNotBlank()) append("\n${contact.email}")
                    }
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    context.startActivity(Intent.createChooser(intent, "Share contact"))
                }) {
                    Icon(Icons.Default.Share, contentDescription = "Share ${contact.name}", tint = Paper.copy(alpha = 0.7f))
                }
                IconButton(onClick = { onContactsChange(contacts - contact) }) {
                    Icon(Icons.Default.Delete, contentDescription = "Remove ${contact.name}", tint = Paper.copy(alpha = 0.6f))
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedButton(
                onClick = {
                    if (hasContactsPermission) {
                        pickContactLauncher.launch(null)
                    } else {
                        permissionLauncher.launch(Manifest.permission.READ_CONTACTS)
                    }
                },
                modifier = Modifier.height(48.dp)
            ) {
                Icon(Icons.Default.Contacts, contentDescription = null, tint = Paper.copy(alpha = 0.7f))
                Spacer(Modifier.width(8.dp))
                Text("FROM CONTACTS", style = MaterialTheme.typography.bodyMedium)
            }
            OutlinedButton(
                onClick = { showManualAdd = true },
                modifier = Modifier.height(48.dp)
            ) {
                Icon(Icons.Default.PersonAdd, contentDescription = null, tint = Paper.copy(alpha = 0.7f))
                Spacer(Modifier.width(8.dp))
                Text("ADD MANUALLY", style = MaterialTheme.typography.bodyMedium)
            }
        }
    }

    if (showManualAdd) {
        ManualAddContactDialog(
            onDismiss = { showManualAdd = false },
            onConfirm = { contact ->
                onContactsChange(contacts + contact)
                showManualAdd = false
            }
        )
    }
}

@Composable
private fun ManualAddContactDialog(
    onDismiss: () -> Unit,
    onConfirm: (TaskContact) -> Unit
) {
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("ADD CONTACT", style = MaterialTheme.typography.titleMedium) },
        text = {
            Column {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("NAME") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = phone,
                    onValueChange = { phone = it },
                    label = { Text("PHONE") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    label = { Text("EMAIL") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (name.isNotBlank()) {
                        onConfirm(TaskContact(name = name.trim(), email = email.trim(), phone = phone.trim()))
                    }
                }
            ) {
                Text("ADD", color = AmberTab)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("CANCEL", color = Paper.copy(alpha = 0.7f))
            }
        }
    )
}

package com.saud.taskstrip

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.content.IntentCompat
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.saud.taskstrip.backup.AutoBackupPrefs
import com.saud.taskstrip.backup.AutoBackupScheduler
import com.saud.taskstrip.backup.BackupViewModel
import com.saud.taskstrip.backup.BackupViewModelFactory
import com.saud.taskstrip.data.AppDatabase
import com.saud.taskstrip.data.CredentialRepository
import com.saud.taskstrip.data.NoteRepository
import com.saud.taskstrip.data.ReminderRepository
import com.saud.taskstrip.data.StorageRepository
import com.saud.taskstrip.data.TaskRepository
import com.saud.taskstrip.notifications.DigestPrefs
import com.saud.taskstrip.notifications.DigestScheduler
import com.saud.taskstrip.notifications.GeneralReminderScheduler
import com.saud.taskstrip.notifications.NotificationHelper
import com.saud.taskstrip.notifications.ReminderScheduler
import com.saud.taskstrip.notifications.WeeklyDigestPrefs
import com.saud.taskstrip.notifications.WeeklyDigestScheduler
import com.saud.taskstrip.ui.screens.AddEditTaskScreen
import com.saud.taskstrip.ui.screens.ArchiveScreen
import com.saud.taskstrip.ui.screens.BackupScreen
import com.saud.taskstrip.ui.screens.CredentialEditScreen
import com.saud.taskstrip.ui.screens.CredentialsScreen
import com.saud.taskstrip.ui.screens.HomeScreen
import com.saud.taskstrip.ui.screens.NotesScreen
import com.saud.taskstrip.ui.screens.ReminderEditScreen
import com.saud.taskstrip.ui.screens.RemindersScreen
import com.saud.taskstrip.ui.screens.ShareStorageScreen
import com.saud.taskstrip.ui.screens.ShareTargetScreen
import com.saud.taskstrip.ui.screens.SketchCanvasScreen
import com.saud.taskstrip.ui.screens.SketchListScreen
import com.saud.taskstrip.ui.screens.StandupScreen
import com.saud.taskstrip.ui.screens.StorageScreen
import com.saud.taskstrip.ui.screens.TagProgressScreen
import com.saud.taskstrip.ui.theme.TaskStripTheme
import com.saud.taskstrip.voice.VoiceDraft
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.net.URLDecoder
import java.net.URLEncoder

class MainActivity : FragmentActivity() {

    companion object {
        const val EXTRA_OPEN_TASK_ID = "open_task_id"
        const val EXTRA_OPEN_NEW_TASK = "open_new_task"
        const val EXTRA_OPEN_REMINDER_ID = "open_reminder_id"

        private val VCARD_MIME_TYPES = setOf("text/x-vcard", "text/vcard")

        private fun parseShareIntent(context: Context, intent: Intent?): VoiceDraft? {
            if (intent?.action != Intent.ACTION_SEND) return null
            return when (intent.type) {
                "text/plain" -> parseTextShare(intent)
                in VCARD_MIME_TYPES -> parseContactShare(context, intent)
                else -> null
            }
        }

        /** A photo, video, or document shared in from another app's share sheet — single or
         * multiple. Returns the stream Uris to hand to [StorageViewModel.addFromUri]; null if this
         * intent isn't a file share at all (text/vcard shares are handled by [parseShareIntent]). */
        private fun parseFileShareIntent(intent: Intent?): List<Uri>? {
            val type = intent?.type ?: return null
            if (type == "text/plain" || type in VCARD_MIME_TYPES) return null
            return when (intent.action) {
                Intent.ACTION_SEND ->
                    IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)?.let { listOf(it) }
                Intent.ACTION_SEND_MULTIPLE ->
                    IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                else -> null
            }
        }

        private fun parseTextShare(intent: Intent): VoiceDraft? {
            val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim()
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
            if (subject.isNullOrBlank() && text.isNullOrBlank()) return null
            val title = when {
                !subject.isNullOrBlank() -> subject
                !text.isNullOrBlank() -> text.lineSequence().firstOrNull()?.take(80) ?: "Shared item"
                else -> "Shared item"
            }
            return VoiceDraft(title = title, notes = text.orEmpty(), priority = null)
        }

        private fun parseContactShare(context: Context, intent: Intent): VoiceDraft? {
            val uri = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java) ?: return null
            val vcard = try {
                context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            } catch (e: Exception) {
                null
            } ?: return null

            var name: String? = null
            val phones = mutableListOf<String>()
            val emails = mutableListOf<String>()
            vcard.lineSequence().forEach { raw ->
                val line = raw.trim()
                when {
                    line.startsWith("FN:", ignoreCase = true) -> name = line.substringAfter(":").trim()
                    line.startsWith("N:", ignoreCase = true) && name == null -> {
                        name = line.substringAfter(":").split(";").filter { it.isNotBlank() }.joinToString(" ")
                    }
                    line.startsWith("TEL", ignoreCase = true) ->
                        line.substringAfter(":").trim().takeIf { it.isNotBlank() }?.let { phones += it }
                    line.startsWith("EMAIL", ignoreCase = true) ->
                        line.substringAfter(":").trim().takeIf { it.isNotBlank() }?.let { emails += it }
                }
            }
            val finalName = name?.takeIf { it.isNotBlank() } ?: return null
            val notesLines = buildList {
                if (phones.isNotEmpty()) add("Phone: " + phones.joinToString(", "))
                if (emails.isNotEmpty()) add("Email: " + emails.joinToString(", "))
            }
            return VoiceDraft(
                title = finalName,
                notes = notesLines.joinToString("\n"),
                priority = null,
                contactEmail = emails.firstOrNull(),
                contactPhone = phones.firstOrNull()
            )
        }
    }

    // A share, a widget tap, or a notification tap can all arrive as a new intent while this
    // Activity instance already exists (singleTask). NavHost's `startDestination` only takes
    // effect on the very first composition — Activity.recreate() looked like the simple fix, but
    // it restores the NavController's previously *saved* back stack (still sitting on "home"),
    // silently ignoring the new startDestination. Bumping a version counter and reacting to it
    // with an explicit navigate() call below sidesteps that entirely.
    private var intentVersion by mutableIntStateOf(0)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intentVersion++
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        NotificationHelper.ensureChannel(applicationContext)
        if (DigestPrefs.isEnabled(applicationContext)) {
            DigestScheduler.scheduleNext(applicationContext)
        }
        if (WeeklyDigestPrefs.isEnabled(applicationContext)) {
            WeeklyDigestScheduler.scheduleNext(applicationContext)
        }
        if (AutoBackupPrefs.isEnabled(applicationContext)) {
            AutoBackupScheduler.scheduleNext(applicationContext)
        }

        val database = AppDatabase.getInstance(applicationContext)
        val repository = TaskRepository(database.taskDao())
        val factory = TaskViewModelFactory(application, repository)
        val credentialRepository = CredentialRepository(database.credentialDao())
        val credentialFactory = CredentialViewModelFactory(application, credentialRepository)
        val backupFactory = BackupViewModelFactory(application)
        val noteRepository = NoteRepository(database.noteDao())
        val noteFactory = NoteViewModelFactory(application, noteRepository)
        val reminderRepository = ReminderRepository(database.reminderDao())
        val reminderFactory = ReminderViewModelFactory(application, reminderRepository)
        val storageRepository = StorageRepository(database.storageItemDao())
        val storageFactory = StorageViewModelFactory(application, storageRepository)

        // One-time correction for alarms scheduled by an older build that treated the picked
        // wall-clock time as a real UTC instant instead of re-anchoring it to this device's
        // timezone — any reminder/due-date alarm already registered with AlarmManager keeps its
        // stale (offset) trigger time until something re-schedules it, which a plain app update
        // does not do on its own.
        CoroutineScope(Dispatchers.IO).launch {
            database.reminderDao().getAllOnce().forEach { reminder ->
                GeneralReminderScheduler.schedule(applicationContext, reminder)
            }
            database.taskDao().getAllOnce().forEach { task ->
                if (task.dueAt != null) ReminderScheduler.schedule(applicationContext, task)
            }
        }
        setContent {
            TaskStripTheme {
                val viewModel: TaskViewModel = viewModel(factory = factory)
                val credentialViewModel: CredentialViewModel = viewModel(factory = credentialFactory)
                val backupViewModel: BackupViewModel = viewModel(factory = backupFactory)
                val noteViewModel: NoteViewModel = viewModel(factory = noteFactory)
                val reminderViewModel: ReminderViewModel = viewModel(factory = reminderFactory)
                val storageViewModel: StorageViewModel = viewModel(factory = storageFactory)
                val navController = rememberNavController()
                var sharedContent by remember { mutableStateOf<VoiceDraft?>(null) }
                var sharedFileUris by remember { mutableStateOf<List<Uri>?>(null) }

                // Navigation-Compose doesn't reliably bind typed route arguments (like the
                // taskId in "editor/{taskId}") when that route is used as the graph's
                // startDestination — it silently defaults to 0 instead of the real id. Routing
                // every intent-driven destination (cold start included) through an explicit
                // navigate() call from "home" sidesteps that entirely, and also means cold start
                // and a warm restart (tapping a widget row or notification while already running)
                // share one consistent code path.
                LaunchedEffect(intentVersion) {
                    val current = intent
                    val taskId = current.getLongExtra(EXTRA_OPEN_TASK_ID, -1L)
                    val newTask = current.getBooleanExtra(EXTRA_OPEN_NEW_TASK, false)
                    val reminderId = current.getLongExtra(EXTRA_OPEN_REMINDER_ID, -1L)
                    val shared = parseShareIntent(applicationContext, current)
                    val sharedFiles = parseFileShareIntent(current)
                    when {
                        taskId >= 0 -> navController.navigate("editor/$taskId")
                        newTask -> navController.navigate("editor/-1")
                        reminderId >= 0 -> navController.navigate("reminder-editor/$reminderId")
                        shared != null -> {
                            sharedContent = shared
                            navController.navigate("share-target")
                        }
                        !sharedFiles.isNullOrEmpty() -> {
                            sharedFileUris = sharedFiles
                            navController.navigate("share-storage")
                        }
                    }
                }

                NavHost(
                    navController = navController,
                    startDestination = "home"
                ) {
                    composable("home") {
                        HomeScreen(
                            viewModel = viewModel,
                            onAddClick = { navController.navigate("editor/-1") },
                            onTaskClick = { id -> navController.navigate("editor/$id") },
                            onArchiveClick = { navController.navigate("archive") },
                            onSketchesClick = { navController.navigate("sketches") },
                            onCredentialsClick = { navController.navigate("credentials") },
                            onBackupClick = { navController.navigate("backup") },
                            onNotesClick = { navController.navigate("notes") },
                            onStandupClick = { navController.navigate("standup") },
                            onTagProgressClick = { navController.navigate("tag-progress") },
                            onRemindersClick = { navController.navigate("reminders") },
                            onNewReminderClick = { navController.navigate("reminder-editor/-1") },
                            onNewReminderByVoice = { spoken ->
                                reminderViewModel.setPendingText(spoken)
                                navController.navigate("reminder-editor/-1")
                            },
                            onStorageClick = { navController.navigate("storage") }
                        )
                    }
                    composable("storage") {
                        StorageScreen(
                            viewModel = storageViewModel,
                            onBack = { navController.popBackStack() }
                        )
                    }
                    composable("share-storage") {
                        ShareStorageScreen(
                            uris = sharedFileUris.orEmpty(),
                            storageViewModel = storageViewModel,
                            onDone = {
                                navController.navigate("home") { popUpTo("share-storage") { inclusive = true } }
                            },
                            onCancel = {
                                navController.navigate("home") { popUpTo("share-storage") { inclusive = true } }
                            }
                        )
                    }
                    composable("reminders") {
                        RemindersScreen(
                            viewModel = reminderViewModel,
                            onBack = { navController.popBackStack() },
                            onAddClick = { navController.navigate("reminder-editor/-1") },
                            onEditClick = { id -> navController.navigate("reminder-editor/$id") }
                        )
                    }
                    composable(
                        route = "reminder-editor/{reminderId}",
                        arguments = listOf(navArgument("reminderId") { type = NavType.LongType })
                    ) { backStackEntry ->
                        val reminderId = backStackEntry.arguments?.getLong("reminderId") ?: -1L
                        ReminderEditScreen(
                            viewModel = reminderViewModel,
                            reminderId = reminderId,
                            onDone = { navController.popBackStack() }
                        )
                    }
                    composable("standup") {
                        StandupScreen(
                            viewModel = viewModel,
                            onBack = { navController.popBackStack() }
                        )
                    }
                    composable("tag-progress") {
                        TagProgressScreen(
                            viewModel = viewModel,
                            onBack = { navController.popBackStack() }
                        )
                    }
                    composable("notes") {
                        NotesScreen(
                            noteViewModel = noteViewModel,
                            taskViewModel = viewModel,
                            onBack = { navController.popBackStack() }
                        )
                    }
                    composable("backup") {
                        BackupScreen(
                            viewModel = backupViewModel,
                            onBack = { navController.popBackStack() }
                        )
                    }
                    composable("credentials") {
                        CredentialsScreen(
                            viewModel = credentialViewModel,
                            onBack = { navController.popBackStack() },
                            onAddClick = { navController.navigate("credential-editor/-1") },
                            onEditClick = { id -> navController.navigate("credential-editor/$id") }
                        )
                    }
                    composable(
                        route = "credential-editor/{credentialId}",
                        arguments = listOf(navArgument("credentialId") { type = NavType.LongType })
                    ) { backStackEntry ->
                        val credentialId = backStackEntry.arguments?.getLong("credentialId") ?: -1L
                        CredentialEditScreen(
                            viewModel = credentialViewModel,
                            credentialId = credentialId,
                            onDone = { navController.popBackStack() }
                        )
                    }
                    composable(
                        route = "editor/{taskId}",
                        arguments = listOf(navArgument("taskId") { type = NavType.LongType })
                    ) { backStackEntry ->
                        val taskId = backStackEntry.arguments?.getLong("taskId") ?: -1L
                        AddEditTaskScreen(
                            viewModel = viewModel,
                            storageViewModel = storageViewModel,
                            taskId = taskId,
                            onDone = { navController.popBackStack() },
                            onOpenSketch = { fileName ->
                                val encoded = URLEncoder.encode(fileName, "UTF-8")
                                navController.navigate("sketch/$encoded")
                            }
                        )
                    }
                    composable("archive") {
                        ArchiveScreen(
                            viewModel = viewModel,
                            onBack = { navController.popBackStack() },
                            onTaskClick = { id -> navController.navigate("editor/$id") }
                        )
                    }
                    composable("sketches") {
                        SketchListScreen(
                            onBack = { navController.popBackStack() },
                            onOpenSketch = { fileName ->
                                val encoded = URLEncoder.encode(fileName ?: "new", "UTF-8")
                                navController.navigate("sketch/$encoded")
                            }
                        )
                    }
                    composable(
                        route = "sketch/{fileName}",
                        arguments = listOf(navArgument("fileName") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val encoded = backStackEntry.arguments?.getString("fileName") ?: "new"
                        val fileName = if (encoded == "new") null else URLDecoder.decode(encoded, "UTF-8")
                        SketchCanvasScreen(
                            fileName = fileName,
                            onDone = { navController.popBackStack() }
                        )
                    }
                    composable("share-target") {
                        ShareTargetScreen(
                            content = sharedContent ?: VoiceDraft("", "", null),
                            viewModel = viewModel,
                            onCreateNew = { draft ->
                                viewModel.setPendingDraft(draft)
                                navController.navigate("home") { popUpTo("share-target") { inclusive = true } }
                                navController.navigate("editor/-1")
                            },
                            onDone = {
                                navController.navigate("home") { popUpTo("share-target") { inclusive = true } }
                            }
                        )
                    }
                }
            }
        }
    }
}

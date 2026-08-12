package com.saud.taskstrip.ui.screens

import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saud.taskstrip.TaskViewModel
import com.saud.taskstrip.data.TaskEntity
import com.saud.taskstrip.ui.components.isDueTodayOrOverdue
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.BaySurface
import com.saud.taskstrip.ui.theme.Paper
import java.util.concurrent.TimeUnit

private fun buildStandupText(done: List<TaskEntity>, planned: List<TaskEntity>, blocked: List<TaskEntity>): String =
    buildString {
        appendLine("STANDUP SUMMARY")
        appendLine()
        appendLine("Done recently:")
        if (done.isEmpty()) appendLine("- (nothing)") else done.forEach { appendLine("- ${it.title}") }
        appendLine()
        appendLine("Planned today:")
        if (planned.isEmpty()) appendLine("- (nothing)") else planned.forEach { appendLine("- ${it.title}") }
        appendLine()
        appendLine("Blockers:")
        if (blocked.isEmpty()) appendLine("- (none)") else blocked.forEach { appendLine("- ${it.title}") }
    }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StandupScreen(
    viewModel: TaskViewModel,
    onBack: () -> Unit
) {
    val tasks by viewModel.tasks.collectAsStateWithLifecycle()
    val context: Context = LocalContext.current
    val clipboard: ClipboardManager = LocalClipboardManager.current

    val doneRecently = remember(tasks) {
        val since = System.currentTimeMillis() - TimeUnit.HOURS.toMillis(24)
        tasks.filter { it.isDone && (it.completedAt ?: 0L) >= since }
    }
    val plannedToday = remember(tasks) {
        tasks.filter { !it.isDone && !it.isArchived && isDueTodayOrOverdue(it.dueAt, it.isDone) }
    }
    val blocked = remember(tasks) {
        tasks.filter { t ->
            !t.isDone && !t.isArchived &&
                t.blockedByTaskId?.let { id -> tasks.find { it.id == id }?.isDone == false } == true
        }
    }

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = { Text("STANDUP SUMMARY", style = MaterialTheme.typography.titleLarge, color = Paper) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Paper)
                    }
                },
                actions = {
                    IconButton(onClick = {
                        clipboard.setText(AnnotatedString(buildStandupText(doneRecently, plannedToday, blocked)))
                        Toast.makeText(context, "Copied", Toast.LENGTH_SHORT).show()
                    }) {
                        Icon(Icons.Default.ContentCopy, contentDescription = "Copy summary", tint = Paper)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier.padding(padding).fillMaxSize(),
            contentPadding = PaddingValues(16.dp)
        ) {
            item { StandupSection(title = "DONE RECENTLY", tasks = doneRecently, emptyLabel = "Nothing completed in the last 24h") }
            item { StandupSection(title = "PLANNED TODAY", tasks = plannedToday, emptyLabel = "Nothing due today or overdue") }
            item { StandupSection(title = "BLOCKERS", tasks = blocked, emptyLabel = "Nothing blocked") }
        }
    }
}

@Composable
private fun StandupSection(title: String, tasks: List<TaskEntity>, emptyLabel: String) {
    Column(Modifier.fillMaxWidth().padding(bottom = 20.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelLarge,
            color = AmberTab
        )
        if (tasks.isEmpty()) {
            Text(
                text = emptyLabel,
                style = MaterialTheme.typography.bodyMedium,
                color = Paper.copy(alpha = 0.5f),
                modifier = Modifier.padding(top = 8.dp)
            )
        } else {
            Column {
                tasks.forEach { task ->
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp)
                            .background(BaySurface, RoundedCornerShape(4.dp))
                            .padding(12.dp)
                    ) {
                        Text(
                            text = task.title.uppercase(),
                            style = MaterialTheme.typography.bodyMedium,
                            color = Paper
                        )
                    }
                }
            }
        }
    }
}

package com.saud.taskstrip.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Unarchive
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saud.taskstrip.TaskViewModel
import com.saud.taskstrip.ui.components.DateRange
import com.saud.taskstrip.ui.components.DateRangeFilterDialog
import com.saud.taskstrip.ui.components.FlightStripRow
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArchiveScreen(
    viewModel: TaskViewModel,
    onBack: () -> Unit,
    onTaskClick: (Long) -> Unit
) {
    val archivedRaw by viewModel.archivedTasks.collectAsStateWithLifecycle()
    var query by remember { mutableStateOf("") }
    var dateRange by remember { mutableStateOf(DateRange.EMPTY) }
    var showDateFilterDialog by remember { mutableStateOf(false) }

    val archived = remember(archivedRaw, dateRange) {
        archivedRaw.filter { dateRange.contains(it.createdAt) }
    }

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = { Text("ARCHIVE", style = MaterialTheme.typography.titleLarge, color = Paper) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Paper)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp)
            ) {
                OutlinedTextField(
                    value = query,
                    onValueChange = {
                        query = it
                        viewModel.setArchiveQuery(it)
                    },
                    placeholder = { Text("SEARCH ARCHIVE") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, tint = Paper.copy(alpha = 0.6f)) },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyLarge,
                    colors = TextFieldDefaults.colors(
                        focusedTextColor = Paper,
                        unfocusedTextColor = Paper,
                        focusedContainerColor = androidx.compose.ui.graphics.Color.Transparent,
                        unfocusedContainerColor = androidx.compose.ui.graphics.Color.Transparent
                    ),
                    modifier = Modifier
                        .weight(1f)
                        .padding(horizontal = 8.dp)
                )
                IconButton(onClick = { showDateFilterDialog = true }) {
                    Icon(
                        Icons.Default.DateRange,
                        contentDescription = dateRange.label() ?: "Filter by filed date",
                        tint = if (dateRange.isSet) AmberTab else Paper
                    )
                }
            }

            if (archived.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        text = if (query.isBlank() && !dateRange.isSet) "NO ARCHIVED TASKS" else "NO MATCHES",
                        style = MaterialTheme.typography.titleMedium,
                        color = Paper.copy(alpha = 0.5f)
                    )
                }
            } else {
                LazyColumn(Modifier.fillMaxSize()) {
                    items(archived, key = { it.id }) { task ->
                        FlightStripRow(
                            task = task,
                            completed = true,
                            onClick = { onTaskClick(task.id) },
                            onDelete = { viewModel.deleteTask(task) },
                            trailingActions = {
                                IconButton(onClick = { viewModel.unarchiveTask(task) }) {
                                    Icon(
                                        Icons.Default.Unarchive,
                                        contentDescription = "Unarchive",
                                        tint = InkColor.copy(alpha = 0.6f)
                                    )
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    if (showDateFilterDialog) {
        DateRangeFilterDialog(
            onDismiss = { showDateFilterDialog = false },
            onConfirm = { range -> dateRange = range },
            onClear = { dateRange = DateRange.EMPTY }
        )
    }
}

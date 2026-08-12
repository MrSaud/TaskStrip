package com.saud.taskstrip.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.saud.taskstrip.TaskViewModel
import com.saud.taskstrip.ui.theme.AmberTab
import com.saud.taskstrip.ui.theme.BayBackground
import com.saud.taskstrip.ui.theme.BaySurface
import com.saud.taskstrip.ui.theme.InkColor
import com.saud.taskstrip.ui.theme.Paper

private data class TagStat(val tag: String, val done: Int, val total: Int) {
    val fraction: Float get() = if (total == 0) 0f else done.toFloat() / total
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TagProgressScreen(
    viewModel: TaskViewModel,
    onBack: () -> Unit
) {
    val tasks by viewModel.tasks.collectAsStateWithLifecycle()

    val stats = remember(tasks) {
        val nonArchived = tasks.filter { !it.isArchived }
        nonArchived
            .flatMap { t -> t.tags.map { it to t.isDone } }
            .groupBy({ it.first.lowercase() }, { it.second })
            .map { (tagLower, doneFlags) ->
                val displayTag = nonArchived.flatMap { it.tags }.first { it.lowercase() == tagLower }
                TagStat(tag = displayTag, done = doneFlags.count { it }, total = doneFlags.size)
            }
            .sortedByDescending { it.total }
    }

    Scaffold(
        containerColor = BayBackground,
        topBar = {
            TopAppBar(
                title = { Text("TAG PROGRESS", style = MaterialTheme.typography.titleLarge, color = Paper) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = Paper)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BayBackground)
            )
        }
    ) { padding ->
        if (stats.isEmpty()) {
            Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    text = "NO TAGGED STRIPS YET",
                    style = MaterialTheme.typography.titleMedium,
                    color = Paper.copy(alpha = 0.5f)
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.padding(padding).fillMaxSize(),
                contentPadding = PaddingValues(16.dp)
            ) {
                items(stats, key = { it.tag.lowercase() }) { stat ->
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .padding(bottom = 12.dp)
                            .background(BaySurface, RoundedCornerShape(4.dp))
                            .padding(14.dp)
                    ) {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(
                                text = stat.tag.uppercase(),
                                style = MaterialTheme.typography.bodyLarge,
                                color = Paper
                            )
                            Text(
                                text = "${stat.done}/${stat.total}",
                                style = MaterialTheme.typography.bodyMedium,
                                color = AmberTab
                            )
                        }
                        Spacer(Modifier.height(8.dp))
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .height(6.dp)
                                .background(InkColor.copy(alpha = 0.3f), RoundedCornerShape(3.dp))
                        ) {
                            Box(
                                Modifier
                                    .fillMaxWidth(stat.fraction.coerceIn(0f, 1f))
                                    .height(6.dp)
                                    .background(AmberTab, RoundedCornerShape(3.dp))
                            )
                        }
                    }
                }
            }
        }
    }
}

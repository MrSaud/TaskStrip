package com.saud.taskstrip.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val StripColorScheme = darkColorScheme(
    background = BayBackground,
    surface = BaySurface,
    onBackground = Paper,
    onSurface = Paper,
    primary = AmberTab,
    onPrimary = InkColor,
    secondary = PriorityNormal,
    surfaceVariant = BaySurface,
    onSurfaceVariant = Paper
)

@Composable
fun TaskStripTheme(content: @Composable () -> Unit) {
    // The board is always a dark tray, like a real strip bay, regardless of system theme.
    MaterialTheme(
        colorScheme = StripColorScheme,
        typography = StripTypography,
        content = content
    )
}

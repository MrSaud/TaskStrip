package com.saud.taskstrip.data

import kotlinx.coroutines.flow.Flow

class ClipboardRepository(private val dao: ClipboardDao) {
    val items: Flow<List<ClipboardEntity>> = dao.observeAll()

    suspend fun add(text: String, label: String = ""): Long =
        dao.insert(ClipboardEntity(text = text, label = label))

    suspend fun update(item: ClipboardEntity) = dao.update(item)

    suspend fun delete(item: ClipboardEntity) = dao.delete(item)

    /** Clears the pile of one-off snippets while keeping the pinned ones. */
    suspend fun clearUnpinned() = dao.deleteUnpinned()
}

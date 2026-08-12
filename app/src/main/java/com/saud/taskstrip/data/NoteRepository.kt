package com.saud.taskstrip.data

import kotlinx.coroutines.flow.Flow

class NoteRepository(private val dao: NoteDao) {
    val notes: Flow<List<NoteEntity>> = dao.observeAll()

    suspend fun add(text: String): Long = dao.insert(NoteEntity(text = text))

    suspend fun delete(note: NoteEntity) = dao.delete(note)
}

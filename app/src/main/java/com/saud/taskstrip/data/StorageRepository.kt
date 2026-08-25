package com.saud.taskstrip.data

import kotlinx.coroutines.flow.Flow

class StorageRepository(private val dao: StorageItemDao) {
    val items: Flow<List<StorageItemEntity>> = dao.observeAll()

    suspend fun add(name: String, path: String, type: String, mimeType: String, sizeBytes: Long): StorageItemEntity {
        val entity = StorageItemEntity(name = name, path = path, type = type, mimeType = mimeType, sizeBytes = sizeBytes)
        val id = dao.insert(entity)
        return entity.copy(id = id)
    }

    suspend fun delete(item: StorageItemEntity) = dao.delete(item)
}

package com.saud.taskstrip.data

import kotlinx.coroutines.flow.Flow

class StorageRepository(private val dao: StorageItemDao) {
    val items: Flow<List<StorageItemEntity>> = dao.observeAll()

    suspend fun add(
        name: String,
        path: String,
        type: String,
        mimeType: String,
        sizeBytes: Long,
        tag: String = "",
        tagEmoji: String = ""
    ): StorageItemEntity {
        val entity = StorageItemEntity(name = name, path = path, type = type, mimeType = mimeType, sizeBytes = sizeBytes, tag = tag, tagEmoji = tagEmoji)
        val id = dao.insert(entity)
        return entity.copy(id = id)
    }

    suspend fun setTag(item: StorageItemEntity, tag: String, tagEmoji: String) =
        dao.update(item.copy(tag = tag, tagEmoji = tagEmoji, updatedAt = System.currentTimeMillis()))

    /** A tombstone, not a removal — see TaskRepository.deleteTask. */
    suspend fun delete(item: StorageItemEntity) = dao.update(
        item.copy(isDeleted = true, updatedAt = System.currentTimeMillis())
    )

    /** What the sync sends: live items and the tombstones of dead ones. */
    suspend fun getAllForSync(): List<StorageItemEntity> = dao.getAllForSync()
}

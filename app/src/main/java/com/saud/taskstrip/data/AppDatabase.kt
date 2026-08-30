package com.saud.taskstrip.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

// Real migration for the schema jump a device with actual saved tasks is currently on (v3,
// pre-documents) to the current version — this one must never fall back to a destructive wipe.
val MIGRATION_3_4 = object : Migration(3, 4) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE tasks ADD COLUMN documents TEXT NOT NULL DEFAULT ''")
    }
}

val MIGRATION_4_5 = object : Migration(4, 5) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE tasks ADD COLUMN videos TEXT NOT NULL DEFAULT ''")
    }
}

val MIGRATION_5_6 = object : Migration(5, 6) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS credentials (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                "title TEXT NOT NULL, " +
                "username TEXT NOT NULL DEFAULT '', " +
                "encryptedPassword TEXT NOT NULL DEFAULT '', " +
                "url TEXT NOT NULL DEFAULT '', " +
                "notes TEXT NOT NULL DEFAULT '', " +
                "createdAt INTEGER NOT NULL)"
        )
    }
}

val MIGRATION_6_7 = object : Migration(6, 7) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE tasks ADD COLUMN repeatIntervalDays INTEGER")
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS notes (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                "text TEXT NOT NULL, " +
                "createdAt INTEGER NOT NULL)"
        )
    }
}

val MIGRATION_7_8 = object : Migration(7, 8) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE tasks ADD COLUMN contacts TEXT NOT NULL DEFAULT '[]'")
    }
}

val MIGRATION_8_9 = object : Migration(8, 9) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE tasks ADD COLUMN tags TEXT NOT NULL DEFAULT ''")
        // Tags replace the old single free-text category — carry any existing value over as this
        // task's first tag instead of silently dropping it.
        db.execSQL("UPDATE tasks SET tags = route WHERE route IS NOT NULL AND route != ''")
    }
}

val MIGRATION_9_10 = object : Migration(9, 10) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE tasks ADD COLUMN completedAt INTEGER")
        db.execSQL("ALTER TABLE tasks ADD COLUMN blockedByTaskId INTEGER")
        db.execSQL("ALTER TABLE tasks ADD COLUMN waitingOnName TEXT NOT NULL DEFAULT ''")
        db.execSQL("ALTER TABLE tasks ADD COLUMN waitingOnSince INTEGER")
        db.execSQL("ALTER TABLE tasks ADD COLUMN waitingOnFollowUpDays INTEGER")
        // Backfill completedAt for rows already done before this column existed, so they don't
        // silently drop out of "done this week"-style rollups just because they finished earlier.
        db.execSQL("UPDATE tasks SET completedAt = createdAt WHERE isDone = 1 AND completedAt IS NULL")
    }
}

val MIGRATION_10_11 = object : Migration(10, 11) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE tasks ADD COLUMN linkedSketchId TEXT")
    }
}

val MIGRATION_11_12 = object : Migration(11, 12) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE tasks ADD COLUMN actionLog TEXT NOT NULL DEFAULT '[]'")
    }
}

val MIGRATION_12_13 = object : Migration(12, 13) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE tasks ADD COLUMN links TEXT NOT NULL DEFAULT '[]'")
    }
}

val MIGRATION_13_14 = object : Migration(13, 14) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS reminders (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                "text TEXT NOT NULL, " +
                "triggerAt INTEGER NOT NULL, " +
                "isDone INTEGER NOT NULL DEFAULT 0, " +
                "createdAt INTEGER NOT NULL)"
        )
    }
}

val MIGRATION_14_15 = object : Migration(14, 15) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE reminders ADD COLUMN leadMinutesBefore INTEGER")
    }
}

val MIGRATION_15_16 = object : Migration(15, 16) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE reminders ADD COLUMN repeatAmount INTEGER")
        db.execSQL("ALTER TABLE reminders ADD COLUMN repeatUnit TEXT")
    }
}

val MIGRATION_16_17 = object : Migration(16, 17) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE reminders ADD COLUMN description TEXT NOT NULL DEFAULT ''")
    }
}

val MIGRATION_17_18 = object : Migration(17, 18) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE reminders ADD COLUMN tag TEXT NOT NULL DEFAULT ''")
        db.execSQL("ALTER TABLE reminders ADD COLUMN tagEmoji TEXT NOT NULL DEFAULT ''")
    }
}

val MIGRATION_18_19 = object : Migration(18, 19) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS storage_items (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                "name TEXT NOT NULL, " +
                "path TEXT NOT NULL, " +
                "type TEXT NOT NULL, " +
                "mimeType TEXT NOT NULL DEFAULT '', " +
                "sizeBytes INTEGER NOT NULL DEFAULT 0, " +
                "createdAt INTEGER NOT NULL)"
        )
    }
}

val MIGRATION_19_20 = object : Migration(19, 20) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE storage_items ADD COLUMN tag TEXT NOT NULL DEFAULT ''")
        db.execSQL("ALTER TABLE storage_items ADD COLUMN tagEmoji TEXT NOT NULL DEFAULT ''")
    }
}

val MIGRATION_20_21 = object : Migration(20, 21) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE tasks ADD COLUMN notesRtl INTEGER NOT NULL DEFAULT 0")
    }
}

val MIGRATION_21_22 = object : Migration(21, 22) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS clipboard_items (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                "text TEXT NOT NULL, " +
                "label TEXT NOT NULL DEFAULT '', " +
                "isPinned INTEGER NOT NULL DEFAULT 0, " +
                "isSyncable INTEGER NOT NULL DEFAULT 1, " +
                "createdAt INTEGER NOT NULL)"
        )
    }
}

// The Clipboard feature (and its clipboard_items table from MIGRATION_21_22) was removed —
// this only drops the table for any device that already reached v22, rather than falling back
// to a destructive migration that would wipe everything else too.
val MIGRATION_22_23 = object : Migration(22, 23) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("DROP TABLE IF EXISTS clipboard_items")
    }
}

val MIGRATION_23_24 = object : Migration(23, 24) {
    override fun migrate(db: SupportSQLiteDatabase) {
        // The id is the shared UUID rather than an autoincrementing key: it has to mean the same
        // note on the Mac, which is the whole point of the table.
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS sync_notes (" +
                "id TEXT PRIMARY KEY NOT NULL, " +
                "title TEXT NOT NULL DEFAULT '', " +
                "text TEXT NOT NULL DEFAULT '', " +
                "updatedAt INTEGER NOT NULL, " +
                "isDeleted INTEGER NOT NULL DEFAULT 0)"
        )
    }
}

@Database(
    entities = [TaskEntity::class, CredentialEntity::class, NoteEntity::class, ReminderEntity::class, StorageItemEntity::class, SyncNoteEntity::class],
    version = 24,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {
    abstract fun taskDao(): TaskDao
    abstract fun credentialDao(): CredentialDao
    abstract fun noteDao(): NoteDao
    abstract fun reminderDao(): ReminderDao
    abstract fun storageItemDao(): StorageItemDao
    abstract fun syncNoteDao(): SyncNoteDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        fun getInstance(context: Context): AppDatabase =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "taskstrip.db"
                )
                    .addMigrations(MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9, MIGRATION_9_10, MIGRATION_10_11, MIGRATION_11_12, MIGRATION_12_13, MIGRATION_13_14, MIGRATION_14_15, MIGRATION_15_16, MIGRATION_16_17, MIGRATION_17_18, MIGRATION_18_19, MIGRATION_19_20, MIGRATION_20_21, MIGRATION_21_22, MIGRATION_22_23, MIGRATION_23_24)
                    // Only reached for version jumps with no real user data behind them
                    // (e.g. a stale pre-v3 dev install) — every jump from here on gets a
                    // real Migration above instead, so saved tasks are never silently wiped.
                    .fallbackToDestructiveMigration()
                    .build().also { INSTANCE = it }
            }
    }
}

import Foundation
import SwiftData

/// SwiftData's objects in, records out, and back again.
///
/// Mirrors BoardRecords.kt. The one place that knows both shapes: the document knows nothing about
/// SwiftData and SwiftData knows nothing about the document, so neither can drift into depending
/// on the other's incidental details.
///
/// Dates cross here too. A record carries milliseconds since the epoch, because that is what
/// Android writes everywhere and the two have to read each other's numbers without a second
/// thought; this side holds `Date`.
enum BoardRecords {

    /// The three parts the backup's crypto already produces. Named here so this file doesn't
    /// depend on it.
    struct PortablePassword {
        var salt: String
        var iv: String
        var cipher: String
    }

    // MARK: - Out: what this machine sends

    /// - Parameter syncIDOfTask: resolves a blocker to its shared id. A blocker whose row has gone
    ///   resolves to nil rather than to a made-up id — the far side would only have to clear a
    ///   dangling link, and inventing one to send is worse than sending none.
    static func record(
        for task: TaskItem,
        attachments: [SyncAttachment] = [],
        syncIDOfTask: (UUID) -> String? = { _ in nil },
        syncIDOfSketch: (String) -> String? = { _ in nil }
    ) -> SyncTaskRecord {
        SyncTaskRecord(
            id: task.id.uuidString,
            updatedAt: millis(task.lastEditedAt),
            isDeleted: task.isTombstoned,
            title: task.title,
            notes: task.notes,
            notesRtl: task.notesRtl,
            priority: task.priorityRaw,
            dueAt: task.dueAt.map(millis),
            orderIndex: task.orderIndex,
            isDone: task.isDone,
            isArchived: task.isArchived,
            progress: task.progress,
            completedAt: task.completedAt.map(millis),
            blockedBySyncID: task.blockedByID.flatMap(syncIDOfTask),
            waitingOnName: task.waitingOnName,
            waitingOnSince: task.waitingOnSince.map(millis),
            waitingOnFollowUpDays: task.waitingOnFollowUpDays,
            reminderMinutesBefore: task.reminderMinutesBefore,
            repeatIntervalDays: task.repeatIntervalDays,
            linkedSketchSyncID: task.linkedSketchID.flatMap(syncIDOfSketch),
            tags: task.tags,
            links: task.links.map { SyncLink(url: $0.url, label: $0.label) },
            actionLog: task.actionLog.map { SyncLogEntry(text: $0.text, timestamp: millis($0.timestamp)) },
            contacts: task.contacts.map { SyncContact(name: $0.name, email: $0.email, phone: $0.phone) },
            attachments: attachments,
            createdAt: millis(task.createdAt)
        )
    }

    static func record(for reminder: Reminder) -> SyncReminderRecord {
        SyncReminderRecord(
            id: reminder.id.uuidString,
            updatedAt: millis(reminder.lastEditedAt),
            isDeleted: reminder.isTombstoned,
            text: reminder.text,
            details: reminder.details,
            triggerAt: millis(reminder.triggerAt),
            leadMinutesBefore: reminder.leadMinutesBefore,
            repeatAmount: reminder.repeatAmount,
            repeatUnit: reminder.repeatUnitRaw,
            tag: reminder.tag,
            tagEmoji: reminder.tagEmoji,
            isDone: reminder.isDone,
            createdAt: millis(reminder.createdAt)
        )
    }

    static func record(for item: StorageItem, hash: String) -> SyncStorageRecord {
        SyncStorageRecord(
            id: item.id.uuidString,
            updatedAt: millis(item.lastEditedAt),
            isDeleted: item.isTombstoned,
            name: item.name,
            type: item.typeRaw,
            mimeType: item.mimeType,
            sizeBytes: Int64(item.sizeBytes),
            tag: item.tag,
            tagEmoji: item.tagEmoji,
            hash: hash,
            createdAt: millis(item.createdAt)
        )
    }

    /// - Parameter password: the ciphertext under the user's passphrase, or nil when there isn't
    ///   one. Never the keychain's own copy, which is dead on arrival anywhere else, and never the
    ///   plaintext. A credential with no passphrase travels without its secret.
    static func record(for credential: Credential, password: PortablePassword? = nil) -> SyncCredentialRecord {
        SyncCredentialRecord(
            id: credential.id.uuidString,
            updatedAt: millis(credential.lastEditedAt),
            isDeleted: credential.isTombstoned,
            title: credential.title,
            username: credential.username,
            url: credential.url,
            notes: credential.notes,
            passwordSalt: password?.salt,
            passwordIv: password?.iv,
            passwordCipher: password?.cipher,
            createdAt: millis(credential.createdAt)
        )
    }

    // MARK: - In: what arrives, folded onto what is here

    /// Folded onto `task` rather than rebuilt.
    ///
    /// Everything the record does not carry is left as it is — a local file path, this machine's
    /// own attachments. That is the point: a strip arriving from the phone must not lose the files
    /// this machine holds for it just because the record only named their hashes.
    static func apply(
        _ record: SyncTaskRecord,
        to task: TaskItem,
        localIDOfSyncID: (String) -> UUID? = { _ in nil },
        localSketchIDOf: (String) -> String? = { _ in nil }
    ) {
        task.updatedAt = date(record.updatedAt)
        task.isTombstoned = record.isDeleted
        task.title = record.title
        task.notes = record.notes
        task.notesRtl = record.notesRtl
        // An unrecognised priority falls back rather than throwing: a strip from a newer version of
        // the app should be worth less, not fatal.
        task.priorityRaw = Priority(rawValue: record.priority)?.rawValue ?? Priority.normal.rawValue
        task.dueAt = record.dueAt.map(date)
        task.orderIndex = record.orderIndex
        task.isDone = record.isDone
        task.isArchived = record.isArchived
        task.progress = record.progress
        task.completedAt = record.completedAt.map(date)
        task.blockedByID = record.blockedBySyncID.flatMap(localIDOfSyncID)
        task.waitingOnName = record.waitingOnName
        task.waitingOnSince = record.waitingOnSince.map(date)
        task.waitingOnFollowUpDays = record.waitingOnFollowUpDays
        task.reminderMinutesBefore = record.reminderMinutesBefore
        task.repeatIntervalDays = record.repeatIntervalDays
        task.linkedSketchID = record.linkedSketchSyncID.flatMap(localSketchIDOf)
        task.tags = record.tags
        task.links = record.links.map { TaskLink(url: $0.url, label: $0.label) }
        task.actionLog = record.actionLog.map { TaskActionLogEntry(text: $0.text, timestamp: date($0.timestamp)) }
        task.contacts = record.contacts.map { TaskContact(name: $0.name, email: $0.email, phone: $0.phone) }
    }

    /// A strip this machine has never seen. Its id is the shared one, which is what makes the next
    /// sync recognise it rather than send it back as something new.
    static func newTask(from record: SyncTaskRecord) -> TaskItem? {
        guard let id = UUID(uuidString: record.id) else { return nil }
        return TaskItem(
            title: record.title,
            orderIndex: record.orderIndex,
            id: id,
            createdAt: date(record.createdAt)
        )
    }

    static func apply(_ record: SyncReminderRecord, to reminder: Reminder) {
        reminder.updatedAt = date(record.updatedAt)
        reminder.isTombstoned = record.isDeleted
        reminder.text = record.text
        reminder.details = record.details
        reminder.triggerAt = date(record.triggerAt)
        reminder.leadMinutesBefore = record.leadMinutesBefore
        reminder.repeatAmount = record.repeatAmount
        reminder.repeatUnitRaw = record.repeatUnit
        reminder.tag = record.tag
        reminder.tagEmoji = record.tagEmoji
        reminder.isDone = record.isDone
    }

    static func newReminder(from record: SyncReminderRecord) -> Reminder? {
        guard let id = UUID(uuidString: record.id) else { return nil }
        return Reminder(
            text: record.text,
            triggerAt: date(record.triggerAt),
            id: id,
            createdAt: date(record.createdAt)
        )
    }

    /// The path is left alone on purpose: a record names a file by its hash, never by where this
    /// machine keeps it, and overwriting the path would leave the item listed and no longer
    /// openable.
    static func apply(_ record: SyncStorageRecord, to item: StorageItem) {
        item.updatedAt = date(record.updatedAt)
        item.isTombstoned = record.isDeleted
        item.name = record.name
        item.typeRaw = record.type
        item.mimeType = record.mimeType
        item.sizeBytes = Int(record.sizeBytes)
        item.tag = record.tag
        item.tagEmoji = record.tagEmoji
    }

    /// The password is deliberately not here.
    ///
    /// Unlike Android, this side keeps the secret in the Keychain under the credential's id rather
    /// than in a column, so there is no field on the model to write and nothing for this function
    /// to do with one. Storing an arriving password is the caller's business, because only the
    /// caller holds the passphrase needed to open it — and a record whose secret cannot be read
    /// must leave the one already in the Keychain alone rather than clearing it.
    static func apply(_ record: SyncCredentialRecord, to credential: Credential) {
        credential.updatedAt = date(record.updatedAt)
        credential.isTombstoned = record.isDeleted
        credential.title = record.title
        credential.username = record.username
        credential.url = record.url
        credential.notes = record.notes
    }

    // MARK: - Milliseconds, both ways

    static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    static func date(_ millis: Int64) -> Date { Date(timeIntervalSince1970: Double(millis) / 1000) }
}

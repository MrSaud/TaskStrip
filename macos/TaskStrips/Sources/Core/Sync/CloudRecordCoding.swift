import CloudKit
import Foundation

/// Each model to and from its CloudKit record, following docs/CloudKitSchema.md.
///
/// `encode` always writes onto a record it's given — the copy last received from the server when
/// there is one — rather than building a fresh one. That keeps the record's change tag, and it
/// keeps any field this version doesn't know about: a newer device's additions survive an older
/// device's edit.
///
/// `decode` reads what's there. A missing value means different things by kind of field: for one
/// that is optional in the model (a due date, a blocker) it means "cleared", because clearing it
/// is how it goes missing; for one that always has a value (a title, a flag) it means the record
/// predates the field, and the model's own value is left alone.
enum CloudRecordCoding {
    static func newRecord(type: String, name: String) -> CKRecord {
        CKRecord(recordType: type, recordID: CloudSchema.recordID(name))
    }

    // MARK: - Strip

    /// `sortKey` is the strip's place on the board, from SortKey — the sync layer owns it, since
    /// it depends on the neighbours as iCloud last saw them rather than on anything in the model.
    static func encode(_ task: TaskItem, sortKey: String, into record: CKRecord) {
        typealias K = CloudSchema.Strip
        stamp(record)
        let secret = record.encryptedValues
        secret[K.title] = task.title
        secret[K.notes] = task.notes
        secret[K.tags] = task.tags
        secret[K.waitingOn] = task.waitingOnName
        secret[K.contacts] = json(task.contacts)
        secret[K.links] = json(task.links)
        secret[K.log] = json(task.actionLog)

        record[K.notesRTL] = flag(task.notesRtl)
        record[K.priority] = task.priorityRaw
        record[K.dueAt] = task.dueAt
        record[K.sortKey] = sortKey
        record[K.done] = flag(task.isDone)
        record[K.archived] = flag(task.isArchived)
        record[K.progress] = Int64(task.progress)
        record[K.completedAt] = task.completedAt
        record[K.blockedBy] = task.blockedByID?.uuidString
        record[K.waitingSince] = task.waitingOnSince
        record[K.followUpDays] = task.waitingOnFollowUpDays.map(Int64.init)
        record[K.sketchID] = task.linkedSketchID
        record[K.remindBefore] = task.reminderMinutesBefore.map(Int64.init)
        record[K.repeatDays] = task.repeatIntervalDays.map(Int64.init)
        record[K.createdAt] = task.createdAt
    }

    /// Attachments are their own records, and the sort key belongs to the sync layer's ordering,
    /// so neither is touched here.
    static func decode(_ record: CKRecord, into task: TaskItem) {
        typealias K = CloudSchema.Strip
        let secret = record.encryptedValues
        if let v = secret[K.title] as? String { task.title = v }
        if let v = secret[K.notes] as? String { task.notes = v }
        if let v = secret[K.tags] as? [String] { task.tags = v }
        if let v = secret[K.waitingOn] as? String { task.waitingOnName = v }
        if let v: [TaskContact] = value(secret[K.contacts]) { task.contacts = v }
        if let v: [TaskLink] = value(secret[K.links]) { task.links = v }
        if let v: [TaskActionLogEntry] = value(secret[K.log]) { task.actionLog = v }

        if let v = record[K.notesRTL] as? Int64 { task.notesRtl = v != 0 }
        if let v = record[K.priority] as? String, Priority(rawValue: v) != nil { task.priorityRaw = v }
        task.dueAt = record[K.dueAt] as? Date
        if let v = record[K.done] as? Int64 { task.isDone = v != 0 }
        if let v = record[K.archived] as? Int64 { task.isArchived = v != 0 }
        if let v = record[K.progress] as? Int64 { task.progress = Int(min(max(v, 0), 100)) }
        task.completedAt = record[K.completedAt] as? Date
        task.blockedByID = (record[K.blockedBy] as? String).flatMap(UUID.init(uuidString:))
        task.waitingOnSince = record[K.waitingSince] as? Date
        task.waitingOnFollowUpDays = (record[K.followUpDays] as? Int64).map(Int.init)
        task.linkedSketchID = record[K.sketchID] as? String
        task.reminderMinutesBefore = (record[K.remindBefore] as? Int64).map(Int.init)
        task.repeatIntervalDays = (record[K.repeatDays] as? Int64).map(Int.init)
        if let v = record[K.createdAt] as? Date { task.createdAt = v }
    }

    // MARK: - Attachment

    static func encode(_ attachment: TaskAttachment, stripID: UUID, file: URL?, into record: CKRecord) {
        typealias K = CloudSchema.Attachment
        stamp(record)
        record.encryptedValues[K.name] = attachment.name
        record[K.strip] = CKRecord.Reference(recordID: CloudSchema.recordID(stripID.uuidString), action: .deleteSelf)
        record[K.kind] = attachment.kind.rawValue
        record[K.addedAt] = attachment.addedAt
        if let file { record[K.file] = CKAsset(fileURL: file) }
    }

    struct DecodedAttachment {
        var attachment: TaskAttachment
        var stripID: UUID
        /// Where CloudKit put the downloaded file; the caller copies it into the store.
        var file: URL?
    }

    static func decodeAttachment(_ record: CKRecord) -> DecodedAttachment? {
        typealias K = CloudSchema.Attachment
        guard let id = UUID(uuidString: record.recordID.recordName),
              let strip = (record[K.strip] as? CKRecord.Reference).flatMap({ UUID(uuidString: $0.recordID.recordName) })
        else { return nil }
        var attachment = TaskAttachment()
        attachment.id = id
        attachment.kind = (record[K.kind] as? String).flatMap(AttachmentKind.init(rawValue:)) ?? .document
        attachment.name = record.encryptedValues[K.name] as? String ?? ""
        attachment.addedAt = record[K.addedAt] as? Date ?? .now
        return DecodedAttachment(attachment: attachment, stripID: strip, file: (record[K.file] as? CKAsset)?.fileURL)
    }

    // MARK: - Reminder

    static func encode(_ reminder: Reminder, into record: CKRecord) {
        typealias K = CloudSchema.Reminder
        stamp(record)
        let secret = record.encryptedValues
        secret[K.text] = reminder.text
        secret[K.details] = reminder.details
        secret[K.tag] = reminder.tag
        secret[K.tagEmoji] = reminder.tagEmoji

        record[K.triggerAt] = reminder.triggerAt
        record[K.leadMinutes] = reminder.leadMinutesBefore.map(Int64.init)
        record[K.repeatAmount] = reminder.repeatAmount.map(Int64.init)
        record[K.repeatUnit] = reminder.repeatUnitRaw
        record[K.done] = flag(reminder.isDone)
        record[K.createdAt] = reminder.createdAt
    }

    static func decode(_ record: CKRecord, into reminder: Reminder) {
        typealias K = CloudSchema.Reminder
        let secret = record.encryptedValues
        if let v = secret[K.text] as? String { reminder.text = v }
        if let v = secret[K.details] as? String { reminder.details = v }
        if let v = secret[K.tag] as? String { reminder.tag = v }
        if let v = secret[K.tagEmoji] as? String { reminder.tagEmoji = v }

        if let v = record[K.triggerAt] as? Date { reminder.triggerAt = v }
        reminder.leadMinutesBefore = (record[K.leadMinutes] as? Int64).map(Int.init)
        reminder.repeatAmount = (record[K.repeatAmount] as? Int64).map(Int.init)
        reminder.repeatUnitRaw = (record[K.repeatUnit] as? String).flatMap { ReminderRepeatUnit(rawValue: $0)?.rawValue }
        if let v = record[K.done] as? Int64 { reminder.isDone = v != 0 }
        if let v = record[K.createdAt] as? Date { reminder.createdAt = v }
    }

    // MARK: - Note

    static func encode(_ note: Note, into record: CKRecord) {
        stamp(record)
        record.encryptedValues[CloudSchema.Note.text] = note.text
        record[CloudSchema.Note.createdAt] = note.createdAt
    }

    static func decode(_ record: CKRecord, into note: Note) {
        if let v = record.encryptedValues[CloudSchema.Note.text] as? String { note.text = v }
        if let v = record[CloudSchema.Note.createdAt] as? Date { note.createdAt = v }
    }

    // MARK: - Storage file

    static func encode(_ item: StorageItem, file: URL?, into record: CKRecord) {
        typealias K = CloudSchema.StorageFile
        stamp(record)
        let secret = record.encryptedValues
        secret[K.name] = item.name
        secret[K.tag] = item.tag
        secret[K.tagEmoji] = item.tagEmoji

        record[K.type] = item.typeRaw
        record[K.mimeType] = item.mimeType
        record[K.size] = Int64(item.sizeBytes)
        record[K.createdAt] = item.createdAt
        if let file { record[K.file] = CKAsset(fileURL: file) }
    }

    /// Returns where CloudKit put the downloaded file, for the caller to copy into the store.
    @discardableResult
    static func decode(_ record: CKRecord, into item: StorageItem) -> URL? {
        typealias K = CloudSchema.StorageFile
        let secret = record.encryptedValues
        if let v = secret[K.name] as? String { item.name = v }
        if let v = secret[K.tag] as? String { item.tag = v }
        if let v = secret[K.tagEmoji] as? String { item.tagEmoji = v }

        if let v = record[K.type] as? String, StorageItemType(rawValue: v) != nil { item.typeRaw = v }
        if let v = record[K.mimeType] as? String { item.mimeType = v }
        if let v = record[K.size] as? Int64 { item.sizeBytes = Int(v) }
        if let v = record[K.createdAt] as? Date { item.createdAt = v }
        return (record[K.file] as? CKAsset)?.fileURL
    }

    // MARK: - Credential (its password is in iCloud Keychain, never here)

    static func encode(_ credential: Credential, into record: CKRecord) {
        typealias K = CloudSchema.Credential
        stamp(record)
        let secret = record.encryptedValues
        secret[K.title] = credential.title
        secret[K.username] = credential.username
        secret[K.url] = credential.url
        secret[K.notes] = credential.notes
        record[K.createdAt] = credential.createdAt
    }

    static func decode(_ record: CKRecord, into credential: Credential) {
        typealias K = CloudSchema.Credential
        let secret = record.encryptedValues
        if let v = secret[K.title] as? String { credential.title = v }
        if let v = secret[K.username] as? String { credential.username = v }
        if let v = secret[K.url] as? String { credential.url = v }
        if let v = secret[K.notes] as? String { credential.notes = v }
        if let v = record[K.createdAt] as? Date { credential.createdAt = v }
    }

    // MARK: - Sketch

    static func encode(_ sketch: SketchNote, into record: CKRecord) {
        stamp(record)
        record.encryptedValues[CloudSchema.Sketch.name] = sketch.name
        record[CloudSchema.Sketch.createdAt] = sketch.createdAt
    }

    static func encodePage(sketch: String, number: Int, image: URL?, into record: CKRecord) {
        typealias K = CloudSchema.SketchPage
        stamp(record)
        record[K.sketch] = CKRecord.Reference(recordID: CloudSchema.recordID(sketch), action: .deleteSelf)
        record[K.number] = Int64(number)
        if let image { record[K.image] = CKAsset(fileURL: image) }
    }

    // MARK: - Helpers

    private static func stamp(_ record: CKRecord) {
        // Never lowered: a record a newer version wrote keeps saying so after this one edits it.
        let current = record[CloudSchema.schemaVersionKey] as? Int64 ?? 0
        record[CloudSchema.schemaVersionKey] = max(current, CloudSchema.version)
    }

    private static func flag(_ value: Bool) -> Int64 { value ? 1 : 0 }

    /// Sorted keys: the same value must always give the same bytes, or an untouched strip would
    /// look changed on every pass and bounce between devices forever.
    private static func json<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }

    private static func value<T: Decodable>(_ raw: Any?) -> T? {
        guard let data = raw as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

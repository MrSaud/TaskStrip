import CloudKit

/// The CloudKit schema's names, and only its names — see docs/CloudKitSchema.md for the why.
///
/// Every string here is permanent once the schema is deployed to Production: a record type or a
/// field can be added there, never renamed or removed. So these are deliberately not derived from
/// Swift property names, which are free to change.
enum CloudSchema {
    /// Stamped on every record. Bumped when a field is added; never reused.
    static let version: Int64 = 1

    static let containerID = "iCloud.com.saud.taskstrip"
    /// The real board's zone, "Board". The sync test board has its own zone, so test data can
    /// never land among real strips — they share the Development environment.
    static let zoneName = AppLaunch.isSyncTesting ? "BoardTest" : "Board"
    static let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

    static func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    enum RecordType {
        static let strip = "Strip"
        static let attachment = "Attachment"
        static let reminder = "Reminder"
        static let note = "Note"
        static let storageFile = "StorageFile"
        static let credential = "Credential"
        static let sketch = "Sketch"
        static let sketchPage = "SketchPage"

        static let all = [strip, attachment, reminder, note, storageFile, credential, sketch, sketchPage]
    }

    /// On every record type.
    static let schemaVersionKey = "schemaVersion"

    enum Strip {
        static let title = "title", notes = "notes", tags = "tags", contacts = "contacts"
        static let links = "links", log = "log", waitingOn = "waitingOn"
        /// The steps a strip breaks into (schema v1.2), in the person's own words, so encrypted
        /// with the rest of what they wrote.
        static let checklist = "checklist"
        static let encrypted: Set = [title, notes, tags, contacts, links, log, waitingOn, checklist]

        static let notesRTL = "notesRTL", priority = "priority", dueAt = "dueAt", sortKey = "sortKey"
        static let done = "done", archived = "archived", progress = "progress"
        static let completedAt = "completedAt", blockedBy = "blockedBy", waitingSince = "waitingSince"
        static let followUpDays = "followUpDays", sketchID = "sketchID", remindBefore = "remindBefore"
        static let repeatDays = "repeatDays", createdAt = "createdAt"
        /// When the strip comes back onto the board (schema v1.2).
        static let deferUntil = "deferUntil"
        /// The stretches of time spent on it (schema v1.3). Times, not words, so not encrypted.
        static let sessions = "sessions"
        /// The calendar event blocked out for it (schema v1.3).
        static let calendarEvent = "calendarEvent"
    }

    enum Attachment {
        static let name = "name"
        static let encrypted: Set = [name]

        static let strip = "strip", kind = "kind", addedAt = "addedAt", file = "file"
    }

    enum Reminder {
        static let text = "text", details = "details", tag = "tag", tagEmoji = "tagEmoji"
        static let encrypted: Set = [text, details, tag, tagEmoji]

        static let triggerAt = "triggerAt", leadMinutes = "leadMinutes", repeatAmount = "repeatAmount"
        static let repeatUnit = "repeatUnit", done = "done", createdAt = "createdAt"
    }

    enum Note {
        static let text = "text"
        static let encrypted: Set = [text]

        static let createdAt = "createdAt"
    }

    enum StorageFile {
        static let name = "name", tag = "tag", tagEmoji = "tagEmoji"
        static let encrypted: Set = [name, tag, tagEmoji]

        static let type = "type", mimeType = "mimeType", size = "size", createdAt = "createdAt", file = "file"
    }

    enum Credential {
        static let title = "title", username = "username", url = "url", notes = "notes"
        static let encrypted: Set = [title, username, url, notes]

        static let createdAt = "createdAt"
    }

    enum Sketch {
        static let name = "name"
        static let encrypted: Set = [name]

        static let createdAt = "createdAt"
        /// Which paper it's drawn on (schema v1.1, added). An older device that doesn't know the
        /// field leaves it alone and shows the note on plain paper.
        static let paper = "paper"
    }

    enum SketchPage {
        static let sketch = "sketch", number = "number", image = "image"

        /// `<folder>/page<n>`: one record per page, named so it can be found from the sketch.
        static func recordName(sketch: String, number: Int) -> String { "\(sketch)/page\(number)" }
    }
}

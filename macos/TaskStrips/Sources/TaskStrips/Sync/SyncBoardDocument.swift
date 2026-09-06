import Foundation

/// One strip, as it travels. Mirrors SyncTaskRecord in SyncBoardDocument.kt field for field.
///
/// Attachments travel as content hashes; the bytes are a separate errand, so a record stays small
/// and a photo is uploaded once however many strips point at it.
struct SyncTaskRecord: Equatable, Identifiable {
    var id: String
    var updatedAt: Int64 = 0
    var isDeleted = false
    var title = ""
    var notes = ""
    var notesRtl = false
    var priority = "NORMAL"
    var dueAt: Int64?
    var orderIndex = 0
    var isDone = false
    var isArchived = false
    var progress = 0
    var completedAt: Int64?
    /// The blocker's shared id, not its local key — a local key means nothing on the other device,
    /// which is the whole reason this document exists.
    var blockedBySyncID: String?
    var waitingOnName = ""
    var waitingOnSince: Int64?
    var waitingOnFollowUpDays: Int?
    var reminderMinutesBefore: Int?
    var repeatIntervalDays: Int?
    var tags: [String] = []
    var links: [SyncLink] = []
    var actionLog: [SyncLogEntry] = []
    var contacts: [SyncContact] = []
    var attachments: [SyncAttachment] = []
    var createdAt: Int64 = 0
}

struct SyncReminderRecord: Equatable, Identifiable {
    var id: String
    var updatedAt: Int64 = 0
    var isDeleted = false
    var text = ""
    var details = ""
    var triggerAt: Int64 = 0
    var leadMinutesBefore: Int?
    var repeatAmount: Int?
    var repeatUnit: String?
    var tag = ""
    var tagEmoji = ""
    var isDone = false
    var createdAt: Int64 = 0
}

struct SyncLink: Equatable { var url = ""; var label = "" }
struct SyncLogEntry: Equatable { var text = ""; var timestamp: Int64 = 0 }
struct SyncContact: Equatable { var name = ""; var email = ""; var phone = "" }

/// A file a strip carries, named by what's in it.
///
/// `hash` is the SHA-256 of the bytes, which makes the name a fact about the content rather than a
/// choice either device made. Two devices that add the same photo produce the same name and upload
/// it once; a file that changes produces a different name, so a binary never has to be merged and
/// "which copy wins" never comes up.
struct SyncAttachment: Equatable { var hash = ""; var name = ""; var kind = "" }

/// The board both apps read and write: one JSON file beside sync_notes.json in the folder they
/// already share.
///
/// A contract with SyncBoardDocument.kt — the two devices merge the same document independently
/// and have to reach the same answer without talking to each other. Deliberately the same design
/// as SyncNoteDocument, which has been carrying this for a while.
enum SyncBoardDocument {
    static let fileName = "sync_board.json"
    static let mimeType = "application/json"
    static let version = 1

    // MARK: - Reading and writing

    static func data(tasks: [SyncTaskRecord], reminders: [SyncReminderRecord]) throws -> Data {
        let root: [String: Any] = [
            "version": version,
            "tasks": sorted(tasks).map(json(for:)),
            "reminders": sorted(reminders).map(json(for:)),
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// Anything unreadable is nothing rather than an error. A corrupt or half-written document
    /// must not be able to empty this machine — the merge treats "no remote" as "nothing to add".
    static func tasks(from data: Data) -> [SyncTaskRecord] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = root["tasks"] as? [[String: Any]] else { return [] }
        return array.compactMap { object in
            guard let id = object["id"] as? String, !id.isEmpty else { return nil }
            return SyncTaskRecord(
                id: id,
                updatedAt: int64(object["updatedAt"]) ?? 0,
                isDeleted: object["deleted"] as? Bool ?? false,
                title: object["title"] as? String ?? "",
                notes: object["notes"] as? String ?? "",
                notesRtl: object["notesRtl"] as? Bool ?? false,
                priority: (object["priority"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "NORMAL",
                dueAt: int64(object["dueAt"]),
                orderIndex: int(object["orderIndex"]) ?? 0,
                isDone: object["done"] as? Bool ?? false,
                isArchived: object["archived"] as? Bool ?? false,
                progress: int(object["progress"]) ?? 0,
                completedAt: int64(object["completedAt"]),
                blockedBySyncID: string(object["blockedBy"]),
                waitingOnName: object["waitingOnName"] as? String ?? "",
                waitingOnSince: int64(object["waitingOnSince"]),
                waitingOnFollowUpDays: int(object["waitingOnFollowUpDays"]),
                reminderMinutesBefore: int(object["reminderMinutesBefore"]),
                repeatIntervalDays: int(object["repeatIntervalDays"]),
                tags: (object["tags"] as? [String] ?? []).filter { !$0.isEmpty },
                links: (object["links"] as? [[String: Any]] ?? []).map {
                    SyncLink(url: $0["url"] as? String ?? "", label: $0["label"] as? String ?? "")
                },
                actionLog: (object["actionLog"] as? [[String: Any]] ?? []).map {
                    SyncLogEntry(text: $0["text"] as? String ?? "", timestamp: int64($0["timestamp"]) ?? 0)
                },
                contacts: (object["contacts"] as? [[String: Any]] ?? []).map {
                    SyncContact(
                        name: $0["name"] as? String ?? "",
                        email: $0["email"] as? String ?? "",
                        phone: $0["phone"] as? String ?? ""
                    )
                },
                attachments: (object["attachments"] as? [[String: Any]] ?? []).map {
                    SyncAttachment(
                        hash: $0["hash"] as? String ?? "",
                        name: $0["name"] as? String ?? "",
                        kind: $0["kind"] as? String ?? ""
                    )
                },
                createdAt: int64(object["createdAt"]) ?? 0
            )
        }
    }

    static func reminders(from data: Data) -> [SyncReminderRecord] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = root["reminders"] as? [[String: Any]] else { return [] }
        return array.compactMap { object in
            guard let id = object["id"] as? String, !id.isEmpty else { return nil }
            return SyncReminderRecord(
                id: id,
                updatedAt: int64(object["updatedAt"]) ?? 0,
                isDeleted: object["deleted"] as? Bool ?? false,
                text: object["text"] as? String ?? "",
                details: object["details"] as? String ?? "",
                triggerAt: int64(object["triggerAt"]) ?? 0,
                leadMinutesBefore: int(object["leadMinutesBefore"]),
                repeatAmount: int(object["repeatAmount"]),
                repeatUnit: string(object["repeatUnit"]),
                tag: object["tag"] as? String ?? "",
                tagEmoji: object["tagEmoji"] as? String ?? "",
                isDone: object["done"] as? Bool ?? false,
                createdAt: int64(object["createdAt"]) ?? 0
            )
        }
    }

    // MARK: - Merging

    static func merge(local: [SyncTaskRecord], remote: [SyncTaskRecord]) -> [SyncTaskRecord] {
        var byID: [String: SyncTaskRecord] = [:]
        for record in local + remote {
            byID[record.id] = byID[record.id].map { winner($0, record) } ?? record
        }
        return sorted(Array(byID.values))
    }

    static func merge(local: [SyncReminderRecord], remote: [SyncReminderRecord]) -> [SyncReminderRecord] {
        var byID: [String: SyncReminderRecord] = [:]
        for record in local + remote {
            byID[record.id] = byID[record.id].map { winner($0, record) } ?? record
        }
        return sorted(Array(byID.values))
    }

    /// Newer wins. Then a delete wins over a live row, because a delete is a decision and a stale
    /// edit is not. Then the greater title, then the greater notes, purely so two devices holding
    /// genuinely different rows stamped at the same millisecond still pick the *same* side.
    static func winner(_ a: SyncTaskRecord, _ b: SyncTaskRecord) -> SyncTaskRecord {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt ? a : b }
        if a.isDeleted != b.isDeleted { return a.isDeleted ? a : b }
        if a.title != b.title { return isGreater(a.title, b.title) ? a : b }
        if a.notes != b.notes { return isGreater(a.notes, b.notes) ? a : b }
        return a
    }

    static func winner(_ a: SyncReminderRecord, _ b: SyncReminderRecord) -> SyncReminderRecord {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt ? a : b }
        if a.isDeleted != b.isDeleted { return a.isDeleted ? a : b }
        if a.text != b.text { return isGreater(a.text, b.text) ? a : b }
        if a.details != b.details { return isGreater(a.details, b.details) ? a : b }
        return a
    }

    /// Compares UTF-8 bytes, not strings — the same rule and the same reason as
    /// SyncNoteDocument.isGreater.
    static func isGreater(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8)
        let y = Array(b.utf8)
        for index in 0..<min(x.count, y.count) where x[index] != y[index] {
            return x[index] > y[index]
        }
        return x.count > y.count
    }

    /// Ordered by id alone, so the file's bytes don't churn between syncs that changed nothing.
    static func sorted(_ tasks: [SyncTaskRecord]) -> [SyncTaskRecord] { tasks.sorted { $0.id < $1.id } }
    static func sorted(_ reminders: [SyncReminderRecord]) -> [SyncReminderRecord] {
        reminders.sorted { $0.id < $1.id }
    }

    /// What a person should see: tombstones are bookkeeping, not rows.
    static func visible(_ tasks: [SyncTaskRecord]) -> [SyncTaskRecord] { tasks.filter { !$0.isDeleted } }
    static func visible(_ reminders: [SyncReminderRecord]) -> [SyncReminderRecord] {
        reminders.filter { !$0.isDeleted }
    }

    /// Every file the board still points at. What isn't in here is an orphan and can go.
    static func referencedHashes(_ tasks: [SyncTaskRecord]) -> Set<String> {
        Set(tasks.filter { !$0.isDeleted }.flatMap(\.attachments).map(\.hash).filter { !$0.isEmpty })
    }

    // MARK: - JSON plumbing

    private static func json(for task: SyncTaskRecord) -> [String: Any] {
        [
            "id": task.id,
            "updatedAt": task.updatedAt,
            "deleted": task.isDeleted,
            "title": task.title,
            "notes": task.notes,
            "notesRtl": task.notesRtl,
            "priority": task.priority,
            "dueAt": task.dueAt as Any? ?? NSNull(),
            "orderIndex": task.orderIndex,
            "done": task.isDone,
            "archived": task.isArchived,
            "progress": task.progress,
            "completedAt": task.completedAt as Any? ?? NSNull(),
            "blockedBy": task.blockedBySyncID as Any? ?? NSNull(),
            "waitingOnName": task.waitingOnName,
            "waitingOnSince": task.waitingOnSince as Any? ?? NSNull(),
            "waitingOnFollowUpDays": task.waitingOnFollowUpDays as Any? ?? NSNull(),
            "reminderMinutesBefore": task.reminderMinutesBefore as Any? ?? NSNull(),
            "repeatIntervalDays": task.repeatIntervalDays as Any? ?? NSNull(),
            "tags": task.tags,
            "links": task.links.map { ["url": $0.url, "label": $0.label] },
            "actionLog": task.actionLog.map { ["text": $0.text, "timestamp": $0.timestamp] },
            "contacts": task.contacts.map { ["name": $0.name, "email": $0.email, "phone": $0.phone] },
            "attachments": task.attachments.map { ["hash": $0.hash, "name": $0.name, "kind": $0.kind] },
            "createdAt": task.createdAt,
        ]
    }

    private static func json(for reminder: SyncReminderRecord) -> [String: Any] {
        [
            "id": reminder.id,
            "updatedAt": reminder.updatedAt,
            "deleted": reminder.isDeleted,
            "text": reminder.text,
            "details": reminder.details,
            "triggerAt": reminder.triggerAt,
            "leadMinutesBefore": reminder.leadMinutesBefore as Any? ?? NSNull(),
            "repeatAmount": reminder.repeatAmount as Any? ?? NSNull(),
            "repeatUnit": reminder.repeatUnit as Any? ?? NSNull(),
            "tag": reminder.tag,
            "tagEmoji": reminder.tagEmoji,
            "done": reminder.isDone,
            "createdAt": reminder.createdAt,
        ]
    }

    // A JSON null must read back as nothing, not as zero — the writer meant "no due date", and a
    // default would quietly invent one.
    private static func int64(_ value: Any?) -> Int64? { (value as? NSNumber)?.int64Value }
    private static func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}

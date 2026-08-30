import Foundation
import SwiftData

enum BackupImportError: LocalizedError {
    case notJSON
    case noTasksSection

    var errorDescription: String? {
        switch self {
        case .notJSON:
            return "This backup's backup.json isn't valid JSON."
        case .noTasksSection:
            return "This backup has no \"tasks\" section — it may be from a different app."
        }
    }
}

/// One strip as it appears in the backup, before it becomes a `TaskItem`.
///
/// `blockedByIndex` is a *position within the backup's own tasks array*, not an id — Android
/// stores it that way because restored rows get fresh auto-generated ids (see the comment in
/// `BackupHelper.createBackupZip`). It's remapped to a real `TaskItem.id` in `apply`.
struct ImportedTask {
    var title: String = ""
    var notes: String = ""
    var notesRtl: Bool = false
    var priority: Priority = .normal
    var dueAt: Date?
    var orderIndex: Int = 0
    var isDone: Bool = false
    var isArchived: Bool = false
    var progress: Int = 0
    var completedAt: Date?
    var waitingOnName: String = ""
    var waitingOnSince: Date?
    var waitingOnFollowUpDays: Int?
    var reminderMinutesBefore: Int?
    var repeatIntervalDays: Int?
    var tags: [String] = []
    var contacts: [TaskContact] = []
    var links: [TaskLink] = []
    var actionLog: [TaskActionLogEntry] = []
    var createdAt: Date = .now
    var blockedByIndex: Int?
    /// The files this strip claims, as paths relative to the media root — which is also where
    /// they sit inside the archive, behind a "media/" prefix.
    var attachments: [ImportedAttachment] = []
    var hasReminder: Bool = false

    var attachmentCount: Int { attachments.count }
}

/// A file a backup says belongs to a strip. Whether its bytes are actually in the archive is a
/// separate question, answered by `restoreMedia`.
struct ImportedAttachment: Hashable {
    var kind: AttachmentKind
    var path: String
}

/// One quick note out of the backup. As small as NoteEntity itself — the whole point of the
/// scratchpad is that a note carries nothing but its text and when it was written.
struct ImportedNote {
    var text: String = ""
    var createdAt: Date = .now
}

/// One library row out of the backup. Same fields as StorageItemEntity, since the Mac keeps the
/// library in the same shape.
struct ImportedStorageItem {
    var name: String = ""
    var path: String = ""
    var type: StorageItemType = .document
    var mimeType: String = ""
    var sizeBytes: Int = 0
    var tag: String = ""
    var tagEmoji: String = ""
    var createdAt: Date = .now
}

/// What a backup holds, including the parts this app can't take yet, so the user is told rather
/// than left to notice the gap themselves.
struct BackupImportSummary: Identifiable {
    let id = UUID()
    /// The archive this was parsed from, kept so the media can be fetched when the user actually
    /// commits — parsing shouldn't be writing files to disk.
    var sourceURL: URL?
    var version: Int = 0
    var tasks: [ImportedTask] = []
    var notes: [ImportedNote] = []
    var storageItems: [ImportedStorageItem] = []
    var attachmentCount: Int = 0
    var reminderOnTaskCount: Int = 0
    /// Whole top-level sections of the backup with no Mac equivalent, e.g. "notes": 12.
    var skippedSections: [(name: String, count: Int)] = []

    /// Every file path the strips reference.
    var referencedAttachmentPaths: Set<String> {
        Set(tasks.flatMap { $0.attachments.map(\.path) })
    }

    /// Everything worth pulling out of the archive: a strip's attachments plus the library's own
    /// files, which belong to no strip and would otherwise be left behind.
    var referencedMediaPaths: Set<String> {
        referencedAttachmentPaths.union(storageItems.map(\.path))
    }
}

enum ImportMode {
    case add
    case replace
}

enum BackupImport {
    /// Section name in backup.json -> what to call it in the UI. Everything here is a feature the
    /// Android app has and the Mac port doesn't, so it's reported and dropped.
    private static let skippableSections: [(key: String, label: String)] = [
        ("reminders", "standalone reminders"),
        ("credentials", "credentials"),
    ]

    /// `timeZone` is only used for due dates — see `dueDate(fromAndroidWallClock:in:)` — and is a
    /// parameter so tests can pin it rather than depending on the machine's.
    static func parse(manifest data: Data, timeZone: TimeZone = .current) throws -> BackupImportSummary {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackupImportError.notJSON
        }
        guard let rawTasks = root["tasks"] as? [Any] else {
            throw BackupImportError.noTasksSection
        }

        var summary = BackupImportSummary()
        summary.version = intValue(root, "version") ?? 0
        summary.tasks = rawTasks.compactMap { $0 as? [String: Any] }
            .map { task(from: $0, timeZone: timeZone) }
        summary.notes = (root["notes"] as? [Any] ?? [])
            .compactMap { $0 as? [String: Any] }
            .map { ImportedNote(text: stringValue($0, "text"), createdAt: dateValue($0, "createdAt") ?? .now) }
        summary.storageItems = (root["storageItems"] as? [Any] ?? [])
            .compactMap { $0 as? [String: Any] }
            .map { storageItem(from: $0) }
            // A library row with no file behind it points at nothing and can't be opened,
            // tagged, or copied onto a strip.
            .filter { !$0.path.isEmpty }
        summary.attachmentCount = summary.tasks.reduce(0) { $0 + $1.attachmentCount }
        summary.reminderOnTaskCount = summary.tasks.filter(\.hasReminder).count
        summary.skippedSections = skippableSections.compactMap { section -> (name: String, count: Int)? in
            guard let items = root[section.key] as? [Any], !items.isEmpty else { return nil }
            return (name: section.label, count: items.count)
        }
        return summary
    }

    private static func task(from object: [String: Any], timeZone: TimeZone) -> ImportedTask {
        var task = ImportedTask()
        task.title = stringValue(object, "title")
        task.notes = stringValue(object, "notes")
        task.notesRtl = boolValue(object, "notesRtl")
        task.priority = Priority(rawValue: stringValue(object, "priority")) ?? .normal
        // The one field that isn't a real instant. Everything else here — createdAt,
        // completedAt, waitingOnSince, the action log — is a genuine System.currentTimeMillis()
        // and converts straight across.
        task.dueAt = numberValue(object, "dueAt").map {
            dueDate(fromAndroidWallClock: $0, in: timeZone)
        }
        task.orderIndex = intValue(object, "orderIndex") ?? 0
        task.isDone = boolValue(object, "isDone")
        task.isArchived = boolValue(object, "isArchived")
        task.progress = min(max(intValue(object, "progress") ?? 0, 0), 100)
        task.completedAt = dateValue(object, "completedAt")
        task.waitingOnName = stringValue(object, "waitingOnName")
        task.waitingOnSince = dateValue(object, "waitingOnSince")
        task.waitingOnFollowUpDays = intValue(object, "waitingOnFollowUpDays")
        task.tags = (object["tags"] as? [Any])?.compactMap { $0 as? String } ?? []
        task.createdAt = dateValue(object, "createdAt") ?? .now
        task.blockedByIndex = intValue(object, "blockedByIndex")

        task.contacts = (object["contacts"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map {
            TaskContact(
                name: stringValue($0, "name"),
                email: stringValue($0, "email"),
                phone: stringValue($0, "phone")
            )
        }
        task.links = (object["links"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map {
            TaskLink(url: stringValue($0, "url"), label: stringValue($0, "label"))
        }
        task.actionLog = (object["actionLog"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map {
            TaskActionLogEntry(
                text: stringValue($0, "text"),
                timestamp: dateValue($0, "timestamp") ?? .now
            )
        }

        task.attachments = AttachmentKind.allCases.flatMap { kind in
            (object[kind.backupKey] as? [Any] ?? [])
                .compactMap { $0 as? String }
                .filter { !$0.isEmpty }
                .map { ImportedAttachment(kind: kind, path: $0) }
        }
        task.reminderMinutesBefore = intValue(object, "reminderMinutesBefore")
        task.repeatIntervalDays = intValue(object, "repeatIntervalDays")
        task.hasReminder = task.reminderMinutesBefore != nil

        return task
    }

    private static func storageItem(from object: [String: Any]) -> ImportedStorageItem {
        var item = ImportedStorageItem()
        item.path = stringValue(object, "path")
        item.name = stringValue(object, "name")
        if item.name.isEmpty { item.name = (item.path as NSString).lastPathComponent }
        item.mimeType = stringValue(object, "mimeType")
        // The stored category wins; the MIME type and then the extension only stand in for a row
        // that predates it or came from somewhere else.
        item.type = StorageItemType(rawValue: stringValue(object, "type"))
            ?? StorageItemType.inferred(mimeType: item.mimeType, name: item.name)
        item.sizeBytes = max(intValue(object, "sizeBytes") ?? 0, 0)
        item.tag = stringValue(object, "tag")
        item.tagEmoji = stringValue(object, "tagEmoji")
        item.createdAt = dateValue(object, "createdAt") ?? .now
        return item
    }

    /// Inserts the backup's library rows, returning how many landed.
    ///
    /// Whether the bytes are actually there is `restoreMedia`'s business — a row whose file the
    /// archive didn't carry still comes across, the same way a strip keeps an attachment it can
    /// no longer open.
    @discardableResult
    static func apply(
        storageItems: [ImportedStorageItem],
        mode: ImportMode,
        existing: [StorageItem],
        context: ModelContext
    ) -> Int {
        if mode == .replace {
            for item in existing { context.delete(item) }
        }
        for imported in storageItems {
            context.insert(
                StorageItem(
                    name: imported.name,
                    path: imported.path,
                    type: imported.type,
                    mimeType: imported.mimeType,
                    sizeBytes: imported.sizeBytes,
                    tag: imported.tag,
                    tagEmoji: imported.tagEmoji,
                    createdAt: imported.createdAt
                )
            )
        }
        return storageItems.count
    }

    /// Pulls the files the strips reference out of the archive and into the attachment store.
    ///
    /// Only the referenced ones: `paths` is whatever the caller means to keep — a strip's
    /// attachments and the library's files — and an Android backup also carries sketches, which
    /// have nowhere to go yet, so copying those would just grow the folder.
    /// Returns the paths actually written — a backup can name a file whose bytes never made it
    /// into the zip, and the caller needs to know which.
    @discardableResult
    static func restoreMedia(
        fromArchiveAt url: URL,
        paths: Set<String>,
        into store: AttachmentStore
    ) throws -> Set<String> {
        guard !paths.isEmpty, url.pathExtension.lowercased() != "json" else { return [] }

        let archive = try Data(contentsOf: url, options: .mappedIfSafe)
        var restored: Set<String> = []
        for entry in try BackupArchive.entries(inArchive: archive) where !entry.isDirectory {
            guard entry.name.hasPrefix(BackupArchive.mediaPrefix) else { continue }
            let path = String(entry.name.dropFirst(BackupArchive.mediaPrefix.count))
            guard paths.contains(path) else { continue }
            try store.write(try BackupArchive.data(for: entry, inArchive: archive), toRelativePath: path)
            restored.insert(path)
        }
        return restored
    }

    /// Inserts `tasks` into `context`, returning how many strips landed on the board.
    ///
    /// In `.add` mode imported strips are appended below whatever is already there; in `.replace`
    /// mode every existing strip is deleted first, matching Android's own restore.
    @discardableResult
    static func apply(
        _ tasks: [ImportedTask],
        mode: ImportMode,
        existing: [TaskItem],
        context: ModelContext
    ) -> Int {
        if mode == .replace {
            for task in existing { context.delete(task) }
        }
        let baseOrder = mode == .replace ? 0 : ((existing.map(\.orderIndex).max() ?? -1) + 1)

        // The backup's array order is insertion order, not board order — but blockedByIndex points
        // into that array, so the array order has to stay the identity mapping. Board position is
        // derived separately from each strip's own orderIndex, ties broken by array position.
        var rankOfTask = [Int](repeating: 0, count: tasks.count)
        let byBoardOrder = tasks.indices.sorted { lhs, rhs in
            tasks[lhs].orderIndex == tasks[rhs].orderIndex
                ? lhs < rhs
                : tasks[lhs].orderIndex < tasks[rhs].orderIndex
        }
        for (rank, index) in byBoardOrder.enumerated() { rankOfTask[index] = rank }

        var created: [TaskItem] = []
        created.reserveCapacity(tasks.count)
        for (index, imported) in tasks.enumerated() {
            let item = TaskItem(
                title: imported.title,
                orderIndex: baseOrder + rankOfTask[index],
                priority: imported.priority,
                createdAt: imported.createdAt
            )
            item.notes = imported.notes
            item.notesRtl = imported.notesRtl
            item.dueAt = imported.dueAt
            item.isDone = imported.isDone
            item.isArchived = imported.isArchived
            item.progress = imported.progress
            item.completedAt = imported.completedAt
            item.waitingOnName = imported.waitingOnName
            item.waitingOnSince = imported.waitingOnSince
            item.waitingOnFollowUpDays = imported.waitingOnFollowUpDays
            item.tags = imported.tags
            item.contacts = imported.contacts
            item.links = imported.links
            item.actionLog = imported.actionLog
            item.attachments = attachments(for: imported)
            item.reminderMinutesBefore = imported.reminderMinutesBefore
            item.repeatIntervalDays = imported.repeatIntervalDays
            context.insert(item)
            created.append(item)
        }

        for (index, imported) in tasks.enumerated() {
            guard let blockedBy = imported.blockedByIndex, created.indices.contains(blockedBy) else {
                continue
            }
            created[index].blockedByID = created[blockedBy].id
        }

        return created.count
    }

    /// Inserts the backup's quick notes, returning how many landed on the scratchpad.
    ///
    /// Separate from `apply` because notes and strips are independent: a backup can carry either
    /// without the other, and nothing in a note points at a task. `.replace` clears the existing
    /// notes for the same reason it clears the board — the user asked for the backup's state, not
    /// a merge of the two.
    @discardableResult
    static func apply(
        notes: [ImportedNote],
        mode: ImportMode,
        existing: [Note],
        context: ModelContext
    ) -> Int {
        if mode == .replace {
            for note in existing { context.delete(note) }
        }
        for imported in notes {
            context.insert(Note(text: imported.text, createdAt: imported.createdAt))
        }
        return notes.count
    }

    /// Turns the backup's paths into attachments.
    ///
    /// A path whose bytes weren't in the archive still becomes an attachment: the strip did have
    /// a file, and saying so — the UI marks it "missing" — keeps more of the truth than dropping
    /// it silently would.
    ///
    /// Only documents carry a name worth showing; everything else is stored under a uuid, so it
    /// gets numbered per kind the way it would read on the strip.
    private static func attachments(for imported: ImportedTask) -> [TaskAttachment] {
        var countsByKind: [AttachmentKind: Int] = [:]
        return imported.attachments.map { reference in
            let index = (countsByKind[reference.kind] ?? 0) + 1
            countsByKind[reference.kind] = index
            let name = reference.kind == .document
                ? (reference.path as NSString).lastPathComponent
                : "\(reference.kind.label) \(index)"
            return TaskAttachment(kind: reference.kind, path: reference.path, name: name)
        }
    }

    // MARK: - JSON accessors
    //
    // Mirrors org.json's opt* forgiveness: a field that's missing, null, or the wrong type falls
    // back to a default rather than failing the whole import. Only `tasks` itself is required.

    private static func stringValue(_ object: [String: Any], _ key: String) -> String {
        object[key] as? String ?? ""
    }

    private static func boolValue(_ object: [String: Any], _ key: String) -> Bool {
        object[key] as? Bool ?? false
    }

    private static func intValue(_ object: [String: Any], _ key: String) -> Int? {
        if let number = object[key] as? NSNumber { return number.intValue }
        if let text = object[key] as? String { return Int(text) }
        return nil
    }

    /// Android writes every timestamp as epoch milliseconds.
    private static func dateValue(_ object: [String: Any], _ key: String) -> Date? {
        numberValue(object, key).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    private static func numberValue(_ object: [String: Any], _ key: String) -> Double? {
        (object[key] as? NSNumber)?.doubleValue
    }

    /// Re-anchors a due date from Android's convention to a real instant.
    ///
    /// dueAt is the one timestamp Android doesn't store as an instant. It holds a wall-clock
    /// value pinned to UTC — 14:00 on the phone is stored as 14:00Z wherever you are — and every
    /// display formats it in UTC to match, which is why Formatting.kt has dueAtAsLocalInstant and
    /// only the alarm scheduler calls it. Read as a true instant, a due date would land on the
    /// Mac shifted by the local offset: three hours late at UTC+3.
    ///
    /// So: read the wall clock in UTC, then rebuild it in the local zone. 14:00 on the phone
    /// becomes 14:00 here.
    static func dueDate(fromAndroidWallClock milliseconds: Double, in timeZone: TimeZone) -> Date {
        let instant = Date(timeIntervalSince1970: milliseconds / 1000)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let wallClock = utc.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: instant
        )

        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        return local.date(from: wallClock) ?? instant
    }
}

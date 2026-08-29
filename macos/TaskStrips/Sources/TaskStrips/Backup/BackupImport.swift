import Foundation
import SwiftData

extension Notification.Name {
    static let importAndroidBackup = Notification.Name("com.saud.taskstrip.mac.importAndroidBackup")
}

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
    var tags: [String] = []
    var contacts: [TaskContact] = []
    var links: [TaskLink] = []
    var actionLog: [TaskActionLogEntry] = []
    var createdAt: Date = .now
    var blockedByIndex: Int?
    /// Images/voice notes/documents/videos on this strip. Counted only so the import sheet can
    /// say what's being left behind — the Mac model carries no attachments yet.
    var attachmentCount: Int = 0
    var hasReminder: Bool = false
}

/// What a backup holds, including the parts this app can't take yet, so the user is told rather
/// than left to notice the gap themselves.
struct BackupImportSummary: Identifiable {
    let id = UUID()
    var version: Int = 0
    var tasks: [ImportedTask] = []
    var attachmentCount: Int = 0
    var reminderOnTaskCount: Int = 0
    /// Whole top-level sections of the backup with no Mac equivalent, e.g. "notes": 12.
    var skippedSections: [(name: String, count: Int)] = []
}

enum ImportMode {
    case add
    case replace
}

enum BackupImport {
    /// Section name in backup.json -> what to call it in the UI. Everything here is a feature the
    /// Android app has and the Mac port doesn't, so it's reported and dropped.
    private static let skippableSections: [(key: String, label: String)] = [
        ("notes", "notes"),
        ("reminders", "standalone reminders"),
        ("credentials", "credentials"),
        ("storageItems", "storage items"),
    ]

    static func parse(manifest data: Data) throws -> BackupImportSummary {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackupImportError.notJSON
        }
        guard let rawTasks = root["tasks"] as? [Any] else {
            throw BackupImportError.noTasksSection
        }

        var summary = BackupImportSummary()
        summary.version = intValue(root, "version") ?? 0
        summary.tasks = rawTasks.compactMap { $0 as? [String: Any] }.map(task(from:))
        summary.attachmentCount = summary.tasks.reduce(0) { $0 + $1.attachmentCount }
        summary.reminderOnTaskCount = summary.tasks.filter(\.hasReminder).count
        summary.skippedSections = skippableSections.compactMap { section -> (name: String, count: Int)? in
            guard let items = root[section.key] as? [Any], !items.isEmpty else { return nil }
            return (name: section.label, count: items.count)
        }
        return summary
    }

    private static func task(from object: [String: Any]) -> ImportedTask {
        var task = ImportedTask()
        task.title = stringValue(object, "title")
        task.notes = stringValue(object, "notes")
        task.notesRtl = boolValue(object, "notesRtl")
        task.priority = Priority(rawValue: stringValue(object, "priority")) ?? .normal
        task.dueAt = dateValue(object, "dueAt")
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

        task.attachmentCount = ["images", "voiceNotes", "documents", "videos"]
            .reduce(0) { $0 + ((object[$1] as? [Any])?.count ?? 0) }
        task.hasReminder = intValue(object, "reminderMinutesBefore") != nil

        return task
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
        guard let number = object[key] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue / 1000)
    }
}

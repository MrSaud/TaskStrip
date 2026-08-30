import Foundation
import SwiftData

// Mirrors com.saud.taskstrip.data.Priority — same case names/order, since the Drive backup
// JSON (Phase 2) stores the Android enum's name() as a plain string.
enum Priority: String, Codable, CaseIterable, Identifiable {
    case urgent = "URGENT"
    case high = "HIGH"
    case normal = "NORMAL"
    case low = "LOW"

    var id: String { rawValue }
    var label: String { rawValue }
}

// Mirrors TaskContact.kt.
struct TaskContact: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var email: String = ""
    var phone: String = ""
}

// Mirrors TaskLink.kt.
struct TaskLink: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var url: String = ""
    var label: String = ""
}

// Mirrors TaskActionLogEntry.kt.
struct TaskActionLogEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var text: String = ""
    var timestamp: Date = .now
}

// Mirrors the task-relevant fields of TaskEntity.kt (app/src/main/java/com/saud/taskstrip/data/TaskEntity.kt).
// Deliberately omits `route` (dead field on Android, superseded by `tags`) and everything
// reminder/sketch-related. Attachments arrived later — see TaskAttachment and AttachmentStore.
//
// `blockedByID` is a plain UUID lookup rather than a SwiftData relationship: a self-referencing
// to-one relationship with no inverse risks a dangling reference if the blocker is deleted.
// Resolving by id (same as Android's raw Long blockedByTaskId, resolved by lookup at read time)
// keeps deletion simple — see TaskListView.delete(_:), which clears any dangling references.
@Model
final class TaskItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var notesRtl: Bool
    var priorityRaw: String
    var dueAt: Date?
    var orderIndex: Int
    var isDone: Bool
    var isArchived: Bool
    var progress: Int
    // Set the instant a strip is marked done, cleared if it's reopened — mirrors TaskEntity's
    // completedAt, which drives "done this week" style rollups elsewhere in the Android app.
    var completedAt: Date?
    var blockedByID: UUID?
    var waitingOnName: String
    var waitingOnSince: Date?
    var waitingOnFollowUpDays: Int?
    /// The folder name of the sketch this strip points at — see SketchStore.
    ///
    /// It carried nothing but a round trip at first: the Mac had no canvas, and the field existed
    /// only so a backup written here still pointed at the right sketch when it landed back on a
    /// phone. Now the editor links and opens one, on the same id the phone uses.
    var linkedSketchID: String?
    var tags: [String]
    var contacts: [TaskContact]
    var links: [TaskLink]
    var actionLog: [TaskActionLogEntry]
    /// Files on this strip. Added after Phase 1, so it carries a default for SwiftData's
    /// lightweight migration to fill in on an existing store.
    var attachments: [TaskAttachment] = []
    /// Fire a reminder this many minutes before `dueAt`. Nil means no reminder.
    var reminderMinutesBefore: Int? = nil
    /// Completing this strip spawns the next one this many days later — see ReminderPlan.
    var repeatIntervalDays: Int? = nil
    var createdAt: Date

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    init(
        title: String,
        orderIndex: Int,
        priority: Priority = .normal,
        id: UUID = UUID(),
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = ""
        self.notesRtl = false
        self.priorityRaw = priority.rawValue
        self.dueAt = nil
        self.orderIndex = orderIndex
        self.isDone = false
        self.isArchived = false
        self.progress = 0
        self.completedAt = nil
        self.blockedByID = nil
        self.waitingOnName = ""
        self.waitingOnSince = nil
        self.waitingOnFollowUpDays = nil
        self.linkedSketchID = nil
        self.tags = []
        self.contacts = []
        self.links = []
        self.actionLog = []
        self.attachments = []
        self.reminderMinutesBefore = nil
        self.repeatIntervalDays = nil
        self.createdAt = createdAt
    }
}

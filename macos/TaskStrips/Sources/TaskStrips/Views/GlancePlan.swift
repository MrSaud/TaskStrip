import Foundation

/// What the glance shows, mirroring WidgetUpdater.kt: five open strips and three reminders that
/// haven't been dealt with, soonest first.
///
/// Pure, so the rules — how many, which ones, in what order — are pinned without a window.
enum GlancePlan {
    static let stripLimit = 5
    static let reminderLimit = 3

    /// Open work only: what's already done isn't a glance, it's history. Archived strips aren't
    /// on the board at all.
    ///
    /// Board order, not due order — the widget shows the top of the board, which is the order the
    /// user themselves put it in.
    static func strips(from tasks: [TaskItem]) -> [TaskItem] {
        tasks
            .filter { !$0.isDone && !$0.isArchived }
            .sorted { $0.orderIndex < $1.orderIndex }
            .prefix(stripLimit)
            .map { $0 }
    }

    /// Reminders go by when they fire rather than by any order the user chose, because that's the
    /// only order a reminder has.
    static func reminders(from reminders: [Reminder]) -> [Reminder] {
        reminders
            .filter { !$0.isDone }
            .sorted { $0.triggerAt < $1.triggerAt }
            .prefix(reminderLimit)
            .map { $0 }
    }

    /// What the menu bar itself says: the number of open strips, or nothing when the board is
    /// clear. A permanent badge reading zero is just clutter in the menu bar.
    static func openCount(_ tasks: [TaskItem]) -> Int {
        tasks.filter { !$0.isDone && !$0.isArchived }.count
    }
}

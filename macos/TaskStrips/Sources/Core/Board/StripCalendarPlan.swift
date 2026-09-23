import Foundation

/// When a strip's block of time should go, and what the event should say.
///
/// Kept apart from EventKit so the decision — which hour, how long, what it's called — can be
/// checked without a calendar, a permission prompt or a device.
enum StripCalendarPlan {
    /// An hour, which is what "block some time for this" means to most people.
    static let defaultDuration: TimeInterval = 3600

    /// Where the block lands.
    ///
    /// Before the due time if there is one, because the point is to finish by then; otherwise the
    /// next hour that hasn't started yet. Never in the past: a block you can't attend is a lie on
    /// the calendar.
    static func start(
        for task: TaskItem,
        duration: TimeInterval = defaultDuration,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        guard let due = task.dueAt else { return nextHour(after: now, calendar: calendar) }
        let before = due.addingTimeInterval(-duration)
        return before > now ? before : nextHour(after: now, calendar: calendar)
    }

    private static func nextHour(after now: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let thisHour = calendar.date(from: parts) ?? now
        return calendar.date(byAdding: .hour, value: 1, to: thisHour) ?? now.addingTimeInterval(3600)
    }

    static func title(for task: TaskItem) -> String {
        task.title.isEmpty ? "Task Strips" : task.title
    }

    /// What the event carries with it, so the calendar entry means something on its own: the
    /// notes, the steps still to do, and where it came from.
    static func notes(for task: TaskItem) -> String {
        var lines: [String] = []
        let notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { lines.append(notes) }

        let open = task.checklist.filter { !$0.isDone }
        if !open.isEmpty {
            lines.append("")
            lines.append("Still to do:")
            lines.append(contentsOf: open.map { "• \($0.text)" })
        }
        lines.append("")
        lines.append("— Task Strips")
        return lines.joined(separator: "\n")
    }
}

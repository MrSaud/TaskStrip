import Foundation

/// The three questions a standup actually asks, answered from the board.
///
/// Mirrors ui/screens/StandupScreen.kt. Pure and parameterised on `now`, because a roll-up whose
/// answer depends on the wall clock is exactly the kind of thing that can't be checked by reading
/// it.
struct StandupSummary: Equatable {
    var doneRecently: [TaskItem] = []
    var plannedToday: [TaskItem] = []
    var blocked: [TaskItem] = []

    /// "Recently" is the last day, as on Android — long enough to cover yesterday afternoon,
    /// short enough that the list is still a standup and not a changelog.
    static let recentWindow: TimeInterval = 24 * 60 * 60

    var isEmpty: Bool { doneRecently.isEmpty && plannedToday.isEmpty && blocked.isEmpty }

    /// `tasks` is the board — the strips that aren't archived. Android's roll-ups read the same
    /// flow the board does, which already excludes archived strips, so an archived strip counts
    /// for nothing here: not as work done, and not as a blocker.
    static func make(from tasks: [TaskItem], now: Date = .now, calendar: Calendar = .current) -> StandupSummary {
        let since = now.addingTimeInterval(-recentWindow)
        var summary = StandupSummary()
        summary.doneRecently = tasks.filter { task in
            guard task.isDone, let completedAt = task.completedAt else { return false }
            return completedAt >= since
        }
        summary.plannedToday = tasks.filter {
            isDueTodayOrOverdue($0, now: now, calendar: calendar)
        }
        summary.blocked = tasks.filter { task in
            guard !task.isDone, let blockerID = task.blockedByID else { return false }
            guard let blocker = tasks.first(where: { $0.id == blockerID }) else { return false }
            return !blocker.isDone
        }
        return summary
    }

    /// Whole days, not the next 24 hours: something due at 9am today is still "planned today" at
    /// 5pm, and something overdue stays on the list until it's done.
    ///
    /// Android compares in UTC because that's where it pins a due date's wall clock; the Mac
    /// converts that wall clock to a local date on import, so the same comparison is the local
    /// one here.
    static func isDueTodayOrOverdue(_ task: TaskItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !task.isDone, let dueAt = task.dueAt else { return false }
        return calendar.startOfDay(for: dueAt) <= calendar.startOfDay(for: now)
    }

    /// The summary as something you can paste into a chat window, which is the whole point of
    /// standing up in the first place. Same shape as Android's buildStandupText.
    var plainText: String {
        func section(_ heading: String, _ tasks: [TaskItem], empty: String) -> String {
            let lines = tasks.isEmpty ? ["- \(empty)"] : tasks.map { "- \($0.title)" }
            return ([heading] + lines).joined(separator: "\n")
        }
        return [
            "STANDUP SUMMARY",
            "",
            section("Done recently:", doneRecently, empty: "(nothing)"),
            "",
            section("Planned today:", plannedToday, empty: "(nothing)"),
            "",
            section("Blockers:", blocked, empty: "(none)"),
        ].joined(separator: "\n")
    }
}

import Foundation

/// The daily report: what today wants, and what yesterday got.
///
/// Richer than the old digest, which only counted what was due. This also says what was finished,
/// what was written in the logs and how long the clock ran, because a report that only ever asks
/// and never acknowledges is a report people switch off.
///
/// Pure, like the rest of the reminder rules: the wording and the "say nothing when there's
/// nothing to say" line are the parts worth pinning, and posting it is somebody else's job.
struct DayReport: Equatable {
    var overdue: [String] = []
    var dueToday: [String] = []
    var reminders: [String] = []
    /// Strips finished since the last report.
    var done: [String] = []
    /// Entries written into strips' logs since the last report.
    var actions: [String] = []
    /// Time the clock ran since the last report.
    var worked: TimeInterval = 0

    /// Nothing asked for and nothing done: a report that says so every morning is a report people
    /// turn off, so it isn't sent at all.
    var isEmpty: Bool {
        overdue.isEmpty && dueToday.isEmpty && reminders.isEmpty && done.isEmpty && actions.isEmpty
    }

    var title: String {
        let waiting = overdue.count + dueToday.count + reminders.count
        if waiting == 0 { return done.isEmpty ? "Nothing on today" : "Yesterday's work" }
        return waiting == 1 ? "1 thing today" : "\(waiting) things today"
    }

    /// Short lines in the order they matter: what's late, what's due, what will go off, then what
    /// was already done.
    var body: String {
        var lines: [String] = []
        if !overdue.isEmpty { lines.append("Late: " + list(overdue)) }
        if !dueToday.isEmpty { lines.append("Due: " + list(dueToday)) }
        if !reminders.isEmpty { lines.append("Reminders: " + list(reminders)) }
        if !done.isEmpty { lines.append("Done: " + list(done)) }
        if !actions.isEmpty { lines.append("Logged: " + list(actions)) }
        if worked > 0 { lines.append("Worked: " + StripTime.label(worked)) }
        return lines.joined(separator: "\n")
    }

    /// Three, then a count. A notification that needs scrolling is a notification nobody reads.
    private func list(_ items: [String]) -> String {
        let shown = items.prefix(3).joined(separator: ", ")
        return items.count > 3 ? "\(shown) + \(items.count - 3) more" : shown
    }

    /// What the report would say if it fired at `date`, looking back over the day before it.
    ///
    /// Worked out for the moment it will fire rather than for now, for the same reason the digest
    /// is: the content of a scheduled notification is fixed when it's scheduled, so asking at
    /// 11pm what is due "today" would answer about the wrong day.
    static func make(
        tasks: [TaskItem],
        reminders allReminders: [Reminder] = [],
        on date: Date,
        since: Date? = nil,
        calendar: Calendar = .current
    ) -> DayReport {
        let today = calendar.startOfDay(for: date)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let looksBackTo = since ?? calendar.date(byAdding: .day, value: -1, to: date) ?? today

        var report = DayReport()
        let live = tasks.filter { !$0.isArchived && !$0.isTombstoned }

        for task in live where !task.isDone {
            if StripDeferral.isDeferred(task.deferUntil, now: date, calendar: calendar) { continue }
            guard let due = task.dueAt else { continue }
            let day = calendar.startOfDay(for: due)
            if day < today {
                report.overdue.append(task.title.uppercased())
            } else if day == today {
                report.dueToday.append(task.title.uppercased())
            }
        }

        report.reminders = allReminders
            .filter { !$0.isDone && !$0.isTombstoned }
            .filter { $0.triggerAt >= date && $0.triggerAt < tomorrow }
            .sorted { $0.triggerAt < $1.triggerAt }
            .map(\.text)

        // What happened since the last report: finished, written down, and spent.
        for task in live {
            if let completedAt = task.completedAt, completedAt >= looksBackTo, completedAt <= date {
                report.done.append(task.title.uppercased())
            }
            for entry in task.actionLog where entry.timestamp >= looksBackTo && entry.timestamp <= date {
                report.actions.append(entry.text)
            }
            for session in task.sessions {
                guard let ended = session.endedAt else { continue }
                let from = max(session.startedAt, looksBackTo)
                let to = min(ended, date)
                report.worked += max(to.timeIntervalSince(from), 0)
            }
        }
        return report
    }
}

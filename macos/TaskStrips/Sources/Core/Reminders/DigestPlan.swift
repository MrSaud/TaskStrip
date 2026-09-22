import Foundation

/// The scheduled summaries: the morning digest, the Friday review, and when the next automatic
/// backup is owed.
///
/// All of it pure. The times, the wording and the "say nothing when there's nothing to say" rule
/// are the parts worth pinning; posting them is somebody else's job.
enum DigestPlan {
    /// Mirrors DigestScheduler.kt and WeeklyDigestScheduler.kt: 8am daily, 5pm Friday, and a
    /// backup at 3am — a quiet hour that competes with nothing.
    static let dailyHour = 8
    static let weeklyHour = 17
    /// Calendar's own numbering, where Sunday is 1, so Friday is 6.
    static let weeklyWeekday = 6
    static let backupHour = 3

    // MARK: - When

    static func nextDaily(after now: Date, calendar: Calendar = .current) -> Date? {
        nextTime(hour: dailyHour, weekday: nil, after: now, calendar: calendar)
    }

    static func nextWeekly(after now: Date, calendar: Calendar = .current) -> Date? {
        nextTime(hour: weeklyHour, weekday: weeklyWeekday, after: now, calendar: calendar)
    }

    static func nextBackup(after now: Date, calendar: Calendar = .current) -> Date? {
        nextTime(hour: backupHour, weekday: nil, after: now, calendar: calendar)
    }

    /// The next time it's that hour — today if it hasn't passed, otherwise the next day that
    /// qualifies. Strictly after `now`, so re-arming at the moment one fires lands on the next.
    private static func nextTime(
        hour: Int,
        weekday: Int?,
        after now: Date,
        calendar: Calendar
    ) -> Date? {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        components.second = 0
        if let weekday { components.weekday = weekday }
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
    }

    // MARK: - The morning digest

    struct Daily: Equatable {
        var titles: [String] = []
        var total: Int = 0

        /// Nothing due means nothing is said. A digest that arrives every morning to report an
        /// empty board is a digest people turn off.
        var isEmpty: Bool { total == 0 }

        var title: String {
            total == 1 ? "1 strip needs attention today" : "\(total) strips need attention today"
        }

        /// Five, then a count — the same shape Android's inbox-style notification takes.
        var body: String {
            var lines = titles
            if total > titles.count { lines.append("+ \(total - titles.count) more") }
            return lines.joined(separator: ", ")
        }
    }

    /// What the digest would say if it fired at `date`.
    ///
    /// Worked out for the moment it will fire rather than for now, which matters on a Mac: the
    /// content of a scheduled notification is fixed when it's scheduled, so asking "what is due
    /// today" at 11pm for an 8am digest would answer about the wrong day.
    static func daily(for tasks: [TaskItem], on date: Date, calendar: Calendar = .current) -> Daily {
        let due = tasks.filter {
            !$0.isArchived && StandupSummary.isDueTodayOrOverdue($0, now: date, calendar: calendar)
        }
        return Daily(titles: due.prefix(5).map { $0.title.uppercased() }, total: due.count)
    }

    // MARK: - The Friday review

    struct Weekly: Equatable {
        var done: Int = 0
        var overdue: Int = 0

        var isEmpty: Bool { done == 0 && overdue == 0 }
        var title: String { "Week in review" }

        var body: String {
            let doneText = done == 1 ? "1 strip done" : "\(done) strips done"
            let overdueText = overdue == 1 ? "1 still overdue" : "\(overdue) still overdue"
            return "\(doneText) · \(overdueText)"
        }
    }

    static func weekly(for tasks: [TaskItem], on date: Date, calendar: Calendar = .current) -> Weekly {
        let weekAgo = date.addingTimeInterval(-7 * 24 * 60 * 60)
        return Weekly(
            done: tasks.filter { task in
                guard task.isDone, let completedAt = task.completedAt else { return false }
                return completedAt >= weekAgo && completedAt <= date
            }.count,
            overdue: tasks.filter {
                !$0.isArchived && StandupSummary.isDueTodayOrOverdue($0, now: date, calendar: calendar)
            }.count
        )
    }

    // MARK: - The automatic backup

    /// Whether a backup is owed.
    ///
    /// Android sets an alarm for 3am and the system wakes the app to run it. Nothing wakes a Mac
    /// app that isn't running, so this asks a question instead of keeping a schedule: has a day
    /// gone by since the last one? Checked whenever the app is open, which makes it "daily, from
    /// the next time you open it" rather than "daily at 3am".
    static func isBackupDue(lastBackup: Date?, now: Date = .now) -> Bool {
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) >= 24 * 60 * 60
    }
}

import Foundation

/// What the week actually did, and what it quietly didn't.
///
/// The daily report answers "what's due today". Nothing answered the harder question: what has
/// been sitting there untouched, what was started and abandoned half-done, who has been waiting
/// so long that the follow-up itself has been forgotten, and which budget crept up while nobody
/// was adding it up. Those are the things that don't announce themselves, and they're the whole
/// reason a review exists.
struct WeeklyReview: Equatable {
    /// Open, not deferred, and nothing has happened to it in a fortnight.
    var stalled: [TaskItem] = []
    /// Started and left: some steps ticked, the rest untouched for a week.
    var halfFinished: [TaskItem] = []
    /// Waiting on somebody far longer than the follow-up allowed, or with no follow-up set at
    /// all — which is how a thing waits forever without anybody being nagged about it.
    var waitingTooLong: [TaskItem] = []
    /// A total that has passed three quarters of what it was allowed.
    var budgetsCreeping: [TaskItem] = []
    /// Finished since the last review. A review that only lists failures is one nobody opens
    /// twice.
    var finished: [TaskItem] = []

    var isEmpty: Bool {
        stalled.isEmpty && halfFinished.isEmpty && waitingTooLong.isEmpty
            && budgetsCreeping.isEmpty && finished.isEmpty
    }

    /// Everything worth acting on — what the count on a button should say.
    var needingAttention: Int {
        stalled.count + halfFinished.count + waitingTooLong.count + budgetsCreeping.count
    }
}

extension WeeklyReview {
    /// A fortnight of nothing is stalled. A week is ordinary — plenty of work waits a week for a
    /// reason — and a month is too late to be told.
    static let stalledAfterDays = 14
    /// Half-finished for this long is abandoned rather than in progress.
    static let abandonedAfterDays = 7
    /// How far into a budget is worth mentioning before the alert at nine tenths.
    static let budgetWatch = 0.75

    /// When anything last happened to a strip: an edit, a logged action, a stretch of work, an
    /// entry on a total. A strip somebody worked on yesterday isn't stalled, whatever its
    /// updatedAt says.
    static func lastActivity(of task: TaskItem) -> Date {
        var latest = task.lastEditedAt
        if let logged = task.actionLog.map(\.timestamp).max() { latest = max(latest, logged) }
        if let worked = task.sessions.compactMap({ $0.endedAt ?? $0.startedAt }).max() {
            latest = max(latest, worked)
        }
        let counted = task.tallies.flatMap(\.entries).map(\.at).max()
        if let counted { latest = max(latest, counted) }
        return latest
    }

    static func make(
        from tasks: [TaskItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> WeeklyReview {
        var review = WeeklyReview()
        let open = tasks.filter { !$0.isArchived && !$0.isTombstoned && !$0.isDone }
        let day = 24.0 * 60 * 60

        for task in open {
            // A strip waiting for its day hasn't stalled; it's asleep on purpose.
            guard !StripDeferral.isDeferred(task.deferUntil, now: now, calendar: calendar) else { continue }
            let quiet = now.timeIntervalSince(lastActivity(of: task)) / day

            let ticked = StripChecklist.progress(of: task.checklist) ?? 0
            if !task.checklist.isEmpty, ticked > 0, ticked < 100, quiet >= Double(abandonedAfterDays) {
                review.halfFinished.append(task)
            } else if quiet >= Double(stalledAfterDays) {
                review.stalled.append(task)
            }

            if isWaitingTooLong(task, now: now) { review.waitingTooLong.append(task) }
            if task.tallies.contains(where: isCreeping) { review.budgetsCreeping.append(task) }
        }

        let weekAgo = now.addingTimeInterval(-7 * day)
        review.finished = tasks.filter { task in
            guard task.isDone, let completedAt = task.completedAt else { return false }
            return completedAt >= weekAgo && completedAt <= now
        }

        // Longest silence first in each list: the thing that has been ignored the longest is the
        // thing most likely to have been forgotten entirely.
        review.stalled.sort { lastActivity(of: $0) < lastActivity(of: $1) }
        review.halfFinished.sort { lastActivity(of: $0) < lastActivity(of: $1) }
        review.waitingTooLong.sort { ($0.waitingOnSince ?? now) < ($1.waitingOnSince ?? now) }
        review.finished.sort { ($0.completedAt ?? now) > ($1.completedAt ?? now) }
        return review
    }

    /// Waiting well past the agreed follow-up, or waiting with nothing agreed at all.
    static func isWaitingTooLong(_ task: TaskItem, now: Date = .now) -> Bool {
        guard !task.waitingOnName.trimmingCharacters(in: .whitespaces).isEmpty,
              let since = task.waitingOnSince
        else { return false }
        let waited = now.timeIntervalSince(max(since, task.waitingOnChasedAt ?? since)) / (24 * 60 * 60)
        guard let days = task.waitingOnFollowUpDays else {
            // Nothing agreed: a fortnight of silence is worth a mention either way.
            return waited >= Double(stalledAfterDays)
        }
        // Twice the agreed wait, because the follow-up notification already covers the first.
        return waited >= Double(days) * 2
    }

    static func isCreeping(_ tally: TaskTally) -> Bool {
        guard let progress = tally.progress else { return false }
        return progress >= budgetWatch
    }

    /// How long a strip has been quiet, said the way somebody would say it.
    static func silence(of task: TaskItem, now: Date = .now) -> String {
        let days = Int(now.timeIntervalSince(lastActivity(of: task)) / (24 * 60 * 60))
        switch days {
        case ..<1: return "today"
        case 1: return "1 day"
        case 2..<14: return "\(days) days"
        case 14..<60: return "\(days / 7) weeks"
        default: return "\(days / 30) months"
        }
    }
}

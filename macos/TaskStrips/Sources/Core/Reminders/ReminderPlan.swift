import Foundation

/// The rules about reminders and repeats, with no notification machinery in sight.
///
/// Both mirror Android exactly — ReminderScheduler.schedule for when a reminder fires,
/// TaskViewModel.toggleTask for what completing a repeating strip does — and both are pure, so
/// they can be tested without asking anyone for notification permission.
enum ReminderPlan {
    /// When this strip's reminder should fire, or nil if it shouldn't fire at all.
    ///
    /// Nil covers every case Android skips: no due date, no lead time, already done, archived, or
    /// a moment that has already passed. That last one matters on import — a backup is full of
    /// due dates in the past, and none of them should announce themselves on arrival.
    static func fireDate(for task: TaskItem, now: Date = .now) -> Date? {
        guard !task.isDone, !task.isArchived,
              let dueAt = task.dueAt,
              let minutesBefore = task.reminderMinutesBefore
        else { return nil }

        let fireAt = dueAt.addingTimeInterval(-Double(minutesBefore) * 60)
        return fireAt > now ? fireAt : nil
    }

    /// When to chase whoever this strip is waiting on, or nil if there's no one to chase.
    ///
    /// Mirrors FollowUpScheduler.schedule: counted from when the waiting started, not from the
    /// due date, because "I handed this over on Tuesday, nudge me on Friday" is what the field
    /// means. Nil covers the same cases the reminder does — done, archived, already past — plus
    /// the two halves this needs: someone to chase, and a date to count from.
    static func followUpDate(for task: TaskItem, now: Date = .now) -> Date? {
        guard !task.isDone, !task.isArchived,
              !task.waitingOnName.trimmingCharacters(in: .whitespaces).isEmpty,
              let since = task.waitingOnSince,
              let days = task.waitingOnFollowUpDays
        else { return nil }

        let fireAt = since.addingTimeInterval(Double(days) * 24 * 60 * 60)
        return fireAt > now ? fireAt : nil
    }

    /// When a strip's own due moment should announce itself, or nil if it shouldn't.
    ///
    /// Separate from the reminder before it: "remind me an hour before" and "it's due now" are
    /// two different things to be told, and a strip with no lead time set was previously told
    /// neither. Same exclusions as the reminder — done, archived, no due date, already past.
    static func dueDate(for task: TaskItem, now: Date = .now) -> Date? {
        guard !task.isDone, !task.isArchived, let dueAt = task.dueAt else { return nil }
        return dueAt > now ? dueAt : nil
    }

    /// The morning a deferred strip comes back onto the board, or nil if it isn't deferred.
    ///
    /// Eight in the morning rather than the exact moment it was deferred to: a strip that
    /// reappears at 3am should say so when someone's awake to read it.
    static func returnDate(for task: TaskItem, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard !task.isDone, !task.isArchived, let deferUntil = task.deferUntil else { return nil }
        let morning = calendar.date(
            bySettingHour: DigestPlan.dailyHour, minute: 0, second: 0,
            of: calendar.startOfDay(for: deferUntil)
        )
        guard let morning else { return nil }
        return morning > now ? morning : nil
    }

    /// The strip that completing a repeating one should spawn, or nil if it doesn't repeat.
    ///
    /// A new strip rather than an edit in place, which is Android's choice and the right one: the
    /// completed strip stays as history instead of being quietly rolled forward, so "what did I
    /// finish last week" keeps working.
    ///
    /// It carries what describes the work — title, notes, priority, tags, and the reminder and
    /// repeat settings that make it recur. It deliberately doesn't carry progress, attachments,
    /// contacts, links, the activity log, or blocked-by/waiting-on: those belong to the occurrence
    /// that just finished, not to the next one.
    static func nextOccurrence(completing task: TaskItem, orderIndex: Int) -> TaskItem? {
        guard let interval = task.repeatIntervalDays, interval > 0, let dueAt = task.dueAt else {
            return nil
        }

        let next = TaskItem(title: task.title, orderIndex: orderIndex, priority: task.priority)
        next.notes = task.notes
        next.notesRtl = task.notesRtl
        next.tags = task.tags
        next.dueAt = dueAt.addingTimeInterval(Double(interval) * 24 * 60 * 60)
        next.reminderMinutesBefore = task.reminderMinutesBefore
        next.repeatIntervalDays = interval
        return next
    }
}

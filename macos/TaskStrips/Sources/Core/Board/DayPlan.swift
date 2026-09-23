import Foundation

/// What today actually asks of you: the work that's late, the work that's due, the people you're
/// waiting on who are now overdue a chase, and the reminders that go off before bedtime.
///
/// It reads the board rather than holding anything of its own, so there's nothing to keep in step
/// and nothing to sync. Everything it decides is decided here, where it can be tested without a
/// board on screen.
struct DayPlan: Equatable {
    /// Due before today and not done. The first thing anyone wants to know.
    var overdue: [TaskItem] = []
    /// Due today.
    var due: [TaskItem] = []
    /// Waiting on somebody, and the follow-up they agreed to has come round.
    var chase: [TaskItem] = []
    /// Back on the board today after being deferred to it.
    var returning: [TaskItem] = []
    var reminders: [Reminder] = []

    var isEmpty: Bool {
        overdue.isEmpty && due.isEmpty && chase.isEmpty && returning.isEmpty && reminders.isEmpty
    }

    /// How many things the day is asking for, for a badge or a sentence.
    var count: Int { overdue.count + due.count + chase.count + returning.count + reminders.count }

    static func make(
        tasks: [TaskItem],
        reminders allReminders: [Reminder] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DayPlan {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        // Archived strips aren't work any more, and a deferred one isn't today's problem — the
        // day it comes back it stops being deferred and lands in `returning` instead.
        let live = tasks.filter { !$0.isArchived && !$0.isTombstoned && !$0.isDone }

        var plan = DayPlan()
        for task in live {
            if StripDeferral.isDeferred(task.deferUntil, now: now, calendar: calendar) { continue }

            if let due = task.dueAt {
                let day = calendar.startOfDay(for: due)
                if day < today {
                    plan.overdue.append(task)
                } else if day == today {
                    plan.due.append(task)
                }
            }
            if isChaseDue(task, now: now, calendar: calendar) { plan.chase.append(task) }
            if let deferUntil = task.deferUntil, calendar.startOfDay(for: deferUntil) == today {
                plan.returning.append(task)
            }
        }

        plan.reminders = allReminders
            .filter { !$0.isDone && !$0.isTombstoned }
            .filter { $0.triggerAt >= today && $0.triggerAt < tomorrow }
            .sorted { $0.triggerAt < $1.triggerAt }

        plan.overdue.sort { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
        plan.due.sort { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
        return plan
    }

    /// Waiting on someone, with a follow-up agreed, and that many days have passed.
    static func isChaseDue(_ task: TaskItem, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !task.waitingOnName.isEmpty,
              let days = task.waitingOnFollowUpDays,
              let since = task.waitingOnSince,
              let due = calendar.date(byAdding: .day, value: days, to: since)
        else { return false }
        return calendar.startOfDay(for: due) <= calendar.startOfDay(for: now)
    }
}

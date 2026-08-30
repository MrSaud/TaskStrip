import Foundation

/// The rules for standalone reminders: when one fires, when a repeating one comes back, and how
/// the list is narrowed. Pure, like ReminderPlan is for strips.
enum ReminderSchedule {
    /// Quick-pick starting points for the tag fields — not a restricted set, just presets that
    /// fill both in one go. Different list from the storage library's: what you tag a reminder
    /// with isn't what you tag a document with.
    static let tagPresets: [(tag: String, emoji: String)] = [
        ("Birthday", "🎂"),
        ("Service", "🔧"),
        ("Documents", "📄"),
        ("Bill", "💳"),
        ("Appointment", "📅"),
        ("Travel", "✈️"),
        ("Health", "💊"),
        ("Family", "👪"),
    ]

    /// How far ahead a reminder can be set to fire. Shared with the strip editor so "1 hour
    /// before" means the same thing wherever it's offered.
    static let leadTimes: [(minutes: Int, label: String)] = [
        (5, "5 minutes before"),
        (15, "15 minutes before"),
        (30, "30 minutes before"),
        (60, "1 hour before"),
        (120, "2 hours before"),
        (1440, "1 day before"),
        (2880, "2 days before"),
    ]

    /// When this reminder should fire, or nil if it shouldn't.
    ///
    /// Nil covers the same cases a strip's does: already done, or a moment that has passed. The
    /// lead time, when set, is the *only* alarm — Android schedules one at trigger-minus-lead
    /// rather than a second one at the trigger itself.
    static func fireDate(for reminder: Reminder, now: Date = .now) -> Date? {
        guard !reminder.isDone else { return nil }
        let fireAt = reminder.triggerAt.addingTimeInterval(-Double(reminder.leadMinutesBefore ?? 0) * 60)
        return fireAt > now ? fireAt : nil
    }

    /// The moment a repeating reminder comes back after `from`.
    ///
    /// Calendar arithmetic, matching GeneralReminderReceiver.nextOccurrence: adding a month to
    /// the 31st has to land on a real date, and adding twelve of them has to land on the same day
    /// next year rather than 365 days later.
    static func nextOccurrence(
        after from: Date,
        amount: Int,
        unit: ReminderRepeatUnit,
        calendar: Calendar = .current
    ) -> Date? {
        guard amount > 0 else { return nil }
        return calendar.date(byAdding: unit.component, value: amount, to: from)
    }

    /// Where a repeating reminder's next occurrence actually is, given that the app may have been
    /// closed through several of them.
    ///
    /// Android advances one step per firing, inside the broadcast receiver that fires it. The Mac
    /// has no equivalent hook — nothing of ours runs when a notification is delivered — so a
    /// reminder is instead rolled forward the next time the app sees it, skipping however many
    /// occurrences went by while it was shut. Same series either way; a run of missed ones
    /// collapses into the next one due rather than announcing all of them at once.
    ///
    /// Returns nil when there's nothing to move: not repeating, already done, or still ahead.
    static func rolledForward(_ reminder: Reminder, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard reminder.repeats, !reminder.isDone,
              let amount = reminder.repeatAmount,
              let unit = reminder.repeatUnit,
              reminder.triggerAt <= now
        else { return nil }

        var next = reminder.triggerAt
        // Bounded: a yearly reminder from a decade-old backup is a handful of steps, but a daily
        // one is thousands, and a corrupt interval could be worse. Whatever it lands on is still
        // in the series.
        for _ in 0..<10_000 {
            guard let candidate = nextOccurrence(after: next, amount: amount, unit: unit, calendar: calendar) else {
                return nil
            }
            next = candidate
            if next > now { return next }
        }
        return next
    }

    /// The list as the screen shows it: matching the search, narrowed to a tag, soonest first
    /// unless asked otherwise.
    static func visible(
        _ reminders: [Reminder],
        search: String = "",
        tag: String? = nil,
        newestFirst: Bool = false
    ) -> [Reminder] {
        var result = Tagging.filtered(reminders, tag: tag)
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            // Android searches the title only, not the description.
            result = result.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
        }
        return result.sorted { newestFirst ? $0.triggerAt > $1.triggerAt : $0.triggerAt < $1.triggerAt }
    }

    /// Reads back when it's for, and what's about to happen — the two things a row has to answer.
    static func summary(for reminder: Reminder, now: Date = .now) -> String {
        var parts = [reminder.triggerAt.formatted(date: .abbreviated, time: .shortened)]
        if let lead = reminder.leadMinutesBefore, lead > 0 {
            parts.append("\(lead) min before")
        }
        if let repeatLabel = reminder.repeatLabel {
            parts.append(repeatLabel.lowercased())
        }
        if !reminder.isDone, reminder.triggerAt < now {
            parts.append("overdue")
        }
        return parts.joined(separator: " · ")
    }
}

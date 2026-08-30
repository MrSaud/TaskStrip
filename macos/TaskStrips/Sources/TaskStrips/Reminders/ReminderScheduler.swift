import Foundation
import UserNotifications

/// Posts the notifications ReminderPlan decides on.
///
/// Deliberately thin: every rule about whether and when a reminder fires lives in ReminderPlan,
/// which is testable without a notification centre. This part only does what can't be tested
/// headlessly — asking permission and handing requests to the system.
///
/// Authorisation is requested the first time a reminder is actually switched on, never at launch.
/// An app that asks before you've expressed any interest gets denied, and a denial is sticky.
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    /// UI tests run with notifications off entirely. A system permission dialog appearing
    /// mid-suite would derail every test after it, and none of them are about reminders.
    private let isEnabled: Bool

    private var center: UNUserNotificationCenter { .current() }

    private init() {
        isEnabled = !ProcessInfo.processInfo.arguments.contains(TaskStripsApp.uiTestingArgument)
    }

    /// Returns whether reminders can actually be posted. Safe to call repeatedly — the system
    /// only prompts once and answers from its own record after that.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isEnabled else { return false }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Whether the system will refuse whatever we schedule.
    ///
    /// Asked rather than assumed: a reminder that was set up months ago goes quiet if
    /// notifications are later turned off in System Settings, and nothing in the app would
    /// otherwise say so.
    func isDenied() async -> Bool {
        guard isEnabled else { return false }
        return await center.notificationSettings().authorizationStatus == .denied
    }

    /// Brings the system's idea of this strip's alarms in line with the strip.
    ///
    /// Always clears first, so this doubles as the cancel path: a strip that's been completed,
    /// archived, had its due date removed or its reminder switched off ends up with nothing
    /// pending, without the caller having to work out which case it's in.
    /// Both of a strip's alarms in one call — the due-date reminder and the delegation follow-up.
    ///
    /// Together rather than separately because they're driven by the same edits: completing,
    /// archiving, changing a due date or handing something over all change both answers, and a
    /// caller that remembered one and forgot the other is exactly how the follow-up came to be
    /// stored but never scheduled.
    func schedule(for task: TaskItem) {
        post(
            identifier: task.id.uuidString,
            at: ReminderPlan.fireDate(for: task),
            title: task.title,
            body: body(for: task)
        )
        post(
            identifier: Self.followUpIdentifier(forTaskID: task.id),
            at: ReminderPlan.followUpDate(for: task),
            title: "Follow up with \(task.waitingOnName)",
            body: task.title.uppercased()
        )
    }

    func cancel(taskID: UUID) {
        center.removePendingNotificationRequests(
            withIdentifiers: [taskID.uuidString, Self.followUpIdentifier(forTaskID: taskID)]
        )
    }

    /// Namespaced for the same reason a standalone reminder's is: one flat namespace, and a strip
    /// now has two alarms in it.
    static func followUpIdentifier(forTaskID id: UUID) -> String {
        "followup-\(id.uuidString)"
    }

    /// Always clears first, so passing a nil date is how anything gets cancelled.
    private func post(identifier: String, at fireAt: Date?, title: String, body: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard isEnabled, let fireAt else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireAt
        )
        center.add(
            UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
        )
    }

    /// The same contract for a standalone reminder: always clears first, so this is the cancel
    /// path too. Its identifier is namespaced because a strip and a reminder are different things
    /// that both have a uuid, and the system's identifiers are one flat namespace.
    func schedule(for reminder: Reminder) {
        let identifier = Self.identifier(forReminderID: reminder.id)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard isEnabled, let fireAt = ReminderSchedule.fireDate(for: reminder) else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.text
        content.body = body(for: reminder)
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireAt
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        center.add(request)
    }

    func cancel(reminderID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(forReminderID: reminderID)])
    }

    static func identifier(forReminderID id: UUID) -> String {
        "reminder-\(id.uuidString)"
    }

    /// Arms the two scheduled summaries, or clears them when they're switched off.
    ///
    /// Each is scheduled one at a time rather than as a repeating notification, because a
    /// repeating one would say the same thing every morning: the system fixes a notification's
    /// text when it's scheduled, and nothing of ours runs at the moment it fires to refresh it.
    /// So each is re-armed with fresh content every time the board changes while the app is open.
    ///
    /// The consequence, which is worth knowing: if the Mac hasn't been opened since the last
    /// digest fired, the next one reports the board as it stood when it was last seen. Android
    /// recomputes at fire time inside a broadcast receiver; there's no equivalent hook here.
    func scheduleDigests(_ tasks: [TaskItem], daily: Bool, weekly: Bool, now: Date = .now) {
        if daily, let fireAt = DigestPlan.nextDaily(after: now) {
            let digest = DigestPlan.daily(for: tasks, on: fireAt)
            post(
                identifier: Self.dailyDigestIdentifier,
                at: digest.isEmpty ? nil : fireAt,
                title: digest.title,
                body: digest.body
            )
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.dailyDigestIdentifier])
        }

        if weekly, let fireAt = DigestPlan.nextWeekly(after: now) {
            let review = DigestPlan.weekly(for: tasks, on: fireAt)
            post(
                identifier: Self.weeklyDigestIdentifier,
                at: review.isEmpty ? nil : fireAt,
                title: review.title,
                body: review.body
            )
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [Self.weeklyDigestIdentifier])
        }
    }

    static let dailyDigestIdentifier = "digest-daily"
    static let weeklyDigestIdentifier = "digest-weekly"

    /// Reconciles everything at launch, and after an import.
    ///
    /// Pending notifications live in the system, not the store, so the two drift apart whenever
    /// the app isn't running — a strip completed on the phone and imported here, a due date
    /// edited, a backup restored wholesale. Rescheduling every strip is cheap and makes the
    /// system's view a function of the board rather than of history.
    func sync(_ tasks: [TaskItem]) {
        guard isEnabled else { return }
        for task in tasks { schedule(for: task) }
    }

    /// Same reconciliation for standalone reminders, plus the one thing they need that strips
    /// don't: a repeating reminder whose moment passed while the app was shut is moved on to its
    /// next occurrence first. Returns whether anything moved, so the caller knows to save.
    @discardableResult
    func sync(_ reminders: [Reminder], now: Date = .now) -> Bool {
        var moved = false
        for reminder in reminders {
            if let next = ReminderSchedule.rolledForward(reminder, now: now) {
                reminder.triggerAt = next
                moved = true
            }
            schedule(for: reminder)
        }
        return moved
    }

    private func body(for reminder: Reminder) -> String {
        var parts: [String] = []
        if !reminder.details.isEmpty { parts.append(reminder.details) }
        if reminder.isTagged { parts.append(reminder.tagLabel) }
        return parts.isEmpty
            ? reminder.triggerAt.formatted(date: .abbreviated, time: .shortened)
            : parts.joined(separator: " · ")
    }

    private func body(for task: TaskItem) -> String {
        guard let dueAt = task.dueAt else { return "Due soon" }
        let due = dueAt.formatted(date: .abbreviated, time: .shortened)
        return task.tags.isEmpty ? "Due \(due)" : "Due \(due) · \(task.tags.joined(separator: ", "))"
    }
}

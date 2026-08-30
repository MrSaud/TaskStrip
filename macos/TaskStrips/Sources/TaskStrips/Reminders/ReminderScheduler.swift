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

    /// Brings the system's idea of this strip's reminder in line with the strip.
    ///
    /// Always clears first, so this doubles as the cancel path: a strip that's been completed,
    /// archived, had its due date removed or its reminder switched off ends up with nothing
    /// pending, without the caller having to work out which case it's in.
    func schedule(for task: TaskItem) {
        let identifier = task.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard isEnabled, let fireAt = ReminderPlan.fireDate(for: task) else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = body(for: task)
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

    func cancel(taskID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [taskID.uuidString])
    }

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

    private func body(for task: TaskItem) -> String {
        guard let dueAt = task.dueAt else { return "Due soon" }
        let due = dueAt.formatted(date: .abbreviated, time: .shortened)
        return task.tags.isEmpty ? "Due \(due)" : "Due \(due) · \(task.tags.joined(separator: ", "))"
    }
}

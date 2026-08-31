import Foundation
import SwiftData
import WidgetKit

/// Pushes the board out to the widget.
///
/// The mirror of Android's WidgetUpdater, and it exists for the same reason: the widget is not
/// given the data, it is handed a rendering of it. There it is RemoteViews pushed to the launcher;
/// here it is a small JSON snapshot in the group container, which the extension reads.
///
/// Which strips and which reminders is decided here rather than in the widget, so both apps pick
/// the same ones: the top of the board in its own order, and the reminders still coming, soonest
/// first.
enum WidgetPublisher {
    static func publish(tasks: [TaskItem], reminders: [Reminder], now: Date = .now) {
        let snapshot = snapshot(tasks: tasks, reminders: reminders, now: now)

        // Only when something actually changed. WidgetCenter throttles reloads, and spending that
        // budget on writes that say the same thing means a real change later may be ignored.
        guard snapshot != WidgetSnapshot.read() else { return }
        snapshot.write()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Split out so the choosing can be tested without a group container to write into.
    static func snapshot(tasks: [TaskItem], reminders: [Reminder], now: Date = .now) -> WidgetSnapshot {
        let strips = tasks
            .filter { !$0.isDone && !$0.isArchived }
            .sorted { $0.orderIndex < $1.orderIndex }
            .prefix(WidgetSnapshot.maxStrips)
            .map {
                WidgetSnapshot.Strip(
                    id: $0.id.uuidString,
                    title: $0.title,
                    priority: $0.priorityRaw,
                    dueAt: $0.dueAt
                )
            }

        // Still-open reminders, soonest first. An overdue one is still coming and stays; a
        // finished one has nothing left to say.
        let upcoming = reminders
            .filter { !$0.isDone }
            .sorted { $0.triggerAt < $1.triggerAt }
            .prefix(WidgetSnapshot.maxReminders)
            .map {
                WidgetSnapshot.Reminder(
                    id: $0.id.uuidString,
                    text: $0.text,
                    triggerAt: $0.triggerAt
                )
            }

        return WidgetSnapshot(strips: Array(strips), reminders: Array(upcoming), writtenAt: now)
    }
}

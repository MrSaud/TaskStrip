import AppKit
import SwiftData
import SwiftUI

/// The menu bar glance: what's on the board without opening the board.
///
/// Android puts this on the home screen as a widget. The closest thing a Mac has is the menu bar
/// — always there, one click, no window. It shows what WidgetUpdater.kt shows: five open strips
/// and three reminders.
struct GlanceView: View {
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \TaskItem.orderIndex) private var allTasks: [TaskItem]
    @Query private var allReminders: [Reminder]

    private var strips: [TaskItem] { GlancePlan.strips(from: allTasks) }
    private var reminders: [Reminder] { GlancePlan.reminders(from: allReminders) }
    private var openCount: Int { GlancePlan.openCount(allTasks) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("THE BOARD")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TaskStripTheme.amber)
                Spacer()
                if openCount > strips.count {
                    Text("\(openCount) open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if strips.isEmpty {
                Text("Nothing on the board")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(strips) { task in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(task.priority.tabColor)
                            .frame(width: 6, height: 6)
                        Text(task.title.uppercased())
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        if let dueAt = task.dueAt {
                            Text(dueAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
            }

            Divider()

            Text("REMINDERS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TaskStripTheme.amber)

            if reminders.isEmpty {
                Text("Nothing pending")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reminders) { reminder in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(reminder.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(reminder.triggerAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }

            Divider()

            HStack {
                Button("Open Task Strips") { openWindow(id: TaskStripsApp.boardWindowID) }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 320)
        .background(TaskStripTheme.bayBackground)
    }
}

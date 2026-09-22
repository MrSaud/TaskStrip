import SwiftUI
import WidgetKit

/// The board on the desktop, showing what the phone's home-screen widget shows: the top active
/// strips with their priority colour and due time, then the next few reminders.
struct BoardEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct BoardProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        completion(BoardEntry(date: .now, snapshot: WidgetSnapshot.read()))
    }

    /// One entry, refreshed on the hour.
    ///
    /// The app reloads this itself whenever the board changes, which is what actually keeps it
    /// current; the hourly entry is only so a widget on a Mac whose app hasn't run for a while
    /// still re-reads and re-renders its relative times rather than sitting frozen.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        let entry = BoardEntry(date: .now, snapshot: WidgetSnapshot.read())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct BoardWidgetView: View {
    var entry: BoardEntry

    private var strips: [WidgetSnapshot.Strip] {
        Array(entry.snapshot.strips.prefix(WidgetSnapshot.maxStrips))
    }

    private var reminders: [WidgetSnapshot.Reminder] {
        Array(entry.snapshot.reminders.prefix(WidgetSnapshot.maxReminders))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TASK STRIPS")
                .font(.caption.bold())
                .foregroundStyle(WidgetTheme.amber)

            if strips.isEmpty {
                Text("No active strips")
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.paper.opacity(0.5))
            } else {
                ForEach(strips) { strip in
                    HStack(spacing: 6) {
                        // The coloured holder down the left edge, same as a strip on the board.
                        RoundedRectangle(cornerRadius: 1)
                            .fill(WidgetTheme.color(forPriority: strip.priority))
                            .frame(width: 3)
                        Text(strip.title.uppercased())
                            .font(.caption)
                            .foregroundStyle(WidgetTheme.paper)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let due = strip.dueAt {
                            Text(WidgetTheme.due(due))
                                .font(.caption2.monospaced())
                                .foregroundStyle(WidgetTheme.paper.opacity(0.6))
                        }
                    }
                    .frame(height: 14)
                }
            }

            Divider().overlay(WidgetTheme.paper.opacity(0.2))

            if reminders.isEmpty {
                Text("No reminders")
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.paper.opacity(0.5))
            } else {
                ForEach(reminders) { reminder in
                    HStack(spacing: 6) {
                        Image(systemName: "bell")
                            .font(.caption2)
                            .foregroundStyle(WidgetTheme.amber.opacity(0.8))
                        Text(reminder.text)
                            .font(.caption)
                            .foregroundStyle(WidgetTheme.paper)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(WidgetTheme.due(reminder.triggerAt))
                            .font(.caption2.monospaced())
                            .foregroundStyle(WidgetTheme.paper.opacity(0.6))
                    }
                    .frame(height: 14)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .containerBackground(WidgetTheme.bayBackground, for: .widget)
    }
}

struct BoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.saud.taskstrip.mac.board", provider: BoardProvider()) { entry in
            BoardWidgetView(entry: entry)
        }
        .configurationDisplayName("Task Strips")
        .description("Your top active strips and the reminders coming up.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

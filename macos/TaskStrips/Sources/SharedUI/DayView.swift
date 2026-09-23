import EventKit
import SwiftData
import SwiftUI

/// What today is asking for, in one list: what's late, what's due, who's owed a chase, what's
/// just come back off deferral, and the reminders that go off before bedtime.
///
/// It holds nothing of its own — everything here is the board, read through DayPlan — so there's
/// no second copy of the truth to keep in step.
struct DayView: View {
    let tasks: [TaskItem]
    let reminders: [Reminder]
    var showsHeader = false
    let onEdit: (TaskItem) -> Void

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettingsKey.showCalendar) private var showCalendar = false
    @State private var now = Date.now
    @State private var events: [EKEvent] = []

    private var plan: DayPlan { DayPlan.make(tasks: tasks, reminders: reminders, now: now) }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader { header }
            if plan.isEmpty && events.isEmpty {
                empty
            } else {
                list
            }
        }
        .background(TaskStripTheme.bayBackground)
        // A board left open overnight should wake up to the new day rather than yesterday's.
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        .task(id: showCalendar) { await loadCalendar() }
        .onChange(of: now) { _, _ in Task { await loadCalendar() } }
    }

    /// Today's events, once the person has asked for them and the calendar has said yes.
    private func loadCalendar() async {
        guard showCalendar else {
            events = []
            return
        }
        let calendar = StripCalendar.shared
        if calendar.access == .unknown { _ = await calendar.requestReading() }
        events = calendar.today(now: now)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label("TODAY", systemImage: "sun.max")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TaskStripTheme.amber)
            Spacer(minLength: 0)
            if !plan.isEmpty {
                Text("\(plan.count)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(TaskStripTheme.baySurfaceFaded)
    }

    private var list: some View {
        List {
            section("LATE", plan.overdue, tint: TaskStripTheme.urgent)
            section("DUE TODAY", plan.due, tint: TaskStripTheme.amber)
            section("CHASE", plan.chase, tint: TaskStripTheme.high, subtitle: { "waiting on \($0.waitingOnName)" })
            section("BACK TODAY", plan.returning, tint: TaskStripTheme.low)

            if !events.isEmpty {
                Section {
                    ForEach(events, id: \.eventIdentifier) { event in
                        HStack(spacing: 10) {
                            Text(event.startDate.formatted(date: .omitted, time: .shortened))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(event.title ?? "")
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    heading("IN THE CALENDAR", tint: TaskStripTheme.low)
                }
            }

            if !plan.reminders.isEmpty {
                Section {
                    ForEach(plan.reminders) { reminder in
                        HStack(spacing: 10) {
                            Text(reminder.triggerAt.formatted(date: .omitted, time: .shortened))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(reminder.text)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    heading("REMINDERS", tint: TaskStripTheme.normal)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func section(
        _ title: String,
        _ strips: [TaskItem],
        tint: Color,
        subtitle: ((TaskItem) -> String)? = nil
    ) -> some View {
        if !strips.isEmpty {
            Section {
                ForEach(strips) { strip in
                    Button {
                        onEdit(strip)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(strip.title.uppercased())
                                    .font(.system(.callout, design: .monospaced))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if let due = strip.dueAt {
                                    Text(due.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(tint)
                                }
                            }
                            if let subtitle {
                                Text(subtitle(strip))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let steps = StripChecklist.summary(of: strip.checklist) {
                                Text("\(steps) steps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            _ = StripActions.toggleDone(strip, in: tasks, context: modelContext)
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .tint(TaskStripTheme.normal)
                    }
                }
            } header: {
                heading(title, tint: tint)
            }
        }
    }

    private func heading(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(tint)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("NOTHING DUE TODAY")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Nothing late, nobody to chase.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

import SwiftData
import SwiftUI

/// The iPhone board: Strips and Reminders as two pages under one fixed header, like Android.
///
/// The gesture rule, learned on Android the hard way: a strip may claim a swipe to the RIGHT
/// (mark it done) and nothing else. A swipe to the left must always reach the pager — so there
/// are no trailing swipe actions on the board, and delete lives in the editor behind a confirm.
struct BoardScreen: View {
    enum Page: Hashable { case strips, reminders }

    @State private var page: Page = .strips

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BoardPageTabs(page: $page)
                BoardPager(pages: [Page.strips, .reminders], selection: $page) { page in
                    switch page {
                    case .strips: StripsPage()
                    case .reminders: RemindersPage()
                    }
                }
            }
            .background(TaskStripTheme.bayBackground)
            .navigationTitle("Task Strips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(TaskStripTheme.bayBackground, for: .navigationBar)
        }
    }
}

private struct BoardPageTabs: View {
    @Binding var page: BoardScreen.Page

    var body: some View {
        HStack(spacing: 0) {
            tab("STRIPS", .strips)
            tab("REMINDERS", .reminders)
        }
        .background(TaskStripTheme.bayBackground)
    }

    private func tab(_ title: String, _ target: BoardScreen.Page) -> some View {
        Button {
            withAnimation { page = target }
        } label: {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(page == target ? TaskStripTheme.amber : TaskStripTheme.paper.opacity(0.5))
                Rectangle()
                    .fill(page == target ? TaskStripTheme.amber : .clear)
                    .frame(height: 2)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(page == target ? .isSelected : [])
    }
}

private struct StripsPage: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { !$0.isArchived && !$0.isTombstoned }, sort: \TaskItem.orderIndex)
    private var strips: [TaskItem]

    private var active: [TaskItem] { strips.filter { !$0.isDone } }
    private var completed: [TaskItem] { strips.filter(\.isDone) }

    var body: some View {
        List {
            ForEach(active) { strip in
                row(strip)
            }
            .onMove(perform: move)

            if !completed.isEmpty {
                Section {
                    ForEach(completed) { strip in
                        row(strip)
                    }
                } header: {
                    Text("COMPLETED")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(TaskStripTheme.paper.opacity(0.5))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if strips.isEmpty {
                ContentUnavailableView("No strips yet", systemImage: "rectangle.stack")
            }
        }
    }

    private func row(_ strip: TaskItem) -> some View {
        TaskRowView(task: strip, blocker: nil)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            // Leading only, and on purpose — see BoardScreen.
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    toggleDone(strip)
                } label: {
                    Label(strip.isDone ? "Reopen" : "Done",
                          systemImage: strip.isDone ? "arrow.uturn.backward" : "checkmark")
                }
                .tint(TaskStripTheme.normal)
            }
    }

    private func toggleDone(_ strip: TaskItem) {
        strip.isDone.toggle()
        strip.completedAt = strip.isDone ? .now : nil
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = active
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, strip) in reordered.enumerated() { strip.orderIndex = index }
    }
}

private struct RemindersPage: View {
    @Query(filter: #Predicate<Reminder> { !$0.isDone }, sort: \Reminder.triggerAt)
    private var reminders: [Reminder]

    var body: some View {
        List(reminders) { reminder in
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(TaskStripTheme.paper)
                Text(reminder.triggerAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(TaskStripTheme.amber)
            }
            .listRowBackground(TaskStripTheme.baySurface)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if reminders.isEmpty {
                ContentUnavailableView("No reminders", systemImage: "bell")
            }
        }
    }
}

#if DEBUG
/// Sample board for the simulator and the gesture prototype: `-SeedSampleBoard` at launch, and
/// only into an empty store, so it can never mix with real strips.
enum SampleBoard {
    static func seedIfAsked(into container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains("-SeedSampleBoard") else { return }
        let context = ModelContext(container)
        guard ((try? context.fetchCount(FetchDescriptor<TaskItem>())) ?? 0) == 0 else { return }
        let samples: [(String, Priority, Int, [String])] = [
            ("Renew passport", .urgent, 40, ["home"]),
            ("Quarterly report", .high, 70, ["work"]),
            ("Call the bank", .normal, 0, ["money"]),
            ("Fix bike brakes", .low, 10, []),
            ("Book dentist", .normal, 0, ["health"]),
        ]
        for (index, sample) in samples.enumerated() {
            let strip = TaskItem(title: sample.0, orderIndex: index, priority: sample.1)
            strip.progress = sample.2
            strip.tags = sample.3
            if index < 2 { strip.dueAt = Calendar.current.date(byAdding: .day, value: index, to: .now) }
            context.insert(strip)
        }
        context.insert(Reminder(text: "Take out recycling", triggerAt: .now.addingTimeInterval(3600)))
        context.insert(Reminder(text: "Pay rent", triggerAt: .now.addingTimeInterval(86_400 * 3)))
        try? context.save()
    }
}
#endif

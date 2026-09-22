import SwiftData
import SwiftUI

/// The iPhone board: Strips and Reminders as two pages under one fixed header, like Android.
///
/// The gesture rule, learned on Android the hard way: a strip may claim a swipe to the RIGHT
/// (mark it done) and nothing else. A swipe to the left must always reach the pager — so there
/// are no trailing swipe actions on the board, and delete lives in the editor and in a completed
/// strip's menu, behind a confirm.
struct BoardScreen: View {
    enum Page: Hashable { case strips, reminders }

    /// Everything else in the app, one sheet at a time, from the board's menu.
    enum Destination: String, Identifiable, CaseIterable {
        case archive, notes, credentials, storage, sketches, standup, tags, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .archive: "Archive"
            case .notes: "Notes"
            case .credentials: "Credentials"
            case .storage: "Storage Library"
            case .sketches: "Sketches"
            case .standup: "Standup"
            case .tags: "Tag Progress"
            case .settings: "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .archive: "archivebox"
            case .notes: "note.text"
            case .credentials: "key"
            case .storage: "folder"
            case .sketches: "scribble"
            case .standup: "list.bullet.clipboard"
            case .tags: "chart.bar"
            case .settings: "gear"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { !$0.isTombstoned }, sort: \TaskItem.orderIndex)
    private var allTasks: [TaskItem]

    @AppStorage(AppSettingsKey.defaultPriority) private var defaultPriority = Priority.normal
    @AppStorage(AppSettingsKey.defaultNotesRtl) private var defaultNotesRtl = false
    @AppStorage(AppSettingsKey.showQuote) private var showQuote = true
    @State private var quote: Quote?
    @State private var now = Date.now

    @State private var page: Page = .strips
    @State private var search = ""
    @State private var editing: TaskItem?
    @State private var isCreating = false
    @State private var destination: Destination?
    @State private var isBackingUp = false
    @State private var isRestoring = false

    private var boardTasks: [TaskItem] { allTasks.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed, like Android's: today's date belongs to both pages. A plain line on a
                // minute timer rather than a TimelineView: in this layout (above the pager, under
                // a navigation bar with search) a TimelineView sent SwiftUI into an endless
                // layout pass — 100% CPU and a blank screen.
                Text(BoardCalendars.headerText(now))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(TaskStripTheme.baySurfaceFaded)
                    .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
                if showQuote, let quote {
                    QuoteOfDayCard(quote: quote)
                }
                BoardPageTabs(page: $page)
                BoardPager(pages: [Page.strips, .reminders], selection: $page) { page in
                    switch page {
                    case .strips:
                        StripsPage(
                            strips: boardTasks,
                            allTasks: allTasks,
                            search: search,
                            onEdit: { editing = $0 }
                        )
                    case .reminders:
                        RemindersView(isEmbedded: true, isActive: self.page == .reminders)
                    }
                }
            }
            .background(TaskStripTheme.bayBackground)
            .navigationTitle("Task Strips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(TaskStripTheme.bayBackground, for: .navigationBar)
            .searchable(if: page == .strips, text: $search, prompt: "Search strips")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { menu }
                if page == .strips {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isCreating = true
                        } label: {
                            Label("New strip", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(item: $editing) { task in
                NavigationStack {
                    TaskEditView(
                        editingTask: task,
                        allTasks: allTasks,
                        nextOrderIndex: StripActions.nextOrderIndex(in: allTasks),
                        onSaved: {},
                        onDeleted: { StripActions.releaseBlocked(by: task.id, in: allTasks) }
                    )
                }
            }
            .sheet(isPresented: $isCreating) {
                NavigationStack {
                    TaskEditView(
                        editingTask: nil,
                        allTasks: allTasks,
                        nextOrderIndex: StripActions.nextOrderIndex(in: allTasks),
                        defaultPriority: defaultPriority,
                        defaultNotesRtl: defaultNotesRtl,
                        onSaved: {},
                        onDeleted: {}
                    )
                }
            }
            .sheet(item: $destination) { destination in
                NavigationStack {
                    screen(for: destination)
                }
            }
            .modifier(BoardBackup(isBackingUp: $isBackingUp, isRestoring: $isRestoring))
            .task {
                ReminderScheduler.shared.sync(allTasks)
                if showQuote { quote = await QuoteOfTheDay.today() }
            }
        }
    }

    private var menu: some View {
        Menu {
            ForEach(Destination.allCases) { item in
                Button {
                    destination = item
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
            }
            Divider()
            Button {
                isBackingUp = true
            } label: {
                Label("Back Up…", systemImage: "arrow.up.doc")
            }
            Button {
                isRestoring = true
            } label: {
                Label("Restore…", systemImage: "arrow.down.doc")
            }
        } label: {
            Label("Menu", systemImage: "line.3.horizontal")
        }
    }

    @ViewBuilder
    private func screen(for destination: Destination) -> some View {
        switch destination {
        case .archive:
            ArchivedTasksView(
                tasks: allTasks.filter(\.isArchived),
                onUnarchive: { StripActions.unarchive($0, in: allTasks) }
            )
        case .notes:
            NotesView(nextOrderIndex: { StripActions.nextOrderIndex(in: allTasks) })
        case .credentials:
            CredentialsView()
        case .storage:
            StorageLibraryView()
        case .sketches:
            SketchListView()
        case .standup:
            // The board, not every strip: an archived strip is neither work done today nor a
            // blocker, which is how Android's roll-ups read it too.
            RollUpsView(showing: .standup, tasks: boardTasks)
        case .tags:
            RollUpsView(showing: .tags, tasks: boardTasks)
        case .settings:
            // The Mac's Settings is its own window with no Done button; a sheet needs one.
            SettingsView()
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { self.destination = nil }
                    }
                }
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
    let strips: [TaskItem]
    let allTasks: [TaskItem]
    let search: String
    let onEdit: (TaskItem) -> Void

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettingsKey.confirmBeforeDelete) private var confirmBeforeDelete = true
    @State private var blockedBy: TaskItem?
    @State private var pendingArchive: TaskItem?
    @State private var pendingDeletion: TaskItem?

    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private var visible: [TaskItem] {
        guard !query.isEmpty else { return strips }
        return strips.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var active: [TaskItem] { visible.filter { !$0.isDone } }
    private var completed: [TaskItem] { visible.filter(\.isDone) }

    var body: some View {
        List {
            ForEach(active) { strip in
                row(strip)
            }
            // A filtered list has gaps, and dragging within it would renumber the board around
            // strips that aren't showing — the Mac turns reordering off for the same reason.
            .onMove(perform: query.isEmpty ? move : nil)

            if !completed.isEmpty {
                Section {
                    ForEach(completed) { strip in
                        row(strip)
                            // Only finished strips get a menu: on an active one a long press
                            // is the start of a drag to reorder.
                            .contextMenu {
                                Button {
                                    pendingArchive = strip
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                Button(role: .destructive) {
                                    requestDelete(strip)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
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
                ContentUnavailableView("No strips yet", systemImage: "rectangle.stack",
                                       description: Text("Tap + to file one."))
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .alert(
            "Blocked",
            isPresented: Binding(get: { blockedBy != nil }, set: { if !$0 { blockedBy = nil } }),
            presenting: blockedBy
        ) { _ in
            Button("OK") {}
        } message: { blocker in
            Text("Blocked by \"\(blocker.title)\" — finish that one first.")
        }
        .confirmationDialog(
            "Archive \"\(pendingArchive?.title ?? "")\"?",
            isPresented: Binding(get: { pendingArchive != nil }, set: { if !$0 { pendingArchive = nil } }),
            titleVisibility: .visible
        ) {
            Button("Archive") {
                if let strip = pendingArchive { StripActions.archive(strip) }
                pendingArchive = nil
            }
        } message: {
            Text("It leaves the board and stays in the Archive.")
        }
        .confirmationDialog(
            "Delete \"\(pendingDeletion?.title ?? "")\"?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let strip = pendingDeletion { delete(strip) }
                pendingDeletion = nil
            }
        } message: {
            Text("Deleting a strip is permanent. Archiving keeps it.")
        }
    }

    private func row(_ strip: TaskItem) -> some View {
        TaskRowView(task: strip, blocker: StripActions.blocker(for: strip, in: allTasks))
            .contentShape(Rectangle())
            .onTapGesture { onEdit(strip) }
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
        if case .blocked(let blocker) = StripActions.toggleDone(strip, in: allTasks, context: modelContext) {
            blockedBy = blocker
        }
    }

    private func requestDelete(_ strip: TaskItem) {
        if confirmBeforeDelete { pendingDeletion = strip } else { delete(strip) }
    }

    private func delete(_ strip: TaskItem) {
        StripActions.delete(strip, in: allTasks, context: modelContext)
    }

    private func move(from source: IndexSet, to destination: Int) {
        BoardOrdering.move(from: source, to: destination, in: active)
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

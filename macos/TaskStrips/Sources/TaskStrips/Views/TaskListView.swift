import SwiftUI
import SwiftData

// Mirrors ui/screens/HomeScreen.kt's "The Board" list at the concept level: search, tag filter,
// due-date range filter, a progress sort toggle, and manual drag-reorder when no filter/sort
// override is active (mirroring FlightStripRow's swipe-to-complete/swipe-to-delete + drag reorder).
enum ProgressSort: String, CaseIterable, Identifiable {
    case manual = "Manual order"
    case progressAscending = "Progress ↑"
    case progressDescending = "Progress ↓"
    var id: String { rawValue }
}

struct TaskListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.orderIndex) private var allTasks: [TaskItem]

    @State private var searchText = ""
    @State private var tagFilter: String?
    @State private var sortMode: ProgressSort = .manual
    @State private var dueFrom: Date?
    @State private var dueTo: Date?
    @State private var showDateFilter = false
    @State private var editingTask: TaskItem?
    @State private var isPresentingNewTask = false
    @State private var showArchive = false
    @State private var blockedAlertTask: TaskItem?

    private var activeTasks: [TaskItem] { allTasks.filter { !$0.isArchived } }

    private var availableTags: [String] {
        Array(Set(activeTasks.flatMap(\.tags))).sorted()
    }

    private var filtered: [TaskItem] {
        var result = activeTasks
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmedSearch.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(trimmedSearch) }
        }
        if let tag = tagFilter {
            result = result.filter { $0.tags.contains(tag) }
        }
        if dueFrom != nil || dueTo != nil {
            result = result.filter { task in
                guard let due = task.dueAt else { return false }
                if let from = dueFrom, due < from { return false }
                if let to = dueTo, due > to { return false }
                return true
            }
        }
        switch sortMode {
        case .manual: break
        case .progressAscending: result.sort { $0.progress < $1.progress }
        case .progressDescending: result.sort { $0.progress > $1.progress }
        }
        return result
    }

    private var canReorder: Bool {
        sortMode == .manual && tagFilter == nil && dueFrom == nil && dueTo == nil
            && searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func blocker(for task: TaskItem) -> TaskItem? {
        guard let id = task.blockedByID else { return nil }
        return allTasks.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            List {
                if canReorder {
                    ForEach(filtered) { task in
                        row(for: task)
                    }
                    .onMove(perform: move)
                } else {
                    ForEach(filtered) { task in
                        row(for: task)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(TaskStripTheme.bayBackground)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search strips")
            .navigationTitle("THE BOARD")
            .toolbar { toolbarContent }
            .sheet(item: $editingTask) { task in
                NavigationStack {
                    TaskEditView(
                        editingTask: task,
                        allTasks: allTasks,
                        nextOrderIndex: nextOrderIndex(),
                        onSaved: {},
                        onDeleted: { cleanUpDanglingBlockers(deletedID: task.id) }
                    )
                }
            }
            .sheet(isPresented: $isPresentingNewTask) {
                NavigationStack {
                    TaskEditView(
                        editingTask: nil,
                        allTasks: allTasks,
                        nextOrderIndex: nextOrderIndex(),
                        onSaved: {},
                        onDeleted: {}
                    )
                }
            }
            .sheet(isPresented: $showArchive) {
                NavigationStack {
                    ArchivedTasksView(tasks: allTasks.filter(\.isArchived))
                }
            }
            .popover(isPresented: $showDateFilter) {
                DateRangeFilterView(from: $dueFrom, to: $dueTo)
            }
            .alert(item: $blockedAlertTask) { task in
                Alert(
                    title: Text("Blocked"),
                    message: Text("Blocked by \"\(blocker(for: task)?.title ?? "")\""),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    @ViewBuilder
    private func row(for task: TaskItem) -> some View {
        Button {
            editingTask = task
        } label: {
            TaskRowView(task: task, blocker: blocker(for: task))
        }
        .buttonStyle(.plain)
        // Swipe gestures need an actual trackpad and expose no accessibility action, so a
        // mouse-only user (or VoiceOver) would have no way to reach these at all — the context
        // menu is the primary, always-reachable path; swipe is left as a trackpad-only shortcut
        // on top of it, not the only way in.
        .contextMenu {
            Button {
                toggleDone(task)
            } label: {
                Label(task.isDone ? "Reopen" : "Complete", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
            }
            Button {
                task.isArchived = true
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive) {
                delete(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                toggleDone(task)
            } label: {
                Label(task.isDone ? "Reopen" : "Complete", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(TaskStripTheme.normal)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                task.isArchived = true
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.gray)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigation) {
                Button {
                    showArchive = true
                } label: {
                    Label("Archived", systemImage: "archivebox")
                }
            }
            ToolbarItem {
                Menu {
                    Button("All tags") { tagFilter = nil }
                    ForEach(availableTags, id: \.self) { tag in
                        Button(tag) { tagFilter = tag }
                    }
                } label: {
                    Label("Tag filter", systemImage: tagFilter == nil ? "tag" : "tag.fill")
                }
                .disabled(availableTags.isEmpty)
            }
            ToolbarItem {
                Button {
                    showDateFilter = true
                } label: {
                    Label("Due date filter", systemImage: (dueFrom != nil || dueTo != nil) ? "calendar.badge.checkmark" : "calendar")
                }
            }
            ToolbarItem {
                Menu {
                    ForEach(ProgressSort.allCases) { mode in
                        Button {
                            sortMode = mode
                        } label: {
                            if sortMode == mode {
                                Label(mode.rawValue, systemImage: "checkmark")
                            } else {
                                Text(mode.rawValue)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
            ToolbarItem {
                Button {
                    isPresentingNewTask = true
                } label: {
                    Label("New strip", systemImage: "plus")
                }
            }
        }
    }

    private func nextOrderIndex() -> Int {
        (allTasks.map(\.orderIndex).max() ?? -1) + 1
    }

    private func toggleDone(_ task: TaskItem) {
        if !task.isDone, let blockerTask = blocker(for: task), !blockerTask.isDone {
            blockedAlertTask = task
            return
        }
        task.isDone.toggle()
        task.completedAt = task.isDone ? .now : nil
    }

    private func delete(_ task: TaskItem) {
        let id = task.id
        modelContext.delete(task)
        cleanUpDanglingBlockers(deletedID: id)
    }

    private func cleanUpDanglingBlockers(deletedID: UUID) {
        for task in allTasks where task.blockedByID == deletedID {
            task.blockedByID = nil
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = filtered
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, task) in reordered.enumerated() {
            task.orderIndex = index
        }
    }
}

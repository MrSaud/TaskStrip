import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var importSummary: BackupImportSummary?
    @State private var importMessage: ImportMessage?
    @State private var selectedTaskID: TaskItem.ID?
    @State private var pendingDeletion: TaskItem?

    @AppStorage(AppSettingsKey.defaultPriority) private var defaultPriority = Priority.normal
    @AppStorage(AppSettingsKey.defaultNotesRtl) private var defaultNotesRtl = false
    @AppStorage(AppSettingsKey.confirmBeforeDelete) private var confirmBeforeDelete = true

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
            VStack(spacing: 0) {
                reorderNotice
                board
            }
        }
    }

    private var selectedTask: TaskItem? {
        filtered.first { $0.id == selectedTaskID }
    }

    private var board: some View {
        List(selection: $selectedTaskID) {
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
                        defaultPriority: defaultPriority,
                        defaultNotesRtl: defaultNotesRtl,
                        onSaved: {},
                        onDeleted: {}
                    )
                }
            }
            .sheet(isPresented: $showArchive) {
                NavigationStack {
                    ArchivedTasksView(
                        tasks: allTasks.filter(\.isArchived),
                        onUnarchive: { task in
                            // Renumbering only ever walks the strips on the board, so this one's
                            // orderIndex is whatever it held before it was archived — it would
                            // reappear at some arbitrary spot mid-board. Send it to the bottom.
                            task.orderIndex = nextOrderIndex()
                            task.isArchived = false
                        }
                    )
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
            .sheet(item: $importSummary) { summary in
                ImportBackupSheet(
                    summary: summary,
                    existingCount: allTasks.count,
                    onImport: { mode in performImport(summary, mode: mode) },
                    onCancel: { importSummary = nil }
                )
            }
            .alert(item: $importMessage) { message in
                Alert(title: Text(message.title), message: Text(message.body), dismissButton: .default(Text("OK")))
            }
            .confirmationDialog(
                "Delete \"\(pendingDeletion?.title ?? "")\"?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let task = pendingDeletion { delete(task) }
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("Deleting a strip is permanent. Archiving keeps it.")
            }
            .focusedSceneValue(\.boardCommands, commandTarget)
    }

    /// Hands the menu bar everything it can act on. Rebuilt whenever the board changes, so the
    /// closures always close over the current selection rather than a stale one.
    private var commandTarget: BoardCommandTarget {
        BoardCommandTarget(
            newStrip: { isPresentingNewTask = true },
            importBackup: chooseBackupFile,
            showArchived: { showArchive = true },
            clearFilters: clearFilters,
            isFiltered: !canReorder,
            sortMode: sortMode,
            setSortMode: { sortMode = $0 },
            selection: selectedTask.map { task in
                SelectedStripCommands(
                    isDone: task.isDone,
                    edit: { editingTask = task },
                    toggleDone: { toggleDone(task) },
                    archive: { archive(task) },
                    delete: { requestDelete(task) },
                    canMove: { canReorder && BoardOrdering.canMove(task, $0, in: filtered) },
                    move: { _ = BoardOrdering.move(task, $0, in: filtered) }
                )
            }
        )
    }

    /// Says why drag-reorder went away, and offers the way back.
    ///
    /// `canReorder` silently switching off whenever the board is filtered or sorted reads as the
    /// feature being broken rather than suspended — there's nothing on screen tying the two
    /// together.
    @ViewBuilder
    private var reorderNotice: some View {
        if !canReorder {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(TaskStripTheme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reorderNoticeText)
                        .font(.callout)
                    Text("Reordering is off until the whole board is showing in manual order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Show All", action: clearFilters)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TaskStripTheme.baySurface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(TaskStripTheme.bayBackground)
                    .frame(height: 1)
            }
        }
    }

    private var reorderNoticeText: String {
        filtered.count < activeTasks.count
            ? "Showing \(filtered.count) of \(activeTasks.count) strips — \(activeFilterSummary)."
            : "This board is \(activeFilterSummary)."
    }

    /// Reads back what's actually narrowing the board, so "Show All" is an obvious undo rather
    /// than a guess at which of four controls is the culprit.
    private var activeFilterSummary: String {
        var parts: [String] = []
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmedSearch.isEmpty { parts.append("matching \"\(trimmedSearch)\"") }
        if let tag = tagFilter { parts.append("tagged \(tag)") }
        if dueFrom != nil || dueTo != nil { parts.append("filtered by due date") }
        if sortMode != .manual { parts.append("sorted by \(sortMode.rawValue.lowercased())") }
        return parts.isEmpty ? "filtered" : parts.formatted(.list(type: .and))
    }

    private func clearFilters() {
        searchText = ""
        tagFilter = nil
        dueFrom = nil
        dueTo = nil
        sortMode = .manual
    }

    @ViewBuilder
    private func row(for task: TaskItem) -> some View {
        TaskRowView(task: task, blocker: blocker(for: task))
            // Now that the List carries a selection, rows follow the Mac convention: one click
            // picks the strip — which is what lights up the Strip menu — and two open it. 991191a
            // wrapped the row in a Button because a bare .onTapGesture wouldn't reliably open the
            // editor; if that still bites, Edit in the context menu and cmd-E both still do.
            .contentShape(Rectangle())
            // Both taps are explicit because CI proved the single click wasn't getting through:
            // .onTapGesture(count: 2) alone swallows it while it waits to see whether a second
            // click is coming, so the row never became selected, and everything hanging off
            // selection — the whole Strip menu, cmd-E — stayed dead. Setting selection here
            // rather than leaving it to the List is what makes the click land.
            .onTapGesture(count: 2) { editingTask = task }
            .onTapGesture(count: 1) { selectedTaskID = task.id }
            .tag(task.id)
        // Swipe gestures need an actual trackpad and expose no accessibility action, so a
        // mouse-only user (or VoiceOver) would have no way to reach these at all — the context
        // menu is the primary, always-reachable path; swipe is left as a trackpad-only shortcut
        // on top of it, not the only way in.
        .contextMenu {
            Button {
                editingTask = task
            } label: {
                Label("Edit…", systemImage: "square.and.pencil")
            }
            Divider()
            Button {
                toggleDone(task)
            } label: {
                Label(task.isDone ? "Reopen" : "Complete", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
            }
            Button {
                archive(task)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Divider()
            // Drag-reorder needs a real trackpad gesture and offers nothing to VoiceOver, exactly
            // like the swipe actions did — so the menu carries the same moves as a reachable path.
            ForEach(BoardMove.allCases, id: \.self) { move in
                Button {
                    _ = BoardOrdering.move(task, move, in: filtered)
                } label: {
                    Label(move.label, systemImage: move.systemImage)
                }
                .disabled(!canReorder || !BoardOrdering.canMove(task, move, in: filtered))
            }
            if !canReorder {
                Text("Reordering is off while the board is filtered or sorted")
            }
            Divider()
            Button(role: .destructive) {
                requestDelete(task)
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
                requestDelete(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                archive(task)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.gray)
        }
        .listRowBackground(
            selectedTaskID == task.id ? TaskStripTheme.amber.opacity(0.18) : Color.clear
        )
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
                    chooseBackupFile()
                } label: {
                    Label("Import Android backup", systemImage: "square.and.arrow.down")
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

    private func archive(_ task: TaskItem) {
        task.isArchived = true
        if selectedTaskID == task.id { selectedTaskID = nil }
    }

    /// Deleting a strip is permanent and there's no undo, so the board asks first unless the user
    /// has turned that off — the edit sheet has always confirmed, and the board's own delete
    /// (context menu, swipe, and now cmd-delete) shouldn't be the one quiet exception.
    private func requestDelete(_ task: TaskItem) {
        if confirmBeforeDelete {
            pendingDeletion = task
        } else {
            delete(task)
        }
    }

    private func delete(_ task: TaskItem) {
        let id = task.id
        if selectedTaskID == id { selectedTaskID = nil }
        modelContext.delete(task)
        cleanUpDanglingBlockers(deletedID: id)
    }

    private func cleanUpDanglingBlockers(deletedID: UUID) {
        for task in allTasks where task.blockedByID == deletedID {
            task.blockedByID = nil
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        BoardOrdering.move(from: source, to: destination, in: filtered)
    }

    // MARK: - Android backup import

    private func chooseBackupFile() {
        guard importSummary == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Read Backup"
        panel.message = "Choose a TaskStrip backup exported from Android (taskstrip_backup_*.zip), "
            + "or a backup.json unzipped from one."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            importSummary = try BackupImport.parse(manifest: BackupArchive.manifestData(at: url))
        } catch {
            importMessage = ImportMessage(
                title: "Couldn't read that backup",
                body: error.localizedDescription
            )
        }
    }

    private func performImport(_ summary: BackupImportSummary, mode: ImportMode) {
        let replaced = mode == .replace ? allTasks.count : 0
        let imported = BackupImport.apply(
            summary.tasks,
            mode: mode,
            existing: allTasks,
            context: modelContext
        )
        importSummary = nil

        // SwiftData autosaves, but a failure here is exactly the silent-save class of bug that bit
        // Phase 1 — an import that quietly wrote nothing would look identical to an empty backup.
        let result: ImportMessage
        do {
            try modelContext.save()
            result = ImportMessage(
                title: "Import complete",
                body: mode == .replace
                    ? "Replaced \(replaced) strip\(replaced == 1 ? "" : "s") with \(imported) from the backup."
                    : "Added \(imported) strip\(imported == 1 ? "" : "s") to the board."
            )
        } catch {
            result = ImportMessage(
                title: "Import failed",
                body: "The strips couldn't be saved: \(error.localizedDescription)"
            )
        }

        // Raising the alert in the same update that dismisses the sheet can swallow it — let the
        // sheet finish going away first.
        DispatchQueue.main.async { importMessage = result }
    }
}

/// Alert payload — `.alert(item:)` needs something Identifiable, and a bare String isn't.
struct ImportMessage: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

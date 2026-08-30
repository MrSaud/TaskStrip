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
    /// Only needed so a Replace import knows what it's clearing — the notes sheet runs its own
    /// query.
    @Query private var allNotes: [Note]
    /// Same reason as the notes above: a Replace import needs to know what it's clearing.
    @Query private var allStorageItems: [StorageItem]
    /// Same again for the standalone reminders.
    @Query private var allReminders: [Reminder]
    /// And the credentials, whose passwords a Replace has to clear from the keychain as well.
    @Query private var allCredentials: [Credential]

    @State private var searchText = ""
    @State private var tagFilter: String?
    @State private var sortMode: ProgressSort = .manual
    @State private var dueFrom: Date?
    @State private var dueTo: Date?
    @State private var showDateFilter = false
    @State private var editingTask: TaskItem?
    @State private var isPresentingNewTask = false
    @State private var isCapturingVoice = false
    @State private var showArchive = false
    @State private var showNotes = false
    @State private var showStorage = false
    @State private var showReminders = false
    @State private var showCredentials = false
    @State private var rollUp: RollUp?
    @State private var blockedAlertTask: TaskItem?
    @State private var importSummary: BackupImportSummary?
    @State private var importMessage: ImportMessage?
    @State private var isExporting = false
    @State private var showDrive = false
    @State private var progress: BackupProgress?
    @ObservedObject private var reader = SpeechReader.shared
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
                dateHeader
                reorderNotice
                board
            }
        }
    }

    /// Today in both calendars, with how long each month runs.
    ///
    /// Rebuilt every minute rather than once: a board left open overnight would otherwise still
    /// be showing yesterday, which is worse than showing nothing.
    private var dateHeader: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(BoardCalendars.headerText(context.date))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(TaskStripTheme.baySurfaceFaded)
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
            .sheet(item: $rollUp) { rollUp in
                NavigationStack {
                    // The board, not every strip: an archived strip is neither work done today
                    // nor a blocker, which is how Android's roll-ups read it too.
                    RollUpsView(showing: rollUp, tasks: activeTasks)
                }
            }
            .sheet(isPresented: $showCredentials) {
                NavigationStack {
                    CredentialsView()
                }
            }
            .sheet(isPresented: $showReminders) {
                NavigationStack {
                    RemindersView()
                }
            }
            .sheet(isPresented: $showStorage) {
                NavigationStack {
                    StorageLibraryView()
                }
            }
            .sheet(isPresented: $showNotes) {
                NavigationStack {
                    NotesView(nextOrderIndex: nextOrderIndex)
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
            .sheet(isPresented: Binding(
                get: { progress != nil },
                set: { if !$0 { progress = nil } }
            )) {
                if let progress { BackupProgressView(progress: progress) }
            }
            .sheet(isPresented: $isCapturingVoice) {
                VoiceCaptureSheet(
                    onFile: { draft in
                        isCapturingVoice = false
                        fileVoiceDraft(draft)
                    },
                    onCancel: { isCapturingVoice = false }
                )
            }
            .sheet(isPresented: $showDrive) {
                DriveBackupsView(contents: exportContents, onRestore: readDriveArchive)
            }
            .sheet(isPresented: $isExporting) {
                ExportBackupSheet(
                    contents: exportContents,
                    onExport: { passphrase in
                        isExporting = false
                        exportBackup(passphrase: passphrase)
                    },
                    onCancel: { isExporting = false }
                )
            }
            .sheet(item: $importSummary) { summary in
                ImportBackupSheet(
                    summary: summary,
                    existingCount: allTasks.count,
                    onImport: { mode, passphrase in
                        performImport(summary, mode: mode, passphrase: passphrase)
                    },
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
            .task { ReminderScheduler.shared.sync(allTasks) }
            .focusedSceneValue(\.boardCommandState, commandState)
            .onChange(of: commandState, initial: true) { publishCommandActions() }
    }

    /// What the menu bar reads. Plain data, so SwiftUI can tell one value from the next — see the
    /// note on BoardCommandState for why that matters.
    private var commandState: BoardCommandState {
        BoardCommandState(
            selectedID: selectedTaskID,
            selectionIsDone: selectedTask?.isDone ?? false,
            selectionHasNotes: selectedTask.flatMap(SpeechReader.speech(for:)) != nil,
            availableMoves: selectedTask.map { task in
                Set(BoardMove.allCases.filter { canReorder && BoardOrdering.canMove(task, $0, in: filtered) })
            } ?? [],
            isFiltered: !canReorder,
            sortMode: sortMode,
            visibleIDs: filtered.map(\.id)
        )
    }

    /// What the menu bar runs. Republished whenever the state above changes, which covers a new
    /// selection and a reordered board alike; the menu items hold a closure over BoardActions
    /// rather than over any of this, so a menu item SwiftUI never refreshed still acts on what's
    /// selected now.
    private func publishCommandActions() {
        let actions = BoardActions.shared
        actions.newStrip = { isPresentingNewTask = true }
        actions.newStripByVoice = { isCapturingVoice = true }
        actions.readSelectionAloud = {
            guard let task = selectedTask, let speech = SpeechReader.speech(for: task) else { return }
            SpeechReader.shared.toggle(speech, id: task.id)
        }
        actions.importBackup = { chooseBackupFile() }
        actions.exportBackup = { isExporting = true }
        actions.showDrive = { showDrive = true }
        actions.showArchived = { showArchive = true }
        actions.showNotes = { showNotes = true }
        actions.showStorage = { showStorage = true }
        actions.showReminders = { showReminders = true }
        actions.showCredentials = { showCredentials = true }
        actions.showRollUp = { rollUp = $0 }
        actions.clearFilters = { clearFilters() }
        actions.setSortMode = { sortMode = $0 }

        guard let task = selectedTask else {
            actions.clearSelectionActions()
            return
        }
        let visible = filtered
        let reorderable = canReorder
        actions.editSelection = { editingTask = task }
        actions.toggleSelectionDone = { toggleDone(task) }
        actions.archiveSelection = { archive(task) }
        actions.deleteSelection = { requestDelete(task) }
        actions.moveSelection = { move in
            guard reorderable else { return }
            _ = BoardOrdering.move(task, move, in: visible)
        }
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
            if let speech = SpeechReader.speech(for: task) {
                Button {
                    reader.toggle(speech, id: task.id)
                } label: {
                    Label(
                        reader.isSpeaking(task.id) ? "Stop Reading" : "Read Notes Aloud",
                        systemImage: reader.isSpeaking(task.id) ? "stop.circle" : "speaker.wave.2"
                    )
                }
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

    /// Split in two because SwiftUI's builders top out at ten children, and the second list of
    /// places to go pushed this past it. Nesting groups is the fix; the order on screen is
    /// unchanged.
    private var toolbarContent: some ToolbarContent {
        Group {
            placesToolbarItems
            boardToolbarItems
        }
    }

    /// The other places the app keeps things, none of which are the board.
    private var placesToolbarItems: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigation) {
                Button {
                    showArchive = true
                } label: {
                    Label("Archived", systemImage: "archivebox")
                }
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    showNotes = true
                } label: {
                    Label("Quick notes", systemImage: "note.text")
                }
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    showStorage = true
                } label: {
                    Label("Storage library", systemImage: "tray.full")
                }
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    showReminders = true
                } label: {
                    Label("Reminders", systemImage: "bell")
                }
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    showCredentials = true
                } label: {
                    Label("Credentials", systemImage: "key")
                }
            }
            ToolbarItem(placement: .navigation) {
                Menu {
                    ForEach(RollUp.allCases) { item in
                        Button(item.rawValue) { rollUp = item }
                    }
                } label: {
                    Label("Roll-ups", systemImage: "chart.bar.doc.horizontal")
                }
            }
        }
    }

    /// What acts on the board itself: what's shown, in what order, and adding to it.
    private var boardToolbarItems: some ToolbarContent {
        Group {
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

    /// Files what the voice sheet handed back. It arrives already reviewed, so this is an
    /// ordinary insert — the same one the editor does.
    private func fileVoiceDraft(_ draft: VoiceDraft) {
        let task = TaskItem(
            title: draft.title,
            orderIndex: nextOrderIndex(),
            priority: draft.priority ?? defaultPriority
        )
        task.notes = draft.notes
        task.notesRtl = defaultNotesRtl
        modelContext.insert(task)
        selectedTaskID = task.id
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

        // Completing a repeating strip spawns the next one rather than rolling this one forward,
        // so the finished occurrence stays as history — Android's choice, and the reason "what did
        // I finish last week" keeps working.
        if task.isDone, let next = ReminderPlan.nextOccurrence(completing: task, orderIndex: nextOrderIndex()) {
            modelContext.insert(next)
            ReminderScheduler.shared.schedule(for: next)
        }
        // Covers both directions: completing clears the pending reminder, reopening restores it.
        ReminderScheduler.shared.schedule(for: task)
    }

    private func archive(_ task: TaskItem) {
        task.isArchived = true
        if selectedTaskID == task.id { selectedTaskID = nil }
        ReminderScheduler.shared.schedule(for: task)
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
        // The strip's files go with it — nothing else points at them, and leaving them behind
        // would grow the media folder forever.
        for attachment in task.attachments { AttachmentStore.shared.remove(attachment) }
        ReminderScheduler.shared.cancel(taskID: id)
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

    // MARK: - Export

    /// Everything the app holds, archived ones included — a backup is the whole state, not the
    /// visible part of it.
    private var exportContents: BackupExport.Contents {
        BackupExport.Contents(
            tasks: allTasks,
            notes: allNotes,
            storageItems: allStorageItems,
            reminders: allReminders,
            credentials: allCredentials
        )
    }

    /// A backup pulled off Drive goes through exactly the same door as one picked off disk: the
    /// summary sheet, the add-or-replace choice, the passphrase field. The only difference is
    /// where the bytes came from.
    ///
    /// Written to a temp file first because restoring the media reads the archive from a URL —
    /// and because a multi-gigabyte backup shouldn't be held in memory twice.
    private func readDriveArchive(_ archive: Data) {
        do {
            let url = FileManager.default.temporaryDirectory
                .appending(path: "TaskStrips-drive-\(UUID().uuidString).zip")
            try archive.write(to: url)
            var summary = try BackupImport.parse(manifest: BackupArchive.manifestData(inArchive: archive))
            summary.sourceURL = url
            importSummary = summary
        } catch {
            importMessage = ImportMessage(
                title: "Couldn't read that backup",
                body: error.localizedDescription
            )
        }
    }

    private func exportBackup(passphrase: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = BackupExport.suggestedFileName()
        panel.prompt = "Export"
        panel.message = "Where should the backup go?"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            // The manifest reads the board, so it has to be built here; packing the files is
            // nothing but paths and bytes, so that part goes elsewhere and the window stays alive.
            var passwordsIncluded = 0
            let manifest = try BackupExport.manifestData(
                exportContents,
                passphrase: passphrase,
                credentialStore: .shared,
                passwordsIncluded: &passwordsIncluded
            )
            let paths = BackupExport.mediaPaths(exportContents, store: .shared)
            let strips = exportContents.tasks.count
            progress = BackupProgress(
                title: "Writing the backup",
                step: paths.isEmpty ? "Packing" : "Packing files",
                completed: 0,
                total: paths.count
            )

            Task {
                var result = await Task.detached {
                    BackupExport.archive(
                        manifest: manifest,
                        mediaPaths: paths,
                        store: .shared,
                        progress: { done, total in
                            DispatchQueue.main.async {
                                progress?.completed = done
                                progress?.total = total
                            }
                        }
                    )
                }.value
                result.passwordsIncluded = passwordsIncluded
                progress = nil
                finishExport(result, to: url, strips: strips)
            }
        } catch {
            progress = nil
            importMessage = ImportMessage(
                title: "Couldn't write the backup",
                body: error.localizedDescription
            )
        }
    }

    private func finishExport(_ result: BackupExport.Result, to url: URL, strips: Int) {
        do {
            try result.archive.write(to: url)

            var body = "Wrote \(strips) strip"
                + "\(strips == 1 ? "" : "s") and \(result.fileCount) file"
                + "\(result.fileCount == 1 ? "" : "s") to \(url.lastPathComponent)."
            if result.passwordsIncluded > 0 {
                body += " \(result.passwordsIncluded) password"
                    + "\(result.passwordsIncluded == 1 ? " is" : "s are") encrypted with your passphrase."
            }
            if result.filesMissing > 0 {
                body += " \(result.filesMissing) file\(result.filesMissing == 1 ? "" : "s") named by a strip "
                    + "couldn't be read, so \(result.filesMissing == 1 ? "it isn't" : "they aren't") in the backup."
            }
            importMessage = ImportMessage(title: "Backup written", body: body)
        } catch {
            importMessage = ImportMessage(
                title: "Couldn't write the backup",
                body: error.localizedDescription
            )
        }
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
            var summary = try BackupImport.parse(manifest: BackupArchive.manifestData(at: url))
            // Kept so the files can be fetched if the user actually commits. Parsing shouldn't be
            // writing anything to disk.
            summary.sourceURL = url
            importSummary = summary
        } catch {
            importMessage = ImportMessage(
                title: "Couldn't read that backup",
                body: error.localizedDescription
            )
        }
    }

    private func performImport(_ summary: BackupImportSummary, mode: ImportMode, passphrase: String) {
        let referenced = summary.referencedMediaPaths

        // Files first: a strip that ends up pointing at nothing is better than files on disk that
        // nothing points at, and this is the step that can fail on its own. It's also the slow
        // one, so it happens off the main thread with the count on screen.
        guard let source = summary.sourceURL, !referenced.isEmpty else {
            finishImport(summary, mode: mode, passphrase: passphrase, restored: [], mediaProblem: nil)
            return
        }

        importSummary = nil
        progress = BackupProgress(
            title: "Reading the backup",
            step: "Restoring files",
            completed: 0,
            total: referenced.count
        )

        Task {
            let outcome = await Task.detached { () -> (Set<String>, String?) in
                do {
                    let restored = try BackupImport.restoreMedia(
                        fromArchiveAt: source,
                        paths: referenced,
                        into: .shared,
                        progress: { done, total in
                            DispatchQueue.main.async {
                                progress?.completed = done
                                progress?.total = total
                            }
                        }
                    )
                    return (restored, nil)
                } catch {
                    return ([], error.localizedDescription)
                }
            }.value

            progress = nil
            finishImport(
                summary,
                mode: mode,
                passphrase: passphrase,
                restored: outcome.0,
                mediaProblem: outcome.1
            )
        }
    }

    /// Everything that touches the store, which has to be here rather than on a background task:
    /// SwiftData objects belong to the thread that made them.
    private func finishImport(
        _ summary: BackupImportSummary,
        mode: ImportMode,
        passphrase: String,
        restored: Set<String>,
        mediaProblem: String?
    ) {
        let replaced = mode == .replace ? allTasks.count : 0
        let referenced = summary.referencedMediaPaths

        let imported = BackupImport.apply(
            summary.tasks,
            mode: mode,
            existing: allTasks,
            context: modelContext
        )
        let importedNotes = BackupImport.apply(
            notes: summary.notes,
            mode: mode,
            existing: allNotes,
            context: modelContext
        )
        let importedFiles = BackupImport.apply(
            storageItems: summary.storageItems,
            mode: mode,
            existing: allStorageItems,
            context: modelContext
        )
        let importedReminders = BackupImport.apply(
            reminders: summary.reminders,
            mode: mode,
            existing: allReminders,
            context: modelContext
        )
        let importedCredentials = BackupImport.apply(
            credentials: summary.credentials,
            mode: mode,
            existing: allCredentials,
            passphrase: passphrase,
            store: .shared,
            context: modelContext
        )
        importSummary = nil
        ReminderScheduler.shared.sync(allTasks)
        ReminderScheduler.shared.sync(allReminders)

        // SwiftData autosaves, but a failure here is exactly the silent-save class of bug that bit
        // Phase 1 — an import that quietly wrote nothing would look identical to an empty backup.
        let result: ImportMessage
        do {
            try modelContext.save()
            var body = mode == .replace
                ? "Replaced \(replaced) strip\(replaced == 1 ? "" : "s") with \(imported) from the backup."
                : "Added \(imported) strip\(imported == 1 ? "" : "s") to the board."
            if importedNotes > 0 {
                body += " \(importedNotes) quick note\(importedNotes == 1 ? "" : "s") came across too."
            }
            if importedFiles > 0 {
                body += " \(importedFiles) file\(importedFiles == 1 ? "" : "s") joined the storage library."
            }
            if importedReminders > 0 {
                body += " \(importedReminders) standalone reminder\(importedReminders == 1 ? "" : "s") came across."
            }
            if importedCredentials.imported > 0 {
                body += " \(importedCredentials.imported) credential\(importedCredentials.imported == 1 ? "" : "s") came across"
                let withPasswords = importedCredentials.passwordsRestored
                if withPasswords == 0 {
                    body += summary.hasEncryptedPasswords
                        ? ", but none of their passwords could be unlocked — check the passphrase."
                        : ", without passwords: the backup was written without a passphrase, so it carries none."
                } else {
                    body += ", \(withPasswords) with \(withPasswords == 1 ? "its password" : "their passwords")."
                }
            }
            if !referenced.isEmpty {
                body += " Restored \(restored.count) of \(referenced.count) file\(referenced.count == 1 ? "" : "s")."
            }
            let missing = referenced.count - restored.count
            if missing > 0 {
                body += " The \(missing) the archive didn't carry show as missing on their strips."
            }
            if let mediaProblem {
                body += " Files couldn't be read: \(mediaProblem)"
            }
            result = ImportMessage(title: "Import complete", body: body)
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

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

extension ProgressSort {
    var asFilterSort: BoardFilter.Sort {
        switch self {
        case .manual: .manual
        case .progressAscending: .progressAscending
        case .progressDescending: .progressDescending
        }
    }
}

struct TaskListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { !$0.isTombstoned }, sort: \TaskItem.orderIndex)
    private var allTasks: [TaskItem]
    /// Only needed so a Replace import knows what it's clearing — the notes sheet runs its own
    /// query.
    @Query private var allNotes: [Note]
    /// Same reason as the notes above: a Replace import needs to know what it's clearing.
    @Query(filter: #Predicate<StorageItem> { !$0.isTombstoned }) private var allStorageItems: [StorageItem]
    /// Same again for the standalone reminders.
    @Query(filter: #Predicate<Reminder> { !$0.isTombstoned }) private var allReminders: [Reminder]
    /// And the credentials, whose passwords a Replace has to clear from the keychain as well.
    @Query(filter: #Predicate<Credential> { !$0.isTombstoned }) private var allCredentials: [Credential]

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
    @State private var showStorage = false
    @State private var showCredentials = false
    @State private var showSketches = false
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
    @AppStorage(AppSettingsKey.dailyDigest) private var dailyDigest = false
    @AppStorage(AppSettingsKey.weeklyReview) private var weeklyReview = false
    @AppStorage(AppSettingsKey.autoBackup) private var autoBackup = false
    @AppStorage(AppSettingsKey.lastAutoBackup) private var lastAutoBackup: Double = 0
    @AppStorage(AppSettingsKey.showQuote) private var showQuote = true
    @AppStorage(AppSettingsKey.dateStyle) private var dateStyle = BoardDateStyle.both
    @AppStorage(AppSettingsKey.clockStyle) private var clockStyle = BoardClockStyle.digital
    @State private var quote: Quote?
    /// Which lists are pinned on the board, remembered between launches.
    @AppStorage(AppSettingsKey.boardPanes) private var panes: BoardPanes = .everything

    private var activeTasks: [TaskItem] { allTasks.filter { !$0.isArchived } }

    private var availableTags: [String] {
        Array(Set(activeTasks.flatMap(\.tags))).sorted()
    }

    /// The board's own controls, as the shared rules read them — the same ones the iPhone board
    /// uses, so "what does this filter show" has one answer (see BoardFilter).
    private var filter: BoardFilter {
        BoardFilter(
            search: searchText,
            tag: tagFilter,
            dueFrom: dueFrom,
            dueTo: dueTo,
            sort: sortMode.asFilterSort
        )
    }

    private var filtered: [TaskItem] {
        filter.apply(to: activeTasks)
    }

    private var canReorder: Bool { filter.allowsReordering }

    private func blocker(for task: TaskItem) -> TaskItem? {
        StripActions.blocker(for: task, in: allTasks)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SyncTestBanner()
                // Fixed: the board's identity and today's date belong to both pages.
                dateHeader
                if showQuote, let quote {
                    QuoteOfDayCard(quote: quote)
                }
                BoardPanesBar(panes: $panes)
                // Side by side, in board order, with whatever is in the way switched off. Only
                // the pane that holds the window's search field and buttons is "active": the
                // others carry their own header, because one bar can't belong to two lists.
                // HSplitView rather than an HStack: it's the Mac's own side-by-side, so each
                // pane is handed a real width (an HStack let the strip rows keep their ideal
                // width and clipped them at the divider) and the dividers can be dragged.
                HSplitView {
                    if panes.shows(.strips) {
                        VStack(spacing: 0) {
                            reorderNotice
                            board
                        }
                        .frame(minWidth: 420, maxWidth: .infinity)
                    }
                    if panes.shows(.reminders) {
                        RemindersView(
                            isEmbedded: true,
                            isActive: panes.lonePane == .reminders,
                            showsHeader: panes.lonePane != .reminders
                        )
                        .frame(minWidth: 320, idealWidth: 440, maxWidth: .infinity)
                    }
                    if panes.shows(.notes) {
                        NotesView(isEmbedded: true, nextOrderIndex: nextOrderIndex)
                            .frame(minWidth: 240, idealWidth: 300, maxWidth: .infinity)
                    }
                }
            }
            // The widget is handed a rendering rather than the data, so something has to hand it
            // over — this is that. Keyed on the snapshot itself, which compares only what the
            // widget shows, so an edit that changes nothing visible doesn't spend a reload.
            .modifier(SyncConfirmationAlert())
            .task { WidgetPublisher.publish(tasks: allTasks, reminders: allReminders) }
            .onChange(of: WidgetPublisher.snapshot(tasks: allTasks, reminders: allReminders)) { _, _ in
                WidgetPublisher.publish(tasks: allTasks, reminders: allReminders)
            }
            // A swipe still steps between the lists, but only while one of them is on its own:
            // with two side by side there's no page to turn, and moving one out from under the
            // hand would be a surprise rather than a gesture.
            .modifier(HorizontalSwipe { forward in
                guard let lone = panes.lonePane,
                      let target = forward ? panes.single(after: lone) : panes.single(before: lone)
                else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    panes = target
                }
            })
        }
    }

    /// Today in both calendars, with how long each month runs.
    ///
    /// Rebuilt every minute rather than once: a board left open overnight would otherwise still
    /// be showing yesterday, which is worse than showing nothing.
    private var dateHeader: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 10) {
                Text(BoardCalendars.headerText(context.date, style: dateStyle))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                BoardClock(date: context.date, style: clockStyle, faceSize: 56, digitSize: 16)
            }
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
            .dropDestination(for: URL.self) { urls, _ in
                fileInStorage(BoardDrop.usableFiles(among: urls))
            }
            .dropDestination(for: String.self) { texts, _ in
                fileAsStrips(texts)
            }
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
                        onUnarchive: { task in StripActions.unarchive(task, in: allTasks) }
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
            .sheet(isPresented: $showSketches) {
                NavigationStack {
                    SketchListView()
                }
            }
            .sheet(isPresented: $showStorage) {
                NavigationStack {
                    StorageLibraryView()
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
            .task {
                ReminderScheduler.shared.sync(allTasks)
                await loadQuote()
                await runAutomaticBackupIfDue()
            }
            // Re-armed whenever the board changes, since a scheduled summary's text is fixed when
            // it's scheduled — see ReminderScheduler.scheduleDigests.
            .onChange(of: allTasks.count, initial: true) { refreshDigests() }
            .onChange(of: dailyDigest) { refreshDigests() }
            .onChange(of: weeklyReview) { refreshDigests() }
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
        actions.showNotes = { panes = panes.showing(.notes) }
        actions.showStorage = { showStorage = true }
        actions.showReminders = { panes = panes.showing(.reminders) }
        actions.showCredentials = { showCredentials = true }
        actions.showSketches = { showSketches = true }
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
        actions.emailSelection = { sendByEmail(task) }
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
            // Dropped on a strip, a file joins that strip. The board behind it catches anything
            // dropped between the rows — see the destination on the list itself.
            // Providers rather than `dropDestination(for: URL.self)`: a message dragged out of
            // Mail arrives as several things at once — a `message:` URL, the subject, and a
            // promise of the .eml — and SwiftUI's URL drop resolves the promise, so the strip got
            // a copy of the email instead of a link to it. This reads the URL and its name.
            .onDrop(of: [.url, .fileURL], isTargeted: nil) { providers in
                accept(providers, on: task)
            }
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
            Button {
                sendByEmail(task)
            } label: {
                Label("Send by Email…", systemImage: "envelope")
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
    ///
    /// Every one of these carries a `.help`, because a row of seven monochrome glyphs tells a
    /// first-time user nothing — hovering is how a Mac toolbar explains itself, and the tooltip
    /// names the keyboard shortcut too, so the toolbar is also where the shortcuts are learned.
    /// The names match the View menu's exactly for the same reason: two names for one thing makes
    /// the user do the matching.
    private var placesToolbarItems: some ToolbarContent {
        Group {
            ToolbarItem(placement: .navigation) {
                Button {
                    showArchive = true
                } label: {
                    Label("Archived Strips", systemImage: "archivebox")
                }
                .help("Archived Strips (⇧⌘R)")
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    panes = panes.showing(.notes)
                } label: {
                    Label("Quick Notes", systemImage: "note.text")
                }
                .help("Quick Notes — the pad pinned beside the strips (⇧⌘N)")
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    showStorage = true
                } label: {
                    // A folder, not a tray: this is where files are kept, and "tray" reads as
                    // an inbox — something arriving rather than something stored.
                    Label("Storage Library", systemImage: "folder")
                }
                .help("Storage Library — files any strip can take a copy of (⇧⌘L)")
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    panes = panes.showing(.reminders)
                } label: {
                    Label("Reminders", systemImage: "bell")
                }
                .help("Reminders — pinned beside the strips (⇧⌘Y)")
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    showCredentials = true
                } label: {
                    Label("Credentials", systemImage: "key")
                }
                .help("Credentials — passwords kept in the Keychain (⇧⌘P)")
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    showSketches = true
                } label: {
                    Label("Sketch Notes", systemImage: "scribble")
                }
                .help("Sketch Notes — draw or write freely (⇧⌘J)")
            }
            ToolbarItem(placement: .navigation) {
                Menu {
                    ForEach(RollUp.allCases) { item in
                        Button(item.rawValue) { rollUp = item }
                    }
                } label: {
                    Label("Roll-Ups", systemImage: "chart.bar")
                }
                .help("Roll-Ups — standup summary and tag progress (⇧⌘S)")
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
                    Label("Tag", systemImage: tagFilter == nil ? "tag" : "tag.fill")
                }
                .disabled(availableTags.isEmpty)
                // Says which state it's in, since a filled tag and an outlined one are a small
                // difference to notice on a strip of icons.
                .help(tagFilter == nil ? "Filter by tag" : "Filtered to \(tagFilter ?? "") — ⇧⌘K shows all")
            }
            ToolbarItem {
                Button {
                    showDateFilter = true
                } label: {
                    Label(
                        "Due Date",
                        systemImage: (dueFrom != nil || dueTo != nil) ? "calendar.badge.checkmark" : "calendar"
                    )
                }
                .help(
                    (dueFrom != nil || dueTo != nil)
                        ? "Filtered by due date — ⇧⌘K shows all"
                        : "Filter by due date"
                )
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
                .help("Sorted by \(sortMode.rawValue)")
            }
            ToolbarItem {
                Button {
                    chooseBackupFile()
                } label: {
                    Label("Import Backup", systemImage: "square.and.arrow.down")
                }
                .help("Import a backup from the phone (⇧⌘I) — export is ⌥⇧⌘E")
            }
            ToolbarItem {
                Button {
                    isPresentingNewTask = true
                } label: {
                    Label("New Strip", systemImage: "plus")
                }
                .help("New Strip (⌘N) — or ⌥⌘N to dictate one")
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

    /// Today's quote: from the cache if it's already been fetched today, otherwise once from the
    /// network. A day with no connection simply has no card.
    private func loadQuote() async {
        guard showQuote else { return }
        quote = await QuoteOfTheDay.today()
    }

    // MARK: - Scheduled summaries and backups

    private func refreshDigests() {
        ReminderScheduler.shared.scheduleDigests(allTasks, daily: dailyDigest, weekly: weeklyReview)
    }

    /// Backs up to Drive if it's switched on and a day has gone by.
    ///
    /// Silent on success, like Android's: a backup that announces itself every morning is noise.
    /// A failure is silent too, but the Drive window shows when the last one actually went up, so
    /// "it hasn't run since Tuesday" is answerable rather than assumed.
    private func runAutomaticBackupIfDue() async {
        let last = lastAutoBackup > 0 ? Date(timeIntervalSince1970: lastAutoBackup) : nil
        guard autoBackup,
              DriveSession.shared.isSignedIn,
              DigestPlan.isBackupDue(lastBackup: last)
        else { return }

        do {
            var passwordsIncluded = 0
            // No passphrase: an unattended backup has nobody to ask for one, so it carries
            // everything except the passwords — which is what Android does without one too.
            let manifest = try BackupExport.manifestData(
                exportContents,
                credentialStore: .shared,
                passwordsIncluded: &passwordsIncluded
            )
            let paths = BackupExport.mediaPaths(exportContents, store: .shared)
            let result = await Task.detached {
                BackupExport.archive(manifest: manifest, mediaPaths: paths, store: .shared)
            }.value

            let client = try await DriveSession.shared.client()
            let folder = try await client.ensureBackupFolder()
            try await client.upload(result.archive, named: BackupExport.suggestedFileName(), toFolder: folder)
            lastAutoBackup = Date.now.timeIntervalSince1970
        } catch {
            // Left for the next launch to try again rather than surfaced: the user didn't ask for
            // this one now, and an alert about it on every launch would be worse than the miss.
        }
    }

    // MARK: - Dropped things

    /// Copied in, exactly as the editor's own Add Files does — the original is left where it is,
    /// which is the only behaviour that's safe when the thing dragged might be someone's only
    /// copy.
    @discardableResult
    /// Opens a mail draft holding the strip: what it is, what's written on it, and the files on
    /// it that are small enough to send.
    private func sendByEmail(_ task: TaskItem) {
        let files = task.attachments.map { AttachmentStore.shared.url(for: $0) }
        StripMailSender.send(StripMailSender.draft(for: task, files: files))
    }

    /// What was dropped on a strip: a file joins it, an email from Mail is linked to it.
    ///
    /// The loading is asynchronous and the drop has to answer straight away, so this says yes to
    /// anything it recognises and does the work as it arrives.
    private func accept(_ providers: [NSItemProvider], on task: TaskItem) -> Bool {
        var recognised = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            recognised = true
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                guard let url = Self.url(from: item) else { return }
                if url.isFileURL {
                    Task { @MainActor in _ = attach([url], to: task) }
                    return
                }
                guard StripMail.isMessageLink(url.absoluteString) else { return }
                // Mail sends the subject alongside the link, which is what the strip should show:
                // the URL itself is an opaque message id.
                provider.loadItem(forTypeIdentifier: "public.url-name") { name, _ in
                    let subject = Self.text(from: name)
                    Task { @MainActor in _ = link(url, named: subject, to: task) }
                }
            }
        }
        return recognised
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let text = item as? String { return URL(string: text) }
        return nil
    }

    private static func text(from item: NSSecureCoding?) -> String {
        if let text = item as? String { return text }
        if let data = item as? Data { return String(data: data, encoding: .utf8) ?? "" }
        return ""
    }

    /// Files an email dragged from Mail as a link on the strip, under its own subject. The same
    /// message dropped twice doesn't become two links.
    @discardableResult
    private func link(_ url: URL, named subject: String, to task: TaskItem) -> Bool {
        let address = url.absoluteString
        guard !task.links.contains(where: { $0.url == address }) else { return false }
        let label = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        task.links.append(TaskLink(url: address, label: label))
        task.actionLog.append(TaskActionLogEntry(text: "Linked an email"))
        selectedTaskID = task.id
        return true
    }

    private func link(_ urls: [URL], to task: TaskItem) -> Bool {
        var added = false
        for url in urls where link(url, named: "", to: task) { added = true }
        return added
    }

    private func attach(_ urls: [URL], to task: TaskItem) -> Bool {
        guard !urls.isEmpty else { return false }
        var attached = 0
        for url in urls {
            guard let attachment = try? AttachmentStore.shared.add(
                contentsOf: url, kind: BoardDrop.attachmentKind(for: url)
            ) else { continue }
            task.attachments.append(attachment)
            attached += 1
            // Mail sometimes drops the message itself rather than a link to it. The file is kept,
            // and the message it came from is linked as well, so the strip can still open it.
            if StripMail.isEmailFile(url),
               let text = try? String(contentsOf: url, encoding: .utf8),
               let link = StripMail.messageLink(fromEmail: text) {
                _ = self.link([URL(string: link)].compactMap { $0 }, to: task)
            }
        }
        if attached > 0 { selectedTaskID = task.id }
        return attached > 0
    }

    @discardableResult
    private func fileInStorage(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        var filed = 0
        for url in urls {
            let type = BoardDrop.storageType(for: url)
            guard let copy = try? AttachmentStore.shared.add(
                contentsOf: url, kind: type.attachmentKind
            ) else { continue }
            modelContext.insert(
                StorageItem(
                    name: url.lastPathComponent,
                    path: copy.path,
                    type: type,
                    mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "",
                    sizeBytes: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                )
            )
            filed += 1
        }
        if filed > 0 {
            importMessage = ImportMessage(
                title: "Filed in storage",
                body: "\(filed) file\(filed == 1 ? "" : "s") went to the storage library, where any "
                    + "strip can take a copy."
            )
        }
        return filed > 0
    }

    @discardableResult
    private func fileAsStrips(_ texts: [String]) -> Bool {
        var filed = false
        for text in texts {
            guard let strip = BoardDrop.strip(fromDroppedText: text, orderIndex: nextOrderIndex()) else {
                continue
            }
            modelContext.insert(strip)
            selectedTaskID = strip.id
            filed = true
        }
        return filed
    }

    private func nextOrderIndex() -> Int {
        StripActions.nextOrderIndex(in: allTasks)
    }

    private func toggleDone(_ task: TaskItem) {
        if case .blocked = StripActions.toggleDone(task, in: allTasks, context: modelContext) {
            blockedAlertTask = task
        }
    }

    private func archive(_ task: TaskItem) {
        if selectedTaskID == task.id { selectedTaskID = nil }
        StripActions.archive(task)
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
        if selectedTaskID == task.id { selectedTaskID = nil }
        StripActions.delete(task, in: allTasks, context: modelContext)
    }

    private func cleanUpDanglingBlockers(deletedID: UUID) {
        StripActions.releaseBlocked(by: deletedID, in: allTasks)
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
            let prepared = try BackupFlow.prepareExport(exportContents, passphrase: passphrase)
            progress = BackupProgress(
                title: "Writing the backup",
                step: prepared.mediaPaths.isEmpty ? "Packing" : "Packing files",
                completed: 0,
                total: prepared.mediaPaths.count
            )
            Task {
                let result = await BackupFlow.pack(prepared) { done, total in
                    progress?.completed = done
                    progress?.total = total
                }
                progress = nil
                finishExport(result, to: url, strips: prepared.strips)
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
            importMessage = BackupFlow.exportMessage(result, fileName: url.lastPathComponent, strips: strips)
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
            importSummary = try BackupFlow.readSummary(at: url)
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
        guard summary.sourceURL != nil, !referenced.isEmpty else {
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
            let outcome = await BackupFlow.restoreMedia(for: summary) { done, total in
                progress?.completed = done
                progress?.total = total
            }
            progress = nil
            finishImport(
                summary,
                mode: mode,
                passphrase: passphrase,
                restored: outcome.restored,
                mediaProblem: outcome.problem
            )
        }
    }

    private func finishImport(
        _ summary: BackupImportSummary,
        mode: ImportMode,
        passphrase: String,
        restored: Set<String>,
        mediaProblem: String?
    ) {
        let result = BackupFlow.apply(
            summary,
            mode: mode,
            passphrase: passphrase,
            restored: restored,
            mediaProblem: mediaProblem,
            existing: exportContents,
            context: modelContext
        )
        importSummary = nil
        ReminderScheduler.shared.sync(allTasks)
        ReminderScheduler.shared.sync(allReminders)

        // Raising the alert in the same update that dismisses the sheet can swallow it — let the
        // sheet finish going away first.
        DispatchQueue.main.async { importMessage = result }
    }
}


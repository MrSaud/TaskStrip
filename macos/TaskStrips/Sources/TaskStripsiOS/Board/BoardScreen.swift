import SwiftData
import SwiftUI

/// The iPhone board: Strips and Reminders as two pages under one fixed header, like Android.
///
/// The gesture rule, learned on Android the hard way: a strip may claim a swipe to the RIGHT
/// (mark it done) and nothing else. A swipe to the left must always reach the pager — so there
/// are no trailing swipe actions on the board, and delete lives in the editor and in a completed
/// strip's menu, behind a confirm.
struct BoardScreen: View {
    enum Page: Hashable { case today, strips, reminders }

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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(filter: #Predicate<TaskItem> { !$0.isTombstoned }, sort: \TaskItem.orderIndex)
    private var allTasks: [TaskItem]
    @Query(filter: #Predicate<Reminder> { !$0.isTombstoned }) private var allReminders: [Reminder]

    @AppStorage(AppSettingsKey.defaultPriority) private var defaultPriority = Priority.normal
    @AppStorage(AppSettingsKey.defaultNotesRtl) private var defaultNotesRtl = false
    @AppStorage(AppSettingsKey.showQuote) private var showQuote = true
    @AppStorage(AppSettingsKey.dailyDigest) private var dailyDigest = false
    @AppStorage(AppSettingsKey.weeklyReview) private var weeklyReview = false
    @AppStorage(AppSettingsKey.reportHour) private var reportHour = DigestPlan.dailyHour
    @AppStorage(AppSettingsKey.dateStyle) private var dateStyle = BoardDateStyle.both
    @AppStorage(AppSettingsKey.clockStyle) private var clockStyle = BoardClockStyle.digital
    @AppStorage(AppSettingsKey.showCalendar) private var showCalendar = false
    /// iPad only: which lists are pinned side by side. The iPhone has its pager instead.
    @AppStorage(AppSettingsKey.boardPanes) private var panes: BoardPanes = .everything
    @State private var quote: Quote?
    @State private var now = Date.now

    @State private var page: Page = .strips
    @State private var filter = BoardFilter()
    @State private var editing: TaskItem?
    @State private var isCreating = false
    @State private var destination: Destination?
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var isCapturingVoice = false
    /// A sketch started from the board's own button, which exists the moment something is drawn
    /// on it and not before.
    @State private var quickSketch: QuickSketch?
    @State private var shareReport: String?

    private var boardTasks: [TaskItem] { allTasks.filter { !$0.isArchived } }

    /// An iPad, or a big iPhone in landscape: room for both pages at once, so there's no pager
    /// and nothing to swipe between.
    private var isWide: Bool { sizeClass == .regular }

    /// Whether the strips' own controls — search, voice, + — belong on the bar right now. On a
    /// wide screen that's whenever the strips are one of the pinned panes.
    private var showsStripControls: Bool { isWide ? panes.shows(.strips) : page == .strips }

    private var stripsPage: some View {
        StripsPage(strips: boardTasks, allTasks: allTasks, filter: $filter, onEdit: { editing = $0 })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SyncTestBanner()
                // Fixed, like Android's: today's date belongs to both pages. A plain line on a
                // minute timer rather than a TimelineView: in this layout (above the pager, under
                // a navigation bar with search) a TimelineView sent SwiftUI into an endless
                // layout pass — 100% CPU and a blank screen.
                HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    // One line per calendar: at a size worth reading, both on one line runs off
                    // a phone. Each line shrinks a little before it truncates, for the longest
                    // Hijri month names on the narrowest phone.
                    ForEach(BoardCalendars.headerLines(now, style: dateStyle), id: \.self) { line in
                        Text(line)
                            .font(.footnote.monospaced())
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                    .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    // As big as the date lines beside it are tall — bigger again on an iPad,
                    // which has the room. It only moves on the minute, on the same timer as the
                    // date beside it.
                    BoardClock(date: now, style: clockStyle, faceSize: isWide ? 56 : 44, digitSize: 15)
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(TaskStripTheme.baySurfaceFaded)
                    .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
                quickActions
                if showQuote, let quote {
                    QuoteOfDayCard(quote: quote)
                }
                if isWide {
                    BoardPanesBar(panes: $panes)
                    HStack(spacing: 0) {
                        if panes.shows(.today) {
                            DayView(
                                tasks: allTasks,
                                reminders: allReminders,
                                    onEdit: { editing = $0 }
                            )
                            .frame(maxWidth: panes.lonePane == .today ? .infinity : 320)
                            Divider()
                        }
                        if panes.shows(.strips) {
                            stripsPage
                        }
                        if panes.shows(.reminders) {
                            Divider()
                            // The navigation bar is the strips'; the reminders carry their buttons
                            // in a header of their own, unless the strips are put away and the
                            // bar is theirs to use. (A second navigation stack here doesn't keep
                            // its toolbar to itself — its buttons, title and search all took over
                            // the strips' bar.)
                            RemindersView(
                                isEmbedded: true,
                                isActive: panes.lonePane == .reminders,
                                showsHeader: panes.lonePane != .reminders
                            )
                            .frame(maxWidth: panes.lonePane == .reminders ? .infinity : 380)
                        }
                        if panes.shows(.notes) {
                            Divider()
                            NotesView(
                                isEmbedded: true,
                                nextOrderIndex: { StripActions.nextOrderIndex(in: allTasks) }
                            )
                            .frame(maxWidth: panes.lonePane == .notes ? .infinity : 260)
                        }
                    }
                } else {
                    BoardPageTabs(page: $page)
                    BoardPager(pages: [Page.today, .strips, .reminders], selection: $page) { page in
                        switch page {
                        case .today:
                            DayView(tasks: allTasks, reminders: allReminders, onEdit: { editing = $0 })
                        case .strips: stripsPage
                        case .reminders: RemindersView(isEmbedded: true, isActive: self.page == .reminders)
                        }
                    }
                }
            }
            .background(TaskStripTheme.bayBackground)
            .navigationTitle("Task Strips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(TaskStripTheme.bayBackground, for: .navigationBar)
            .searchable(if: showsStripControls, text: $filter.search, prompt: "Search strips")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { menu }
                if showsStripControls {
                    ToolbarItem(placement: .primaryAction) {
                        BoardFilterMenu(filter: $filter)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isCapturingVoice = true
                        } label: {
                            Label("New strip by voice", systemImage: "mic")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isCreating = true
                        } label: {
                            Label("New strip", systemImage: "plus")
                        }
                    }
                }
            }
            .canvasPresentation(item: $quickSketch) { sketch in
                NavigationStack {
                    SketchCanvasView(noteID: sketch.id)
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
            .sheet(isPresented: $isCapturingVoice) {
                VoiceCaptureSheet(
                    onFile: { draft in
                        isCapturingVoice = false
                        file(draft)
                    },
                    onCancel: { isCapturingVoice = false }
                )
            }
            .sheet(item: $destination) { destination in
                NavigationStack {
                    screen(for: destination)
                }
            }
            .modifier(BoardBackup(isBackingUp: $isBackingUp, isRestoring: $isRestoring))
            .modifier(SyncConfirmationAlert())
            // As on the Mac: the widget is handed a rendering, keyed on what it shows, so an edit
            // that changes nothing visible doesn't spend one of WidgetKit's reloads.
            .onChange(of: WidgetPublisher.snapshot(tasks: allTasks, reminders: allReminders), initial: true) {
                WidgetPublisher.publish(tasks: allTasks, reminders: allReminders)
                // The share sheet's list of strips to file an email onto.
                StripIndex.write(StripIndexEntry.board(allTasks))
            }
            // Whatever the Share Extension left while the app was away.
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                let filed = ShareInboxDrain.run(context: modelContext, tasks: allTasks, defaultPriority: defaultPriority)
                if !filed.isEmpty { shareReport = "From Share: " + filed.summary }
            }
            .alert(
                "Shared into Task Strips",
                isPresented: Binding(get: { shareReport != nil }, set: { if !$0 { shareReport = nil } })
            ) {
                Button("OK") {}
            } message: {
                Text(shareReport ?? "")
            }
            .task {
                ReminderScheduler.shared.sync(allTasks)
                // The phone never armed these: the daily report and the Friday review were a Mac
                // affair, which is the wrong way round for the device that's in a pocket.
                ReminderScheduler.shared.scheduleDigests(
                    allTasks, reminders: allReminders,
                    daily: dailyDigest, weekly: weeklyReview, hour: reportHour
                )
                if showQuote { quote = await QuoteOfTheDay.today() }
                #if DEBUG
                // `-OpenLink <url>`: opens a link on launch, which is how a message: link can be
                // tried on a real phone from a Mac — there's no way to tap one from here.
                if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-OpenLink"),
                   index + 1 < ProcessInfo.processInfo.arguments.count,
                   let url = URL(string: ProcessInfo.processInfo.arguments[index + 1]) {
                    try? await Task.sleep(for: .seconds(1))
                    Platform.open(url)
                }
                #endif
            }
        }
    }

    /// Same as the Mac's: a spoken strip lands at the bottom of the board with the defaults for
    /// anything it didn't say.
    private func file(_ draft: VoiceDraft) {
        let task = TaskItem(
            title: draft.title,
            orderIndex: StripActions.nextOrderIndex(in: allTasks),
            priority: draft.priority ?? defaultPriority
        )
        task.notes = draft.notes
        task.notesRtl = defaultNotesRtl
        modelContext.insert(task)
    }

    /// The two things that are worth catching before they're gone: a thought and a drawing.
    /// Fixed on the board rather than folded into the menu, because a note you have to go and
    /// find is a note you don't write.
    private var quickActions: some View {
        HStack(spacing: 8) {
            quickAction("NOTE", systemImage: "note.text") { destination = .notes }
            quickAction("SKETCH", systemImage: "scribble") {
                quickSketch = QuickSketch(id: SketchStore.newNoteID())
            }
            quickAction(
                "CALENDAR",
                systemImage: showCalendar ? "calendar.badge.checkmark" : "calendar",
                lit: showCalendar
            ) {
                showCalendar.toggle()
                // Turning the calendar on with nowhere to show it would do nothing visible.
                if showCalendar, isWide, !panes.shows(.today) { panes = panes.showing(.today) }
                if showCalendar, !isWide { page = .today }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(TaskStripTheme.baySurfaceFaded)
    }

    private func quickAction(
        _ title: String,
        systemImage: String,
        lit: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(lit ? TaskStripTheme.ink : TaskStripTheme.paper.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(lit ? TaskStripTheme.amber : TaskStripTheme.baySurface, in: Capsule())
        }
        .buttonStyle(.plain)
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
            tab("TODAY", .today)
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
    @Binding var filter: BoardFilter
    let onEdit: (TaskItem) -> Void

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettingsKey.confirmBeforeDelete) private var confirmBeforeDelete = true
    @State private var blockedBy: TaskItem?
    @State private var pendingArchive: TaskItem?
    @State private var pendingDeletion: TaskItem?

    private var visible: [TaskItem] { filter.apply(to: strips) }
    private var active: [TaskItem] { visible.filter { !$0.isDone } }
    private var completed: [TaskItem] { visible.filter(\.isDone) }

    /// The board's tags for the chips, plus a selected one that has since left the board, so a
    /// filter can always be switched off again.
    private var tags: [String] {
        var seen = Set<String>()
        var all = strips.flatMap(\.tags).filter { seen.insert($0.lowercased()).inserted }
        if let tag = filter.tag, !seen.contains(tag.lowercased()) { all.append(tag) }
        return all.sorted { $0.lowercased() < $1.lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
        if !tags.isEmpty { TagChips(tags: tags, selected: $filter.tag) }
        List {
            ForEach(active) { strip in
                row(strip)
            }
            // A filtered list has gaps, and dragging within it would renumber the board around
            // strips that aren't showing — the Mac turns reordering off for the same reason.
            .onMove(perform: filter.allowsReordering ? move : nil)

            if !completed.isEmpty {
                Section {
                    ForEach(completed) { strip in
                        row(strip)
                            // Only finished strips get a menu: on an active one a long press
                            // is the start of a drag to reorder.
                            .contextMenu {
                                Button {
                                    StripActions.toggleTimer(on: strip, in: allTasks)
                                } label: {
                                    Label(
                                        StripTime.isRunning(strip.sessions) ? "Stop the clock" : "Start the clock",
                                        systemImage: StripTime.isRunning(strip.sessions) ? "stop.circle" : "play.circle"
                                    )
                                }
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
                ContentUnavailableView(
                    "Nothing matches",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(filter.trimmedSearch.isEmpty
                                      ? "No strip fits these filters."
                                      : "No strip matches \u{201C}\(filter.trimmedSearch)\u{201D} with these filters.")
                )
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
    }

    private func row(_ strip: TaskItem) -> some View {
        TaskRowView(task: strip, blocker: StripActions.blocker(for: strip, in: allTasks))
            .contentShape(Rectangle())
            // Behind the row, as on the Mac: a message dragged from Mail on an iPad is linked to
            // the strip, a file is attached to it.
            .background(
                MailDropCatcher(
                    onEmail: { url, name in link(url, named: name, to: strip) },
                    onFiles: { files in attach(files, to: strip) }
                )
            )
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

    /// Files an email dragged from Mail as a link on the strip, under its own subject.
    private func link(_ url: URL, named subject: String, to strip: TaskItem) {
        let address = url.absoluteString
        guard !strip.links.contains(where: { $0.url == address }) else { return }
        strip.links.append(TaskLink(url: address, label: subject.trimmingCharacters(in: .whitespacesAndNewlines)))
        strip.actionLog.append(TaskActionLogEntry(text: "Linked an email"))
    }

    private func attach(_ urls: [URL], to strip: TaskItem) {
        for url in urls {
            guard let attachment = try? AttachmentStore.shared.add(
                contentsOf: url, kind: AttachmentKind.inferred(fromExtension: url.pathExtension)
            ) else { continue }
            strip.attachments.append(attachment)
            // An email dropped as a file still points back at the message it is.
            if EmailLink.isEmailFile(url),
               let text = try? String(contentsOf: url, encoding: .utf8),
               let address = EmailLink.fromEmail(text),
               let link = URL(string: address) {
                self.link(link, named: url.deletingPathExtension().lastPathComponent, to: strip)
            }
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
        // Only ever onto a sync test board. Sample strips seeded onto a real board in Phase 3 are
        // how test data came to sit next to real strips, and from there into iCloud.
        guard AppLaunch.isSyncTesting, ProcessInfo.processInfo.arguments.contains("-SeedSampleBoard") else { return }
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

/// A sketch the board started, named before it exists so it can be presented.
private struct QuickSketch: Identifiable {
    let id: String
}

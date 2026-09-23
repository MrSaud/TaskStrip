import SwiftUI
import SwiftData

// Mirrors ui/screens/AddEditTaskScreen.kt's fields at the concept level. Holds local draft state
// and only writes into the SwiftData model on Save, matching Android's "editing doesn't commit
// until you tap Update/File Strip" behavior — Cancel discards everything.
struct TaskEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let editingTask: TaskItem?
    let allTasks: [TaskItem]
    let nextOrderIndex: Int
    let onSaved: () -> Void
    let onDeleted: () -> Void

    @State private var title: String
    @State private var notes: String
    @State private var notesRtl: Bool
    @State private var priority: Priority
    @State private var hasDueDate: Bool
    @State private var dueAt: Date
    @State private var progress: Double
    @State private var checklist: [TaskChecklistItem]
    @State private var newStep = ""
    @State private var running = false
    @State private var hasDeferUntil: Bool
    @State private var deferUntil: Date
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var links: [TaskLink]
    @State private var newLinkURL = ""
    @State private var contacts: [TaskContact]
    @State private var newContactName = ""
    @State private var actionLog: [TaskActionLogEntry]
    @State private var newLogEntry = ""
    @State private var blockedByID: UUID?
    @State private var waitingOnName: String
    @State private var hasFollowUp: Bool
    @State private var waitingOnFollowUpDays: Double
    @State private var showDeleteConfirm = false
    @State private var hasReminder: Bool
    @State private var reminderMinutesBefore: Int
    @State private var repeats: Bool
    @State private var repeatIntervalDays: Double
    @State private var reminderDenied = false
    @State private var attachments: [TaskAttachment]
    /// Files copied in during this sitting, and files dropped from the strip. Only one of the two
    /// gets deleted, depending on whether you save or cancel.
    @State private var addedAttachments: [TaskAttachment] = []
    @State private var removedAttachments: [TaskAttachment] = []
    @State private var linkedSketchID: String?
    @State private var isPickingSketch = false
    @State private var openingLinkedSketch = false
    #if os(iOS)
    @State private var isEmailing = false
    #endif

    private let attachmentStore = AttachmentStore.shared

    /// `defaultPriority`/`defaultNotesRtl` only apply to a brand-new strip — an existing one
    /// always opens on its own values.
    init(
        editingTask: TaskItem?,
        allTasks: [TaskItem],
        nextOrderIndex: Int,
        defaultPriority: Priority = .normal,
        defaultNotesRtl: Bool = false,
        onSaved: @escaping () -> Void,
        onDeleted: @escaping () -> Void
    ) {
        self.editingTask = editingTask
        self.allTasks = allTasks
        self.nextOrderIndex = nextOrderIndex
        self.onSaved = onSaved
        self.onDeleted = onDeleted

        _title = State(initialValue: editingTask?.title ?? "")
        _notes = State(initialValue: editingTask?.notes ?? "")
        _notesRtl = State(initialValue: editingTask?.notesRtl ?? defaultNotesRtl)
        _priority = State(initialValue: editingTask?.priority ?? defaultPriority)
        _hasDueDate = State(initialValue: editingTask?.dueAt != nil)
        _dueAt = State(initialValue: editingTask?.dueAt ?? .now)
        _progress = State(initialValue: Double(editingTask?.progress ?? 0))
        _checklist = State(initialValue: editingTask?.checklist ?? [])
        _hasDeferUntil = State(initialValue: editingTask?.deferUntil != nil)
        _deferUntil = State(initialValue: editingTask?.deferUntil ?? Date.now.addingTimeInterval(24 * 3600))
        _tags = State(initialValue: editingTask?.tags ?? [])
        _links = State(initialValue: editingTask?.links ?? [])
        _contacts = State(initialValue: editingTask?.contacts ?? [])
        _actionLog = State(initialValue: editingTask?.actionLog ?? [])
        _attachments = State(initialValue: editingTask?.attachments ?? [])
        _hasReminder = State(initialValue: editingTask?.reminderMinutesBefore != nil)
        _reminderMinutesBefore = State(initialValue: editingTask?.reminderMinutesBefore ?? 30)
        _repeats = State(initialValue: editingTask?.repeatIntervalDays != nil)
        _repeatIntervalDays = State(initialValue: Double(editingTask?.repeatIntervalDays ?? 7))
        _blockedByID = State(initialValue: editingTask?.blockedByID)
        _waitingOnName = State(initialValue: editingTask?.waitingOnName ?? "")
        _hasFollowUp = State(initialValue: editingTask?.waitingOnFollowUpDays != nil)
        _waitingOnFollowUpDays = State(initialValue: Double(editingTask?.waitingOnFollowUpDays ?? 3))
        _linkedSketchID = State(initialValue: editingTask?.linkedSketchID)
    }

    private var isEditing: Bool { editingTask != nil }

    /// Lead times worth offering. Minutes throughout, matching what the backup carries.
    /// The standalone reminders offer the same choices, so the list lives with the rules.
    private static let leadTimes = ReminderSchedule.leadTimes

    private var blockableTasks: [TaskItem] {
        allTasks.filter { $0.id != editingTask?.id && !$0.isArchived }
    }

    var body: some View {
        Form {
            Section("TASK") {
                TextField("Title", text: $title)
                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("TAGS") {
                tagsEditor
            }

            Section("DUE DATE") {
                Toggle("Set due date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Due", selection: $dueAt)
                        .labelsHidden()
                }
            }

            Section(progressTitle) {
                // With steps on the strip they decide the bar; dragging it as well would be two
                // answers to one question.
                if let fromSteps = StripChecklist.progress(of: checklist) {
                    ProgressView(value: Double(fromSteps), total: 100)
                        .tint(TaskStripTheme.amber)
                } else {
                    Slider(value: $progress, in: 0...100, step: 1)
                }
            }

            Section(timeTitle) {
                Button {
                    guard let task = editingTask else { return }
                    StripActions.toggleTimer(on: task, in: allTasks)
                    running = StripTime.isRunning(task.sessions)
                } label: {
                    Label(
                        running ? "Stop" : "Start working",
                        systemImage: running ? "stop.circle" : "play.circle"
                    )
                    .foregroundStyle(running ? TaskStripTheme.urgent : TaskStripTheme.normal)
                }
                // The clock belongs to a strip that exists: there's nothing to spend time on
                // until it's been filed.
                .disabled(editingTask == nil)
                if editingTask == nil {
                    Text("File the strip first, then the clock has something to run on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("STEPS") {
                ForEach(checklist) { step in
                    Button {
                        checklist = StripChecklist.toggling(step.id, in: checklist)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(step.isDone ? TaskStripTheme.normal : .secondary)
                            Text(step.text)
                                .strikethrough(step.isDone)
                                .foregroundStyle(step.isDone ? .secondary : .primary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            checklist.removeAll { $0.id == step.id }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    #if os(macOS)
                    .contextMenu {
                        Button("Delete Step", role: .destructive) {
                            checklist.removeAll { $0.id == step.id }
                        }
                    }
                    #endif
                }
                HStack {
                    // A list pasted in whole arrives as one step per line rather than one long
                    // step, which is how a list usually turns up.
                    TextField("Add a step…", text: $newStep)
                        .onSubmit(addSteps)
                    Button("Add", action: addSteps)
                        .disabled(newStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("NOT BEFORE") {
                Toggle("Keep it off the board until a day", isOn: $hasDeferUntil)
                if hasDeferUntil {
                    DatePicker("Back on the board", selection: $deferUntil, displayedComponents: .date)
                }
            }

            Section("NOTES") {
                Toggle("Right-to-left", isOn: $notesRtl)
                // layoutDirection alone only affects SwiftUI's own layout (leading/trailing,
                // stack order) — a TextEditor's underlying NSTextView doesn't infer its text
                // alignment from it, so RTL mode looked like a no-op without also setting
                // multilineTextAlignment explicitly.
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
                    .multilineTextAlignment(notesRtl ? .trailing : .leading)
                    .environment(\.layoutDirection, notesRtl ? .rightToLeft : .leftToRight)
            }

            Section("ACTIVITY LOG") {
                actionLogEditor
            }

            Section("REMINDER") {
                Toggle("Remind me before it's due", isOn: $hasReminder)
                    // A reminder is measured backwards from the due date, so without one there's
                    // nothing to measure from — ReminderPlan would return nil and the toggle
                    // would be a lie.
                    .disabled(!hasDueDate)
                if !hasDueDate {
                    Text("Set a due date first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if hasReminder && hasDueDate {
                    Picker("Remind me", selection: $reminderMinutesBefore) {
                        ForEach(Self.leadTimes, id: \.minutes) { option in
                            Text(option.label).tag(option.minutes)
                        }
                    }
                    if reminderDenied {
                        Text("Notifications are turned off for Task Strips — check \(Platform.settingsApp).")
                            .font(.caption)
                            .foregroundStyle(TaskStripTheme.urgent)
                    }
                }

                Toggle("Repeats", isOn: $repeats)
                    .disabled(!hasDueDate)
                if repeats && hasDueDate {
                    Stepper("Every \(Int(repeatIntervalDays)) day\(Int(repeatIntervalDays) == 1 ? "" : "s")",
                            value: $repeatIntervalDays, in: 1...365)
                    Text("Completing this strip files the next one, due \(Int(repeatIntervalDays)) day\(Int(repeatIntervalDays) == 1 ? "" : "s") later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("ATTACHMENTS") {
                AttachmentsSection(
                    attachments: $attachments,
                    store: attachmentStore,
                    onAdded: { addedAttachments.append($0) },
                    onRemoved: { removedAttachments.append($0) }
                )
            }

            Section("LINKED SKETCH") {
                sketchLink
            }

            Section("LINKS") {
                linksEditor
            }

            Section("CONTACTS") {
                contactsEditor
            }

            Section("BLOCKED BY") {
                Picker("Blocked by", selection: $blockedByID) {
                    Text("None").tag(UUID?.none)
                    ForEach(blockableTasks) { t in
                        Text(t.title).tag(Optional(t.id))
                    }
                }
                .labelsHidden()
            }

            Section("DELEGATE") {
                TextField("Waiting on…", text: $waitingOnName)
                Toggle("Follow up after N days", isOn: $hasFollowUp)
                if hasFollowUp {
                    Stepper("\(Int(waitingOnFollowUpDays)) days", value: $waitingOnFollowUpDays, in: 1...30)
                }
            }

            if isEditing {
                Section {
                    Button("DELETE STRIP", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .macFrame(minWidth: 480, minHeight: 560)
        .onChange(of: hasReminder) { _, isOn in
            guard isOn else { return }
            Task {
                reminderDenied = await !ReminderScheduler.shared.requestAuthorization()
            }
        }
        .navigationTitle(isEditing ? "EDIT STRIP" : "NEW STRIP")
        .onAppear { running = StripTime.isRunning(editingTask?.sessions ?? []) }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { cancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Update" : "File Strip") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sheet(isPresented: $isPickingSketch) {
            NavigationStack {
                SketchListView(onPick: { linkedSketchID = $0.id })
            }
        }
        #if os(iOS)
        .sheet(isPresented: $isEmailing) {
            StripMailComposer(draft: emailDraft) { isEmailing = false }
                .ignoresSafeArea()
        }
        #endif
        .canvasPresentation(isPresented: $openingLinkedSketch) {
            if let linkedSketchID {
                NavigationStack {
                    SketchCanvasView(noteID: linkedSketchID)
                }
            }
        }
        .confirmationDialog("Delete this strip?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let task = editingTask {
                    for attachment in task.attachments { attachmentStore.remove(attachment) }
                    ReminderScheduler.shared.cancel(taskID: task.id)
                    modelContext.delete(task)
                }
                onDeleted()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(title)\" will be permanently deleted. This can't be undone.")
        }
    }

    /// Cancel means cancel: files copied in during this sitting go back out, since nothing will
    /// be pointing at them.
    private func cancel() {
        for attachment in addedAttachments { attachmentStore.remove(attachment) }
        dismiss()
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let task = editingTask ?? TaskItem(title: trimmedTitle, orderIndex: nextOrderIndex)
        if editingTask != nil { task.title = trimmedTitle }
        task.notes = notes
        task.notesRtl = notesRtl
        task.priority = priority
        task.dueAt = hasDueDate ? dueAt : nil
        task.checklist = checklist
        task.deferUntil = hasDeferUntil ? deferUntil : nil
        task.progress = StripChecklist.progress(of: checklist) ?? Int(progress)
        task.tags = tags
        task.links = links
        task.contacts = contacts
        task.actionLog = actionLog
        task.attachments = attachments
        task.reminderMinutesBefore = (hasReminder && hasDueDate) ? reminderMinutesBefore : nil
        task.repeatIntervalDays = (repeats && hasDueDate) ? Int(repeatIntervalDays) : nil
        task.blockedByID = blockedByID
        task.waitingOnName = waitingOnName
        task.waitingOnFollowUpDays = hasFollowUp ? Int(waitingOnFollowUpDays) : nil
        task.linkedSketchID = linkedSketchID

        if editingTask == nil {
            modelContext.insert(task)
        }
        for attachment in removedAttachments { attachmentStore.remove(attachment) }
        ReminderScheduler.shared.schedule(for: task)
        onSaved()
        dismiss()
    }

    /// The strip carries the sketch's folder name, nothing more — which is exactly what a backup
    /// carries, and why a sketch linked on the phone is still linked here.
    @ViewBuilder
    private var sketchLink: some View {
        if let linkedSketchID {
            let note = SketchStore.shared.note(linkedSketchID)
            HStack {
                Image(systemName: "scribble")
                VStack(alignment: .leading) {
                    Text(note?.displayName ?? "Sketch note")
                    // A linked sketch whose pages aren't here yet is the normal state right
                    // after a partial restore, so say so rather than showing an empty row.
                    Text(note == nil ? "Not on \(Platform.thisDevice) yet" : "\(note?.pageCount ?? 0) page(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open") { openingLinkedSketch = true }
                    .disabled(note == nil)
                Button {
                    self.linkedSketchID = nil
                } label: {
                    Label("Unlink sketch", systemImage: "xmark.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }
        } else {
            Button("Link a sketch…") { isPickingSketch = true }
        }
    }

    private var tagsEditor: some View {
        VStack(alignment: .leading) {
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        chip(tag) { tags.removeAll { $0 == tag } }
                    }
                }
            }
            HStack {
                TextField("Add a tag…", text: $newTag)
                    .onSubmit(addTag)
                Button("Add", action: addTag)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        newTag = ""
    }

    private var linksEditor: some View {
        VStack(alignment: .leading) {
            ForEach(links) { link in
                HStack {
                    // A link you can't open is a note about a link. An email dragged from Mail
                    // is a message: URL — an id, not an address — so it's named rather than
                    // shown, and opening it takes you back to the message it came from.
                    Button {
                        open(link)
                    } label: {
                        Label(
                            link.label.isEmpty ? EmailLink.label(for: link.url) : link.label,
                            systemImage: EmailLink.isMessage(link.url) ? "envelope" : "link"
                        )
                        .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help(link.url)
                    Spacer()
                    #if os(iOS)
                    // Tested on the phone: iOS opens Mail but lands in the inbox rather than the
                    // message. Saying so beats letting someone think the link is broken.
                    if EmailLink.isMessage(link.url) {
                        Text("opens on the Mac")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    #endif
                    Button(role: .destructive) {
                        links.removeAll { $0.id == link.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                TextField("Paste a link…", text: $newLinkURL)
                    .onSubmit(addLink)
                Button("Add", action: addLink)
                    .disabled(newLinkURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Two ways out to somebody else: mail, which can carry the files, and the share
            // sheet, which can reach anything else on the device — a message, a note, a chat.
            // Neither is collaboration: what leaves is a copy of what the strip says today.
            HStack(spacing: 14) {
                Button {
                    sendByEmail()
                } label: {
                    Label("Send by Email…", systemImage: "envelope")
                }
                ShareLink(
                    item: StripMail.shareText(for: draftedStrip()),
                    subject: Text(title),
                    message: Text("")
                ) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.top, 4)
        }
    }

    /// The strip as it stands in the editor, saved or not — sending what's on screen rather than
    /// what was last written down is what someone means by "send this".
    private func draftedStrip() -> TaskItem {
        let task = TaskItem(
            title: title.trimmingCharacters(in: .whitespaces),
            orderIndex: editingTask?.orderIndex ?? nextOrderIndex,
            priority: priority
        )
        task.notes = notes
        task.dueAt = hasDueDate ? dueAt : nil
        task.checklist = checklist
        task.deferUntil = hasDeferUntil ? deferUntil : nil
        task.progress = StripChecklist.progress(of: checklist) ?? Int(progress)
        task.isDone = editingTask?.isDone ?? false
        task.tags = tags
        task.links = links
        task.contacts = contacts
        return task
    }

    private var emailDraft: StripMailSender.Draft {
        StripMailSender.draft(
            for: draftedStrip(),
            files: attachments.map { attachmentStore.url(for: $0) }
        )
    }

    private func sendByEmail() {
        #if os(macOS)
        StripMailSender.send(emailDraft)
        #else
        if StripMailComposer.canSend {
            isEmailing = true
        } else if let url = StripMail.mailtoURL(subject: emailDraft.subject, body: emailDraft.body) {
            // No mail account set up for the composer, so hand it to whatever does have one.
            Platform.open(url)
        }
        #endif
    }

    private func open(_ link: TaskLink) {
        guard let url = URL(string: link.url.trimmingCharacters(in: .whitespaces)) else { return }
        Platform.open(url)
    }

    /// What the clock has to say: what's been spent on this strip, and this week's share of it.
    private var timeTitle: String {
        guard let task = editingTask, !task.sessions.isEmpty else { return "TIME" }
        let total = StripTime.label(StripTime.total(of: task.sessions))
        let week = StripTime.thisWeek(task.sessions)
        return week > 0 ? "TIME: \(total) · \(StripTime.label(week)) THIS WEEK" : "TIME: \(total)"
    }

    private var progressTitle: String {
        if let summary = StripChecklist.summary(of: checklist),
           let fromSteps = StripChecklist.progress(of: checklist) {
            return "PROGRESS: \(fromSteps)% · \(summary) STEPS"
        }
        return "PROGRESS: \(Int(progress))%"
    }

    private func addSteps() {
        let steps = StripChecklist.items(fromTyped: newStep)
        guard !steps.isEmpty else { return }
        checklist.append(contentsOf: steps)
        newStep = ""
    }

    private func addLink() {
        let trimmed = newLinkURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        links.append(TaskLink(url: trimmed, label: ""))
        newLinkURL = ""
    }

    private var contactsEditor: some View {
        VStack(alignment: .leading) {
            ForEach(contacts) { contact in
                HStack {
                    Text(contact.name)
                    Spacer()
                    Button(role: .destructive) {
                        contacts.removeAll { $0.id == contact.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                TextField("Contact name…", text: $newContactName)
                    .onSubmit(addContact)
                Button("Add", action: addContact)
                    .disabled(newContactName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addContact() {
        let trimmed = newContactName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        contacts.append(TaskContact(name: trimmed))
        newContactName = ""
    }

    private var actionLogEditor: some View {
        VStack(alignment: .leading) {
            ForEach(actionLog.sorted(by: { $0.timestamp > $1.timestamp })) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.text)
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        actionLog.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                TextField("Log an action…", text: $newLogEntry)
                    .onSubmit(addLogEntry)
                Button("Add", action: addLogEntry)
                    .disabled(newLogEntry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addLogEntry() {
        let trimmed = newLogEntry.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        actionLog.append(TaskActionLogEntry(text: trimmed, timestamp: .now))
        newLogEntry = ""
    }

    private func chip(_ text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text.uppercased()).font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(TaskStripTheme.amber.opacity(0.2))
        .clipShape(Capsule())
    }
}

// A minimal wrapping HStack, since SwiftUI has no built-in flow layout prior to relying on the
// Layout protocol — used for the tag chips so they wrap instead of overflowing horizontally.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

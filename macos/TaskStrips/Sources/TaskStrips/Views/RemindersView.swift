import SwiftData
import SwiftUI

/// The standalone reminders list, mirroring ui/screens/RemindersScreen.kt.
///
/// Nothing here is work on the board — a birthday, a service due, a document that expires. Search
/// narrows by title, one tag filter narrows the rest, and the sort flips between soonest and
/// latest first.
struct RemindersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Reminder.triggerAt) private var reminders: [Reminder]

    @State private var search = ""
    @State private var tagFilter: String?
    @State private var newestFirst = false
    @State private var editing: Reminder?
    @State private var isCreating = false
    @State private var isDictating = false
    @State private var spokenText = ""
    @ObservedObject private var reader = SpeechReader.shared
    @State private var pendingDeletion: Reminder?
    @State private var notificationsDenied = false

    private var availableTags: [String] { Tagging.availableTags(in: reminders) }
    private var tagEmojis: [String: String] { Tagging.emojis(in: reminders) }
    private var activeTag: String? { Tagging.activeTag(tagFilter, in: reminders) }
    private var visible: [Reminder] {
        ReminderSchedule.visible(reminders, search: search, tag: tagFilter, newestFirst: newestFirst)
    }

    var body: some View {
        VStack(spacing: 0) {
            if notificationsDenied {
                Label(
                    "Notifications are turned off for Task Strips — reminders won't announce themselves until they're allowed in System Settings.",
                    systemImage: "bell.slash"
                )
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TaskStripTheme.baySurface)
            }
            if reminders.isEmpty {
                empty
            } else {
                list
            }
        }
        .frame(minWidth: 520, minHeight: 500)
        .background(TaskStripTheme.bayBackground)
        .searchable(text: $search, placement: .toolbar, prompt: "Search reminders")
        .toolbar { toolbarContent }
        .sheet(isPresented: $isCreating) {
            ReminderEditView(
                reminder: nil,
                spokenText: spokenText,
                onSave: insert,
                onCancel: { isCreating = false; spokenText = "" }
            )
        }
        .sheet(isPresented: $isDictating) {
            SpokenTextSheet(
                title: "New reminder by voice",
                prompt: "Press the dictation key (fn twice) and say it, or type it. "
                    + "The editor opens next for the time and the rest.",
                example: "\"Renew the car registration\"",
                onUse: { text in
                    isDictating = false
                    spokenText = text
                    isCreating = true
                },
                onCancel: { isDictating = false }
            )
        }
        .sheet(item: $editing) { reminder in
            ReminderEditView(reminder: reminder, onSave: { update(reminder, with: $0) }, onCancel: { editing = nil })
        }
        .confirmationDialog(
            "Delete \"\(pendingDeletion?.text ?? "")\"?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let reminder = pendingDeletion { delete(reminder) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This can't be undone.")
        }
        // Rolls any repeating reminder whose moment passed while the app was shut on to its next
        // occurrence — see ReminderSchedule.rolledForward for why that happens here rather than
        // at firing time.
        .task {
            ReminderScheduler.shared.sync(reminders)
            notificationsDenied = await ReminderScheduler.shared.isDenied()
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("NO REMINDERS YET")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("For the things that are only a moment in time, with no strip behind them.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button("New Reminder") { spokenText = ""; isCreating = true }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var list: some View {
        if visible.isEmpty {
            VStack {
                Spacer()
                Text("NOTHING MATCHES")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                ForEach(visible) { reminder in
                    row(for: reminder)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(for reminder: Reminder) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                toggleDone(reminder)
            } label: {
                Image(systemName: reminder.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(reminder.isDone ? TaskStripTheme.normal : .secondary)
            }
            .buttonStyle(.borderless)
            .help(reminder.isDone ? "Reopen" : "Mark done")

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.text)
                    .strikethrough(reminder.isDone)
                if !reminder.details.isEmpty {
                    Text(reminder.details)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Text(ReminderSchedule.summary(for: reminder))
                    if reminder.isTagged {
                        Text(reminder.tagLabel)
                            .foregroundStyle(TaskStripTheme.amber)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                editing = reminder
            } label: {
                Label("Edit \(reminder.text)", systemImage: "square.and.pencil")
            }
            Button(role: .destructive) {
                pendingDeletion = reminder
            } label: {
                Label("Delete \(reminder.text)", systemImage: "trash")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = reminder }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .contextMenu {
            Button(reminder.isDone ? "Reopen" : "Mark Done") { toggleDone(reminder) }
            Button("Edit…") { editing = reminder }
            Button(reader.isSpeaking(reminder.id) ? "Stop Reading" : "Read Aloud") {
                reader.toggle(SpeechReader.speech(for: reminder), id: reminder.id)
            }
            Divider()
            Button("Delete…", role: .destructive) { pendingDeletion = reminder }
        }
    }

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem {
                Menu {
                    Button("All tags") { tagFilter = nil }
                    ForEach(availableTags, id: \.self) { tag in
                        Button([tagEmojis[tag] ?? "", tag].filter { !$0.isEmpty }.joined(separator: " ")) {
                            tagFilter = tag
                        }
                    }
                } label: {
                    Label("Filter by tag", systemImage: activeTag == nil ? "tag" : "tag.fill")
                }
                .disabled(availableTags.isEmpty)
            }
            ToolbarItem {
                Button {
                    newestFirst.toggle()
                } label: {
                    Label(
                        newestFirst ? "Latest first" : "Soonest first",
                        systemImage: newestFirst ? "arrow.down" : "arrow.up"
                    )
                }
            }
            ToolbarItem {
                Button {
                    isDictating = true
                } label: {
                    Label("New reminder by voice", systemImage: "mic")
                }
            }
            ToolbarItem {
                Button {
                    spokenText = ""
                    isCreating = true
                } label: {
                    Label("New reminder", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func insert(_ draft: ReminderDraft) {
        let reminder = Reminder(
            text: draft.text,
            triggerAt: draft.triggerAt,
            details: draft.details,
            leadMinutesBefore: draft.leadMinutesBefore,
            repeatAmount: draft.repeatAmount,
            repeatUnit: draft.repeatUnit,
            tag: draft.tag,
            tagEmoji: draft.tagEmoji
        )
        modelContext.insert(reminder)
        ReminderScheduler.shared.schedule(for: reminder)
        isCreating = false
        spokenText = ""
    }

    private func update(_ reminder: Reminder, with draft: ReminderDraft) {
        reminder.text = draft.text
        reminder.details = draft.details
        reminder.triggerAt = draft.triggerAt
        reminder.leadMinutesBefore = draft.leadMinutesBefore
        reminder.repeatAmount = draft.repeatAmount
        reminder.repeatUnit = draft.repeatUnit
        reminder.tag = draft.tag
        reminder.tagEmoji = draft.tagEmoji
        ReminderScheduler.shared.schedule(for: reminder)
        editing = nil
    }

    private func toggleDone(_ reminder: Reminder) {
        reminder.isDone.toggle()
        // Covers both directions: finishing one clears its pending notification, reopening puts
        // it back.
        ReminderScheduler.shared.schedule(for: reminder)
    }

    private func delete(_ reminder: Reminder) {
        ReminderScheduler.shared.cancel(reminderID: reminder.id)
        modelContext.delete(reminder)
    }
}

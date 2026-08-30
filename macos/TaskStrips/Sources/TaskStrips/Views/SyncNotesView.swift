import SwiftData
import SwiftUI

/// The text list, and the text.
///
/// A list on the left of every synced note, the chosen one open on the right. Editing writes
/// straight into the store and stamps `updatedAt`; syncing is what carries it, and it happens when
/// the page opens, when it closes, and whenever asked.
struct SyncNotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SyncNote.updatedAt, order: .reverse) private var stored: [SyncNote]

    @ObservedObject private var session = DriveSession.shared

    @State private var selection: String?
    @State private var isSyncing = false
    @State private var status: String?
    @State private var problem: String?

    /// Tombstones are how a delete travels; they are not notes.
    private var notes: [SyncNote] { stored.filter { !$0.isDeleted } }
    private var selected: SyncNote? { notes.first { $0.syncID == selection } }

    var body: some View {
        NavigationSplitView {
            list
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 480)
        .navigationTitle("SYNC NOTES")
        .toolbar { toolbarContent }
        .task { await syncNow(quietly: true) }
        .alert("Couldn't sync", isPresented: Binding(
            get: { problem != nil },
            set: { if !$0 { problem = nil } }
        )) {
            Button("OK") { problem = nil }
        } message: {
            Text(problem ?? "")
        }
    }

    // MARK: - The list

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.record.displayTitle)
                            .lineLimit(1)
                        Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(note.syncID)
                    .contextMenu {
                        Button("Delete", role: .destructive) { delete(note) }
                    }
                }
            }
            .frame(minWidth: 220)

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - The text

    @ViewBuilder
    private var detail: some View {
        if let selected {
            SyncNoteEditor(note: selected)
                // Keyed on identity so switching notes rebuilds the editor rather than carrying
                // the previous note's draft into the next one.
                .id(selected.syncID)
        } else if notes.isEmpty {
            empty
        } else {
            Text("Pick a note.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("NOTHING SYNCED YET")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(session.isSignedIn
                 ? "Write something here and it turns up on the phone."
                 : "Sign in to Google Drive from the board's Drive window to sync.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button("New Note") { newNote() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button {
                newNote()
            } label: {
                Label("New Note", systemImage: "plus")
            }
            .keyboardShortcut("n")
            .help("New synced note (⌘N)")
        }
        ToolbarItem {
            Button {
                Task { await syncNow(quietly: false) }
            } label: {
                if isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(isSyncing || !session.isSignedIn)
            .help(session.isSignedIn
                  ? "Sync with the phone through Google Drive (⌘R)"
                  : "Sign in to Google Drive first")
            .keyboardShortcut("r")
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                Task {
                    await syncNow(quietly: true)
                    dismiss()
                }
            }
        }
    }

    // MARK: - Editing

    private func newNote() {
        let note = SyncNote()
        modelContext.insert(note)
        selection = note.syncID
    }

    /// A delete is a tombstone, not a removal: the row has to survive long enough to tell the
    /// other device the note is gone, or the next sync brings it straight back.
    private func delete(_ note: SyncNote) {
        note.isDeleted = true
        note.text = ""
        note.title = ""
        note.updatedAt = .now
        if selection == note.syncID { selection = nil }
        Task { await syncNow(quietly: true) }
    }

    // MARK: - Syncing

    /// `quietly` is for the syncs nobody asked for — opening and closing the page. Those must not
    /// raise an alert over a network that happens to be down, or every visit becomes a dialog.
    private func syncNow(quietly: Bool) async {
        guard session.isSignedIn, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let client = try await session.client()
            let outcome = try await SyncNoteSync(client: client).run(local: stored.map(\.record))
            apply(outcome.merged)
            status = outcome.summary
        } catch {
            status = "Last sync failed."
            if !quietly { problem = error.localizedDescription }
        }
    }

    /// Writes the merge back into the store: existing rows updated in place so nothing that points
    /// at them breaks, and anything the other device knows about that this one doesn't inserted.
    private func apply(_ merged: [SyncNoteRecord]) {
        // Built by hand rather than with uniqueKeysWithValues, which traps on a duplicate key.
        // The unique attribute should make that impossible; a crash is a poor way to find out it
        // didn't.
        var byID: [String: SyncNote] = [:]
        for note in stored { byID[note.syncID] = note }
        for record in merged {
            if let existing = byID[record.id] {
                // Only when the merge actually chose the other side, so an untouched note keeps
                // its row exactly as it was.
                if existing.record != record { existing.apply(record) }
            } else {
                let note = SyncNote(
                    syncID: record.id,
                    title: record.title,
                    text: record.text,
                    updatedAt: record.updatedAt,
                    isDeleted: record.isDeleted
                )
                modelContext.insert(note)
                byID[record.id] = note
            }
        }
    }
}

/// The text itself. Kept apart so its draft state belongs to one note and dies with it.
private struct SyncNoteEditor: View {
    @Bindable var note: SyncNote

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: Binding(
                get: { note.title },
                set: { note.title = $0; note.updatedAt = .now }
            ))
            .textFieldStyle(.plain)
            .font(.title2)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .accessibilityIdentifier("syncNoteTitle")

            Divider().padding(.vertical, 12)

            TextEditor(text: Binding(
                get: { note.text },
                set: { note.text = $0; note.updatedAt = .now }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .accessibilityIdentifier("syncNoteText")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

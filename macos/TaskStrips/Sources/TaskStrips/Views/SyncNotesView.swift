import AppKit
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
    @State private var mode = SyncFolder.mode
    @State private var folderName = SyncNotesView.currentFolderName()

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
                        Button("Copy") { copy(note.text) }
                            .disabled(note.text.isEmpty)
                        Button("Delete", role: .destructive) { delete(note) }
                    }
                }
            }
            .frame(minWidth: 220)

            Divider()
            whereItSyncs
                .padding(8)

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Both ways in, named for what they actually are rather than for the API each uses.
    private var whereItSyncs: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Sync through", selection: $mode) {
                Text("Google Drive").tag(SyncFolder.Mode.drive)
                Text("A folder").tag(SyncFolder.Mode.folder)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { _, new in
                SyncFolder.mode = new
                Task { await syncNow(quietly: true) }
            }

            if mode == .folder {
                HStack(spacing: 6) {
                    Text(folderName ?? "No folder yet")
                        .font(.caption)
                        .foregroundStyle(folderName == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(folderName == nil ? "Choose…" : "Change…") { chooseFolder() }
                        .controlSize(.small)
                }
            } else if !session.isSignedIn {
                Text("Sign in from the board's Drive window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Text(canSync
                 ? "Write something here and it turns up on the phone."
                 : "Choose where to sync below, and it turns up on the phone.")
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
                copy(selected?.text ?? "")
            } label: {
                Label("Copy Note", systemImage: "doc.on.doc")
            }
            .disabled(selected?.text.isEmpty ?? true)
            // Not plain ⌘C, which belongs to whatever is selected in the text editor — this copies
            // the whole note whether or not anything in it is selected, so it needs its own key.
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("Copy the whole note (⇧⌘C)")
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
            .disabled(isSyncing || !canSync)
            .help(mode == .folder
                  ? "Sync through the folder (⌘R)"
                  : "Sync with the phone through Google Drive (⌘R)")
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
        note.updatedAt = .now
        if selection == note.syncID { selection = nil }
        Task { await syncNow(quietly: true) }
    }

    /// Copying is most of why a text is worth syncing at all — it arrives on this machine to be
    /// pasted somewhere else on it.
    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Syncing

    /// `quietly` is for the syncs nobody asked for — opening and closing the page. Those must not
    /// raise an alert over a network that happens to be down, or every visit becomes a dialog.
    private func syncNow(quietly: Bool) async {
        guard !isSyncing, canSync else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Folder mode holds a security-scoped resource for exactly as long as the sync takes.
        var scoped: URL?
        defer { if let scoped { SyncFolder.endAccess(scoped) } }

        do {
            let transport: SyncNoteTransport
            switch mode {
            case .drive:
                transport = DriveSyncTransport(client: try await session.client())
            case .folder:
                guard let folder = SyncFolder.resolve() else {
                    status = "Pick a folder to sync through."
                    return
                }
                scoped = folder
                transport = FolderSyncTransport(folder: folder)
            }

            let outcome = try await SyncNoteSync(transport: transport).run(local: stored.map(\.record))
            apply(outcome.merged)
            status = outcome.summary
        } catch {
            status = "Last sync failed."
            if !quietly { problem = error.localizedDescription }
        }
    }

    private var canSync: Bool {
        switch mode {
        case .drive: return session.isSignedIn
        case .folder: return folderName != nil
        }
    }

    private static func currentFolderName() -> String? {
        guard let url = SyncFolder.resolve() else { return nil }
        defer { SyncFolder.endAccess(url) }
        return url.lastPathComponent
    }

    /// Picking the folder is also how the app is granted access to it — the open panel is the
    /// grant, which is why there is no way to type a path instead.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Sync Here"
        panel.message = "Pick the folder both machines share — inside Google Drive, if you use Drive for desktop."
        panel.directoryURL = SyncFolder.likelyDriveFolder

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard SyncFolder.store(url) else {
            problem = "Couldn't keep access to that folder."
            return
        }
        folderName = url.lastPathComponent
        mode = .folder
        SyncFolder.mode = .folder
        Task { await syncNow(quietly: false) }
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

/// The text itself, and all of it — a synced note has no title field.
///
/// There was one above this editor and it earned its keep nowhere: the list names a note by its
/// first line whether or not a title was typed, so the field was a second place to write the same
/// thing and a decision to make before writing anything at all.
///
/// Kept apart so its draft state belongs to one note and dies with it.
private struct SyncNoteEditor: View {
    @Bindable var note: SyncNote

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextEditor(text: Binding(
                get: { note.text },
                set: { note.text = $0; note.updatedAt = .now }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(12)
            .accessibilityIdentifier("syncNoteText")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

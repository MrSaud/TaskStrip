import SwiftData
import SwiftUI

/// Mirrors ui/screens/NotesScreen.kt: a scratchpad that costs nothing to write to, and two ways
/// out of it — promote the whole note to one strip, or split a jotted list into one strip per
/// line. Both consume the note, exactly as Android does; a thought that became work shouldn't
/// linger here as a second copy of it.
struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    /// Newest first, matching NoteDao's `ORDER BY createdAt DESC` — the note you just wrote is
    /// the one you're still thinking about.
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    /// The board owns where a new strip lands, since it's the only place that knows the current
    /// manual order.
    let nextOrderIndex: () -> Int

    @State private var draft = ""
    /// Says what just happened, because the board it happened to is behind this sheet. Android
    /// doesn't need this — there, promoting navigates you back to the strips.
    @State private var lastAction: String?

    var body: some View {
        VStack(spacing: 0) {
            composer
            Divider()
            list
        }
        .frame(minWidth: 480, minHeight: 460)
        .background(TaskStripTheme.bayBackground)
        .navigationTitle("QUICK NOTES")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Multi-line on purpose, same as Android: jotting a meeting down as one point per
            // line is what makes "Split into Strips" below worth having. Return inserts a line,
            // so the button — or cmd-return — is what files the note.
            TextEditor(text: $draft)
                .accessibilityIdentifier("noteComposer")
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .background(TaskStripTheme.baySurface, in: RoundedRectangle(cornerRadius: 6))
                .frame(minHeight: 72, maxHeight: 120)
                .overlay(alignment: .topLeading) {
                    if draft.isEmpty {
                        Text("Jot a thought… (one point per line for meeting notes)")
                            .font(.body.monospaced())
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                if let lastAction {
                    Text(lastAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Note") { add() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var list: some View {
        if notes.isEmpty {
            VStack {
                Spacer()
                Text("NO NOTES YET")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                ForEach(notes) { note in
                    row(for: note)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(for note: Note) -> some View {
        let lines = NotePromotion.splitLines(of: note.text)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.text)
                    .font(.body.monospaced())
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            // Splitting a single-line note would just be a promotion that threw the text away, so
            // it's offered only when there's more than one line — the same gate as Android's.
            if lines.count > 1 {
                Button {
                    split(note, into: lines.count)
                } label: {
                    Label("Split into Strips", systemImage: "arrow.triangle.branch")
                }
                .help("File one strip per line, dropping any checkbox prefix")
            }
            Button {
                promote(note)
            } label: {
                Label("Promote to Strip", systemImage: "airplane.departure")
            }
            .help("File this note as one strip, keeping the whole text as its notes")
            Button(role: .destructive) {
                modelContext.delete(note)
            } label: {
                Label("Delete Note", systemImage: "trash")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .contextMenu {
            if lines.count > 1 {
                Button("Split into \(lines.count) Strips") { split(note, into: lines.count) }
            }
            Button("Promote to Strip") { promote(note) }
            Divider()
            Button("Delete Note", role: .destructive) { modelContext.delete(note) }
        }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        modelContext.insert(Note(text: text))
        draft = ""
        lastAction = nil
    }

    private func promote(_ note: Note) {
        modelContext.insert(NotePromotion.strip(from: note, orderIndex: nextOrderIndex()))
        modelContext.delete(note)
        lastAction = "Filed 1 strip on the board."
    }

    private func split(_ note: Note, into count: Int) {
        for strip in NotePromotion.strips(splitting: note, startingAt: nextOrderIndex()) {
            modelContext.insert(strip)
        }
        modelContext.delete(note)
        lastAction = "Filed \(count) strips on the board."
    }
}

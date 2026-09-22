import SwiftUI

/// Every sketch note, newest first. Mirrors ui/screens/SketchListScreen.kt.
struct SketchListView: View {
    @Environment(\.dismiss) private var dismiss

    var store: SketchStore = .shared
    /// Set when the list is being used to attach a sketch to a strip: picking one hands it back
    /// instead of opening it.
    var onPick: ((SketchNote) -> Void)?

    @State private var notes: [SketchNote] = []
    @State private var opening: SketchOpen?
    @State private var renaming: SketchNote?
    @State private var renameText = ""
    @State private var deleting: SketchNote?

    private var isPicking: Bool { onPick != nil }

    var body: some View {
        Group {
            if notes.isEmpty {
                empty
            } else {
                grid
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(TaskStripTheme.bayBackground)
        .navigationTitle(isPicking ? "LINK A SKETCH" : "SKETCH NOTES")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(isPicking ? "Cancel" : "Done") { dismiss() }
            }
            if !isPicking {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        opening = SketchOpen(id: SketchStore.newNoteID())
                    } label: {
                        Label("New sketch", systemImage: "plus")
                    }
                    .keyboardShortcut("n")
                }
            }
        }
        .onAppear(perform: refresh)
        // A sheet rather than a pushed screen: this list is itself presented as a sheet from the
        // board, and stacking two navigation levels inside one sheet is how you lose the toolbar.
        .sheet(item: $opening) { open in
            NavigationStack {
                SketchCanvasView(noteID: open.id, store: store, onChange: refresh)
            }
        }
        .sheet(item: $renaming) { note in
            renameSheet(note)
        }
        .confirmationDialog(
            "Delete this sketch?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let note = deleting { store.deleteNote(note.id) }
                deleting = nil
                refresh()
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("\"\(deleting?.displayName ?? "")\" and all its pages will be permanently deleted.")
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "scribble")
                .font(.largeTitle)
                .foregroundStyle(TaskStripTheme.paper.opacity(0.3))
            Text("NO SKETCHES YET")
                .font(.headline)
                .foregroundStyle(TaskStripTheme.paper.opacity(0.5))
            Text(isPicking
                 ? "Draw one from the Sketches window first."
                 : "Click + to draw or write freely.")
                .font(.callout)
                .foregroundStyle(TaskStripTheme.paper.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(notes) { note in
                    tile(note)
                }
            }
            .padding(16)
        }
    }

    private func tile(_ note: SketchNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if let onPick {
                    onPick(note)
                    dismiss()
                } else {
                    opening = SketchOpen(id: note.id)
                }
            } label: {
                ZStack(alignment: .bottomLeading) {
                    thumbnail(note)
                    if note.pageCount > 1 {
                        Text("\(note.pageCount) PAGES")
                            .font(.caption2)
                            .foregroundStyle(TaskStripTheme.paper)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(TaskStripTheme.ink.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }
            }
            .buttonStyle(.plain)

            Text(note.name ?? "UNTITLED SKETCH")
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(TaskStripTheme.paper.opacity(note.name == nil ? 0.5 : 0.85))
            Text("Created \(note.createdLabel)")
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(TaskStripTheme.paper.opacity(0.5))
        }
        .contextMenu {
            Button("Rename…") {
                renameText = note.name ?? ""
                renaming = note
            }
            Button("Delete", role: .destructive) { deleting = note }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(note.displayName)
    }

    private func thumbnail(_ note: SketchNote) -> some View {
        // Re-read every time rather than cached: a page is overwritten in place, so its URL is
        // the same picture it was before the edit as far as any cache can tell.
        let image = store.pages(of: note.id).first.flatMap { SketchRenderer.image(atPath: $0) }
        return Rectangle()
            .fill(TaskStripTheme.paper)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func renameSheet(_ note: SketchNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RENAME SKETCH").font(.headline)
            TextField(SketchStore.dateLabel(note.lastModified), text: $renameText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("sketchName")
            HStack {
                Spacer()
                Button("Cancel") { renaming = nil }
                Button("Save") {
                    store.setName(renameText, of: note.id)
                    renaming = nil
                    refresh()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func refresh() {
        notes = store.notes()
    }
}

/// A note id `.sheet(item:)` can present. A wrapper rather than making String itself Identifiable,
/// which would put a very general conformance in the app's way for the sake of one sheet.
private struct SketchOpen: Identifiable {
    let id: String
}

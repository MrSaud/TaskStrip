import AppKit
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The shared library, mirroring ui/screens/StorageScreen.kt.
///
/// Deliberately not part of any strip: a file lands here once and any strip can take its own copy
/// later. Photos and videos are shown as thumbnails, documents as rows, and one tag filter
/// applies to all three — three separate filters would be more chrome than the page can carry.
struct StorageLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StorageItem.createdAt, order: .reverse) private var items: [StorageItem]

    @State private var tagFilter: String?
    @State private var taggingItem: StorageItem?
    @State private var pendingDeletion: StorageItem?
    @State private var problem: StorageProblem?
    @State private var selection: UUID?
    /// Non-nil while the system Quick Look panel is up. Space puts a URL here and takes it away
    /// again; the panel follows.
    @State private var previewURL: URL?
    @FocusState private var libraryHasFocus: Bool

    private var store: AttachmentStore { .shared }
    private var availableTags: [String] { StorageLibrary.availableTags(in: items) }
    private var tagEmojis: [String: String] { StorageLibrary.tagEmojis(in: items) }
    /// Derived rather than written back to `tagFilter`, so the view never assigns state it is
    /// also reading.
    private var activeTag: String? { StorageLibrary.activeTag(tagFilter, in: items) }
    private var visible: [StorageItem] { StorageLibrary.visible(items, tag: tagFilter) }

    var body: some View {
        Group {
            if items.isEmpty {
                empty
            } else {
                library
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .background(TaskStripTheme.bayBackground)
        .toolbar { toolbarContent }
        .sheet(item: $taggingItem) { item in
            StorageTagSheet(
                name: item.name,
                tag: item.tag,
                emoji: item.tagEmoji,
                onSave: { tag, emoji in
                    item.tag = tag.trimmingCharacters(in: .whitespaces)
                    item.tagEmoji = emoji.trimmingCharacters(in: .whitespaces)
                    taggingItem = nil
                },
                onCancel: { taggingItem = nil }
            )
        }
        .confirmationDialog(
            "Delete \"\(pendingDeletion?.name ?? "")\" from storage?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = pendingDeletion { delete(item) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("The file goes for good. Strips that already took a copy of it keep theirs.")
        }
        .alert(problem?.title ?? "", isPresented: Binding(
            get: { problem != nil },
            set: { if !$0 { problem = nil } }
        )) {
            Button("OK") { problem = nil }
        } message: {
            Text(problem?.message ?? "")
        }
        // The system panel, not a window of our own: it reads anything the Mac can read, which is
        // the whole point of asking for it by name.
        .quickLookPreview($previewURL)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("NOTHING IN STORAGE YET")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Files kept here belong to no strip in particular — any strip can take a copy.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Button("Add Files…") { addFiles(of: nil) }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if activeTag != nil && visible.isEmpty {
                    Text("NOTHING TAGGED \(activeTag?.uppercased() ?? "")")
                        .foregroundStyle(.secondary)
                }
                section(.image) { thumbnails(StorageLibrary.items(visible, ofType: .image)) }
                section(.video) { thumbnails(StorageLibrary.items(visible, ofType: .video)) }
                section(.document) { documents(StorageLibrary.items(visible, ofType: .document)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        // Focusable so the space bar has somewhere to land. Clicking a file moves focus here, and
        // the focus ring is suppressed because the selected tile already shows where you are.
        .focusable()
        .focusEffectDisabled()
        .focused($libraryHasFocus)
        .onKeyPress(.space, action: toggleQuickLook)
        // Clicking the background is how you stop having something selected.
        .onTapGesture { selection = nil }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ type: StorageItemType,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let matching = StorageLibrary.items(visible, ofType: type)
        if !matching.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(type.sectionTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(TaskStripTheme.amber)
                content()
            }
        }
    }

    private func thumbnails(_ items: [StorageItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
            ForEach(items) { item in
                thumbnail(for: item)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(TaskStripTheme.amber, lineWidth: selection == item.id ? 3 : 0)
                    }
                    .help(item.name)
                    // The count: 2 gesture has to come first, or the single tap swallows it.
                    .onTapGesture(count: 2) { quickLook(item) }
                    .onTapGesture { select(item) }
                    .contextMenu { itemMenu(item) }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for item: StorageItem) -> some View {
        // Videos have no still to show without decoding a frame, so they get their category's
        // symbol rather than a blank tile.
        if item.type == .image, let image = NSImage(contentsOf: store.url(forRelativePath: item.path)) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                TaskStripTheme.baySurface
                Image(systemName: item.type.systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func documents(_ items: [StorageItem]) -> some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(TaskStripTheme.amber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 8) {
                            if !StorageLibrary.readableSize(item.sizeBytes).isEmpty {
                                Text(StorageLibrary.readableSize(item.sizeBytes))
                            }
                            if item.isTagged {
                                Text(item.tagLabel)
                                    .foregroundStyle(TaskStripTheme.amber)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        taggingItem = item
                    } label: {
                        Label("Tag \(item.name)", systemImage: item.isTagged ? "tag.fill" : "tag")
                    }
                    Button(role: .destructive) {
                        pendingDeletion = item
                    } label: {
                        Label("Remove \(item.name)", systemImage: "trash")
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .padding(12)
                .background(
                    selection == item.id ? TaskStripTheme.amber.opacity(0.25) : TaskStripTheme.baySurface,
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { quickLook(item) }
                .onTapGesture { select(item) }
                .contextMenu { itemMenu(item) }
            }
        }
    }

    @ViewBuilder
    private func itemMenu(_ item: StorageItem) -> some View {
        // Named the way Finder names it, space hint included, because that's where the shortcut
        // is worth discovering.
        Button("Quick Look (Space)") { quickLook(item) }
        Button("Show in Finder") { reveal(item) }
        Button(item.isTagged ? "Change Tag…" : "Tag…") { taggingItem = item }
        Divider()
        Button("Delete…", role: .destructive) { pendingDeletion = item }
    }

    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem {
                Menu {
                    Button("All") { tagFilter = nil }
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
                Menu {
                    Button("Add Photos…") { addFiles(of: .image) }
                    Button("Add Videos…") { addFiles(of: .video) }
                    Button("Add Files…") { addFiles(of: nil) }
                } label: {
                    Label("Add to storage", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    /// `type` narrows the open panel; nil takes anything and lets the file decide where it lands.
    private func addFiles(of type: StorageItemType?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        switch type {
        case .image: panel.allowedContentTypes = [.image]
        case .video: panel.allowedContentTypes = [.movie]
        case .document, nil: break
        }
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            do {
                let resolved = type ?? StorageItemType.inferred(
                    mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType,
                    name: url.lastPathComponent
                )
                let copy = try store.add(contentsOf: url, kind: resolved.attachmentKind)
                modelContext.insert(
                    StorageItem(
                        name: url.lastPathComponent,
                        path: copy.path,
                        type: resolved,
                        mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "",
                        sizeBytes: fileSize(of: url)
                    )
                )
            } catch {
                problem = StorageProblem(
                    title: "Couldn't add that file",
                    message: error.localizedDescription
                )
                return
            }
        }
    }

    private func fileSize(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func select(_ item: StorageItem) {
        selection = item.id
        libraryHasFocus = true
    }

    private func toggleQuickLook() -> KeyPress.Result {
        switch StorageLibrary.quickLookAction(
            selection: selection, in: visible, isPreviewing: previewURL != nil
        ) {
        case .close:
            previewURL = nil
        case .open(let id):
            guard let item = visible.first(where: { $0.id == id }) else { return .ignored }
            quickLook(item)
        case .nothing:
            // Nothing selected: hand the key back rather than swallowing it, so space still
            // pages the list the way it does in every other scroll view on the Mac.
            return .ignored
        }
        return .handled
    }

    /// Opens the preview, and selects what it's previewing — so space closes it again and the
    /// next space reopens the same thing.
    private func quickLook(_ item: StorageItem) {
        selection = item.id
        libraryHasFocus = true
        let url = store.url(forRelativePath: item.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            problem = StorageProblem(
                title: "Nothing to preview",
                message: "\"\(item.name)\" is listed here but its file isn't on this Mac. "
                    + "It may not have come across in a restore."
            )
            return
        }
        previewURL = url
    }

    private func reveal(_ item: StorageItem) {
        NSWorkspace.shared.activateFileViewerSelecting([store.url(forRelativePath: item.path)])
    }

    private func delete(_ item: StorageItem) {
        store.remove(relativePath: item.path, kind: item.type.attachmentKind)
        modelContext.delete(item)
    }
}

/// Something that went wrong, with a title that says which thing — adding a file and previewing
/// one fail for entirely different reasons, and one alert title can't cover both.
private struct StorageProblem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Assigns an item's tag and emoji. Clearing both makes it untagged again, which also drops the
/// tag from the filter menu once nothing still uses it.
struct StorageTagSheet: View {
    let name: String
    @State private var tag: String
    @State private var emoji: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    init(
        name: String,
        tag: String,
        emoji: String,
        onSave: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.name = name
        _tag = State(initialValue: tag)
        _emoji = State(initialValue: emoji)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tag this file")
                .font(.title3.weight(.semibold))
            Text(name)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 10) {
                TextField("Tag", text: $tag)
                TextField("Emoji", text: $emoji)
                    .frame(width: 90)
                    // A tag's emoji is one glyph's worth of decoration, not a second label.
                    .onChange(of: emoji) { _, new in
                        if new.count > 4 { emoji = String(new.prefix(4)) }
                    }
            }
            .textFieldStyle(.roundedBorder)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(StorageLibrary.tagPresets, id: \.tag) { preset in
                    Button("\(preset.emoji) \(preset.tag)") {
                        tag = preset.tag
                        emoji = preset.emoji
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Clear") { onSave("", "") }
                    .disabled(tag.isEmpty && emoji.isEmpty)
                Button("Save") { onSave(tag, emoji) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 340)
        .background(TaskStripTheme.bayBackground)
    }
}

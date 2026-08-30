import SwiftData
import SwiftUI

/// Taking files out of the library and onto a strip, mirroring StoragePickerDialog.kt.
///
/// Android opens one of these per category, because its editor keeps four separate attachment
/// lists. The Mac editor keeps one, so this shows the whole library with a filter across the top
/// — same choice, one dialog instead of three.
struct StoragePickerSheet: View {
    @Query(sort: \StorageItem.createdAt, order: .reverse) private var items: [StorageItem]
    let store: AttachmentStore
    let onAdd: ([StorageItem]) -> Void
    let onCancel: () -> Void

    @State private var typeFilter: StorageItemType?
    @State private var selection: Set<UUID> = []

    private var visible: [StorageItem] {
        guard let typeFilter else { return items }
        return StorageLibrary.items(items, ofType: typeFilter)
    }

    /// A row whose file isn't on disk can't be copied anywhere — it's shown, so the library reads
    /// the same here as it does everywhere else, but it can't be picked.
    private func isAvailable(_ item: StorageItem) -> Bool {
        FileManager.default.fileExists(atPath: store.url(forRelativePath: item.path).path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add from storage")
                .font(.title3.weight(.semibold))

            Picker("Show", selection: $typeFilter) {
                Text("All").tag(StorageItemType?.none)
                ForEach(StorageItemType.allCases) { type in
                    Text(type.sectionTitle.capitalized).tag(StorageItemType?.some(type))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if visible.isEmpty {
                VStack {
                    Spacer()
                    Text(items.isEmpty ? "NOTHING IN STORAGE YET" : "NOTHING OF THAT KIND IN STORAGE")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(visible, selection: $selection) { item in
                    row(for: item)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(selection.isEmpty ? "Add" : "Add \(selection.count)") {
                    onAdd(visible.filter { selection.contains($0.id) })
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480, height: 420)
        .background(TaskStripTheme.bayBackground)
    }

    private func row(for item: StorageItem) -> some View {
        let available = isAvailable(item)
        return HStack(spacing: 10) {
            Image(systemName: item.type.systemImage)
                .foregroundStyle(available ? TaskStripTheme.amber : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if item.isTagged { Text(item.tagLabel) }
                    if !StorageLibrary.readableSize(item.sizeBytes).isEmpty {
                        Text(StorageLibrary.readableSize(item.sizeBytes))
                    }
                    if !available {
                        Text("missing")
                            .foregroundStyle(TaskStripTheme.urgent)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .tag(item.id)
        .selectionDisabled(!available)
        .opacity(available ? 1 : 0.5)
    }
}

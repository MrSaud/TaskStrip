import SwiftUI

/// Confirmation step between picking a backup file and writing anything to the board.
///
/// The board is the only copy of the user's Mac-side strips, so a restore that silently replaced
/// it would be unrecoverable. This shows what the file actually contains — including the parts
/// that can't come across — and makes Replace an explicit second choice next to Add.
struct ImportBackupSheet: View {
    let summary: BackupImportSummary
    let existingCount: Int
    let onImport: (ImportMode) -> Void
    let onCancel: () -> Void

    @State private var confirmingReplace = false

    private var archivedCount: Int { summary.tasks.filter(\.isArchived).count }
    private var activeCount: Int { summary.tasks.count - archivedCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Android backup")
                    .font(.title2.weight(.semibold))
                Text(summary.tasks.isEmpty
                     ? "This backup has no strips in it."
                     : "Found \(summary.tasks.count) strip\(summary.tasks.count == 1 ? "" : "s") — \(activeCount) on the board, \(archivedCount) archived.")
                    .foregroundStyle(.secondary)
            }

            if !notImported.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Not imported", systemImage: "exclamationmark.triangle")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(TaskStripTheme.high)
                    ForEach(notImported, id: \.self) { line in
                        Text("• \(line)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("The Android backup file keeps them — nothing is deleted there.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TaskStripTheme.baySurface, in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Replace Board…") { confirmingReplace = true }
                    .disabled(existingCount == 0)
                Button("Add to Board") { onImport(.add) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(summary.tasks.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 300)
        .background(TaskStripTheme.bayBackground)
        .alert("Replace everything on the board?", isPresented: $confirmingReplace) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) { onImport(.replace) }
        } message: {
            Text("This deletes the \(existingCount) strip\(existingCount == 1 ? "" : "s") already on this Mac, archived ones included, and puts the backup's \(summary.tasks.count) in their place. It can't be undone.")
        }
    }

    /// Everything in the file that this app has no home for yet, phrased for the sheet.
    private var notImported: [String] {
        var lines: [String] = []
        if summary.attachmentCount > 0 {
            lines.append("\(summary.attachmentCount) attachment\(summary.attachmentCount == 1 ? "" : "s") (images, voice notes, documents, videos)")
        }
        if summary.reminderOnTaskCount > 0 {
            lines.append("reminders on \(summary.reminderOnTaskCount) strip\(summary.reminderOnTaskCount == 1 ? "" : "s")")
        }
        for section in summary.skippedSections {
            lines.append("\(section.count) \(section.name)")
        }
        return lines
    }
}

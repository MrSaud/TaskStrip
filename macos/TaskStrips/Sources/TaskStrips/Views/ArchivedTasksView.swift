import SwiftUI

// Mirrors ui/screens/ArchiveScreen.kt: a read-mostly list of archived tasks with a way back
// (unarchive) or gone for good (delete).
struct ArchivedTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let tasks: [TaskItem]
    /// The board owns where an unarchived strip lands, since it's the only place that knows the
    /// current manual order.
    let onUnarchive: (TaskItem) -> Void

    var body: some View {
        List {
            if tasks.isEmpty {
                Text("No archived strips")
                    .foregroundStyle(.secondary)
            }
            ForEach(tasks) { task in
                HStack {
                    VStack(alignment: .leading) {
                        Text(task.title).strikethrough(task.isDone)
                        if !task.tags.isEmpty {
                            Text(task.tags.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Unarchive") { onUnarchive(task) }
                    Button(role: .destructive) {
                        modelContext.delete(task)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .navigationTitle("ARCHIVED TASKS")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .frame(minWidth: 420, minHeight: 400)
    }
}

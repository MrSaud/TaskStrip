import SwiftData
import SwiftUI

/// Offered after a sketch is saved: put it on a strip, or don't.
///
/// A sketch made in the middle of doing something usually belongs to that something — the marked
/// up invoice belongs to the invoice strip — but it's saved as a note of its own and then has to
/// be found again from the strip's editor. Asking once, right after it's saved, is the moment
/// somebody knows which strip it was for.
///
/// Never in the way: it's a bar along the bottom of the page, it can be waved off, and it doesn't
/// come back for the same note.
struct SketchStripLinkBar: View {
    let noteID: String
    let onDismiss: () -> Void

    @Query(
        filter: #Predicate<TaskItem> { !$0.isArchived && !$0.isDone },
        sort: [SortDescriptor(\TaskItem.orderIndex)]
    ) private var strips: [TaskItem]
    @Environment(\.modelContext) private var context
    @State private var linked: String?

    /// Nothing to offer if it's already on a strip: that question has been answered.
    private var alreadyLinked: TaskItem? { strips.first { $0.linkedSketchID == noteID } }

    var body: some View {
        if let linked {
            bar {
                Label("Linked to \(linked)", systemImage: "checkmark.circle")
                    .font(.callout)
                Spacer(minLength: 0)
            }
            .task {
                // Long enough to read, then out of the way.
                try? await Task.sleep(for: .seconds(2))
                onDismiss()
            }
        } else if alreadyLinked == nil, !strips.isEmpty {
            bar {
                Text("Link this sketch to a strip?")
                    .font(.callout)
                Spacer(minLength: 0)
                StripPickerMenu(
                    title: "Link this sketch to",
                    note: { $0.linkedSketchID == nil ? nil : "replaces its sketch" },
                    onPick: link
                ) {
                    Label("Choose a strip", systemImage: "link")
                        .font(.callout)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button("Not now", action: onDismiss)
                    .buttonStyle(.borderless)
            }
        }
    }

    private func bar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12, content: content)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(TaskStripTheme.baySurface)
            .overlay(alignment: .top) {
                Rectangle().fill(TaskStripTheme.paper.opacity(0.12)).frame(height: 1)
            }
    }

    /// A strip holds one sketch, so picking a strip that already has one replaces it — which the
    /// menu says in the row before it's tapped.
    private func link(to strip: TaskItem) {
        strip.linkedSketchID = noteID
        strip.actionLog.append(TaskActionLogEntry(text: "Linked a sketch", timestamp: .now))
        try? context.save()
        linked = strip.title.isEmpty ? "the strip" : strip.title
    }
}

import AppKit
import SwiftUI

/// Which roll-up is on screen. Two separate screens on Android; one sheet with a switch here,
/// because a Mac window can afford the segmented control and both answer the same question —
/// what does the board actually say right now.
enum RollUp: String, CaseIterable, Identifiable {
    case standup = "Standup"
    case tags = "Tag Progress"
    var id: String { rawValue }
}

struct RollUpsView: View {
    @Environment(\.dismiss) private var dismiss
    /// The board: the strips that aren't archived. See StandupSummary.make.
    let tasks: [TaskItem]
    @State private var selection: RollUp
    @State private var didCopy = false

    init(showing: RollUp, tasks: [TaskItem]) {
        self.tasks = tasks
        _selection = State(initialValue: showing)
    }

    private var summary: StandupSummary { StandupSummary.make(from: tasks) }
    private var tagStats: [TagProgress] { TagProgress.stats(for: tasks) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Roll-up", selection: $selection) {
                ForEach(RollUp.allCases) { rollUp in
                    Text(rollUp.rawValue).tag(rollUp)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            switch selection {
            case .standup: standup
            case .tags: tagProgress
            }
        }
        .frame(minWidth: 460, minHeight: 460)
        .background(TaskStripTheme.bayBackground)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    copySummary()
                } label: {
                    Label(didCopy ? "Copied" : "Copy Summary", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(selection != .standup)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var standup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("DONE RECENTLY", summary.doneRecently, empty: "Nothing completed in the last 24h")
                section("PLANNED TODAY", summary.plannedToday, empty: "Nothing due today or overdue")
                section("BLOCKERS", summary.blocked, empty: "Nothing blocked")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func section(_ title: String, _ tasks: [TaskItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(TaskStripTheme.amber)
            if tasks.isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tasks) { task in
                    Text(task.title.uppercased())
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(TaskStripTheme.baySurface, in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    @ViewBuilder
    private var tagProgress: some View {
        let stats = tagStats
        if stats.isEmpty {
            VStack {
                Spacer()
                Text("NO TAGGED STRIPS YET")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(stats) { stat in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(stat.tag.uppercased())
                                Spacer()
                                Text("\(stat.done)/\(stat.total)")
                                    .foregroundStyle(TaskStripTheme.amber)
                            }
                            ProgressView(value: stat.fraction)
                                .tint(TaskStripTheme.amber)
                        }
                        .padding(14)
                        .background(TaskStripTheme.baySurface, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(16)
            }
        }
    }

    private func copySummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary.plainText, forType: .string)
        // The button says so rather than a toast: a sheet has nowhere to put one, and a button
        // that reads "Copied" is the same acknowledgement without the transient overlay.
        didCopy = true
    }
}

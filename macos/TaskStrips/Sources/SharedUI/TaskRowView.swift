import SwiftUI

// Mirrors ui/components/FlightStripRow.kt's visual language (colored priority tab, monospace
// paper-on-tray look, DUE/TAGS fields, progress track) — the v1 subset relevant to core tasks,
// leaving out attachment/voice-note indicators since Storage isn't in scope yet.
struct TaskRowView: View {
    let task: TaskItem
    let blocker: TaskItem?

    private var isBlocked: Bool { blocker != nil && blocker?.isDone == false }

    private var emailCount: Int { task.links.filter { EmailLink.isMessage($0.url) }.count }
    private var linkCount: Int { task.links.count - emailCount }

    private var isOverdue: Bool {
        guard !task.isDone, let due = task.dueAt else { return false }
        return due <= .now
    }

    private var dueColor: Color {
        guard let due = task.dueAt else { return TaskStripTheme.paper }
        return due.timeIntervalSinceNow <= 2 * 24 * 3600 ? TaskStripTheme.urgent : TaskStripTheme.amber
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(task.priority.tabColor)
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(task.title.uppercased())
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .strikethrough(task.isDone)
                        .foregroundStyle(TaskStripTheme.paper)
                        .lineLimit(1)
                    Spacer()
                    Text("FILED \(task.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(TaskStripTheme.paper.opacity(0.45))
                    Text(task.priority.label)
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(task.priority.tabColor)
                }

                Divider().overlay(TaskStripTheme.paper.opacity(0.15))

                HStack {
                    if !task.tags.isEmpty {
                        stripField(label: "TAGS", value: task.tags.map { $0.uppercased() }.joined(separator: ", "))
                    }
                    if let due = task.dueAt {
                        stripField(label: "DUE", value: due.formatted(date: .abbreviated, time: .shortened), color: dueColor)
                    }
                    if isOverdue {
                        Image(systemName: "alarm.fill")
                            .foregroundStyle(TaskStripTheme.urgent)
                            .font(.caption)
                    }
                    if !task.attachments.isEmpty {
                        Label("\(task.attachments.count)", systemImage: "paperclip")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(TaskStripTheme.paper.opacity(0.6))
                    }
                    // A linked email and a linked page are both worth seeing from the board:
                    // a link nobody can tell is there is a link nobody opens.
                    // A running clock is the one thing on a strip that's happening right now, so
                    // it's amber and it's first.
                    if StripTime.isRunning(task.sessions) {
                        Label(StripTime.label(StripTime.total(of: task.sessions)), systemImage: "record.circle")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(TaskStripTheme.amber)
                    } else if StripTime.total(of: task.sessions) > 0 {
                        Label(StripTime.label(StripTime.total(of: task.sessions)), systemImage: "clock")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(TaskStripTheme.paper.opacity(0.6))
                    }
                    // What this strip has cost so far, in whatever it's counted in. On the row
                    // because the whole point of keeping a total is seeing it without opening
                    // anything — and in urgent where a target has been passed.
                    if !StripTally.summary(task.tallies).isEmpty {
                        Label(StripTally.summary(task.tallies), systemImage: "sum")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(
                                task.tallies.contains(where: \.isOverTarget)
                                    ? TaskStripTheme.urgent
                                    : TaskStripTheme.paper.opacity(0.6)
                            )
                    }
                    if let steps = StripChecklist.summary(of: task.checklist) {
                        Label(steps, systemImage: "checklist")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(TaskStripTheme.paper.opacity(0.6))
                    }
                    if emailCount > 0 {
                        Label("\(emailCount)", systemImage: "envelope")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(TaskStripTheme.amber.opacity(0.85))
                    }
                    if linkCount > 0 {
                        Label("\(linkCount)", systemImage: "link")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(TaskStripTheme.paper.opacity(0.6))
                    }
                    Spacer()
                }

                if let deferred = StripDeferral.label(task.deferUntil) {
                    Label(deferred, systemImage: "moon.zzz")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(TaskStripTheme.low)
                        .lineLimit(1)
                }

                if isBlocked || (!task.waitingOnName.isEmpty && !task.isDone) {
                    HStack(spacing: 10) {
                        if isBlocked {
                            Label("BLOCKED BY \(blocker?.title.uppercased() ?? "")", systemImage: "hand.raised.fill")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(TaskStripTheme.urgent)
                                .lineLimit(1)
                        }
                        if !task.waitingOnName.isEmpty && !task.isDone {
                            Label("WAITING ON \(task.waitingOnName.uppercased())", systemImage: "hourglass")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(TaskStripTheme.paper.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                }

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(TaskStripTheme.paper.opacity(0.6))
                        .lineLimit(1)
                }

                ZStack(alignment: .trailing) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(TaskStripTheme.paper.opacity(0.1))
                            Rectangle()
                                .fill(task.priority.tabColor)
                                .frame(width: geo.size.width * CGFloat(task.progress.clamped(0, 100)) / 100)
                        }
                    }
                    .frame(height: 4)
                    if task.progress > 0 {
                        Text("\(task.progress)%")
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(task.priority.tabColor)
                            .offset(y: -10)
                    }
                }
            }
            .padding(10)
        }
        .background(task.isDone ? TaskStripTheme.baySurfaceFaded : TaskStripTheme.baySurface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // A hairline and a soft shadow: in the dark the strip separates from the bay by being
        // lighter, in daylight it has to separate by having an edge.
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(TaskStripTheme.paper.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
        .opacity(task.isDone ? 0.7 : 1)
    }

    private func stripField(label: String, value: String, color: Color = TaskStripTheme.paper) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(TaskStripTheme.paper.opacity(0.5))
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .padding(.trailing, 14)
    }
}

extension Comparable {
    func clamped(_ lower: Self, _ upper: Self) -> Self {
        min(max(self, lower), upper)
    }
}

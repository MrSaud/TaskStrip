import SwiftData
import SwiftUI

/// The ten minutes on a Thursday that catch what nothing else does.
///
/// Everything else in the app tells you about a moment — this is due, that's late, somebody was
/// chased. This is the opposite: the strips that have said nothing at all, which is exactly why
/// nothing else brings them up.
struct WeeklyReviewView: View {
    let tasks: [TaskItem]
    let onEdit: (TaskItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var now = Date.now

    private var review: WeeklyReview { WeeklyReview.make(from: tasks, now: now) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if review.isEmpty {
                nothing
            } else {
                list
            }
        }
        .readerSize()
        .background(TaskStripTheme.bayBackground)
        .onAppear { now = .now }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("THE WEEK IN REVIEW")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TaskStripTheme.amber)
                Text(summary)
                    .font(.headline)
            }
            Spacer(minLength: 0)
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding(14)
        .background(TaskStripTheme.baySurfaceFaded)
    }

    private var summary: String {
        let needing = review.needingAttention
        let finished = review.finished.count
        switch (needing, finished) {
        case (0, 0): return "A quiet week"
        case (0, _): return "\(finished) finished, nothing stuck"
        case (_, 0): return "\(needing) worth a look"
        default: return "\(finished) finished · \(needing) worth a look"
        }
    }

    private var nothing: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(TaskStripTheme.normal)
            Text("Nothing stalled, nothing abandoned, nobody left waiting.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        List {
            section(
                "STALLED",
                review.stalled,
                tint: TaskStripTheme.urgent,
                note: "Nothing has happened to these in a fortnight.",
                detail: { "quiet for \(WeeklyReview.silence(of: $0, now: now))" }
            )
            section(
                "STARTED AND LEFT",
                review.halfFinished,
                tint: TaskStripTheme.high,
                note: "Some steps ticked, the rest untouched for a week.",
                detail: { strip in
                    let done = StripChecklist.summary(of: strip.checklist) ?? ""
                    return "\(done) · quiet for \(WeeklyReview.silence(of: strip, now: now))"
                }
            )
            section(
                "WAITING TOO LONG",
                review.waitingTooLong,
                tint: TaskStripTheme.high,
                note: "Past the follow-up, or never given one.",
                detail: { strip in
                    let days = StripChase.daysWaiting(strip, now: now).map { "\($0) days" } ?? "a while"
                    return "waiting on \(strip.waitingOnName) · \(days)"
                }
            )
            section(
                "BUDGETS CREEPING",
                review.budgetsCreeping,
                tint: TaskStripTheme.high,
                note: "Three quarters of the way through what they were allowed.",
                detail: { strip in
                    strip.tallies
                        .filter(WeeklyReview.isCreeping)
                        .map { "\($0.name): \(StripTally.formatted($0.total, unit: $0.unit)) of \(StripTally.formatted($0.target ?? 0, unit: $0.unit))" }
                        .joined(separator: " · ")
                }
            )
            section(
                "FINISHED THIS WEEK",
                review.finished,
                tint: TaskStripTheme.normal,
                note: nil,
                detail: { strip in
                    strip.completedAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
                }
            )
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func section(
        _ title: String,
        _ strips: [TaskItem],
        tint: Color,
        note: String?,
        detail: @escaping (TaskItem) -> String
    ) -> some View {
        if !strips.isEmpty {
            Section {
                ForEach(strips) { strip in
                    Button {
                        onEdit(strip)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(strip.title.isEmpty ? "(untitled)" : strip.title)
                                .font(.callout)
                                .lineLimit(1)
                            Text(detail(strip))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            } header: {
                HStack(spacing: 6) {
                    Text("\(title) (\(strips.count))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                    Spacer(minLength: 0)
                }
            } footer: {
                if let note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

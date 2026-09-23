import SwiftUI

/// The dates found in a document, and what to do with one.
///
/// A scanned letter has a date on it that somebody has to act on, and the usual way that reaches
/// a board is somebody reading it and typing it in. This reads it instead: the words come off the
/// page, the dates come out of the words, and the line each one sits on says which is the one
/// that matters.
struct DocumentDatesView: View {
    let title: String
    let url: URL
    /// Called with the date to put on the strip — as a due date, or as a reminder.
    let onUse: (FoundDate, Use) -> Void

    enum Use { case dueDate, reminder }

    @Environment(\.dismiss) private var dismiss
    @State private var found: [FoundDate] = []
    @State private var isReading = true
    @State private var problem: String?
    @State private var used: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .readerSize()
        .background(TaskStripTheme.bayBackground)
        .task { await read() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DATES IN THIS DOCUMENT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TaskStripTheme.amber)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding(14)
        .background(TaskStripTheme.baySurfaceFaded)
    }

    @ViewBuilder
    private var content: some View {
        if isReading {
            centred {
                ProgressView()
                Text("Reading the document…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let problem {
            centred {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(TaskStripTheme.high)
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else if found.isEmpty {
            centred {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No dates found in this document.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("A photograph taken at an angle, or a faint scan, can read badly enough to hide them.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        } else {
            List {
                if let used {
                    Text(used)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(found) { date in
                    row(for: date)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(for date: FoundDate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(date.kind.label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TaskStripTheme.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colour(for: date.kind), in: Capsule())
                Text(date.date.formatted(date: .long, time: .omitted))
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                if date.date < .now {
                    Text("past")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            // The line it was found on, which is what says whether this is the right date.
            Text(date.context)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Button {
                    onUse(date, .dueDate)
                    used = "Due date set to \(date.date.formatted(date: .abbreviated, time: .omitted))."
                } label: {
                    Label("Set as due date", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
                Button {
                    onUse(date, .reminder)
                    used = "Reminder added for \(date.date.formatted(date: .abbreviated, time: .omitted))."
                } label: {
                    Label("Remind me", systemImage: "bell")
                }
                .buttonStyle(.bordered)
            }
            .font(.callout)
        }
        .padding(.vertical, 6)
    }

    private func colour(for meaning: DocumentDates.Meaning) -> Color {
        switch meaning {
        case .deadline: return TaskStripTheme.urgent
        case .expiry: return TaskStripTheme.high
        case .appointment: return TaskStripTheme.normal
        case .issued, .unknown: return TaskStripTheme.low
        }
    }

    private func centred<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            Spacer()
            content()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func read() async {
        isReading = true
        problem = nil
        do {
            let text = try await DocumentTextReader.text(of: url)
            found = DocumentDates.find(in: text)
        } catch {
            problem = error.localizedDescription
        }
        isReading = false
    }
}

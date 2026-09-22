import SwiftUI

/// What a backup is doing while it does it.
///
/// A phone's worth of photos takes real time to pack or unpack, and until now the window simply
/// stopped responding — which looks exactly like a crash. This says which step is running and,
/// once it's copying files, how far through it is.
struct BackupProgress: Equatable {
    var title: String
    var step: String
    /// Nil while the work has no countable unit — signing in, talking to Drive, writing the zip.
    var completed: Int?
    var total: Int?

    var fraction: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return Double(completed) / Double(total)
    }

    init(title: String, step: String, completed: Int? = nil, total: Int? = nil) {
        self.title = title
        self.step = step
        self.completed = completed
        self.total = total
    }
}

struct BackupProgressView: View {
    let progress: BackupProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(progress.title)
                .font(.headline)

            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .tint(TaskStripTheme.amber)
            } else {
                // Indeterminate: a spinner is honest about not knowing, where a bar stuck at zero
                // reads as stuck.
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(TaskStripTheme.amber)
            }

            HStack {
                Text(progress.step)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if let completed = progress.completed, let total = progress.total, total > 0 {
                    Text("\(completed) of \(total)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(TaskStripTheme.bayBackground)
        // Nothing to cancel with: the work is one file-system pass, and stopping halfway through
        // a restore would leave the board holding a partial import.
        .interactiveDismissDisabled()
    }
}

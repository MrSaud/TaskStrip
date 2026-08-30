import SwiftUI

/// Saying something short and having it land in a field, for the places that take the sentence
/// as it comes rather than parsing it.
///
/// Android's NEW REMINDER BY VOICE does exactly this: the spoken text becomes the reminder's
/// title, and the editor opens for the rest. Nothing here asks for the microphone — it's the
/// system's own dictation writing into an ordinary field.
struct SpokenTextSheet: View {
    let title: String
    let prompt: String
    let example: String
    let onUse: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(prompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .accessibilityIdentifier("spokenText")
                .font(.body.monospaced())
                .focused($focused)
                .scrollContentBackground(.hidden)
                .background(TaskStripTheme.baySurface, in: RoundedRectangle(cornerRadius: 6))
                .frame(height: 90)

            Text(example)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Continue") { onUse(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440, height: 300)
        .background(TaskStripTheme.bayBackground)
        .onAppear { focused = true }
    }
}

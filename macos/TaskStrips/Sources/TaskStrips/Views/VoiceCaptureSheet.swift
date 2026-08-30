import SwiftUI

/// Filing a strip by saying it, mirroring HomeScreen.kt's CREATE BY VOICE.
///
/// Android hands the spoken sentence to the parser and then opens the editor so the result can be
/// checked before it's saved. This does the checking here instead: the parsed fields are editable
/// in place, which is the same guarantee — nothing is filed that you haven't seen — without a
/// second sheet on top of this one.
struct VoiceCaptureSheet: View {
    let onFile: (VoiceDraft) -> Void
    let onCancel: () -> Void

    @State private var sentence = ""
    @State private var title = ""
    @State private var notes = ""
    @State private var priority: Priority = .normal
    @FocusState private var sentenceFocused: Bool

    private var canFile: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("File a strip by voice")
                    .font(.title3.weight(.semibold))
                // No microphone permission is asked for, because none is needed: this is the
                // system's own dictation writing into an ordinary text field.
                Text("Press the dictation key (fn twice) and say it, or type it. "
                     + "Try: \"add a strip for renew the passport, urgent, notes bring the old one\".")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $sentence)
                .accessibilityIdentifier("voiceSentence")
                .font(.body.monospaced())
                .focused($sentenceFocused)
                .scrollContentBackground(.hidden)
                .background(TaskStripTheme.baySurface, in: RoundedRectangle(cornerRadius: 6))
                .frame(height: 70)
                // Re-parsed as the sentence changes, which overwrites anything typed into the
                // fields below — say it, then correct it, not the other way round.
                .onChange(of: sentence) { _, new in
                    let draft = VoiceCommandParser.parse(new)
                    title = draft.title
                    notes = draft.notes
                    priority = draft.priority ?? .normal
                }

            Divider()

            Text("WHAT WILL BE FILED")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TaskStripTheme.amber)

            Form {
                TextField("Title", text: $title)
                    .accessibilityIdentifier("voiceTitle")
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("File Strip") {
                    onFile(
                        VoiceDraft(
                            title: title.trimmingCharacters(in: .whitespaces),
                            notes: notes.trimmingCharacters(in: .whitespaces),
                            priority: priority
                        )
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canFile)
            }
        }
        .padding(20)
        .frame(width: 480, height: 470)
        .background(TaskStripTheme.bayBackground)
        .onAppear { sentenceFocused = true }
    }
}

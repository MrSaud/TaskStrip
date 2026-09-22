import SwiftUI

/// What the editor hands back. A plain value rather than the model itself, so a cancelled edit
/// leaves nothing behind — SwiftData would otherwise have already written every keystroke.
struct ReminderDraft {
    var text: String = ""
    var details: String = ""
    var triggerAt: Date = .now
    var leadMinutesBefore: Int?
    var repeatAmount: Int?
    var repeatUnit: ReminderRepeatUnit?
    var tag: String = ""
    var tagEmoji: String = ""
}

/// Creating and editing a standalone reminder, mirroring ReminderEditScreen.kt.
struct ReminderEditView: View {
    let onSave: (ReminderDraft) -> Void
    let onCancel: () -> Void

    @State private var draft: ReminderDraft
    @State private var hasLead: Bool
    @State private var repeats: Bool
    @State private var leadMinutes: Int
    @State private var repeatAmount: Int
    @State private var repeatUnit: ReminderRepeatUnit

    private let isEditing: Bool

    /// `spokenText` prefills the title for a new reminder dictated rather than typed — Android's
    /// NEW REMINDER BY VOICE hands the sentence straight over without parsing it, since a
    /// reminder is mostly its one line.
    init(
        reminder: Reminder?,
        spokenText: String = "",
        onSave: @escaping (ReminderDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
        isEditing = reminder != nil

        var draft = ReminderDraft()
        if let reminder {
            draft.text = reminder.text
            draft.details = reminder.details
            draft.triggerAt = reminder.triggerAt
            draft.tag = reminder.tag
            draft.tagEmoji = reminder.tagEmoji
        } else {
            // A reminder for a moment that has already passed would never fire, so a new one
            // starts an hour out rather than at this instant.
            draft.triggerAt = Date.now.addingTimeInterval(3600)
            draft.text = spokenText
        }
        _draft = State(initialValue: draft)
        _hasLead = State(initialValue: reminder?.leadMinutesBefore != nil)
        _leadMinutes = State(initialValue: reminder?.leadMinutesBefore ?? 60)
        _repeats = State(initialValue: reminder?.repeats ?? false)
        _repeatAmount = State(initialValue: reminder?.repeatAmount ?? 1)
        _repeatUnit = State(initialValue: reminder?.repeatUnit ?? .monthly)
    }

    private var canSave: Bool {
        !draft.text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("REMINDER") {
                    TextField("What is it?", text: $draft.text)
                        // Looked up by identifier in the UI tests: a SwiftUI TextField in a Form
                        // doesn't expose its placeholder as an accessibility label on macOS, so
                        // searching for the prompt text finds nothing.
                        .accessibilityIdentifier("reminderTitle")
                    TextField("Anything else worth remembering", text: $draft.details, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("WHEN") {
                    DatePicker("Fires", selection: $draft.triggerAt)
                    Toggle("Warn me early", isOn: $hasLead)
                    if hasLead {
                        Picker("Notify", selection: $leadMinutes) {
                            ForEach(ReminderSchedule.leadTimes, id: \.minutes) { option in
                                Text(option.label).tag(option.minutes)
                            }
                        }
                        // One alarm, not two — the same choice a strip's due-date reminder makes.
                        Text("This is the only alert; nothing fires at the time itself.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("REPEAT") {
                    Toggle("Repeats", isOn: $repeats)
                    if repeats {
                        Stepper("Every \(repeatAmount)", value: $repeatAmount, in: 1...99)
                        Picker("Unit", selection: $repeatUnit) {
                            ForEach(ReminderRepeatUnit.allCases) { unit in
                                Text(unit.label).tag(unit)
                            }
                        }
                        Text("Comes back every \(repeatAmount) \(repeatUnit.label.lowercased()), keeping the same date rather than drifting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("TAG") {
                    HStack(spacing: 10) {
                        TextField("Tag", text: $draft.tag)
                        TextField("Emoji", text: $draft.tagEmoji)
                            .frame(width: 90)
                            .onChange(of: draft.tagEmoji) { _, new in
                                if new.count > 4 { draft.tagEmoji = String(new.prefix(4)) }
                            }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], spacing: 6) {
                        ForEach(ReminderSchedule.tagPresets, id: \.tag) { preset in
                            Button("\(preset.emoji) \(preset.tag)") {
                                draft.tag = preset.tag
                                draft.tagEmoji = preset.emoji
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(width: 480, height: 560)
        .background(TaskStripTheme.bayBackground)
    }

    private func save() {
        var result = draft
        result.text = draft.text.trimmingCharacters(in: .whitespaces)
        result.details = draft.details.trimmingCharacters(in: .whitespaces)
        result.tag = draft.tag.trimmingCharacters(in: .whitespaces)
        result.tagEmoji = draft.tagEmoji.trimmingCharacters(in: .whitespaces)
        result.leadMinutesBefore = hasLead ? leadMinutes : nil
        result.repeatAmount = repeats ? repeatAmount : nil
        result.repeatUnit = repeats ? repeatUnit : nil

        // Asked for only when a reminder is actually being made, never at launch — an app that
        // asks before you've shown any interest gets denied, and a denial sticks. The answer
        // isn't waited on: this sheet is closing either way, and the list says when a reminder
        // can't actually announce itself.
        Task { await ReminderScheduler.shared.requestAuthorization() }
        onSave(result)
    }
}

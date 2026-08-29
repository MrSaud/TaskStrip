import SwiftUI

enum AppSettingsKey {
    static let defaultPriority = "defaultPriority"
    static let defaultNotesRtl = "defaultNotesRtl"
    static let confirmBeforeDelete = "confirmBeforeDelete"
}

/// The cmd-, window. Deliberately small: only settings that change something the app already
/// does, rather than a page of switches invented to fill it.
struct SettingsView: View {
    @AppStorage(AppSettingsKey.defaultPriority) private var defaultPriority = Priority.normal
    @AppStorage(AppSettingsKey.defaultNotesRtl) private var defaultNotesRtl = false
    @AppStorage(AppSettingsKey.confirmBeforeDelete) private var confirmBeforeDelete = true

    var body: some View {
        Form {
            Section("New strips") {
                Picker("Priority", selection: $defaultPriority) {
                    ForEach(Priority.allCases) { priority in
                        Text(priority.label).tag(priority)
                    }
                }
                Picker("Notes are written", selection: $defaultNotesRtl) {
                    Text("Left to right").tag(false)
                    Text("Right to left").tag(true)
                }
            }
            Section {
                Toggle("Ask before deleting a strip", isOn: $confirmBeforeDelete)
            } footer: {
                Text("Deleting a strip is permanent — archiving keeps it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

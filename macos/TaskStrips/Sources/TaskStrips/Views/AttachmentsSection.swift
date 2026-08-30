import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The attachments editor inside the edit sheet.
///
/// Files are copied into the store the moment they're picked, but the sheet only commits on Save
/// — so this reports what changed rather than acting on it, and TaskEditView cleans up whichever
/// side of the change got discarded. Without that, cancelling out of a sheet would leave copies
/// behind on disk with nothing pointing at them.
struct AttachmentsSection: View {
    @Binding var attachments: [TaskAttachment]
    let store: AttachmentStore
    /// Called with each file newly copied in, so the sheet can delete it again if you cancel.
    let onAdded: (TaskAttachment) -> Void
    /// Called with each file dropped from the strip, so the sheet can delete it on save.
    let onRemoved: (TaskAttachment) -> Void

    @State private var failure: String?
    @State private var isPickingFromLibrary = false
    @StateObject private var recorder = VoiceRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if attachments.isEmpty {
                Text("No files on this strip")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(attachments) { attachment in
                    row(for: attachment)
                }
            }

            HStack {
                Button {
                    pickFiles()
                } label: {
                    Label("Add Files…", systemImage: "paperclip")
                }
                Button {
                    isPickingFromLibrary = true
                } label: {
                    Label("Add from Library…", systemImage: "tray.full")
                }
                if recorder.isRecording {
                    Button {
                        stopRecording()
                    } label: {
                        Label("Stop \(AudioDuration.formatted(recorder.elapsed))", systemImage: "stop.circle.fill")
                    }
                    .tint(TaskStripTheme.urgent)
                    Button("Discard") { recorder.cancel() }
                } else {
                    Button {
                        startRecording()
                    } label: {
                        Label("Record", systemImage: "mic")
                    }
                }
                Spacer()
                if !attachments.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(TaskStripTheme.urgent)
            }
        }
        .sheet(isPresented: $isPickingFromLibrary) {
            StoragePickerSheet(
                store: store,
                onAdd: { picked in
                    isPickingFromLibrary = false
                    takeFromLibrary(picked)
                },
                onCancel: { isPickingFromLibrary = false }
            )
        }
    }

    private func row(for attachment: TaskAttachment) -> some View {
        HStack(spacing: 8) {
            Image(systemName: attachment.kind.systemImage)
                .foregroundStyle(TaskStripTheme.amber)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(attachment.kind.label)
                    if attachment.kind == .voiceNote,
                       let duration = AudioDuration.formatted(of: store.url(for: attachment)) {
                        Text(duration)
                    }
                    if !store.exists(attachment) {
                        // An imported backup can name a file the zip didn't carry, and a store
                        // can be moved out from under the app. Better to say so than to show a
                        // row that does nothing when clicked.
                        Text("missing")
                            .foregroundStyle(TaskStripTheme.urgent)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NSWorkspace.shared.open(store.url(for: attachment))
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Open")
            .disabled(!store.exists(attachment))

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([store.url(for: attachment)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            .disabled(!store.exists(attachment))

            Button(role: .destructive) {
                attachments.removeAll { $0.id == attachment.id }
                onRemoved(attachment)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove")
        }
    }

    private var summary: String {
        let counts = Dictionary(grouping: attachments, by: \.kind)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.value.count) \($0.key.label.lowercased())\($0.value.count == 1 ? "" : "s")" }
        return counts.joined(separator: ", ")
    }

    /// The strip gets its own copy of the file, not a second pointer at the library's — so
    /// deleting it from storage later leaves this strip's attachment intact, which is exactly
    /// what the library's delete dialog promises.
    private func takeFromLibrary(_ items: [StorageItem]) {
        var problems: [String] = []
        for item in items {
            do {
                let attachment = try store.duplicate(
                    relativePath: item.path,
                    kind: item.type.attachmentKind,
                    name: item.name
                )
                attachments.append(attachment)
                onAdded(attachment)
            } catch {
                problems.append(item.name)
            }
        }
        failure = problems.isEmpty
            ? nil
            : "Couldn't copy \(problems.joined(separator: ", ")) from storage."
    }

    private func startRecording() {
        Task {
            do {
                failure = nil
                try await recorder.start()
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// A finished recording joins the strip by exactly the same road a picked file takes, so
    /// cancelling the sheet cleans it up like anything else.
    private func stopRecording() {
        guard let url = recorder.stop() else {
            failure = "That recording came out empty, so nothing was attached."
            return
        }
        do {
            let attachment = try store.add(contentsOf: url, kind: .voiceNote)
            attachments.append(attachment)
            onAdded(attachment)
            // The store keeps its own copy; the temporary one has done its job.
            try? FileManager.default.removeItem(at: url)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Attach"
        panel.message = "Choose files to attach to this strip."
        guard panel.runModal() == .OK else { return }

        var problems: [String] = []
        for url in panel.urls {
            do {
                let attachment = try store.add(contentsOf: url)
                attachments.append(attachment)
                onAdded(attachment)
            } catch {
                problems.append(url.lastPathComponent)
            }
        }
        failure = problems.isEmpty
            ? nil
            : "Couldn't attach \(problems.joined(separator: ", "))."
    }
}

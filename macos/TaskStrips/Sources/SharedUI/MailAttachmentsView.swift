import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The files that came with a message: what they are, and the two things worth doing with them —
/// saving one, or putting it on a strip.
///
/// Filing an invoice onto the strip it belongs to is the whole reason this is here rather than in
/// a mail client: the board already holds files, and this is where they come from.
struct MailAttachmentsView: View {
    let attachments: [MailAttachment]
    /// Set when only part of the message was fetched, so the files are incomplete or missing.
    var isTruncated = false
    var onFetchWholeMessage: (() -> Void)?

    @Environment(\.modelContext) private var context

    @State private var saving: MailAttachment?
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                Text(attachments.isEmpty ? "ATTACHMENTS" : "\(attachments.count) ATTACHMENT\(attachments.count == 1 ? "" : "S")")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(TaskStripTheme.amber)

            if isTruncated {
                // Saying so rather than quietly fetching twenty megabytes on someone's phone.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Only part of this message was fetched, so its files may be missing or cut short.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let onFetchWholeMessage {
                        Button("Fetch the whole message", action: onFetchWholeMessage)
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                }
            }

            ForEach(attachments) { attachment in
                row(for: attachment)
            }

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(TaskStripTheme.baySurface)
        .fileExporter(
            isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } }),
            document: saving.map { MailAttachmentFile(bytes: $0.bytes) },
            contentType: saving.map(Self.contentType) ?? .data,
            defaultFilename: saving?.name
        ) { result in
            if case .failure(let error) = result { note = error.localizedDescription }
            saving = nil
        }
    }

    private func row(for attachment: MailAttachment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(for: attachment))
                .foregroundStyle(TaskStripTheme.paper.opacity(0.7))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(attachment.size)
                    if attachment.isInline {
                        Text("· inline")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)

            Button {
                saving = attachment
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.title3)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Save this file")

            StripPickerMenu(title: "Add this file to a strip") { strip in
                add(attachment, to: strip)
            } label: {
                Image(systemName: "tray.and.arrow.down")
                    .font(.title3)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Put this file on a strip")
        }
    }

    /// Copies the file into the board's own store and points a strip at it, which is exactly what
    /// dragging a file onto a strip does.
    private func add(_ attachment: MailAttachment, to strip: TaskItem) {
        do {
            let saved = try AttachmentStore.shared.add(attachment.bytes, named: attachment.name)
            strip.attachments.append(saved)
            strip.actionLog.append(
                TaskActionLogEntry(text: "Filed \"\(attachment.name)\" from an email", timestamp: .now)
            )
            try? context.save()
            note = "Added \(attachment.name) to \(strip.title)."
        } catch {
            note = error.localizedDescription
        }
    }

    private func icon(for attachment: MailAttachment) -> String {
        let type = attachment.type.lowercased()
        if type.hasPrefix("image/") { return "photo" }
        if type.hasPrefix("audio/") { return "waveform" }
        if type.hasPrefix("video/") { return "film" }
        if type.contains("pdf") { return "doc.richtext" }
        if type.contains("zip") || type.contains("compressed") { return "doc.zipper" }
        if type.contains("sheet") || type.contains("excel") || type.contains("csv") { return "tablecells" }
        return "doc"
    }

    private static func contentType(for attachment: MailAttachment) -> UTType {
        UTType(mimeType: attachment.type)
            ?? UTType(filenameExtension: (attachment.name as NSString).pathExtension)
            ?? .data
    }
}

/// The wrapper a save panel wants. It only ever exports: the bytes are already in hand.
struct MailAttachmentFile: FileDocument {
    static let readableContentTypes: [UTType] = [.data]

    var bytes: Data

    init(bytes: Data) { self.bytes = bytes }

    init(configuration: ReadConfiguration) throws {
        bytes = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: bytes)
    }
}

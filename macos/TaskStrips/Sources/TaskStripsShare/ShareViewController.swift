import Contacts
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Share Extension: what Android's share target does, on iPhone and iPad. Text, a link or a
/// contact card becomes a new strip; photos, videos and documents go to the storage library.
///
/// It files nothing itself — it can't open the app's store — so it leaves an entry in the
/// ShareInbox and the app files it the next time it's opened.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(items: extensionContext?.inputItems as? [NSExtensionItem] ?? [])
        let root = ShareSheetView(
            model: model,
            onDone: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
            }
        )
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    @Published var isLoading = true
    @Published var title = ""
    @Published var notes = ""
    @Published var contacts: [SharedEntry.Contact] = []
    @Published var links: [String] = []
    @Published var files: [URL] = []
    @Published var tag = ""
    @Published var problem: String?
    /// The strip this is being filed onto, or nil for a new one.
    @Published var target: StripIndexEntry?
    @Published var strips: [StripIndexEntry] = []

    private let items: [NSExtensionItem]

    init(items: [NSExtensionItem]) {
        self.items = items
        // Written by the app whenever the board changes; if it isn't there, the only thing on
        // offer is a new strip, which is what this always used to do.
        strips = StripIndex.read()
    }

    /// Files win: a photo shared with a caption is a photo for the library, not a strip.
    /// A shared email is a strip with a link on it, even though a file came with it — the point
    /// of sharing it here is the message, not a copy of it in the library.
    var kind: SharedEntry.Kind { files.isEmpty || !links.isEmpty ? .strip : .files }

    var canFile: Bool {
        if target != nil { return true }
        switch kind {
        case .strip: return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .files: return true
        }
    }

    func load() async {
        defer { isLoading = false }
        var texts: [String] = []
        var subject: String?

        for item in items {
            if let text = item.attributedContentText?.string, !text.isEmpty { subject = subject ?? text }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.vCard.identifier) {
                    if let data = try? await provider.loadData(for: .vCard) { contacts += Self.contacts(in: data) }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let url = await provider.load(URL.self), !url.isFileURL {
                    // A message shared out of Mail: linked to the strip rather than pasted into
                    // it, so it opens the email it came from.
                    if EmailLink.isMessage(url.absoluteString) {
                        links.append(url.absoluteString)
                    } else {
                        texts.append(url.absoluteString)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = await provider.load(String.self) {
                    texts.append(text)
                } else if let file = await Self.copyFile(from: provider) {
                    files.append(file)
                    // Mail shares the message itself as a file; its Message-ID is the link back
                    // to it, so the strip gets both the copy and the way home.
                    if EmailLink.isEmailFile(file),
                       let text = try? String(contentsOf: file, encoding: .utf8),
                       let link = EmailLink.fromEmail(text) {
                        links.append(link)
                    }
                }
            }
        }

        let body = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Android's rule: the subject if there is one, otherwise the first line, at most 80
        // characters; the whole text goes to the notes.
        let firstLine = body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
        title = String((subject ?? firstLine ?? contacts.first?.name ?? "").prefix(80))
        notes = body
        if title.isEmpty && files.isEmpty && contacts.isEmpty && links.isEmpty {
            problem = "There's nothing here Task Strips can file."
        }
    }

    func file() -> Bool {
        let entry = SharedEntry(
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            contacts: contacts,
            links: links,
            targetStripID: target?.id,
            tag: tag.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try ShareInbox.add(entry, files: files)
            return true
        } catch {
            problem = "Couldn't hand this to Task Strips: \(error.localizedDescription)"
            return false
        }
    }

    private static func contacts(in data: Data) -> [SharedEntry.Contact] {
        let parsed = (try? CNContactVCardSerialization.contacts(with: data)) ?? []
        return parsed.map { contact in
            SharedEntry.Contact(
                name: CNContactFormatter.string(from: contact, style: .fullName) ?? "",
                email: contact.emailAddresses.first.map { String($0.value) } ?? "",
                phone: contact.phoneNumbers.first?.value.stringValue ?? ""
            )
        }
    }

    /// A shared file is only readable while its provider's callback runs, so it's copied out to
    /// the extension's own temporary folder first.
    private static func copyFile(from provider: NSItemProvider) async -> URL? {
        let type = [UTType.image, .movie, .pdf, .data].first { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        guard let type else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                guard let url else { return continuation.resume(returning: nil) }
                let copy = FileManager.default.temporaryDirectory
                    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
                    .appending(path: url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(
                        at: copy.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private extension NSItemProvider {
    /// URL and String, which arrive through Foundation's bridged types.
    func load<T: _ObjectiveCBridgeable>(_ type: T.Type) async -> T? where T._ObjectiveCType: NSItemProviderReading {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: type) { value, _ in continuation.resume(returning: value) }
        }
    }

    func loadData(for type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadDataRepresentation(for: type) { data, error in
                if let data { continuation.resume(returning: data) } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }
}

struct ShareSheetView: View {
    @ObservedObject var model: ShareModel
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if model.isLoading {
                    ProgressView()
                } else if let target = model.target {
                    Section("Onto this strip") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.title)
                            if !target.tags.isEmpty {
                                Text(target.tags.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("File as a new strip instead") { model.target = nil }
                    }
                    if !model.links.isEmpty {
                        Section("What's being added") {
                            ForEach(model.links, id: \.self) { link in
                                Label(EmailLink.label(for: link), systemImage: "envelope")
                            }
                            ForEach(model.files, id: \.self) { file in
                                Label(file.lastPathComponent, systemImage: "doc")
                            }
                        }
                    }
                } else if model.kind == .strip {
                    if !model.strips.isEmpty {
                        Section {
                            NavigationLink {
                                StripPickerView(strips: model.strips) { model.target = $0 }
                            } label: {
                                Label("File onto an existing strip…", systemImage: "tray.and.arrow.down")
                            }
                        }
                    }
                    Section("New strip") {
                        TextField("Title", text: $model.title)
                        if !model.notes.isEmpty {
                            Text(model.notes)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                        }
                    }
                    if !model.contacts.isEmpty {
                        Section("Contacts") {
                            ForEach(model.contacts, id: \.name) { contact in
                                VStack(alignment: .leading) {
                                    Text(contact.name)
                                    Text([contact.phone, contact.email].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    Section("To the storage library") {
                        ForEach(model.files, id: \.self) { file in
                            Label(file.lastPathComponent, systemImage: "doc")
                        }
                    }
                    Section {
                        TextField("Tag (optional)", text: $model.tag)
                    }
                }
                if let problem = model.problem {
                    Text(problem).foregroundStyle(.red)
                }
                Section {
                    Text("It's filed the next time you open Task Strips.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Task Strips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.target != nil ? "Add to Strip" : (model.kind == .strip ? "File Strip" : "Add")) {
                        if model.file() { onDone() }
                    }
                    .disabled(model.isLoading || !model.canFile)
                }
            }
        }
    }
}

/// The board, to choose from. A list of names is all the extension can have — it can't open the
/// app's store — and for filing an email onto the right strip, a list of names is enough.
private struct StripPickerView: View {
    let strips: [StripIndexEntry]
    let onPick: (StripIndexEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""

    private var shown: [StripIndexEntry] { StripIndex.matching(search, in: strips) }

    var body: some View {
        List {
            if shown.isEmpty {
                Text("No strip by that name.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { strip in
                Button {
                    onPick(strip)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(strip.title)
                            .strikethrough(strip.isDone)
                            .foregroundStyle(.primary)
                        if !strip.tags.isEmpty {
                            Text(strip.tags.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search strips")
        .navigationTitle("Choose a strip")
        .navigationBarTitleDisplayMode(.inline)
    }
}

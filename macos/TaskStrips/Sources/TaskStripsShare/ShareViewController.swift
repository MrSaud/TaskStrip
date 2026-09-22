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
    @Published var files: [URL] = []
    @Published var tag = ""
    @Published var problem: String?

    private let items: [NSExtensionItem]

    init(items: [NSExtensionItem]) {
        self.items = items
    }

    /// Files win: a photo shared with a caption is a photo for the library, not a strip.
    var kind: SharedEntry.Kind { files.isEmpty ? .strip : .files }

    var canFile: Bool {
        switch kind {
        case .strip: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .files: true
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
                    texts.append(url.absoluteString)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = await provider.load(String.self) {
                    texts.append(text)
                } else if let file = await Self.copyFile(from: provider) {
                    files.append(file)
                }
            }
        }

        let body = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // Android's rule: the subject if there is one, otherwise the first line, at most 80
        // characters; the whole text goes to the notes.
        let firstLine = body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
        title = String((subject ?? firstLine ?? contacts.first?.name ?? "").prefix(80))
        notes = body
        if title.isEmpty && files.isEmpty && contacts.isEmpty {
            problem = "There's nothing here Task Strips can file."
        }
    }

    func file() -> Bool {
        let entry = SharedEntry(
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            contacts: contacts,
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
                } else if model.kind == .strip {
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
                    Button(model.kind == .strip ? "File Strip" : "Add") {
                        if model.file() { onDone() }
                    }
                    .disabled(model.isLoading || !model.canFile)
                }
            }
        }
    }
}

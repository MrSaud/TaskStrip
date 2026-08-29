import Foundation

enum AttachmentStoreError: LocalizedError {
    case cannotRead(URL)
    case cannotWrite(String)

    var errorDescription: String? {
        switch self {
        case .cannotRead(let url):
            return "Couldn't read \"\(url.lastPathComponent)\"."
        case .cannotWrite(let path):
            return "Couldn't save the attachment to \(path)."
        }
    }
}

/// Where attachment files live on disk.
///
/// The layout deliberately mirrors MediaStorage.kt's under Android's filesDir — images/, audio/,
/// documents/<uuid>/<original name>, videos/ — because a backup stores paths relative to exactly
/// that. Keeping the same shape means an imported path is already correct and a future export
/// needs no translation.
///
/// `root` is injectable so tests can work in a temporary directory rather than the real one.
struct AttachmentStore {
    let root: URL

    /// Follows the same launch argument the model container does. Without this, a run started
    /// for a throwaway board would still copy files into the real media folder — the store was
    /// safe and the files weren't, which is worse than either being obviously unsafe.
    static let shared: AttachmentStore = {
        guard ProcessInfo.processInfo.arguments.contains(TaskStripsApp.uiTestingArgument) else {
            return AttachmentStore(root: defaultRoot())
        }
        return AttachmentStore(
            root: FileManager.default.temporaryDirectory
                .appending(path: "TaskStrips-UITesting-Media", directoryHint: .isDirectory)
        )
    }()

    static func defaultRoot() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appending(path: "TaskStrips", directoryHint: .isDirectory)
            .appending(path: "Media", directoryHint: .isDirectory)
    }

    func url(for attachment: TaskAttachment) -> URL {
        root.appending(path: attachment.path)
    }

    func exists(_ attachment: TaskAttachment) -> Bool {
        FileManager.default.fileExists(atPath: url(for: attachment).path)
    }

    /// Copies a picked file into the store. The original is left alone.
    @discardableResult
    func add(contentsOf source: URL, kind explicitKind: AttachmentKind? = nil) throws -> TaskAttachment {
        let kind = explicitKind ?? AttachmentKind.inferred(fromExtension: source.pathExtension)
        let name = source.lastPathComponent
        let relativePath = Self.relativePath(for: name, kind: kind)
        let destination = root.appending(path: relativePath)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard FileManager.default.isReadableFile(atPath: source.path) else {
            throw AttachmentStoreError.cannotRead(source)
        }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw AttachmentStoreError.cannotWrite(relativePath)
        }

        return TaskAttachment(kind: kind, path: relativePath, name: name)
    }

    /// Used by the backup import, which has bytes rather than a file on disk, and a path the
    /// backup already chose.
    func write(_ data: Data, toRelativePath relativePath: String) throws {
        let destination = root.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try data.write(to: destination)
        } catch {
            throw AttachmentStoreError.cannotWrite(relativePath)
        }
    }

    /// Removes the file. Documents get their own folder, so that goes too rather than leaving an
    /// empty one behind.
    func remove(_ attachment: TaskAttachment) {
        let file = url(for: attachment)
        try? FileManager.default.removeItem(at: file)
        if attachment.kind == .document {
            let folder = file.deletingLastPathComponent()
            if folder != root, folder.lastPathComponent != attachment.kind.folder {
                try? FileManager.default.removeItem(at: folder)
            }
        }
    }

    /// Documents keep their original name inside a per-file folder, so two files called
    /// "invoice.pdf" can't collide — same trick as MediaStorage.copyDocumentToLocal. Everything
    /// else is renamed to a uuid, since its name is never shown.
    static func relativePath(for name: String, kind: AttachmentKind) -> String {
        let id = UUID().uuidString
        switch kind {
        case .document:
            return "\(kind.folder)/\(id)/\(name)"
        default:
            let ext = (name as NSString).pathExtension
            return ext.isEmpty ? "\(kind.folder)/\(id)" : "\(kind.folder)/\(id).\(ext)"
        }
    }
}

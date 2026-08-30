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
        url(forRelativePath: attachment.path)
    }

    /// The library stores paths without an attachment around them, so both callers go through
    /// the same place rather than each joining paths their own way.
    func url(forRelativePath path: String) -> URL {
        root.appending(path: path)
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

    /// Every file under a folder of the store, as paths relative to its root.
    ///
    /// Used for the sketch notes a backup carries: nothing in the app points at them, so the only
    /// way to find them again is to look.
    ///
    /// `includingHidden` is what a sketch note needs: its name and its creation date live in
    /// `.name` and `.created` beside the pages, and BackupHelper.kt lists every file inside a note
    /// folder without filtering. Skipping them would export a sketch that arrives on the phone
    /// having lost the name the user gave it.
    func relativePaths(under folder: String, includingHidden: Bool = false) -> Set<String> {
        let base = url(forRelativePath: folder)
        guard let walker = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: includingHidden ? [] : [.skipsHiddenFiles]
        ) else { return [] }

        var paths: Set<String> = []
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(rootPath + "/") else { continue }
            paths.insert(String(full.dropFirst(rootPath.count + 1)))
        }
        return paths
    }

    /// Copies a file the store already holds to a fresh path inside it.
    ///
    /// Taking a library file onto a strip duplicates it rather than pointing both at the same
    /// bytes — which is what lets the library say "strips that already took a copy keep theirs"
    /// and mean it. `name` is what the user should see, since the stored file is usually named
    /// after a uuid.
    func duplicate(relativePath: String, kind: AttachmentKind, name: String) throws -> TaskAttachment {
        let source = url(forRelativePath: relativePath)
        guard FileManager.default.isReadableFile(atPath: source.path) else {
            throw AttachmentStoreError.cannotRead(source)
        }
        let destinationPath = Self.relativePath(for: name, kind: kind)
        let destination = url(forRelativePath: destinationPath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw AttachmentStoreError.cannotWrite(destinationPath)
        }
        return TaskAttachment(kind: kind, path: destinationPath, name: name)
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
        remove(relativePath: attachment.path, kind: attachment.kind)
    }

    func remove(relativePath: String, kind: AttachmentKind) {
        let file = url(forRelativePath: relativePath)
        try? FileManager.default.removeItem(at: file)
        if kind == .document {
            let folder = file.deletingLastPathComponent()
            if folder != root, folder.lastPathComponent != kind.folder {
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

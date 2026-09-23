import Foundation

/// Something another app shared in, waiting for the app to file it.
///
/// The Share Extension runs in its own process and can't open the app's store, so it doesn't
/// file anything itself: it leaves an entry here, in the App Group, and the app files it the
/// next time it comes to the front. The same split as the widget, the other way round.
struct SharedEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        /// Text, a link or a contact card: a new strip, as Android's share target makes one.
        case strip
        /// Photos, videos and documents: into the storage library.
        case files
    }

    struct Contact: Codable, Equatable {
        var name: String
        var email: String
        var phone: String
    }

    var id = UUID()
    var kind: Kind
    var title = ""
    var notes = ""
    var contacts: [Contact] = []
    /// Links to put on the strip — an email shared from Mail arrives as one of these, so the
    /// strip points back at the message rather than quoting it.
    var links: [String] = []
    /// Names of the files beside this entry in its folder.
    var fileNames: [String] = []
    /// Put on every file of a `.files` entry, so a batch of receipts arrives already tagged.
    var tag = ""
    var createdAt = Date.now
}

enum ShareInbox {
    static let appGroup = "group.com.saud.taskstrip"
    private static let entryFile = "entry.json"

    /// Where the entries live. Nil if the App Group isn't there, which is a signing problem, not
    /// something the user can fix — so both sides simply do nothing then.
    static var root: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "ShareInbox", directoryHint: .isDirectory)
    }

    /// Files first, the entry last: an entry's JSON appearing is the signal it's complete, so the
    /// app can never pick up one whose files are still being copied.
    static func add(_ entry: SharedEntry, files: [URL], root: URL? = root) throws {
        guard let root else { throw CocoaError(.fileNoSuchFile) }
        let folder = root.appending(path: entry.id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var entry = entry
        entry.fileNames = []
        for file in files {
            let name = uniqueName(file.lastPathComponent, taken: entry.fileNames)
            try FileManager.default.copyItem(at: file, to: folder.appending(path: name))
            entry.fileNames.append(name)
        }
        let data = try JSONEncoder().encode(entry)
        try data.write(to: folder.appending(path: entryFile), options: .atomic)
    }

    /// Complete entries, oldest first, each with the folder its files are in.
    static func pending(root: URL? = root) -> [(entry: SharedEntry, folder: URL)] {
        guard let root,
              let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return folders
            .compactMap { folder -> (SharedEntry, URL)? in
                guard let data = try? Data(contentsOf: folder.appending(path: entryFile)),
                      let entry = try? JSONDecoder().decode(SharedEntry.self, from: data)
                else { return nil }
                return (entry, folder)
            }
            .sorted { $0.0.createdAt < $1.0.createdAt }
    }

    static func remove(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Two shared photos can both be called IMG_0001.jpg.
    private static func uniqueName(_ name: String, taken: [String]) -> String {
        guard taken.contains(name) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            if !taken.contains(candidate) { return candidate }
            index += 1
        }
    }
}

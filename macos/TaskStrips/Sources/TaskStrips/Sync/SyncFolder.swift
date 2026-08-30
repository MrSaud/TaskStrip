import Foundation

/// The folder the Mac syncs through, remembered across launches.
///
/// A security-scoped bookmark rather than a path. The app runs with the hardened runtime, so the
/// permission to read a folder the user picked lasts only as long as that grant does; a stored
/// path would come back after a relaunch as a folder the app is no longer allowed to open, and the
/// failure would look exactly like the folder having gone away.
enum SyncFolder {
    private static let bookmarkKey = "syncNoteFolderBookmark"
    private static let modeKey = "syncNoteTransport"

    /// Which way this Mac syncs. The phone has no such choice.
    enum Mode: String {
        /// Drive's REST API, using the same sign-in the backups use.
        case drive
        /// A folder on disk — Drive for desktop's, or any other folder that is itself synced.
        case folder
    }

    static var mode: Mode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modeKey),
                  let mode = Mode(rawValue: raw)
            else { return .drive }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    /// Resolves the saved bookmark and starts access. The caller must call `endAccess` when it's
    /// finished, or the app leaks a scoped resource for the rest of its run.
    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        // A stale bookmark still resolves; refreshing it here keeps a folder that was moved or
        // renamed working instead of failing on some later launch for no visible reason.
        if isStale { store(url) }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        return url
    }

    static func endAccess(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    @discardableResult
    static func store(_ url: URL) -> Bool {
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return false }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        return true
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    /// Where Drive for desktop puts things, for the picker to open on rather than making the user
    /// hunt for it. Not assumed to exist — it's a starting point, not a location.
    static var likelyDriveFolder: URL? {
        let cloudStorage = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/CloudStorage", directoryHint: .isDirectory)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: cloudStorage, includingPropertiesForKeys: nil
        )) ?? []
        return contents.first { $0.lastPathComponent.hasPrefix("GoogleDrive") } ?? cloudStorage
    }
}

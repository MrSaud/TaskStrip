import Foundation

/// Where the board lives on disk: its store, its files, and the sync's own bookkeeping. One
/// folder, so wiping it wipes everything that describes it together.
///
/// The sync test board (see AppLaunch.isSyncTesting) is a sibling folder, never the real one.
enum BoardLocation {
    static var directory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let name = AppLaunch.isSyncTesting ? "TaskStrips-SyncTest" : "TaskStrips"
        let folder = appSupport.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static var storeURL: URL { directory.appending(path: "TaskStrips.store") }

    static var mediaDirectory: URL { directory.appending(path: "Media", directoryHint: .isDirectory) }

    /// Per CloudKit environment: a Debug build syncs with Development, a Release build with
    /// Production, and what one knows about the other's records is worthless — so moving to
    /// Production starts from scratch instead of believing Development's records are there.
    static var syncDirectory: URL {
        #if DEBUG
        directory.appending(path: "Sync-Development", directoryHint: .isDirectory)
        #else
        directory.appending(path: "Sync-Production", directoryHint: .isDirectory)
        #endif
    }
}

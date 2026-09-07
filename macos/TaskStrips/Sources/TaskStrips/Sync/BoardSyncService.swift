import Foundation
import SwiftData

/// One sync, from the outside: pick a transport, run it, remember what happened.
///
/// Mirrors BoardSyncService.kt, with the one difference the user chose: this device adopts on its
/// first sync. The two boards already overlap and were never given matching ids, so merging them
/// would union them into duplicates of everything on both. The phone wins; this is the side that
/// gives way, once.
@MainActor
enum BoardSyncService {

    private static let hasSyncedKey = "boardSync.hasSynced"
    private static let lastSummaryKey = "boardSync.lastSummary"

    static var hasSyncedBefore: Bool {
        UserDefaults.standard.bool(forKey: hasSyncedKey)
    }

    static var lastSummary: String? {
        UserDefaults.standard.string(forKey: lastSummaryKey)
    }

    /// Runs against whichever route the synced notes are already set to use, so there is one
    /// answer to "where does this machine sync" rather than two that can disagree.
    static func run(context: ModelContext, passphrase: String? = nil) async -> BoardSyncOutcome {
        var scoped: URL?
        defer { if let scoped { SyncFolder.endAccess(scoped) } }

        let transport: BoardTransport
        switch SyncFolder.mode {
        case .folder:
            guard let folder = SyncFolder.resolve() else {
                return BoardSyncOutcome(failure: "Pick a folder to sync through.")
            }
            scoped = folder
            transport = FolderBoardTransport(folder: folder)
        case .drive:
            guard let client = try? await DriveSession.shared.client() else {
                return BoardSyncOutcome(failure: "Sign in from the board's Drive window first.")
            }
            transport = DriveBoardTransport(client: client)
        }

        do {
            let outcome = try await BoardSyncRunner(
                context: context,
                transport: transport,
                passphrase: passphrase
            ).run(hasSyncedBefore: hasSyncedBefore, adoptsOnFirstSync: true)

            try context.save()
            // Only a sync that got somewhere counts as one. Marking a failure would tell the
            // first-sync rule this machine has synced when it hasn't — and that rule is the only
            // thing standing between an unreachable folder and a board replaced by nothing.
            UserDefaults.standard.set(true, forKey: hasSyncedKey)
            UserDefaults.standard.set(outcome.summary, forKey: lastSummaryKey)
            return outcome
        } catch {
            return BoardSyncOutcome(failure: error.localizedDescription)
        }
    }
}

extension BoardSyncOutcome {
    /// Set when the sync couldn't run at all, as opposed to running and finding nothing to do.
    var failure: String? {
        get { failureReason }
        set { failureReason = newValue }
    }

    init(failure: String) {
        self.init()
        self.failureReason = failure
    }
}

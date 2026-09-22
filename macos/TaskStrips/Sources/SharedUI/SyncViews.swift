import SwiftUI

/// The iCloud section of Settings: what the sync is doing, and the ways to stop it.
///
/// Two ways out, and they mean different things:
/// - Turn Off stops this device. Its board stays; iCloud's copy stays for the others.
/// - Erase iCloud's Copy deletes the copy in iCloud. Every device keeps its own board and stops
///   syncing, so nothing re-uploads what was just erased.
struct SyncSettingsSection: View {
    @ObservedObject private var sync = BoardSync.shared
    @State private var confirmErase = false

    var body: some View {
        Section {
            Text(summary)
                .font(.callout)
                .foregroundStyle(isProblem ? TaskStripTheme.urgent : .secondary)
            if isRunning {
                Button("Sync Now") { Task { await sync.syncNow() } }
                Button("Turn Off on \(Platform.thisDevice.capitalizedFirst)") { sync.turnOff() }
                Button("Erase iCloud's Copy…", role: .destructive) { confirmErase = true }
            } else {
                Button("Turn On") { sync.turnOn() }
            }
        } header: {
            Text(sync.isTestBoard ? "iCloud Sync — test board" : "iCloud Sync")
        } footer: {
            Text((sync.isTestBoard ? "This syncs only the separate test board, never your real one. " : "")
                 + "Turn On uploads this board and brings down what iCloud has. "
                 + "Turn Off keeps this board and iCloud's copy. Erase deletes iCloud's copy; "
                 + "every device keeps its own board and stops syncing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("Erase iCloud's copy of the board?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase iCloud's Copy", role: .destructive) { Task { await sync.eraseICloudCopy() } }
        } message: {
            Text("Every device keeps its own board and stops syncing. This can't be undone, but no board is lost.")
        }
    }

    private var isRunning: Bool {
        switch sync.status {
        case .syncing, .upToDate, .needsConfirmation, .failed: true
        case .off, .stopped: false
        }
    }

    private var isProblem: Bool {
        switch sync.status {
        case .failed, .stopped, .needsConfirmation: true
        default: false
        }
    }

    private var summary: String {
        switch sync.status {
        case .off: "Off."
        case .syncing: "Syncing…"
        case .upToDate(let date): "Up to date — \(date.formatted(date: .omitted, time: .shortened))."
        case .needsConfirmation(let count): "Waiting for you: \(count) deletions held back."
        case .stopped(let reason): reason
        case .failed(let message): "Last sync failed: \(message)"
        }
    }
}

/// The brake's question, on the board itself so it can't go unseen in Settings.
struct SyncConfirmationAlert: ViewModifier {
    @ObservedObject private var sync = BoardSync.shared

    private var pending: Int? {
        if case .needsConfirmation(let count) = sync.status { return count }
        return nil
    }

    func body(content: Content) -> some View {
        content.alert(
            "Delete \(pending ?? 0) items from iCloud?",
            isPresented: Binding(get: { pending != nil }, set: { _ in })
        ) {
            Button("Keep Them", role: .cancel) { sync.confirmHeldDeletions(false) }
            Button("Delete from iCloud", role: .destructive) { sync.confirmHeldDeletions(true) }
        } message: {
            Text("This board is missing most of what iCloud has — after a restore, say, or a wipe. "
                 + "Deleting them removes them from every device. Keeping them brings them back here.")
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Says, on the board itself, that this is the sync test board — so nobody mistakes it for the
/// real one while Phase 5 is being tried.
struct SyncTestBanner: View {
    @ObservedObject private var sync = BoardSync.shared

    var body: some View {
        if AppLaunch.isSyncTesting {
            HStack(spacing: 6) {
                Image(systemName: "flask")
                Text("SYNC TEST BOARD")
                    .fontWeight(.bold)
                Spacer()
                Text(state)
            }
            .font(.caption.monospaced())
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(TaskStripTheme.amber)
        }
    }

    private var state: String {
        switch sync.status {
        case .off: "sync off"
        case .syncing: "syncing…"
        case .upToDate(let date): "synced \(date.formatted(date: .omitted, time: .shortened))"
        case .needsConfirmation: "waiting for you"
        case .stopped: "stopped"
        case .failed: "failed"
        }
    }
}

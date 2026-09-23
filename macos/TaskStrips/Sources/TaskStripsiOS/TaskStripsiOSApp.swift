import SwiftData
import SwiftUI

/// The iPhone and iPad app, over the same models and stores in Core that the Mac uses.
@main
struct TaskStripsiOSApp: App {
    static let sharedModelContainer: ModelContainer = {
        let storeURL = BoardLocation.storeURL
        do {
            return try ModelContainer(
                for: Schema(BoardSchema.models),
                configurations: BoardSchema.configuration(url: storeURL)
            )
        } catch {
            fatalError("Failed to create ModelContainer at \(storeURL): \(error)")
        }
    }()

    #if DEBUG
    init() {
        // Phase 2's check that iCloud Keychain carries what the Mac writes. Only the marker's
        // timestamp, never a password, and only in a Debug build.
        let marker = Keychain(location: .iCloud(accessGroup: Keychain.sharedAccessGroup))
            .value(service: "com.saud.taskstrip.integration-check", account: Keychain.crossDeviceMarkerAccount)
        print("KEYCHAIN-CHECK", marker.map { "found marker written \($0)" } ?? "no marker yet")
        SampleBoard.seedIfAsked(into: Self.sharedModelContainer)
        Self.startSyncIfAllowed()
        // Phase 4: puts the CloudKit schema into the Development environment. Never automatic.
        if ProcessInfo.processInfo.arguments.contains("-SeedCloudSchema") {
            Task { await SchemaSeeder.run { print($0) } }
        }
    }
    #endif

    /// Phase 5: sync runs only on the sync test board (-SyncTestStore); a no-op otherwise.
    private static func startSyncIfAllowed() {
        guard BoardSync.isAllowed else { return }
        let container = sharedModelContainer
        Task { @MainActor in BoardSync.shared.start(container: container) }
    }

    /// Dark as it always was, unless someone has said otherwise — and Auto follows the device.
    @AppStorage(AppSettingsKey.theme) private var theme = BoardTheme.auto

    var body: some Scene {
        WindowGroup {
            BoardScreen()
                .boardTheme(theme)
        }
        .modelContainer(Self.sharedModelContainer)
    }
}

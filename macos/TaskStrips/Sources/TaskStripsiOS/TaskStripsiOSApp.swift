import SwiftData
import SwiftUI

/// The iPhone and iPad app, over the same models and stores in Core that the Mac uses.
@main
struct TaskStripsiOSApp: App {
    static let sharedModelContainer: ModelContainer = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let storeDirectory = appSupport.appending(path: "TaskStrips", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let storeURL = storeDirectory.appending(path: "TaskStrips.store")
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
        // Phase 4: puts the CloudKit schema into the Development environment. Never automatic.
        if ProcessInfo.processInfo.arguments.contains("-SeedCloudSchema") {
            Task { await SchemaSeeder.run { print($0) } }
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            BoardScreen()
                .preferredColorScheme(.dark)
        }
        .modelContainer(Self.sharedModelContainer)
    }
}

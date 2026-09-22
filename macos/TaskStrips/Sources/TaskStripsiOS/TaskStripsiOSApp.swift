import SwiftData
import SwiftUI

/// The iPhone and iPad app. For now it is a shell over the shared models and stores in Core — the
/// real screens come in Phase 3 — but it opens a store with the same schema the Mac uses, so every
/// model already has to compile and load here.
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
    }
    #endif

    var body: some Scene {
        WindowGroup {
            PlaceholderBoard()
        }
        .modelContainer(Self.sharedModelContainer)
    }
}

private struct PlaceholderBoard: View {
    @Query(
        filter: #Predicate<TaskItem> { !$0.isDone && !$0.isArchived && !$0.isTombstoned },
        sort: \TaskItem.orderIndex
    )
    private var strips: [TaskItem]

    var body: some View {
        NavigationStack {
            Group {
                if strips.isEmpty {
                    ContentUnavailableView(
                        "No strips yet",
                        systemImage: "rectangle.stack",
                        description: Text("The iPhone and iPad board is on its way.")
                    )
                } else {
                    List(strips) { strip in
                        Text(strip.title)
                    }
                }
            }
            .navigationTitle("Task Strips")
        }
    }
}

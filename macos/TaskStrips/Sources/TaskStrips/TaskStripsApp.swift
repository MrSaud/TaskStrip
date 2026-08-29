import SwiftUI
import SwiftData

@main
struct TaskStripsApp: App {
    // `.modelContainer(for:)`'s bare convenience form stores at the unqualified
    // "~/Library/Application Support/default.store" — a machine-wide path any SwiftData app
    // could collide on. Namespacing under the app's own subfolder avoids that, and picking a
    // fresh file name here also sidesteps the leftover Phase 0 store (title/isDone/createdAt
    // only), which SwiftData couldn't lightweight-migrate to Phase 1's much larger schema —
    // every save was silently failing against that mismatched store.
    static let sharedModelContainer: ModelContainer = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let storeDirectory = appSupport.appending(path: "TaskStrips", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let storeURL = storeDirectory.appending(path: "TaskStrips.store")
        let configuration = ModelConfiguration(url: storeURL)
        do {
            return try ModelContainer(for: TaskItem.self, configurations: configuration)
        } catch {
            fatalError("Failed to create ModelContainer at \(storeURL): \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            TaskListView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(Self.sharedModelContainer)
    }
}

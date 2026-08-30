import SwiftUI
import SwiftData

@main
struct TaskStripsApp: App {
    /// UI tests launch the app with this argument. It swaps the on-disk store for an in-memory
    /// one seeded with known strips, so a test run can never see — or scribble on — the real
    /// board in ~/Library/Application Support.
    static let uiTestingArgument = "-TaskStripsUITesting"

    /// Titles the UI tests expect on the board, top to bottom.
    static let uiTestingStrips = ["Alpha strip", "Bravo strip", "Charlie strip"]

    private static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    // `.modelContainer(for:)`'s bare convenience form stores at the unqualified
    // "~/Library/Application Support/default.store" — a machine-wide path any SwiftData app
    // could collide on. Namespacing under the app's own subfolder avoids that, and picking a
    // fresh file name here also sidesteps the leftover Phase 0 store (title/isDone/createdAt
    // only), which SwiftData couldn't lightweight-migrate to Phase 1's much larger schema —
    // every save was silently failing against that mismatched store.
    static let sharedModelContainer: ModelContainer = {
        if isUITesting { return uiTestingContainer() }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let storeDirectory = appSupport.appending(path: "TaskStrips", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let storeURL = storeDirectory.appending(path: "TaskStrips.store")
        let configuration = ModelConfiguration(url: storeURL)
        do {
            return try ModelContainer(for: TaskItem.self, Note.self, configurations: configuration)
        } catch {
            fatalError("Failed to create ModelContainer at \(storeURL): \(error)")
        }
    }()

    private static func uiTestingContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: TaskItem.self, Note.self, configurations: configuration)
            let context = ModelContext(container)
            for (index, title) in uiTestingStrips.enumerated() {
                context.insert(TaskItem(title: title, orderIndex: index))
            }
            try context.save()
            return container
        } catch {
            fatalError("Failed to create the UI-testing ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            TaskListView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(Self.sharedModelContainer)
        .defaultSize(width: 860, height: 660)
        .commands { BoardCommandMenus() }

        Settings {
            SettingsView()
                .preferredColorScheme(.dark)
        }
    }
}

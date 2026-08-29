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
        .commands {
            // The board's own toolbar carries this too; a File-menu entry is where a Mac user
            // looks for "open a file from somewhere else", and it's the only way to reach the
            // importer by keyboard. The window owns the picker, so this just pokes it.
            CommandGroup(after: .newItem) {
                Divider()
                Button("Import Android Backup…") {
                    NotificationCenter.default.post(name: .importAndroidBackup, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
    }
}

import SwiftUI
import SwiftData

@main
struct TaskStripsApp: App {
    @AppStorage(AppSettingsKey.showMenuBar) private var showMenuBar = true

    /// UI tests launch the app with this argument. It swaps the on-disk store for an in-memory
    /// one seeded with known strips, so a test run can never see — or scribble on — the real
    /// board in ~/Library/Application Support.
    static let uiTestingArgument = AppLaunch.uiTestingArgument

    /// Titles the UI tests expect on the board, top to bottom.
    static let uiTestingStrips = ["Alpha strip", "Bravo strip", "Charlie strip"]

    /// One file seeded into the storage library, so the library and the "add from storage" picker
    /// have something real to show. Its bytes go into the throwaway media root, never the real
    /// one — see AttachmentStore.shared.
    static let uiTestingLibraryFile = "Seeded receipt.pdf"
    static let uiTestingLibraryPath = "documents/seed/Seeded receipt.pdf"

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

        let storeURL = BoardLocation.storeURL
        let configuration = BoardSchema.configuration(url: storeURL)
        do {
            return try ModelContainer(
                for: Schema(BoardSchema.models),
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create ModelContainer at \(storeURL): \(error)")
        }
    }()

    private static func uiTestingContainer() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(
                for: Schema(BoardSchema.models),
                configurations: configuration
            )
            let context = ModelContext(container)
            for (index, title) in uiTestingStrips.enumerated() {
                context.insert(TaskItem(title: title, orderIndex: index))
            }
            seedLibrary(into: context)
            try context.save()
            return container
        } catch {
            fatalError("Failed to create the UI-testing ModelContainer: \(error)")
        }
    }

    /// The library is only worth testing with something in it, and its rows are only real if the
    /// file behind them exists — the picker greys out anything it can't actually copy.
    private static func seedLibrary(into context: ModelContext) {
        let bytes = Data("a seeded file, standing in for a scanned receipt".utf8)
        try? AttachmentStore.shared.write(bytes, toRelativePath: uiTestingLibraryPath)
        context.insert(
            StorageItem(
                name: uiTestingLibraryFile,
                path: uiTestingLibraryPath,
                type: .document,
                mimeType: "application/pdf",
                sizeBytes: bytes.count,
                tag: "Receipt",
                tagEmoji: "💳"
            )
        )
    }

    /// Named so the menu bar glance can bring the board back after its window has been closed.
    static let boardWindowID = "board"

    init() {
        Self.movePasswordsToICloudKeychain()
        // Phase 5: only on the sync test board (-SyncTestStore); a no-op otherwise.
        if BoardSync.isAllowed {
            let container = Self.sharedModelContainer
            Task { @MainActor in BoardSync.shared.start(container: container) }
        }
    }

    /// Phase 2's one-time move of credential passwords into iCloud Keychain. Off the main thread,
    /// because macOS may ask for the login password to release each old item and the board
    /// shouldn't wait on that. Never under a test: the unit-test host is this app, launched for
    /// real, and it must not go through the real keychain.
    private static func movePasswordsToICloudKeychain() {
        guard !AppLaunch.isUITesting, !AppLaunch.isUnitTesting,
              !CredentialStore.shared.hasMigrated
        else { return }
        let container = sharedModelContainer
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let ids = ((try? context.fetch(FetchDescriptor<Credential>())) ?? []).map(\.id)
            let report = CredentialStore.shared.migrate(ids: ids)
            PasswordMoveStatus.record(report)
        }
    }

    var body: some Scene {
        WindowGroup(id: Self.boardWindowID) {
            TaskListView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(Self.sharedModelContainer)
        .defaultSize(width: 860, height: 660)
        .commands { BoardCommandMenus() }

        // Android puts this on the home screen as a widget. A Mac's nearest equivalent is the
        // menu bar: always there, one click, no window — and unlike a WidgetKit extension it
        // needs no app group, so it reads the same store the board does rather than a copy.
        MenuBarExtra("Task Strips", systemImage: "list.bullet.rectangle", isInserted: $showMenuBar) {
            GlanceView()
                .preferredColorScheme(.dark)
                .modelContainer(Self.sharedModelContainer)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .preferredColorScheme(.dark)
        }
    }
}

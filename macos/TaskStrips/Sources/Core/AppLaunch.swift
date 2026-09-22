import Foundation

/// How the app was launched, for code shared by the Mac and iPhone/iPad apps. The UI tests start
/// the app with this argument, and the stores, the recorder and the sign-in all back off from the
/// real system when they see it.
enum AppLaunch {
    static let uiTestingArgument = "-TaskStripsUITesting"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    /// Running as the host for the unit tests. The app still launches then, and anything it does on
    /// launch against the real keychain or store happens on the test machine for real.
    /// Phase 5: a separate, empty board that sync is allowed to touch. Sync runs only in this
    /// mode until the real data comes over in Phase 6, so a sync bug can only ever hurt test data.
    static let syncTestArgument = "-SyncTestStore"

    /// Sticky in a Debug build, so the app opened from its icon stays on the test board while
    /// Phase 5 is being tried by hand; `-RealStore` switches it back. A Release build never has it.
    static let isSyncTesting: Bool = {
        #if DEBUG
        let key = "debug.syncTestStore"
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-RealStore") {
            UserDefaults.standard.removeObject(forKey: key)
            return false
        }
        if arguments.contains(syncTestArgument) { UserDefaults.standard.set(true, forKey: key) }
        return UserDefaults.standard.bool(forKey: key) && !isUITesting && !isUnitTesting
        #else
        return false
        #endif
    }()

    static var isUnitTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

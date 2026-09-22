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

    static var isSyncTesting: Bool {
        ProcessInfo.processInfo.arguments.contains(syncTestArgument)
    }

    static var isUnitTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

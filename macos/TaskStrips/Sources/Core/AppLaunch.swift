import Foundation

/// How the app was launched, for code shared by the Mac and iPhone/iPad apps. The UI tests start
/// the app with this argument, and the stores, the recorder and the sign-in all back off from the
/// real system when they see it.
enum AppLaunch {
    static let uiTestingArgument = "-TaskStripsUITesting"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }
}

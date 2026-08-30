import Foundation
import LocalAuthentication

/// Touch ID, or the login password if there's no sensor.
///
/// Android asks for a biometric before a password is revealed or copied, and asks again for each
/// — even when the row is already showing. Same rule here: seeing a secret and putting it on the
/// clipboard are separate acts, and the clipboard is the one that leaves the app.
enum LocalAuth {
    /// UI tests can't answer a Touch ID prompt, and the dialog would block the runner until it
    /// timed out. Same escape hatch the notification scheduler uses.
    static var isEnabled: Bool {
        !ProcessInfo.processInfo.arguments.contains(TaskStripsApp.uiTestingArgument)
    }

    static func confirm(reason: String) async -> Bool {
        guard isEnabled else { return true }

        let context = LAContext()
        // deviceOwnerAuthentication rather than biometrics alone: a Mac without Touch ID should
        // fall back to the login password, not refuse outright.
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No Touch ID, no password set, or policy unavailable. Refusing here would lock the
            // user out of their own passwords on a machine they've already unlocked.
            return true
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

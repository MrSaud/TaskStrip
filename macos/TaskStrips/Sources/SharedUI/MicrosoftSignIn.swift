import AuthenticationServices
import Foundation

/// The sign-in itself: a Microsoft page in a sheet the app can't see inside, and a token that
/// comes back through the redirect.
///
/// The password is typed into Microsoft's own page in a browser this app has no access to — which
/// is the point of doing it this way rather than asking for one. What the app keeps is a refresh
/// token, in the same iCloud keychain the other credentials use, so signing in on the Mac signs
/// in on the phone and the iPad too.
@MainActor
final class MicrosoftSignIn: NSObject {
    enum Failure: LocalizedError {
        case cancelled
        case refused(String)
        case noAnswer

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Sign-in was cancelled."
            case .refused(let detail): return detail
            case .noAnswer: return "Microsoft didn't answer the sign-in."
            }
        }
    }

    static let shared = MicrosoftSignIn()

    /// Opens Microsoft's sign-in and returns the tokens it hands back.
    func signIn() async throws -> (tokens: MicrosoftGraph.Tokens, email: String) {
        let verifier = MicrosoftGraph.verifier()
        let state = UUID().uuidString
        guard let url = MicrosoftGraph.signInURL(verifier: verifier, state: state) else {
            throw Failure.noAnswer
        }

        let redirect = try await present(url)
        switch MicrosoftGraph.handoff(from: redirect, expecting: state) {
        case .code(let code):
            let tokens = try await exchange(code: code, verifier: verifier)
            let email = try await MicrosoftTokens.shared.address(using: tokens.access)
            return (tokens, email)
        case .refused(let detail):
            throw Failure.refused(detail)
        case .wrongState:
            // The redirect didn't answer the request this app made. Nothing is taken from it.
            throw Failure.refused("The sign-in answer didn't match the request.")
        }
    }

    private func present(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let scheme = URL(string: MicrosoftGraph.redirectURI)?.scheme ?? "msauth"
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { redirect, error in
                if let redirect {
                    continuation.resume(returning: redirect)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: Failure.cancelled)
                } else {
                    continuation.resume(throwing: error ?? Failure.noAnswer)
                }
            }
            session.presentationContextProvider = self
            // A fresh window each time: signing in as somebody else shouldn't be blocked by whom
            // the browser happens to remember.
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private func exchange(code: String, verifier: String) async throws -> MicrosoftGraph.Tokens {
        let body = MicrosoftGraph.tokenRequestBody(code: code, verifier: verifier)
        return try await MicrosoftTokens.shared.tokens(fromBody: body)
    }
}

extension MicrosoftSignIn: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
        return (scene as? UIWindowScene)?.keyWindow ?? ASPresentationAnchor()
        #endif
    }
}

/// Where Microsoft tokens live, and how they're kept fresh.
///
/// The refresh token is a password in everything but name, so it goes where the passwords go: the
/// iCloud keychain, never the app's own store and never a backup.
actor MicrosoftTokens {
    static let shared = MicrosoftTokens()

    private let keychain = Keychain.iCloud
    private static let service = "com.saud.taskstrip.microsoft"
    private var cached: [UUID: MicrosoftGraph.Tokens] = [:]

    func save(_ tokens: MicrosoftGraph.Tokens, for accountID: UUID) {
        cached[accountID] = tokens
        keychain.set(tokens.refresh, service: Self.service, account: accountID.uuidString)
    }

    func forget(_ accountID: UUID) {
        cached[accountID] = nil
        keychain.remove(service: Self.service, account: accountID.uuidString)
    }

    /// A usable access token: the one in hand while it lasts, a fresh one when it doesn't.
    func access(for accountID: UUID) async throws -> String {
        if let tokens = cached[accountID], tokens.isFresh() { return tokens.access }
        guard let refresh = keychain.value(service: Self.service, account: accountID.uuidString) else {
            throw MicrosoftSignIn.Failure.refused("This account needs signing in again.")
        }
        let renewed = try await tokens(fromBody: MicrosoftGraph.refreshRequestBody(token: refresh))
        save(renewed, for: accountID)
        return renewed.access
    }

    func tokens(fromBody body: String) async throws -> MicrosoftGraph.Tokens {
        var request = URLRequest(url: URL(string: MicrosoftGraph.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let tokens = MicrosoftGraph.tokens(from: json) { return tokens }
        throw MicrosoftSignIn.Failure.refused(
            MicrosoftGraph.errorMessage(in: json) ?? "Microsoft refused the sign-in."
        )
    }

    /// Whose mailbox this is, which is what the account is then called.
    func address(using access: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(MicrosoftGraph.graph)/me")!)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let address = (json["mail"] as? String) ?? (json["userPrincipalName"] as? String)
        guard let address, !address.isEmpty else {
            throw MicrosoftSignIn.Failure.refused(
                MicrosoftGraph.errorMessage(in: json) ?? "Microsoft didn't say which mailbox this is."
            )
        }
        return address
    }
}

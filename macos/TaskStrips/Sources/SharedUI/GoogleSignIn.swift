import AuthenticationServices
import Foundation

/// Signing in to Google, in Google's own page.
///
/// The password is typed into Google's page inside a browser this app can't see into — which is
/// the point of doing it this way instead of asking for an app password. What comes back is a
/// refresh token, kept in the same iCloud keychain as everything else, so signing in on the Mac
/// signs in on the phone and the iPad.
@MainActor
final class GoogleSignIn: NSObject {
    enum Failure: LocalizedError {
        case notConfigured
        case cancelled
        case refused(String)
        case noAnswer

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Add a Google client ID in Settings first — Google gives one to each app."
            case .cancelled: return "Sign-in was cancelled."
            case .refused(let detail): return detail
            case .noAnswer: return "Google didn't answer the sign-in."
            }
        }
    }

    static let shared = GoogleSignIn()

    func signIn() async throws -> (tokens: OAuthTokens, email: String) {
        let clientID = GoogleAuth.clientID()
        guard !clientID.isEmpty, !GoogleAuth.redirectURI(clientID: clientID).isEmpty else {
            throw Failure.notConfigured
        }

        let verifier = OAuthPKCE.verifier()
        let state = UUID().uuidString
        guard let url = GoogleAuth.signInURL(clientID: clientID, verifier: verifier, state: state) else {
            throw Failure.noAnswer
        }

        let redirect = try await present(url, clientID: clientID)
        switch GoogleAuth.handoff(from: redirect, expecting: state) {
        case .code(let code):
            return try await GoogleTokens.shared.exchange(code: code, verifier: verifier, clientID: clientID)
        case .refused(let detail):
            throw Failure.refused(detail)
        case .wrongState:
            throw Failure.refused("The sign-in answer didn't match the request.")
        }
    }

    private func present(_ url: URL, clientID: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let scheme = URL(string: GoogleAuth.redirectURI(clientID: clientID))?.scheme
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { redirect, error in
                if let redirect {
                    continuation.resume(returning: redirect)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: Failure.cancelled)
                } else {
                    continuation.resume(throwing: error ?? Failure.noAnswer)
                }
            }
            session.presentationContextProvider = self
            session.start()
        }
    }
}

extension GoogleSignIn: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
        return (scene as? UIWindowScene)?.keyWindow ?? ASPresentationAnchor()
        #endif
    }
}

/// Google's tokens, kept where the passwords are kept.
actor GoogleTokens {
    static let shared = GoogleTokens()

    private let keychain = Keychain.iCloud
    private static let service = "com.saud.taskstrip.google"
    private var cached: [UUID: OAuthTokens] = [:]

    func save(_ tokens: OAuthTokens, for accountID: UUID) {
        cached[accountID] = tokens
        keychain.set(tokens.refresh, service: Self.service, account: accountID.uuidString)
    }

    func forget(_ accountID: UUID) {
        cached[accountID] = nil
        keychain.remove(service: Self.service, account: accountID.uuidString)
    }

    /// A usable access token: the one in hand while it lasts, a fresh one when it doesn't. This is
    /// what goes to IMAP and SMTP in place of a password.
    func access(for accountID: UUID) async throws -> String {
        if let tokens = cached[accountID], tokens.isFresh() { return tokens.access }
        guard let refresh = keychain.value(service: Self.service, account: accountID.uuidString) else {
            throw GoogleSignIn.Failure.refused("This account needs signing in again.")
        }
        let clientID = GoogleAuth.clientID()
        let json = try await post(GoogleAuth.refreshRequestBody(clientID: clientID, token: refresh))
        // Google sends a refresh token once and not again, so the one already held is kept.
        guard let renewed = OAuthTokens.read(json, keepingRefresh: refresh) else {
            throw GoogleSignIn.Failure.refused(
                GoogleAuth.errorMessage(in: json) ?? "Google refused to refresh the sign-in."
            )
        }
        save(renewed, for: accountID)
        return renewed.access
    }

    func exchange(code: String, verifier: String, clientID: String) async throws -> (tokens: OAuthTokens, email: String) {
        let json = try await post(GoogleAuth.tokenRequestBody(clientID: clientID, code: code, verifier: verifier))
        guard let tokens = OAuthTokens.read(json) else {
            throw GoogleSignIn.Failure.refused(
                GoogleAuth.errorMessage(in: json) ?? "Google refused the sign-in."
            )
        }
        guard let email = (json["id_token"] as? String).flatMap(GoogleAuth.email(inIDToken:)) else {
            throw GoogleSignIn.Failure.refused("Google didn't say which mailbox this is.")
        }
        return (tokens, email)
    }

    private func post(_ body: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: GoogleAuth.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

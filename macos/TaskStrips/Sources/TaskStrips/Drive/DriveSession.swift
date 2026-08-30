import AppKit
import AuthenticationServices
import Foundation

/// Holds the Drive sign-in: runs the consent flow, keeps the access token fresh, and hands out a
/// client that's ready to call.
///
/// The refresh token is the only thing that persists, and it lives in the keychain. Access tokens
/// are kept in memory and last an hour — writing them anywhere would be storing something that's
/// stale by the time it's read.
@MainActor
final class DriveSession: ObservableObject {
    static let shared = DriveSession()

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var isBusy = false

    private var tokens: GoogleOAuth.Tokens?
    private var authSession: ASWebAuthenticationSession?
    private let presenter = Presenter()
    /// UI tests must never reach a browser or the network — a consent window would sit there
    /// until the whole suite timed out.
    private let isEnabled: Bool

    private init() {
        isEnabled = !ProcessInfo.processInfo.arguments.contains(TaskStripsApp.uiTestingArgument)
        isSignedIn = isEnabled && GoogleOAuth.isSignedIn
    }

    var clientID: String? { GoogleOAuth.clientID() }
    var isConfigured: Bool { clientID?.isEmpty == false }

    /// Rejects anything that isn't shaped like a Google client id up front — the alternative is a
    /// consent screen that fails with something unhelpful several steps later.
    func setClientID(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty || GoogleOAuth.redirectScheme(for: trimmed) != nil else {
            throw DriveError.badClientID
        }
        GoogleOAuth.setClientID(trimmed)
        if trimmed.isEmpty { signOut() }
        objectWillChange.send()
    }

    func signIn() async throws {
        guard isEnabled else { return }
        guard let clientID, !clientID.isEmpty else { throw DriveError.notConfigured }
        guard let scheme = GoogleOAuth.redirectScheme(for: clientID) else { throw DriveError.badClientID }

        let pkce = GoogleOAuth.makePKCE()
        guard let url = GoogleOAuth.authorizationURL(clientID: clientID, pkce: pkce) else {
            throw DriveError.badClientID
        }

        isBusy = true
        defer { isBusy = false }

        let callback = try await authorize(url: url, scheme: scheme)
        let code = try GoogleOAuth.authorizationCode(from: callback).get()
        guard let request = GoogleOAuth.tokenRequest(clientID: clientID, code: code, verifier: pkce.verifier) else {
            throw DriveError.badClientID
        }

        let (data, response) = try await URLSessionTransport().send(request)
        guard (200..<300).contains(response.statusCode), let tokens = GoogleOAuth.tokens(from: data) else {
            throw DriveError.http(response.statusCode, DriveClient.errorMessage(from: data))
        }
        // Only the first exchange carries one; without it there's nothing to come back with
        // tomorrow.
        guard let refreshToken = tokens.refreshToken else { throw DriveError.malformedResponse }

        GoogleOAuth.store(refreshToken: refreshToken)
        self.tokens = tokens
        isSignedIn = true
    }

    func signOut() {
        GoogleOAuth.signOut()
        tokens = nil
        isSignedIn = false
    }

    /// A client with a token that's good right now, refreshing first if the one in hand is old.
    func client() async throws -> DriveClient {
        guard isEnabled else { throw DriveError.notSignedIn }
        guard let clientID, !clientID.isEmpty else { throw DriveError.notConfigured }

        if let tokens, tokens.expiresAt > .now {
            return DriveClient(accessToken: tokens.accessToken)
        }
        guard let refreshToken = GoogleOAuth.storedRefreshToken() else {
            isSignedIn = false
            throw DriveError.notSignedIn
        }

        let request = GoogleOAuth.refreshRequest(clientID: clientID, refreshToken: refreshToken)
        let (data, response) = try await URLSessionTransport().send(request)
        guard (200..<300).contains(response.statusCode), let refreshed = GoogleOAuth.tokens(from: data) else {
            // A refresh token can be revoked from the Google account page, and then nothing here
            // will work again until the user signs in afresh.
            signOut()
            throw DriveError.http(response.statusCode, DriveClient.errorMessage(from: data))
        }
        tokens = refreshed
        if let rotated = refreshed.refreshToken { GoogleOAuth.store(refreshToken: rotated) }
        isSignedIn = true
        return DriveClient(accessToken: refreshed.accessToken)
    }

    private func authorize(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: DriveError.signInCancelled)
                } else {
                    continuation.resume(throwing: DriveError.signInFailed(error?.localizedDescription ?? "unknown"))
                }
            }
            session.presentationContextProvider = presenter
            // A shared cookie jar would silently reuse whichever Google account the browser is
            // already signed into, which is exactly the surprise to avoid on a shared Mac.
            session.prefersEphemeralWebBrowserSession = true
            authSession = session
            session.start()
        }
    }

    private final class Presenter: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        }
    }
}

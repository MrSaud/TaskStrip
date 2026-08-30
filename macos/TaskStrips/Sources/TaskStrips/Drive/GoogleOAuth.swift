import AuthenticationServices
import CryptoKit
import Foundation

/// Signing in to Google from a Mac app, the way installed apps are supposed to: the system
/// browser, PKCE, and a refresh token in the keychain.
///
/// The scope is `drive.file`, matching DriveAuthHelper.kt exactly — the app sees only files it
/// created, never anything else in Drive, which is also why neither app needs Google's
/// verification review.
///
/// No client secret. An OAuth client of type iOS (which covers macOS bundle ids) doesn't issue
/// one, and a secret shipped inside an app isn't secret anyway; PKCE is what actually protects
/// the exchange.
enum GoogleOAuth {
    static let scope = "https://www.googleapis.com/auth/drive.file"
    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    private static let service = "com.saud.taskstrip.mac.drive"
    private static let refreshTokenAccount = "refreshToken"
    private static let clientIDAccount = "clientID"

    // MARK: - What the user has to provide

    /// The OAuth client id, kept in the keychain rather than the repository.
    ///
    /// It isn't a secret in the cryptographic sense, but it identifies a Google Cloud project and
    /// has no business in a git history — and it differs per install anyway.
    static func clientID(keychain: Keychain = .shared) -> String? {
        keychain.value(service: service, account: clientIDAccount)
    }

    @discardableResult
    static func setClientID(_ clientID: String?, keychain: Keychain = .shared) -> Bool {
        keychain.set(clientID?.trimmingCharacters(in: .whitespaces), service: service, account: clientIDAccount)
    }

    /// Google's convention for an iOS-type client: the client id reversed, used as a URL scheme.
    /// `123-abc.apps.googleusercontent.com` becomes `com.googleusercontent.apps.123-abc`.
    static func redirectScheme(for clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        return "com.googleusercontent.apps." + String(clientID.dropLast(suffix.count))
    }

    static func redirectURI(for clientID: String) -> String? {
        redirectScheme(for: clientID).map { $0 + ":/oauth2redirect" }
    }

    // MARK: - PKCE

    struct PKCE {
        let verifier: String
        var challenge: String { GoogleOAuth.challenge(for: verifier) }
    }

    static func makePKCE() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return PKCE(verifier: base64URL(Data(bytes)))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// base64url without padding, as RFC 7636 requires. Ordinary base64 would be rejected by the
    /// token endpoint, and the failure reads as a wrong code rather than a wrong encoding.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Building the requests

    static func authorizationURL(clientID: String, pkce: PKCE) -> URL? {
        guard let redirectURI = redirectURI(for: clientID),
              var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)
        else { return nil }

        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // Without both of these Google hands back an access token only, and the app would ask
            // for consent again every hour.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components.url
    }

    /// Pulls the authorization code out of what the browser redirected to, or the error Google
    /// put there instead — a denied consent comes back as `?error=access_denied`, not a failure.
    static func authorizationCode(from callback: URL) -> Result<String, DriveError> {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
            return .failure(.badCallback)
        }
        let items = components.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            return .failure(error == "access_denied" ? .signInCancelled : .signInFailed(error))
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            return .failure(.badCallback)
        }
        return .success(code)
    }

    static func tokenRequest(clientID: String, code: String, verifier: String) -> URLRequest? {
        guard let redirectURI = redirectURI(for: clientID) else { return nil }
        return formRequest([
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ])
    }

    static func refreshRequest(clientID: String, refreshToken: String) -> URLRequest {
        formRequest([
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])!
    }

    private static func formRequest(_ fields: [String: String]) -> URLRequest? {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery.map { Data($0.utf8) }
        return request
    }

    struct Tokens: Equatable {
        var accessToken: String
        /// Only sent on the first exchange; a refresh keeps the one already held.
        var refreshToken: String?
        var expiresAt: Date
    }

    static func tokens(from data: Data, now: Date = .now) -> Tokens? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = object["access_token"] as? String
        else { return nil }

        // A minute of slack: a token that expires while the upload is in flight is worse than one
        // refreshed slightly early.
        let seconds = (object["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return Tokens(
            accessToken: accessToken,
            refreshToken: object["refresh_token"] as? String,
            expiresAt: now.addingTimeInterval(max(seconds - 60, 0))
        )
    }

    // MARK: - The stored refresh token

    static func storedRefreshToken(keychain: Keychain = .shared) -> String? {
        keychain.value(service: service, account: refreshTokenAccount)
    }

    @discardableResult
    static func store(refreshToken: String?, keychain: Keychain = .shared) -> Bool {
        keychain.set(refreshToken, service: service, account: refreshTokenAccount)
    }

    static func signOut(keychain: Keychain = .shared) {
        keychain.remove(service: service, account: refreshTokenAccount)
    }

    static var isSignedIn: Bool { storedRefreshToken() != nil }
}

enum DriveError: LocalizedError, Equatable {
    case notConfigured
    case badClientID
    case signInCancelled
    case signInFailed(String)
    case badCallback
    case notSignedIn
    case http(Int, String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google Drive isn't set up yet — add an OAuth client id in Settings."
        case .badClientID:
            return "That doesn't look like a Google OAuth client id. It should end in "
                + "\".apps.googleusercontent.com\"."
        case .signInCancelled:
            return "Sign-in was cancelled."
        case .signInFailed(let reason):
            return "Google refused the sign-in: \(reason)."
        case .badCallback:
            return "Google's reply couldn't be read."
        case .notSignedIn:
            return "Sign in to Google Drive first."
        case .http(let status, let message):
            return message.isEmpty ? "Drive returned \(status)." : "Drive returned \(status): \(message)"
        case .malformedResponse:
            return "Drive's reply wasn't in the shape this app expects."
        }
    }
}

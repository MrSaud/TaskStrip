import CryptoKit
import Foundation

/// Signing in to Microsoft, and reading mail through Graph.
///
/// Microsoft stopped accepting passwords over IMAP and SMTP, and turning IMAP back on is a switch
/// each organisation decides for itself — most leave it off. Graph doesn't depend on that switch,
/// which is the only reason an app used from more than one organisation can reach Exchange at all.
///
/// The parts that can be checked without a network live here: the sign-in URLs, the proof that
/// goes with them, and the shape of what Graph sends back.
enum MicrosoftGraph {
    /// The app's own registration. A client id is public by design — it names the app, it doesn't
    /// authorise anything. There is no secret: one shipped inside an app isn't a secret, which is
    /// why this signs in with PKCE instead.
    static let clientID = "481f085f-4ccc-4494-a748-43906f942b99"
    static let redirectURI = "msauth.com.saud.taskstrip://auth"

    /// `common` rather than a tenant id: whoever signs in brings their own organisation with them.
    static let authorizeURL = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
    static let tokenURL = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
    static let graph = "https://graph.microsoft.com/v1.0"

    /// Read mail, send mail, know whose mailbox this is, and keep working tomorrow without asking
    /// again. Nothing broader: an app that asks for more than it needs is an app an administrator
    /// refuses.
    static let scopes = [
        "https://graph.microsoft.com/Mail.Read",
        "https://graph.microsoft.com/Mail.Send",
        "https://graph.microsoft.com/User.Read",
        "offline_access",
    ]

    // MARK: - The sign-in

    /// The secret half of PKCE: a random string kept on the device, whose hash is sent up front.
    /// Only whoever holds the original can finish the sign-in, which is what makes a redirect back
    /// into an app safe without a client secret.
    static func verifier(bytes: Data = Data((0..<64).map { _ in UInt8.random(in: 0...255) })) -> String {
        base64URL(bytes)
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Base64 as a URL carries it: no padding, and the two characters that mean something else in
    /// a URL swapped for ones that don't.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func signInURL(verifier: String, state: String) -> URL? {
        var components = URLComponents(string: authorizeURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // Asks which account to use rather than silently taking whichever the browser knows,
            // since somebody signing in here may have two.
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return components?.url
    }

    /// What came back on the redirect: the code, or the reason there isn't one.
    enum Handoff: Equatable {
        case code(String)
        case refused(String)
        case wrongState
    }

    static func handoff(from url: URL, expecting state: String) -> Handoff {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        // The state proves this redirect answers the request this app made, and not somebody
        // else's.
        guard value("state") == state else { return .wrongState }
        if let code = value("code") { return .code(code) }
        let description = value("error_description") ?? value("error") ?? "Sign-in didn't complete."
        return .refused(description)
    }

    static func tokenRequestBody(code: String, verifier: String) -> String {
        form([
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
            "scope": scopes.joined(separator: " "),
        ])
    }

    static func refreshRequestBody(token: String) -> String {
        form([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": token,
            "scope": scopes.joined(separator: " "),
        ])
    }

    static func form(_ fields: [String: String]) -> String {
        fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(escaped($0.value))" }
            .joined(separator: "&")
    }

    static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? value
    }

    /// What the token endpoint answers with.
    struct Tokens: Equatable {
        var access: String
        var refresh: String
        var expiresAt: Date

        /// Refreshed a minute early: a token that expires while a request is in the air is a
        /// request that fails for no good reason.
        func isFresh(at now: Date = .now) -> Bool { expiresAt.addingTimeInterval(-60) > now }
    }

    static func tokens(from json: [String: Any], now: Date = .now) -> Tokens? {
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String
        else { return nil }
        let seconds = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3_600
        return Tokens(access: access, refresh: refresh, expiresAt: now.addingTimeInterval(seconds))
    }

    /// The reason a request was refused, as Graph words it.
    static func errorMessage(in json: [String: Any]) -> String? {
        guard let error = json["error"] else { return nil }
        if let described = error as? [String: Any] {
            return described["message"] as? String ?? described["code"] as? String
        }
        if let code = error as? String {
            return (json["error_description"] as? String) ?? code
        }
        return nil
    }
}

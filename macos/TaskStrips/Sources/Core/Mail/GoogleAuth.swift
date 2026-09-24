import Foundation

/// Signing in to Google, for accounts that would rather not keep an app password.
///
/// Gmail still answers IMAP and SMTP — unlike Exchange — so signing in with Google doesn't need a
/// second mail client. It swaps one line of the conversation: a token instead of a password, and
/// everything after it is the client that already works.
enum GoogleAuth {
    /// Google gives every app its own client id, and the redirect is that id backwards. Kept in
    /// settings rather than in the source because it belongs to whoever builds the app, and
    /// somebody else's copy should carry their own.
    static let clientIDKey = "googleClientID"

    static func clientID(_ defaults: UserDefaults = .standard) -> String {
        (defaults.string(forKey: clientIDKey) ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`, which is the
    /// scheme Google expects an installed app to come back on.
    static func redirectURI(clientID: String) -> String {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return "" }
        return "com.googleusercontent.apps.\(clientID.dropLast(suffix.count)):/oauth2redirect"
    }

    static let authorizeURL = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenURL = "https://oauth2.googleapis.com/token"

    /// Everything IMAP and SMTP need, and the address of the mailbox. `https://mail.google.com/`
    /// is what Google calls the IMAP scope — there isn't a narrower one that lets a mail client
    /// in, which is worth knowing before it's asked for.
    static let scopes = ["https://mail.google.com/", "email"]

    static func signInURL(clientID: String, verifier: String, state: String) -> URL? {
        var components = URLComponents(string: authorizeURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI(clientID: clientID)),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: OAuthPKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // Google only hands over a refresh token when it's asked to, and only the first time
            // unless consent is asked for again. Without these, the account works for an hour and
            // then asks to sign in again forever.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components?.url
    }

    enum Handoff: Equatable {
        case code(String)
        case refused(String)
        case wrongState
    }

    static func handoff(from url: URL, expecting state: String) -> Handoff {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard value("state") == state else { return .wrongState }
        if let code = value("code") { return .code(code) }
        return .refused(value("error") ?? "Sign-in didn't complete.")
    }

    static func tokenRequestBody(clientID: String, code: String, verifier: String) -> String {
        OAuthPKCE.form([
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI(clientID: clientID),
            "code_verifier": verifier,
        ])
    }

    static func refreshRequestBody(clientID: String, token: String) -> String {
        OAuthPKCE.form([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": token,
        ])
    }

    /// Whose mailbox this is. The id token carries it, which saves a second request: the middle
    /// third of a JWT is JSON, and the email is in it.
    static func email(inIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Base64 without its padding, which is how a JWT writes it.
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return json["email"] as? String
    }

    static func errorMessage(in json: [String: Any]) -> String? {
        if let described = json["error_description"] as? String { return described }
        if let code = json["error"] as? String { return code }
        return nil
    }
}

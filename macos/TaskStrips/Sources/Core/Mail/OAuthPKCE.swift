import CryptoKit
import Foundation

/// The proof that lets an app sign somebody in without a secret.
///
/// A secret shipped inside an app isn't a secret — anybody can read it out of the binary. PKCE
/// replaces it: a random string is made here, its hash goes up with the request, and only whoever
/// holds the original can finish the exchange. Microsoft and Google both work this way, which is
/// why it lives here rather than in either one.
enum OAuthPKCE {
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

    static func form(_ fields: [String: String]) -> String {
        fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(escaped($0.value))" }
            .joined(separator: "&")
    }

    static func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? value
    }
}

/// What a provider hands back when somebody signs in.
struct OAuthTokens: Equatable {
    var access: String
    var refresh: String
    var expiresAt: Date

    /// Refreshed a minute early: a token that expires while a request is in the air is a request
    /// that fails for no good reason.
    func isFresh(at now: Date = .now) -> Bool { expiresAt.addingTimeInterval(-60) > now }

    /// Google doesn't send a refresh token again on a refresh — only the first time — so the one
    /// already held is kept.
    static func read(_ json: [String: Any], keepingRefresh existing: String? = nil, now: Date = .now) -> OAuthTokens? {
        guard let access = json["access_token"] as? String else { return nil }
        guard let refresh = (json["refresh_token"] as? String) ?? existing else { return nil }
        let seconds = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3_600
        return OAuthTokens(access: access, refresh: refresh, expiresAt: now.addingTimeInterval(seconds))
    }
}

/// The line that signs in to IMAP or SMTP with a token instead of a password.
///
/// `user=someone@example.com\1auth=Bearer ya29...\1\1`, base64'd. The separators are control
/// characters, which is why this is built rather than written out: a space where a \1 belongs is
/// a sign-in that fails with nothing to look at.
enum XOAUTH2 {
    static func token(email: String, accessToken: String) -> String {
        let one = String(UnicodeScalar(1))
        let line = "user=\(email)\(one)auth=Bearer \(accessToken)\(one)\(one)"
        return Data(line.utf8).base64EncodedString()
    }

    /// IMAP: the whole exchange is one command.
    static func imapCommand(tag: String, email: String, accessToken: String) -> String {
        "\(tag) AUTHENTICATE XOAUTH2 \(token(email: email, accessToken: accessToken))\r\n"
    }

    /// SMTP: the same string, after AUTH XOAUTH2.
    static func smtpCommand(email: String, accessToken: String) -> String {
        "AUTH XOAUTH2 \(token(email: email, accessToken: accessToken))\r\n"
    }
}

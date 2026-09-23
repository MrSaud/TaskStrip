import Foundation

/// What counts as a link to an email, and how to read one out of a message file.
///
/// It lives beside the share inbox rather than with the rest of the mail code because the Share
/// Extension is its own little program: it can see this folder and the App Group, and nothing
/// else of the app. Both sides have to agree on what a linked message is, so both sides read it
/// from here.
enum EmailLink {
    /// Schemes that mean "a message in a mail app" rather than a page on the web. `message:` is
    /// what Mail hands over when a message is dragged out of it; the others are what other mail
    /// apps use for the same thing.
    static let schemes: Set<String> = ["message", "x-msg", "emailmessage", "mailto"]

    static func isMessage(_ url: String) -> Bool {
        guard let scheme = URL(string: url.trimmingCharacters(in: .whitespaces))?.scheme?.lowercased() else {
            return false
        }
        return schemes.contains(scheme)
    }

    /// What a linked message is called on a strip when it carries no label of its own: a
    /// `message:` URL is a long opaque id, and showing that helps nobody.
    static func label(for url: String) -> String {
        guard isMessage(url) else { return url }
        if URL(string: url)?.scheme?.lowercased() == "mailto" {
            let to = url.dropFirst("mailto:".count).prefix { $0 != "?" }
            return to.isEmpty ? "Email" : "Email \(to)"
        }
        return "Email message"
    }

    static func isEmailFile(_ url: URL) -> Bool {
        ["eml", "emlx", "mbox"].contains(url.pathExtension.lowercased())
    }

    /// The link back to a message, read out of an email file.
    ///
    /// Mail hands a message over in more than one shape: sometimes as a `message:` URL, sometimes
    /// as the message itself, a .eml file. Every email carries a Message-ID, which is exactly what
    /// a `message:` URL points at — so a file can still become a link to the message in Mail
    /// rather than only a copy of it on disk.
    static func fromEmail(_ text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(400) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Headers stop at the first blank line; nothing after it is a Message-ID.
            if trimmed.isEmpty { break }
            guard trimmed.lowercased().hasPrefix("message-id:") else { continue }
            let value = trimmed.dropFirst("message-id:".count).trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("<"), value.hasSuffix(">"), value.count > 2 else { continue }
            guard let escaped = value.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~@"))
            ) else { return nil }
            return "message://\(escaped)"
        }
        return nil
    }
}

import Foundation

/// The half of SMTP this app speaks: say hello, sign in, name the sender and the recipients, hand
/// over the message.
///
/// Submission on 465, TLS from the first byte, exactly like the IMAP side. Not 587: that starts in
/// plain text and upgrades with STARTTLS, and a connection already running can't be handed to TLS
/// afterwards here — so the port that is encrypted from the first byte is the only one offered.
enum SMTPCommand {
    static func ehlo(host: String = "localhost") -> String { "EHLO \(host)\r\n" }
    static let authLogin = "AUTH LOGIN\r\n"
    static func base64(_ text: String) -> String { Data(text.utf8).base64EncodedString() + "\r\n" }
    static func mailFrom(_ address: String) -> String { "MAIL FROM:<\(address)>\r\n" }
    static func recipient(_ address: String) -> String { "RCPT TO:<\(address)>\r\n" }
    static let data = "DATA\r\n"
    static let quit = "QUIT\r\n"

    /// The message, ready to be sent after DATA.
    ///
    /// A line of a message that begins with a full stop has another put in front of it, because a
    /// lone full stop on its own line is how the message ends. Getting this wrong truncates mail
    /// at the first line that happens to start with a dot.
    static func body(_ message: String) -> String {
        let stuffed = message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix(".") ? "." + $0 : String($0) }
            .joined(separator: "\r\n")
        return stuffed + "\r\n.\r\n"
    }
}

/// What the server says back: a three-digit code, and a line of English after it.
///
/// A reply can run to several lines — `250-PIPELINING`, `250-SIZE`, then `250 AUTH LOGIN PLAIN` —
/// and it's the last one, with a space rather than a hyphen after the code, that means the server
/// has finished talking.
enum SMTPResponse {
    struct Reply: Equatable {
        var code: Int
        var text: String

        /// 2xx is done, 3xx is "go on" (the password, the message), 4xx and 5xx are refusals.
        var isPositive: Bool { (200..<400).contains(code) }
        var wantsMore: Bool { (300..<400).contains(code) }
    }

    static func complete(in text: String) -> Reply? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: true)
        guard let last = lines.last, last.count >= 4 else { return nil }
        let digits = last.prefix(3)
        guard let code = Int(digits) else { return nil }
        // A hyphen means another line is coming; a space means that was the last of them.
        guard last[last.index(last.startIndex, offsetBy: 3)] == " " else { return nil }

        // The whole reply's text, not only its final line: the useful part of a refusal is often
        // in the middle of one.
        let detail = lines
            .filter { $0.count > 4 && Int($0.prefix(3)) == code }
            .map { String($0.dropFirst(4)) }
            .joined(separator: " ")
        return Reply(code: code, text: detail.isEmpty ? String(last.dropFirst(4)) : detail)
    }
}

/// Where a provider's outgoing server lives, worked out from the incoming one it's already set up
/// beside. Every provider this app meets names the two the same way.
enum SMTPHost {
    static func guess(forIMAPHost host: String) -> String {
        let name = host.lowercased()
        switch name {
        case "imap.gmail.com": return "smtp.gmail.com"
        case "imap.mail.me.com": return "smtp.mail.me.com"
        case "imap.mail.yahoo.com": return "smtp.mail.yahoo.com"
        case "outlook.office365.com": return "smtp.office365.com"
        case "imap.zoho.com": return "smtp.zoho.com"
        default:
            // imap.mail.us-east-1.awsapps.com → smtp.mail.us-east-1.awsapps.com, and
            // imap.example.com → smtp.example.com. Anything else keeps its own name.
            guard name.hasPrefix("imap.") else { return name }
            return "smtp." + name.dropFirst("imap.".count)
        }
    }

    /// Implicit TLS. See the note on SMTPCommand for why 587 isn't offered.
    static let port = 465
}

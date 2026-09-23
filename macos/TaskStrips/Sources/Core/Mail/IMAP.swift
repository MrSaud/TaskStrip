import Foundation

/// An account the app reads mail from directly, over IMAP.
///
/// The password never lives here — it goes in the keychain the credentials already use, which is
/// the iCloud one, so an account set up on the Mac is set up on the phone too.
struct IMAPAccount: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var email: String
    var host: String
    var port: Int = 993
    /// What to call it in the pane when more than one is set up.
    var label: String = ""

    var name: String { label.isEmpty ? email : label }
}

/// Which server an address belongs to, for the ones that can be guessed.
///
/// Guessing saves typing for the four or five providers most people use; anything else asks. The
/// convention `imap.<domain>` is right often enough to offer, never to assume silently.
enum IMAPHost {
    static func guess(for email: String) -> (host: String, port: Int)? {
        let parts = email.split(separator: "@")
        // An address, not a name: something before the @, something with a dot after it.
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let domain = String(parts[1]).lowercased()
        guard domain.contains("."), !domain.contains(" ") else { return nil }
        switch domain {
        case "icloud.com", "me.com", "mac.com": return ("imap.mail.me.com", 993)
        case "gmail.com", "googlemail.com": return ("imap.gmail.com", 993)
        case "yahoo.com", "yahoo.co.uk", "ymail.com": return ("imap.mail.yahoo.com", 993)
        case "outlook.com", "hotmail.com", "live.com": return ("outlook.office365.com", 993)
        default: return ("imap.\(domain)", 993)
        }
    }

    /// Whether this provider still lets a password in at all.
    ///
    /// Microsoft turned basic authentication off for Exchange Online: an IMAP login with a
    /// password is refused there however correct it is, and only OAuth gets in. Saying so when
    /// the address is typed is kinder than a login that fails for reasons nobody can see.
    static func refusesPasswords(_ email: String) -> Bool {
        let domain = email.split(separator: "@").last.map { String($0).lowercased() } ?? ""
        return ["outlook.com", "hotmail.com", "live.com", "office365.com"].contains(domain)
    }

    /// Whether the provider wants a password made for one app rather than the account's own.
    static func wantsAppPassword(_ email: String) -> Bool {
        let domain = email.split(separator: "@").last.map { String($0).lowercased() } ?? ""
        return ["icloud.com", "me.com", "mac.com", "gmail.com", "googlemail.com",
                "yahoo.com", "yahoo.co.uk", "ymail.com"].contains(domain)
    }
}

/// What a refusal actually means, where the server's own words need translating.
///
/// Google answers a correct account password with "Application-specific password required" and a
/// support link — true, but it reads like a bug unless you already know that an app password is
/// a different, sixteen-letter one you have to go and make.
enum IMAPRefusal {
    static func advice(for message: String) -> String? {
        let text = message.lowercased()
        if text.contains("application-specific password") {
            return "Google needs an app password: your Google Account › Security › 2-Step "
                + "Verification › App passwords. It's sixteen letters, and it goes in the password "
                + "field here instead of your own."
        }
        if text.contains("authenticationfailed") || text.contains("invalid credentials") {
            return "The address or password wasn't accepted. On iCloud and Yahoo this field wants "
                + "an app-specific password rather than your own."
        }
        if text.contains("basic authentication") || text.contains("authenticate") && text.contains("disabled") {
            return "This server has turned password sign-in off and wants OAuth, which this app "
                + "doesn't do yet."
        }
        return nil
    }
}

/// The half of IMAP this app speaks: log in, choose the inbox, ask for the newest few headers.
///
/// Every command carries a tag, and a reply belongs to the command whose tag it repeats. Kept
/// apart from the socket so the conversation can be checked without a server.
enum IMAPCommand {
    static func tag(_ number: Int) -> String { "a\(String(format: "%03d", number))" }

    static func login(tag: String, email: String, password: String) -> String {
        // Quoted strings with the two characters IMAP cares about escaped. A password with a
        // quote in it would otherwise end the string early and log in as nobody.
        "\(tag) LOGIN \(quoted(email)) \(quoted(password))\r\n"
    }

    static func selectInbox(tag: String) -> String { "\(tag) SELECT INBOX\r\n" }

    /// The newest `count` of `total`, by sequence number — IMAP numbers them oldest first, so the
    /// newest are at the end.
    static func fetchNewest(tag: String, total: Int, count: Int) -> String {
        let from = max(total - count + 1, 1)
        return "\(tag) FETCH \(from):\(total) (FLAGS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)])\r\n"
    }

    static func logout(tag: String) -> String { "\(tag) LOGOUT\r\n" }

    static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// What came back.
enum IMAPResponse {
    enum Outcome: Equatable {
        case ok(String)
        case no(String)
        case bad(String)
    }

    /// The line that finishes a command, if it's arrived: the one starting with its tag.
    static func completion(for tag: String, in text: String) -> Outcome? {
        for line in text.split(separator: "\r\n", omittingEmptySubsequences: true) {
            guard line.hasPrefix(tag + " ") else { continue }
            let rest = String(line.dropFirst(tag.count + 1))
            let words = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let detail = words.count > 1 ? String(words[1]) : ""
            switch words.first?.uppercased() {
            case "OK": return .ok(detail)
            case "NO": return .no(detail)
            case "BAD": return .bad(detail)
            default: return nil
            }
        }
        return nil
    }

    /// How many messages the mailbox holds, from `* 1234 EXISTS`.
    static func exists(in text: String) -> Int? {
        for line in text.split(separator: "\r\n") {
            let words = line.split(separator: " ")
            guard words.count >= 3, words[0] == "*", words[2].uppercased() == "EXISTS" else { continue }
            return Int(words[1])
        }
        return nil
    }
}

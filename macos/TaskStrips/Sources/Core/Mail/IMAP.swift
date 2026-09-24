import Foundation

/// An account the app reads mail from directly, over IMAP.
///
/// The password never lives here — it goes in the keychain the credentials already use, which is
/// the iCloud one, so an account set up on the Mac is set up on the phone too.
/// How an account signs in and how its mail is fetched.
///
/// Two, because Microsoft leaves no choice: everyone else takes a password over IMAP, and
/// Exchange takes an OAuth token over Graph.
enum MailProvider: String, Codable, Equatable {
    case password
    case microsoft
}

struct IMAPAccount: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var email: String
    var host: String
    var port: Int = 993
    /// What to call it in the pane when more than one is set up.
    var label: String = ""
    /// The outgoing server, where it isn't the one this account's incoming server implies.
    /// Optional so an account saved before the app could send still decodes.
    var smtpHost: String?
    var smtpPort: Int?
    /// The name on mail sent from this account.
    var senderName: String?
    /// What goes at the bottom of everything sent from it. Per account, because the signature on
    /// work mail is not the one on personal mail.
    var signature: MailSignature?

    /// Optional so every account saved before Exchange was possible still decodes — and reads as
    /// what it is, an account with a password.
    var provider: MailProvider?

    var name: String { label.isEmpty ? email : label }

    var signsInWithMicrosoft: Bool { provider == .microsoft }

    /// An account Microsoft signs in for. It has no host of its own: Graph is one address for
    /// everybody, and which mailbox is decided by the token.
    static func microsoft(email: String) -> IMAPAccount {
        IMAPAccount(email: email, host: "graph.microsoft.com", port: 443, provider: .microsoft)
    }

    var outgoingHost: String { smtpHost ?? SMTPHost.guess(forIMAPHost: host) }
    var outgoingPort: Int { smtpPort ?? SMTPHost.port }
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
        // The UID as well as the headers: a sequence number is only true until something is
        // deleted, and the UID is what asking for the message itself later has to quote.
        // TO, CC and REPLY-TO as well: a reply goes where the sender said replies should go, and
        // a reply to everyone needs to know who everyone was.
        return "\(tag) FETCH \(from):\(total) (UID FLAGS BODY.PEEK"
            + "[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID TO CC REPLY-TO)])\r\n"
    }

    /// The whole message, up to a limit. PEEK again: opening a message in this app doesn't mark
    /// it read on the server, the way opening it in a mail client would.
    static func fetchBody(tag: String, uid: Int, limit: Int) -> String {
        "\(tag) UID FETCH \(uid) (BODY.PEEK[]<0.\(limit)>)\r\n"
    }

    static func logout(tag: String) -> String { "\(tag) LOGOUT\r\n" }

    /// Every mailbox the account has, with the attributes that say what each one is for.
    static func listAll(tag: String) -> String { "\(tag) LIST \"\" \"*\"\r\n" }

    /// Puts a message into a mailbox — how a sent message gets into Sent. The byte count is
    /// declared first and the message follows; \Seen because a message you wrote yourself has
    /// been read by the only person who needs to.
    static func append(tag: String, mailbox: String, bytes: Int) -> String {
        "\(tag) APPEND \(quoted(mailbox)) (\\Seen) {\(bytes)}\r\n"
    }

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

    /// Which mailbox is the Sent one, out of a LIST reply.
    ///
    /// Servers disagree about the name — "Sent", "Sent Messages", "Sent Items", and Gmail's
    /// "[Gmail]/Sent Mail" — but most of them tag it `\Sent` in the attributes, which is worth
    /// far more than guessing at names. Only when nothing is tagged does the name matter, and
    /// then the usual four are tried in the order they're commonly used.
    static func sentMailbox(in text: String) -> String? {
        var names: [String] = []
        for line in text.split(separator: "\r\n") {
            guard line.hasPrefix("* LIST ") else { continue }
            guard let close = line.range(of: ")") else { continue }
            let attributes = line[line.startIndex..<close.upperBound].lowercased()
            guard let name = mailboxName(in: line) else { continue }
            if attributes.contains("\\sent") { return name }
            names.append(name)
        }
        let usual = ["sent", "sent messages", "sent items", "[gmail]/sent mail", "inbox.sent"]
        for candidate in usual {
            if let match = names.first(where: { $0.lowercased() == candidate }) { return match }
        }
        return nil
    }

    /// The last field of a LIST line: `* LIST (\HasNoChildren \Sent) "/" "[Gmail]/Sent Mail"`.
    static func mailboxName(in line: Substring) -> String? {
        guard let close = line.range(of: ")") else { return nil }
        let rest = line[close.upperBound...].trimmingCharacters(in: .whitespaces)
        // The delimiter comes first — `"/"` or `NIL` — and the name is what's left.
        let pieces = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard pieces.count == 2 else { return nil }
        let name = pieces[1].trimmingCharacters(in: .whitespaces)
        return name.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).isEmpty
            ? nil
            : name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
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

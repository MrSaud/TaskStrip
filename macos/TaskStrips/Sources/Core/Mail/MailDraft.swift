import Foundation

/// A message on its way out, and the text a server is handed.
///
/// The mirror of MailBodyParser: that takes MIME apart, this puts it together. Anything that isn't
/// ASCII has to be encoded to survive the journey — an Arabic subject as an encoded word, an
/// Arabic body as quoted-printable UTF-8 — which is exactly what the reader decodes coming the
/// other way.
struct MailDraft: Equatable, Identifiable {
    /// Only so a draft can be presented as a sheet; a draft is not a stored thing.
    var id = UUID()
    var from: String
    var fromName: String = ""
    var to: String
    var subject: String
    var body: String
    /// Set when this is a reply: the Message-ID being answered, so mail programs thread it under
    /// the message it belongs to rather than starting a new conversation.
    var inReplyTo: String?

    /// Every address this is going to. One for now; the shape is here so a Cc doesn't need the
    /// sending code rewritten.
    var recipients: [String] { [to.trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty } }

    var isSendable: Bool {
        MailDraft.looksLikeAnAddress(to) && !from.isEmpty
    }

    static func looksLikeAnAddress(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "@")
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        return parts[1].contains(".") && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
            && !trimmed.contains(" ")
    }

    /// The whole message as the server receives it.
    ///
    /// `now` and `messageID` are arguments rather than taken from the world so the same draft
    /// always writes the same message in a test.
    func rendered(now: Date = .now, messageID: String = MailDraft.newMessageID()) -> String {
        var lines: [String] = []
        lines.append("From: \(addressField(name: fromName, address: from))")
        lines.append("To: \(to.trimmingCharacters(in: .whitespaces))")
        lines.append("Subject: \(MailDraft.encodedWord(subject))")
        lines.append("Date: \(MailDraft.dateFormatter.string(from: now))")
        lines.append("Message-ID: <\(messageID)>")
        if let inReplyTo, !inReplyTo.isEmpty {
            let bracketed = "<\(inReplyTo.trimmingCharacters(in: CharacterSet(charactersIn: "<>")))>"
            lines.append("In-Reply-To: \(bracketed)")
            // References is what most clients actually thread on.
            lines.append("References: \(bracketed)")
        }
        lines.append("MIME-Version: 1.0")
        lines.append("Content-Type: text/plain; charset=utf-8")
        lines.append("Content-Transfer-Encoding: quoted-printable")
        lines.append("")
        lines.append(MailDraft.quotedPrintable(body))
        return lines.joined(separator: "\r\n")
    }

    private func addressField(name: String, address: String) -> String {
        guard !name.isEmpty else { return address }
        return "\(MailDraft.encodedWord(name)) <\(address)>"
    }

    /// A header is ASCII. Anything else goes as `=?UTF-8?B?…?=`, which is what the inbox decodes
    /// in the other direction.
    static func encodedWord(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value > 127 }) else { return text }
        return "=?UTF-8?B?\(Data(text.utf8).base64EncodedString())?="
    }

    /// Bytes above 127, and the equals sign itself, written as `=XX`; long lines folded with a
    /// trailing `=`, which means "this line continues".
    static func quotedPrintable(_ text: String, lineLimit: Int = 72) -> String {
        var out = ""
        var column = 0
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if !out.isEmpty { out += "\r\n"; column = 0 }
            for byte in Array(line.utf8) {
                let piece: String
                if byte == 61 || byte > 126 || byte < 32 {
                    piece = String(format: "=%02X", byte)
                } else {
                    piece = String(UnicodeScalar(byte))
                }
                if column + piece.count > lineLimit {
                    out += "=\r\n"
                    column = 0
                }
                out += piece
                column += piece.count
            }
            // A space at the end of a line doesn't survive the journey unless it's encoded.
            if out.hasSuffix(" ") { out.removeLast(); out += "=20"; }
        }
        return out
    }

    static func newMessageID(uuid: UUID = UUID(), host: String = "taskstrips.local") -> String {
        "\(uuid.uuidString.lowercased())@\(host)"
    }

    /// RFC 5322's date, which is not any of Foundation's named styles and must be in English
    /// whatever the phone's language is.
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    // MARK: - Replying

    /// A reply to a message: addressed back to whoever wrote, subject prefixed once, and the
    /// original quoted underneath the way every mail program does it.
    static func reply(to message: MailMessage, from account: String, fromName: String = "", body: MailBody?) -> MailDraft {
        MailDraft(
            from: account,
            fromName: fromName,
            to: message.senderAddress ?? "",
            subject: replySubject(message.subject),
            body: quoting(message, body: body),
            inReplyTo: message.id.isEmpty ? nil : message.id
        )
    }

    static func replySubject(_ subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        // "Re: Re: Re:" is how a thread looks after four people have replied; once is enough.
        guard !trimmed.lowercased().hasPrefix("re:") else { return trimmed }
        return trimmed.isEmpty ? "Re:" : "Re: \(trimmed)"
    }

    /// Blank lines to write in, then the attribution line, then the original behind angle
    /// brackets. Long messages are quoted in part: nobody reads the tail of a quoted newsletter.
    static func quoting(_ message: MailMessage, body: MailBody?, limit: Int = 2_000) -> String {
        let original = (body?.text ?? "").prefix(limit)
        let quoted = original
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> " + $0 }
            .joined(separator: "\n")
        let attribution = "On \(message.receivedAt.formatted(date: .abbreviated, time: .shortened)), "
            + "\(message.senderName) wrote:"
        let ellipsis = (body?.text ?? "").count > limit ? "\n> …" : ""
        return "\n\n\(attribution)\n\(quoted)\(ellipsis)\n"
    }
}

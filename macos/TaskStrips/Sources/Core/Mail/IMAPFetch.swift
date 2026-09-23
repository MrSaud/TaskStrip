import Foundation

/// Turns a FETCH reply into messages.
///
/// A reply looks like `* 12 FETCH (FLAGS (\Seen) BODY[HEADER.FIELDS (…)] {217}` followed by
/// exactly 217 bytes of headers, then `)`. The byte count is the part that matters: headers can
/// contain anything, including the characters that end an IMAP line, so the length is counted
/// rather than the text searched.
enum IMAPFetch {
    static func messages(from response: String, now: Date = .now) -> [MailMessage] {
        var messages: [MailMessage] = []
        var rest = Substring(response)

        while let fetch = rest.range(of: "FETCH (") {
            let body = rest[fetch.upperBound...]
            guard let brace = body.range(of: "{"),
                  let braceEnd = body[brace.upperBound...].range(of: "}"),
                  let length = Int(body[brace.upperBound..<braceEnd.lowerBound])
            else {
                rest = body
                continue
            }

            let seen = body[..<brace.lowerBound].uppercased().contains("\\SEEN")
            // The literal starts after the line break that follows the brace.
            let afterBrace = body[braceEnd.upperBound...]
            guard let newline = afterBrace.range(of: "\r\n") ?? afterBrace.range(of: "\n") else {
                rest = body
                continue
            }
            let headerStart = newline.upperBound
            let headers = String(afterBrace[headerStart...].prefix(length))
            let fields = IMAPHeaders.parse(headers, now: now)

            messages.append(
                MailMessage(
                    id: fields.messageID,
                    subject: fields.subject.isEmpty ? "(no subject)" : fields.subject,
                    sender: fields.from,
                    receivedAt: fields.date ?? now,
                    isRead: seen
                )
            )
            rest = afterBrace[headerStart...].dropFirst(min(length, afterBrace[headerStart...].count))
        }
        return messages
    }
}

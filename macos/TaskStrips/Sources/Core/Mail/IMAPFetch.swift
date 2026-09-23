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

            let attributes = body[..<brace.lowerBound]
            let seen = attributes.uppercased().contains("\\SEEN")
            let uid = self.uid(in: attributes)
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
                    isRead: seen,
                    uid: uid
                )
            )
            rest = afterBrace[headerStart...].dropFirst(min(length, afterBrace[headerStart...].count))
        }
        return messages
    }

    /// `UID 43742` among the attributes, which is how the message is asked for later.
    static func uid(in attributes: Substring) -> Int? {
        guard let range = attributes.range(of: "UID ") else { return nil }
        let digits = attributes[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    /// The literal a body fetch answers with, as the bytes it arrived as.
    ///
    /// Bytes rather than text: a message body can be in any charset, and its own headers say
    /// which. Decoding it as anything before reading those headers is how a message ends up as
    /// question marks.
    static func literal(in response: Data) -> Data? {
        guard let brace = response.range(of: Data("{".utf8)),
              let braceEnd = response[brace.upperBound...].range(of: Data("}".utf8)),
              let count = Int(String(decoding: response[brace.upperBound..<braceEnd.lowerBound], as: UTF8.self)),
              let newline = response[braceEnd.upperBound...].range(of: Data("\r\n".utf8))
        else { return nil }
        let start = newline.upperBound
        let end = response.index(start, offsetBy: count, limitedBy: response.endIndex) ?? response.endIndex
        return Data(response[start..<end])
    }
}

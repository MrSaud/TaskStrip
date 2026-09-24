import Foundation

/// Turning what Graph sends into what the rest of the app already understands.
///
/// Everything above the mail layer — the reader, the composer, making a strip out of a message,
/// reading dates out of attachments — works on `MailMessage` and `MailBody`. So this is the whole
/// job of supporting Exchange: read Graph's JSON into those two, and write a message back out in
/// the shape Graph wants to send.
enum GraphMessages {
    /// What to ask for in a list. Only the headers a list needs: bodies are fetched when somebody
    /// opens one, the same rule the IMAP side follows.
    static let listFields = "id,subject,from,receivedDateTime,isRead,internetMessageId,toRecipients,ccRecipients,replyTo"

    static func inboxURL(count: Int = MailInbox.count) -> String {
        "\(MicrosoftGraph.graph)/me/mailFolders/inbox/messages"
            + "?$top=\(count)&$select=\(listFields)&$orderby=receivedDateTime%20desc"
    }

    static func messageURL(id: String) -> String {
        "\(MicrosoftGraph.graph)/me/messages/\(escaped(id))?$select=body,hasAttachments"
    }

    static func attachmentsURL(id: String) -> String {
        "\(MicrosoftGraph.graph)/me/messages/\(escaped(id))/attachments"
    }

    /// A Graph message id is long and full of characters a URL cares about.
    static func escaped(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? id
    }

    // MARK: - Reading

    static func messages(from json: [String: Any], account: IMAPAccount?, now: Date = .now) -> [MailMessage] {
        let rows = json["value"] as? [[String: Any]] ?? []
        return rows.compactMap { message(from: $0, account: account, now: now) }
    }

    static func message(from row: [String: Any], account: IMAPAccount?, now: Date = .now) -> MailMessage? {
        guard let remoteID = row["id"] as? String else { return nil }
        let sender = address(in: row["from"])

        return MailMessage(
            // The Message-ID, so a link to this message is the same kind of link a dragged one
            // leaves, and two copies of one mail are still one mail.
            id: (row["internetMessageId"] as? String)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "<>")) ?? remoteID,
            subject: (row["subject"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "(no subject)",
            sender: sender,
            receivedAt: date(row["receivedDateTime"]) ?? now,
            isRead: row["isRead"] as? Bool ?? false,
            account: account?.name,
            accountID: account?.id,
            remoteID: remoteID,
            to: addresses(in: row["toRecipients"]),
            cc: addresses(in: row["ccRecipients"]),
            replyTo: addresses(in: row["replyTo"])
        )
    }

    /// `{"emailAddress": {"name": "Mona", "address": "m@kfas.org.kw"}}` as mail writes it.
    static func address(in value: Any?) -> String {
        guard let holder = value as? [String: Any],
              let inner = holder["emailAddress"] as? [String: Any]
        else { return "" }
        let address = inner["address"] as? String ?? ""
        let name = inner["name"] as? String ?? ""
        if name.isEmpty || name == address { return address }
        return "\(name) <\(address)>"
    }

    static func addresses(in value: Any?) -> String? {
        guard let list = value as? [[String: Any]], !list.isEmpty else { return nil }
        let written = list.map { address(in: $0) }.filter { !$0.isEmpty }
        return written.isEmpty ? nil : written.joined(separator: ", ")
    }

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// The message itself. Graph hands over HTML or plain text and says which, so there's no MIME
    /// tree to walk — the HTML still has to be made readable the same way.
    static func body(from json: [String: Any], attachments: [MailAttachment] = []) -> MailBody {
        let body = json["body"] as? [String: Any] ?? [:]
        let content = body["content"] as? String ?? ""
        let isHTML = (body["contentType"] as? String)?.lowercased() == "html"

        return MailBody(
            text: isHTML ? MailBodyParser.readable(fromHTML: content) : MailBodyParser.tidied(content),
            fromHTML: isHTML,
            isTruncated: false,
            attachments: attachments
        )
    }

    static func attachments(from json: [String: Any]) -> [MailAttachment] {
        let rows = json["value"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            // Only files. A message attached to a message, or a link to a file in OneDrive, is
            // not bytes this app can put on a strip.
            guard row["@odata.type"] as? String == "#microsoft.graph.fileAttachment",
                  let name = row["name"] as? String,
                  let encoded = row["contentBytes"] as? String,
                  let bytes = Data(base64Encoded: encoded)
            else { return nil }
            return MailAttachment(
                name: name,
                type: row["contentType"] as? String ?? "application/octet-stream",
                bytes: bytes,
                isInline: row["isInline"] as? Bool ?? false
            )
        }
    }

    // MARK: - Sending

    /// A message as Graph's sendMail wants it.
    ///
    /// The same draft the SMTP side renders, said in JSON instead: HTML when there's a signature
    /// to style, plain text when there isn't.
    static func sendPayload(_ draft: MailDraft) -> [String: Any] {
        var content = draft.body
        var type = "text"
        if let signature = draft.signature, !signature.isEmpty {
            content = MailDraft.htmlBody(draft.body, signature: signature)
            type = "html"
        }

        var message: [String: Any] = [
            "subject": draft.subject,
            "body": ["contentType": type, "content": content],
            "toRecipients": recipients(MailAddress.list(in: draft.to)),
        ]
        let copies = MailAddress.list(in: draft.cc)
        if !copies.isEmpty { message["ccRecipients"] = recipients(copies) }

        // Graph won't take an In-Reply-To header, so a reply is sent from the original instead —
        // see `replyURL`. This carries the rest either way.
        return ["message": message, "saveToSentItems": true]
    }

    static func recipients(_ addresses: [String]) -> [[String: Any]] {
        addresses.map { ["emailAddress": ["address": $0]] }
    }

    static let sendURL = "\(MicrosoftGraph.graph)/me/sendMail"

    /// Replying through the original message is what keeps it in the conversation: Graph builds
    /// the draft with the threading headers already on it, and the body is written into that.
    static func replyDraftURL(id: String) -> String {
        "\(MicrosoftGraph.graph)/me/messages/\(escaped(id))/createReply"
    }

    static func draftURL(id: String) -> String {
        "\(MicrosoftGraph.graph)/me/messages/\(escaped(id))"
    }

    static func sendDraftURL(id: String) -> String {
        "\(MicrosoftGraph.graph)/me/messages/\(escaped(id))/send"
    }

    /// What to write into the reply draft Graph made: the words, and who else it goes to.
    static func replyPayload(_ draft: MailDraft) -> [String: Any] {
        var content = draft.body
        var type = "text"
        if let signature = draft.signature, !signature.isEmpty {
            content = MailDraft.htmlBody(draft.body, signature: signature)
            type = "html"
        }
        var payload: [String: Any] = [
            "body": ["contentType": type, "content": content],
            "toRecipients": recipients(MailAddress.list(in: draft.to)),
        ]
        let copies = MailAddress.list(in: draft.cc)
        payload["ccRecipients"] = recipients(copies)
        return payload
    }
}

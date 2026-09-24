import Foundation

/// Reading and sending mail through Microsoft Graph.
///
/// The same errands as the IMAP client — the newest few headers, one message's words and files,
/// send, reply — over HTTPS instead of a socket, because Exchange no longer answers the socket.
struct GraphMailClient {
    let account: IMAPAccount

    enum Failure: LocalizedError {
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .refused(let detail): return detail
            }
        }
    }

    // MARK: - Reading

    func fetchNewest(count: Int = MailInbox.count, now: Date = .now) async throws -> [MailMessage] {
        let json = try await get(GraphMessages.inboxURL(count: count))
        return GraphMessages.messages(from: json, account: account, now: now)
    }

    /// One message: its words, and the files that came with it.
    func fetchBody(remoteID: String) async throws -> MailBody {
        let message = try await get(GraphMessages.messageURL(id: remoteID))
        var files: [MailAttachment] = []
        if message["hasAttachments"] as? Bool == true {
            let attachments = try await get(GraphMessages.attachmentsURL(id: remoteID))
            files = GraphMessages.attachments(from: attachments)
        }
        var body = GraphMessages.body(from: message, attachments: files)
        // Real attachments first, the signature logos after, as on the IMAP side.
        body.attachments = files.filter { !$0.isInline } + files.filter(\.isInline)
        return body
    }

    // MARK: - Sending

    /// Sends a message. Exchange files its own copy in Sent — `saveToSentItems` — so unlike SMTP
    /// there's nothing to append afterwards.
    func send(_ draft: MailDraft) async throws {
        _ = try await post(GraphMessages.sendURL, body: GraphMessages.sendPayload(draft))
    }

    /// A reply goes through the message it answers, which is what keeps it in the conversation:
    /// Graph makes the draft with the threading already on it, the words are written into that
    /// draft, and then it's sent.
    func reply(_ draft: MailDraft, to remoteID: String) async throws {
        let created = try await post(GraphMessages.replyDraftURL(id: remoteID), body: [:])
        guard let draftID = created["id"] as? String else {
            throw Failure.refused("Microsoft didn't make the reply draft.")
        }
        _ = try await send(
            GraphMessages.draftURL(id: draftID), method: "PATCH", body: GraphMessages.replyPayload(draft)
        )
        _ = try await post(GraphMessages.sendDraftURL(id: draftID), body: nil)
    }

    // MARK: - The wire

    private func get(_ url: String) async throws -> [String: Any] {
        try await send(url, method: "GET", body: nil)
    }

    @discardableResult
    private func post(_ url: String, body: [String: Any]?) async throws -> [String: Any] {
        try await send(url, method: "POST", body: body)
    }

    @discardableResult
    private func send(_ url: String, method: String, body: [String: Any]?) async throws -> [String: Any] {
        guard let url = URL(string: url) else { throw Failure.refused("Couldn't build the request.") }
        let token = try await MicrosoftTokens.shared.access(for: account.id)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body, !body.isEmpty {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(status) else {
            // Graph says why in its own words, and those words are worth passing on: "the
            // administrator has not consented" reads very differently from "not found".
            throw Failure.refused(
                MicrosoftGraph.errorMessage(in: json) ?? "Microsoft refused the request (\(status))."
            )
        }
        return json
    }
}
